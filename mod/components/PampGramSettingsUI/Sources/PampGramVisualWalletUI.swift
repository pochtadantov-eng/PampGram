import Foundation
import UIKit
import Display
import Postbox
import SwiftSignalKit
import TelegramCore
import AccountContext
import PromptUI
import UndoUI
import PampGramCore

// MARK: - Public entry points

/// Visual «Пополнить»: asks for a GRAM amount and credits the card + history.
public func pampGramPresentVisualWalletTopUp(context: AccountContext, presenter: ViewController? = nil) {
    guard let top = pampGramVisualWalletTopController(context: context, preferred: presenter) else {
        return
    }
    top.present(promptController(
        context: context,
        text: "Пополнить GRAM",
        subtitle: "Сумма зачислится только локально на этом устройстве",
        value: "0.1",
        placeholder: "0.1",
        characterLimit: 16,
        apply: { value in
            guard let value, let nanos = pampGramParseGramAmount(value), nanos > 0 else {
                pampGramVisualWalletToast(context: context, text: "Укажите сумму больше 0")
                return
            }
            let _ = (context.account.postbox.transaction { transaction -> PampGramVisualWalletTx? in
                return PampGramVisualWallet.apply(
                    transaction: transaction,
                    kind: .topUp,
                    amountNanos: nanos,
                    peerTitle: "Пополнение"
                )
            }
            |> deliverOnMainQueue).startStandalone(next: { tx in
                if tx != nil {
                    pampGramVisualWalletToast(context: context, text: "Зачислено \(PampGramVisualWallet.formatGrams(nanos)) GRAM")
                } else {
                    pampGramVisualWalletToast(context: context, text: "Включите «Карточка GRAM» в настройках PampGram")
                }
            })
        }
    ), in: .window(.root))
}

/// Visual «Отправить»: uses the current chat peer when given, otherwise asks for @username.
public func pampGramPresentVisualWalletSend(context: AccountContext, preselectedPeerId: EnginePeer.Id? = nil, preselectedTitle: String? = nil, presenter: ViewController? = nil) {
    if let peerId = preselectedPeerId {
        let title = preselectedTitle ?? "Получатель"
        if preselectedTitle == nil {
            let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
            |> deliverOnMainQueue).startStandalone(next: { peer in
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                let resolved = peer?.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder) ?? title
                pampGramPresentVisualWalletSendAmount(context: context, peerId: peerId, peerTitle: resolved, presenter: presenter)
            })
        } else {
            pampGramPresentVisualWalletSendAmount(context: context, peerId: peerId, peerTitle: title, presenter: presenter)
        }
        return
    }
    guard let top = pampGramVisualWalletTopController(context: context, preferred: presenter) else {
        return
    }
    top.present(promptController(
        context: context,
        text: "Выберите получателя",
        subtitle: "Введите @username или числовой id",
        value: "",
        placeholder: "@username",
        characterLimit: 64,
        apply: { value in
            guard let value else {
                return
            }
            pampGramVisualWalletResolvePeer(context: context, query: value, completion: { peerId, title in
                guard let peerId else {
                    pampGramVisualWalletToast(context: context, text: "Получатель не найден")
                    return
                }
                pampGramPresentVisualWalletSendAmount(context: context, peerId: peerId, peerTitle: title)
            })
        }
    ), in: .window(.root))
}

private func pampGramVisualWalletResolvePeer(context: AccountContext, query: String, completion: @escaping (EnginePeer.Id?, String) -> Void) {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        completion(nil, "")
        return
    }
    if let idValue = Int64(trimmed), idValue != 0 {
        let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(idValue))
        let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
        |> deliverOnMainQueue).startStandalone(next: { peer in
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let title = peer?.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder) ?? trimmed
            completion(peerId, title)
        })
        return
    }
    var username = trimmed
    if username.hasPrefix("@") {
        username = String(username.dropFirst())
    }
    let _ = (context.engine.peers.resolvePeerByName(name: username, referrer: nil)
    |> deliverOnMainQueue).startStandalone(next: { result in
        guard case let .result(peer) = result, let peer else {
            completion(nil, "")
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        completion(peer.id, peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder))
    })
}

public func pampGramPresentVisualWalletSendAmount(context: AccountContext, peerId: EnginePeer.Id, peerTitle: String, presenter: ViewController? = nil) {
    guard let top = pampGramVisualWalletTopController(context: context, preferred: presenter) else {
        return
    }
    top.present(promptController(
        context: context,
        text: "Отправить GRAM",
        subtitle: "Кому: \(peerTitle)",
        value: "0.1",
        placeholder: "0.1",
        characterLimit: 16,
        apply: { value in
            guard let value, let nanos = pampGramParseGramAmount(value), nanos > 0 else {
                pampGramVisualWalletToast(context: context, text: "Укажите сумму больше 0")
                return
            }
            pampGramVisualWalletPerformSend(context: context, peerId: peerId, peerTitle: peerTitle, amountNanos: nanos, incoming: false)
        }
    ), in: .window(.root))
}

/// Inserts a visual incoming GRAM card as if the counterparty sent money (does not change their balance).
public func pampGramPresentVisualWalletReceiveInChat(context: AccountContext, peerId: EnginePeer.Id, peerTitle: String, presenter: ViewController? = nil) {
    guard let top = pampGramVisualWalletTopController(context: context, preferred: presenter) else {
        return
    }
    top.present(promptController(
        context: context,
        text: "Получить GRAM в чат",
        subtitle: "Плашка «от \(peerTitle)» + зачисление на карточку",
        value: "0.1",
        placeholder: "0.1",
        characterLimit: 16,
        apply: { value in
            guard let value, let nanos = pampGramParseGramAmount(value), nanos > 0 else {
                pampGramVisualWalletToast(context: context, text: "Укажите сумму больше 0")
                return
            }
            pampGramVisualWalletPerformSend(context: context, peerId: peerId, peerTitle: peerTitle, amountNanos: nanos, incoming: true)
        }
    ), in: .window(.root))
}

public func pampGramPresentVisualWalletTxDetail(context: AccountContext, tx: PampGramVisualWalletTx) {
    guard let top = pampGramVisualWalletTopController(context: context) else {
        return
    }
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let sheet = ActionSheetController(presentationData: presentationData)
    let amount = "\(PampGramVisualWallet.formatGrams(tx.amountNanos, signed: true)) GRAM"
    let usd = PampGramVisualWallet.formatUsd(cents: abs(tx.usdCents))
    let date = pampGramVisualWalletFormatDate(tx.date)
    let kindLabel: String
    switch tx.kind {
    case .topUp: kindLabel = "Пополнение"
    case .send: kindLabel = "Исходящий перевод"
    case .receive: kindLabel = "Входящий перевод"
    case .withdraw: kindLabel = "Вывод"
    }
    sheet.setItemGroups([
        ActionSheetItemGroup(items: [
            ActionSheetTextItem(title: "\(amount)  ·  \(usd)\n\(kindLabel)\n\(tx.peerTitle)\n\(date)\n\(tx.txHash)")
        ]),
        ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: "Перейти к моим Деньгам", color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                pampGramVisualWalletToast(context: context, text: "Откройте кошелёк из профиля — баланс уже визуальный")
            }),
            ActionSheetButtonItem(title: presentationData.strings.Common_Close, color: .accent, font: .bold, action: { [weak sheet] in
                sheet?.dismissAnimated()
            })
        ])
    ])
    top.present(sheet, in: .window(.root))
}

/// True when «Карточка GRAM» is on for this account — WalletScreen send/top-up should stay visual.
public func pampGramVisualWalletIsActive(context: AccountContext) -> Bool {
    return PampGramVisualExtrasRuntime.shared.fakeBalanceNanos(accountKey: context.account.peerId.toInt64()) != nil
}

// MARK: - Send / receive core

private func pampGramVisualWalletPerformSend(
    context: AccountContext,
    peerId: EnginePeer.Id,
    peerTitle: String,
    amountNanos: Int64,
    incoming: Bool
) {
    let kind: PampGramVisualWalletTx.Kind = incoming ? .receive : .send
    let _ = (context.account.postbox.transaction { transaction -> PampGramVisualWalletTx? in
        return PampGramVisualWallet.apply(
            transaction: transaction,
            kind: kind,
            amountNanos: amountNanos,
            peerId: peerId,
            peerTitle: peerTitle
        )
    }
    |> deliverOnMainQueue).startStandalone(next: { tx in
        guard let tx else {
            pampGramVisualWalletToast(context: context, text: "Недостаточно GRAM или карточка выключена")
            return
        }
        pampGramInsertVisualGramTransfer(context: context, peerId: peerId, peerTitle: peerTitle, tx: tx, incoming: incoming)
        let label = incoming ? "Получено" : "Отправлено"
        pampGramVisualWalletToast(context: context, text: "\(label) \(PampGramVisualWallet.formatGrams(abs(tx.amountNanos))) GRAM")
    })
}

private func pampGramInsertVisualGramTransfer(
    context: AccountContext,
    peerId: EnginePeer.Id,
    peerTitle: String,
    tx: PampGramVisualWalletTx,
    incoming: Bool
) {
    let grams = PampGramVisualWallet.formatGrams(abs(tx.amountNanos))
    let usd = PampGramVisualWallet.formatUsd(cents: abs(tx.usdCents))
    let serviceText: String
    if incoming {
        serviceText = "\(peerTitle) отправил(а) Вам \(grams) GRAM (\(usd))"
    } else {
        serviceText = "Вы отправили \(peerTitle) \(grams) GRAM (\(usd))"
    }

    guard let image = pampGramRenderGramTransferCard(
        amountText: "\(incoming ? "+" : "-")\(grams) GRAM",
        peerTitle: peerTitle.uppercased(),
        hashText: tx.txHash,
        ribbon: incoming ? "получено" : "отправлено"
    ),
          let data = image.jpegData(compressionQuality: 0.92),
          let path = pampGramPersistVisualWalletFile(data: data) else {
        return
    }

    let resource = LocalFileReferenceMediaResource(
        localFilePath: path,
        randomId: Int64.random(in: Int64.min ... Int64.max),
        isUniquelyReferencedTemporaryFile: false,
        size: Int64(data.count)
    )
    let representation = TelegramMediaImageRepresentation(
        dimensions: PixelDimensions(image.size),
        resource: resource,
        progressiveSizes: [],
        immediateThumbnailData: nil,
        hasVideo: false,
        isPersonal: false
    )
    let photo = TelegramMediaImage(
        imageId: MediaId(namespace: Namespaces.Media.LocalImage, id: Int64.random(in: Int64.min ... Int64.max)),
        representations: [representation],
        immediateThumbnailData: nil,
        reference: nil,
        partialReference: nil,
        flags: []
    )

    let _ = context.account.postbox.transaction { transaction -> Void in
        let globallyUniqueId = Int64.random(in: Int64.min ... Int64.max)
        let storeMessage = StoreMessage(
            id: .Partial(peerId, Namespaces.Message.Local),
            customStableId: nil,
            globallyUniqueId: globallyUniqueId,
            groupingKey: nil,
            threadId: nil,
            timestamp: Int32(Date().timeIntervalSince1970),
            flags: incoming ? StoreMessageFlags.Incoming : StoreMessageFlags(),
            tags: [],
            globalTags: [],
            localTags: [],
            forwardInfo: nil,
            authorId: incoming ? peerId : context.account.peerId,
            text: serviceText,
            attributes: [PampGramVisualChatMessageAttribute()],
            media: [photo]
        )
        let _ = transaction.addMessages([storeMessage], location: .Random)
    }.start()
}

// MARK: - Card renderer (chat bubble from screenshots)

private func pampGramRenderGramTransferCard(amountText: String, peerTitle: String, hashText: String, ribbon: String) -> UIImage? {
    let size = CGSize(width: 780.0, height: 520.0)
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 2.0
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    return renderer.image { rendererContext in
        let ctx = rendererContext.cgContext
        let top = UIColor(red: 0.10, green: 0.55, blue: 0.95, alpha: 1.0)
        let bottom = UIColor(red: 0.05, green: 0.38, blue: 0.82, alpha: 1.0)
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
        }

        // Ribbon
        ctx.saveGState()
        ctx.translateBy(x: size.width - 90.0, y: 28.0)
        ctx.rotate(by: .pi / 4.0)
        UIColor.white.setFill()
        UIBezierPath(roundedRect: CGRect(x: -70.0, y: -14.0, width: 140.0, height: 28.0), cornerRadius: 4.0).fill()
        let ribbonAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16.0, weight: .semibold),
            .foregroundColor: top
        ]
        let ribbonSize = (ribbon as NSString).size(withAttributes: ribbonAttr)
        (ribbon as NSString).draw(at: CGPoint(x: -ribbonSize.width / 2.0, y: -ribbonSize.height / 2.0), withAttributes: ribbonAttr)
        ctx.restoreGState()

        // Diamond
        let diamond = pampGramGramDiamondImage()
        let diamondRect = CGRect(x: (size.width - 72.0) / 2.0, y: 70.0, width: 72.0, height: 72.0)
        diamond?.draw(in: diamondRect)

        let amountAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 42.0, weight: .bold),
            .foregroundColor: UIColor(red: 0.55, green: 0.95, blue: 1.0, alpha: 1.0)
        ]
        let amountSize = (amountText as NSString).size(withAttributes: amountAttr)
        (amountText as NSString).draw(at: CGPoint(x: (size.width - amountSize.width) / 2.0, y: 160.0), withAttributes: amountAttr)

        let nameAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 18.0, weight: .semibold),
            .foregroundColor: UIColor(white: 0.85, alpha: 1.0)
        ]
        let nameSize = (peerTitle as NSString).size(withAttributes: nameAttr)
        (peerTitle as NSString).draw(at: CGPoint(x: (size.width - nameSize.width) / 2.0, y: 220.0), withAttributes: nameAttr)

        let groups = hashText.split(separator: " ").map(String.init)
        let columns = 4
        let hashAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 15.0, weight: .medium),
            .foregroundColor: UIColor(red: 0.70, green: 0.88, blue: 1.0, alpha: 1.0)
        ]
        var row = 0
        var col = 0
        let startY: CGFloat = 280.0
        let cellW = size.width / CGFloat(columns)
        for group in groups {
            let x = cellW * CGFloat(col) + 24.0
            let y = startY + CGFloat(row) * 28.0
            (group as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: hashAttr)
            col += 1
            if col >= columns {
                col = 0
                row += 1
            }
        }
    }
}

private func pampGramGramDiamondImage() -> UIImage? {
    let side: CGFloat = 120.0
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1.0
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
    return renderer.image { _ in
        let path = UIBezierPath()
        path.move(to: CGPoint(x: side / 2.0, y: 8.0))
        path.addLine(to: CGPoint(x: side - 12.0, y: side / 2.0))
        path.addLine(to: CGPoint(x: side / 2.0, y: side - 8.0))
        path.addLine(to: CGPoint(x: 12.0, y: side / 2.0))
        path.close()
        UIColor.white.setFill()
        path.fill()
    }
}

// MARK: - Helpers

private func pampGramParseGramAmount(_ raw: String) -> Int64? {
    let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: ",", with: ".")
        .replacingOccurrences(of: " ", with: "")
    guard let value = Double(normalized), value.isFinite, value > 0.0 else {
        return nil
    }
    return PampGramVisualWallet.nanos(fromGrams: value)
}

private func pampGramVisualWalletFormatDate(_ timestamp: Int32) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ru_RU")
    formatter.dateFormat = "d MMM 'в' HH:mm"
    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
}

private func pampGramVisualWalletTopController(context: AccountContext, preferred: ViewController? = nil) -> ViewController? {
    if let preferred {
        return preferred
    }
    guard let root = context.sharedContext.mainWindow?.viewController else {
        return nil
    }
    var current: UIViewController = root
    while let presented = current.presentedViewController {
        current = presented
    }
    if let tab = current as? UITabBarController {
        current = tab.selectedViewController ?? tab
    }
    if let nav = current as? NavigationController {
        return (nav.topViewController as? ViewController) ?? nav
    }
    if let nav = current as? UINavigationController {
        return (nav.topViewController as? ViewController) ?? (nav as? ViewController)
    }
    return current as? ViewController
}

private func pampGramVisualWalletToast(context: AccountContext, text: String) {
    guard let controller = pampGramVisualWalletTopController(context: context) else {
        return
    }
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    controller.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), in: .current)
}

private func pampGramPersistVisualWalletFile(data: Data) -> String? {
    guard let root = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
        return nil
    }
    let dir = root.appendingPathComponent("PampGramVisualWallet", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let path = dir.appendingPathComponent("gram-\(UUID().uuidString).jpg").path
    do {
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        return path
    } catch {
        return nil
    }
}
