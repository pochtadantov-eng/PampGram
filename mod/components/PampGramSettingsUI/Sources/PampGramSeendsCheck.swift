import Foundation
import UIKit
import Postbox
import SwiftSignalKit
import TelegramCore
import AccountContext

/// "@seends <сумма><валюта> <режим>" в поле ввода чата превращается в локальное сообщение-чек
/// CryptoBot — такое же, какое приходит через бота @send: «с помощью @send», превью-карточка
/// с суммой, строка «Чек на … (…)» и кнопка «Получить …» под пузырём. Настоящая отправка не
/// выполняется; сообщение вставляется только на этом устройстве, так же как остальные
/// локальные вставки PampGram (см. PampGramFakeContentInsert.swift).
///
/// «чек» — чек от моего имени (исходящее сообщение), кнопка «Получить …». «получено» — чек от
/// собеседника (входящее), уже получен: под ним серая кнопка «✅ Получено: …», как у настоящего.
/// Под чеком всегда есть и маленькая серая кнопка «⇄»: по нажатию чек переходит на другую
/// сторону чата и обратно.

private enum PampGramSeendsMode {
    case issued
    case received
}

private struct PampGramSeendsPayload {
    let amountText: String
    let amountValue: Double
    let code: String
    let mode: PampGramSeendsMode
}

/// Telegram user id of the official CryptoBot, whose inline mode (@send) the real checks come from.
private let pampGramSeendsBotUserId: Int64 = 1559501630

/// Entry point for the chat's send paths: true when any outgoing text message is an `@seends`
/// command (it was turned into a local receipt instead of being sent).
public func pampGramTryHandleSeendsMessages(context: AccountContext, peerId: EnginePeer.Id, messages: [EnqueueMessage]) -> Bool {
    var handled = false
    for message in messages {
        if case let .message(text, _, _, _, _, _, _, _, _, _) = message {
            if pampGramTryHandleSeendsCommand(context: context, peerId: peerId, text: text) {
                handled = true
            }
        }
    }
    return handled
}

public func pampGramTryHandleSeendsCommand(context: AccountContext, peerId: EnginePeer.Id, text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let payload = pampGramParseSeends(trimmed) else {
        return false
    }

    let currency = pampGramSeendsCurrency(code: payload.code)
    let usdValue = payload.amountValue * currency.price
    let usdText = pampGramSeendsFormatUSD(usdValue)
    let shortAmount = pampGramSeendsTruncate(payload.amountValue, fallback: payload.amountText)

    guard let image = pampGramRenderCheckCard(usdText: "$" + usdText, amountText: shortAmount + " " + payload.code, logo: currency.logo),
          let data = image.jpegData(compressionQuality: 0.92),
          let path = pampGramPersistSeendsFile(data: data, pathExtension: "jpg") else {
        return false
    }

    let resource = LocalFileReferenceMediaResource(
        localFilePath: path,
        randomId: Int64.random(in: Int64.min...Int64.max),
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
        imageId: MediaId(namespace: Namespaces.Media.LocalImage, id: Int64.random(in: Int64.min...Int64.max)),
        representations: [representation],
        immediateThumbnailData: nil,
        reference: nil,
        partialReference: nil,
        flags: []
    )

    // The card is a link preview, exactly like the real check: image only, no title or text.
    let checkUrl = "https://t.me/send?start=CQ" + String(Int64.random(in: 100_000_000_000...999_999_999_999))
    let webpage = TelegramMediaWebpage(
        webpageId: MediaId(namespace: Namespaces.Media.LocalWebpage, id: Int64.random(in: Int64.min...Int64.max)),
        content: .Loaded(TelegramMediaWebpageLoadedContent(
            url: checkUrl,
            displayUrl: "t.me/send",
            hash: 0,
            type: "photo",
            websiteName: nil,
            title: nil,
            text: nil,
            embedUrl: nil,
            embedType: nil,
            embedSize: nil,
            duration: nil,
            author: nil,
            isMediaLargeByDefault: true,
            imageIsVideoCover: false,
            image: photo,
            file: nil,
            story: nil,
            attributes: [],
            instantPage: nil
        ))
    )

    // "Чек на 0.014789403 GRAM ($0.01)." — «Чек» is the link, the amount and its dollar value bold.
    let prefix = "Чек на "
    let amountPart = payload.amountText + " " + payload.code + " ($" + usdText + ")"
    let messageText = prefix + amountPart + "."
    let linkLength = ("Чек" as NSString).length
    let boldStart = (prefix as NSString).length
    let boldEnd = boldStart + (amountPart as NSString).length
    let entities: [MessageTextEntity] = [
        MessageTextEntity(range: 0 ..< linkLength, type: .TextUrl(url: checkUrl)),
        MessageTextEntity(range: boldStart ..< boldEnd, type: .Bold)
    ]

    let botPeerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(pampGramSeendsBotUserId))
    // A claimed check keeps its link button but says "✅ Получено: 19.603115 USDT" (the whole amount).
    let buttonTitle = payload.mode == .received ? "✅ Получено: " + payload.amountText + " " + payload.code : "Получить " + shortAmount + " " + payload.code
    let button = ReplyMarkupButton(title: buttonTitle, titleWhenForwarded: nil, action: .url(checkUrl), style: nil)
    // The small grey button under it that moves the check to the other side of the chat.
    let swapData = MemoryBuffer(data: pampGramSeendsSwapPrefix.data(using: .utf8) ?? Data())
    let swapButton = ReplyMarkupButton(title: "⇄", titleWhenForwarded: nil, action: .callback(requiresPassword: false, data: swapData), style: nil)
    let attributes: [MessageAttribute] = [
        InlineBotMessageAttribute(peerId: botPeerId, title: "send"),
        WebpagePreviewMessageAttribute(leadingPreview: true, forceLargeMedia: true, isManuallyAdded: false, isSafe: true),
        TextEntitiesMessageAttribute(entities: entities),
        ReplyMarkupMessageAttribute(rows: [ReplyMarkupRow(buttons: [button]), ReplyMarkupRow(buttons: [swapButton])], flags: [.inline], placeholder: nil)
    ]

    let _ = pampGramInsertSeendsMessage(context: context, peerId: peerId, incoming: payload.mode == .received, text: messageText, attributes: attributes, media: [webpage]).start()
    return true
}

private let pampGramSeendsSwapPrefix = "pgswap"

/// The grey "⇄" button under a local check: moves the check to the other side of the chat.
/// Returns true when the callback was ours.
public func pampGramHandleSeendsCallback(context: AccountContext, message: EngineRawMessage, data: MemoryBuffer?) -> Bool {
    guard let data = data?.makeData(), String(data: data, encoding: .utf8) == pampGramSeendsSwapPrefix else {
        return false
    }
    let accountPeerId = context.account.peerId
    let messageId = message.id
    let _ = context.account.postbox.transaction { transaction -> Void in
        pampGramFlipLocalMessageSide(transaction: transaction, id: messageId, accountPeerId: accountPeerId)
    }.start()
    return true
}

private func pampGramFlipLocalMessageSide(transaction: Transaction, id: MessageId, accountPeerId: PeerId) {
    transaction.updateMessage(id, update: { message -> PostboxUpdateMessage in
        let wasIncoming = message.flags.contains(.Incoming)
        var flags = StoreMessageFlags(message.flags)
        if wasIncoming {
            flags.remove(.Incoming)
        } else {
            flags.insert(.Incoming)
        }
        return .update(StoreMessage(
            id: id,
            customStableId: nil,
            globallyUniqueId: message.globallyUniqueId,
            groupingKey: message.groupingKey,
            threadId: message.threadId,
            timestamp: message.timestamp,
            flags: flags,
            tags: message.tags,
            globalTags: message.globalTags,
            localTags: message.localTags,
            forwardInfo: message.forwardInfo.map(StoreMessageForwardInfo.init),
            authorId: wasIncoming ? accountPeerId : id.peerId,
            text: message.text,
            attributes: message.attributes,
            media: message.media
        ))
    })
}

// MARK: - Parsing

private func pampGramParseSeends(_ text: String) -> PampGramSeendsPayload? {
    let lower = text.lowercased()
    // "@seend" (a missing "s") is accepted too: without it the text would be sent for real.
    let prefixLength: Int
    if lower.hasPrefix("@seends") {
        prefixLength = "@seends".count
    } else if lower.hasPrefix("@seend") {
        prefixLength = "@seend".count
    } else {
        return nil
    }
    let rest = text.dropFirst(prefixLength).trimmingCharacters(in: .whitespacesAndNewlines)
    if rest.isEmpty { return nil }

    let parts = rest.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    guard let first = parts.first else { return nil }

    // The first word carries the number and possibly the currency, in front of it or after it:
    // "100$", "$100", "110gram", "0.5btc".
    var amountChars = ""
    var prefixUnit = ""
    var suffixUnit = ""
    var seenDigit = false
    for ch in first {
        if ch.isNumber {
            if suffixUnit.isEmpty {
                amountChars.append(ch)
                seenDigit = true
            } else {
                suffixUnit.append(ch)
            }
        } else if (ch == "." || ch == ",") && seenDigit && suffixUnit.isEmpty && !amountChars.contains(".") {
            amountChars.append(".")
        } else if !seenDigit {
            prefixUnit.append(ch)
        } else {
            suffixUnit.append(ch)
        }
    }
    guard seenDigit else { return nil }
    if amountChars.hasSuffix(".") {
        amountChars = String(amountChars.dropLast())
    }
    guard let amountValue = Double(amountChars), amountValue > 0.0 else { return nil }

    // A currency that wasn't glued to the number is the next word.
    var currencyRaw = suffixUnit.isEmpty ? prefixUnit : suffixUnit
    var modeTokenIndex = 1
    if currencyRaw.isEmpty, parts.count >= 2 {
        currencyRaw = parts[1]
        modeTokenIndex = 2
    }
    let code = pampGramNormalizeSeendsCurrency(currencyRaw)

    var mode: PampGramSeendsMode = .issued
    if parts.count > modeTokenIndex {
        let modeToken = parts[modeTokenIndex].lowercased()
        if modeToken.contains("получ") || modeToken.contains("recei") || modeToken.contains("пришл") || modeToken.contains("пришёл") {
            mode = .received
        }
    }

    return PampGramSeendsPayload(amountText: amountChars, amountValue: amountValue, code: code, mode: mode)
}

private func pampGramNormalizeSeendsCurrency(_ raw: String) -> String {
    let lower = raw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " .,:;!?"))
    switch lower {
    case "", "$", "usd", "usdt", "дол", "долл", "доллар", "долларов", "tether":
        return "USDT"
    case "usdc":
        return "USDC"
    case "gram", "грам", "грамм", "грамма", "граммов", "g", "gr", "гр", "ton", "тон":
        return "GRAM"
    case "btc", "биткоин", "bitcoin":
        return "BTC"
    case "eth", "эфир", "ethereum":
        return "ETH"
    case "ltc", "litecoin", "лайткоин":
        return "LTC"
    case "trx", "tron", "трон":
        return "TRX"
    case "bnb":
        return "BNB"
    case "sol", "solana", "солана":
        return "SOL"
    case "doge", "dogecoin", "додж":
        return "DOGE"
    case "xaut":
        return "XAUT"
    default:
        return raw.uppercased()
    }
}

/// The coin from the fake CryptoBot's table (its logo and dollar price). Any other currency works
/// too: it gets a generated round logo with its first letter and is priced at 1 dollar, apart
/// from a couple of common ones.
private func pampGramSeendsCurrency(code: String) -> (logo: UIImage?, price: Double) {
    for currency in pampGramFakeCryptoBotCurrencies where currency.code == code {
        return (PampGramFakeCryptoBotAssets.image(currency.assetName), currency.price)
    }
    var price = 1.0
    if code == "RUB" {
        price = 0.0105
    } else if code == "EUR" {
        price = 1.08
    }
    return (pampGramSeendsGenericLogo(code: code), price)
}

/// A flat round badge with the currency's first letter, its colour taken from the code so the
/// same currency always looks the same.
private func pampGramSeendsGenericLogo(code: String) -> UIImage {
    let side: CGFloat = 120.0
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1.0
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
    var hash: UInt32 = 5381
    for scalar in code.unicodeScalars {
        hash = hash &* 33 &+ scalar.value
    }
    let color = UIColor(hue: CGFloat(hash % 360) / 360.0, saturation: 0.62, brightness: 0.82, alpha: 1.0)
    let letter = String(code.prefix(1)) as NSString
    return renderer.image { rendererContext in
        color.setFill()
        rendererContext.cgContext.fillEllipse(in: CGRect(x: 0.0, y: 0.0, width: side, height: side))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 66.0, weight: .bold),
            .foregroundColor: UIColor.white
        ]
        let letterSize = letter.size(withAttributes: attributes)
        letter.draw(at: CGPoint(x: (side - letterSize.width) / 2.0, y: (side - letterSize.height) / 2.0), withAttributes: attributes)
    }
}

// MARK: - Formatting

/// "$0.02"-style dollar value: cents from a cent up, whole numbers without decimals.
private func pampGramSeendsFormatUSD(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = ","
    formatter.usesGroupingSeparator = true
    formatter.decimalSeparator = "."
    formatter.maximumFractionDigits = 2
    formatter.minimumFractionDigits = value == value.rounded() ? 0 : 2
    return formatter.string(from: NSNumber(value: value)) ?? "0"
}

/// The card and the button show at most five decimals, cut off rather than rounded
/// (0.014789403 reads 0.01478), the way the real check does.
private func pampGramSeendsTruncate(_ value: Double, fallback: String) -> String {
    let factor = 100_000.0
    let truncated = (value * factor).rounded(.towardZero) / factor
    if truncated <= 0.0 {
        return fallback
    }
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = false
    formatter.decimalSeparator = "."
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 5
    return formatter.string(from: NSNumber(value: truncated)) ?? fallback
}

// MARK: - The card

private func pampGramSeendsRoundedFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
    let base = UIFont.systemFont(ofSize: size, weight: weight)
    if let descriptor = base.fontDescriptor.withDesign(.rounded) {
        return UIFont(descriptor: descriptor, size: size)
    }
    return base
}

/// The picture inside the check: a dark navy card with a faint pattern of coin badges, the dollar
/// value in big rounded silver letters and, under it, the coin logo with the amount. Drawn at
/// 1350x842 (the real one is a 16:10 image).
private func pampGramRenderCheckCard(usdText: String, amountText: String, logo: UIImage?) -> UIImage? {
    let scale: CGFloat = 1.5
    let size = CGSize(width: 900.0 * scale, height: 561.0 * scale)
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1.0
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(size: size, format: format)

    return renderer.image { rendererContext in
        let ctx = rendererContext.cgContext

        // Background: navy, a little lighter toward the bottom right.
        let colors = [
            UIColor(red: 36.0 / 255.0, green: 46.0 / 255.0, blue: 61.0 / 255.0, alpha: 1.0).cgColor,
            UIColor(red: 47.0 / 255.0, green: 57.0 / 255.0, blue: 76.0 / 255.0, alpha: 1.0).cgColor
        ]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
        }

        // Pattern: a diamond lattice of darker discs, each with a faint logo.
        let radius = 70.0 * scale
        for row in -1 ... 8 {
            let isEven = ((row % 2) + 2) % 2 == 0
            let baseX: CGFloat = isEven ? 182.0 : 13.0
            let centerY = (25.0 + 85.0 * CGFloat(row)) * scale
            for column in -2 ... 4 {
                let centerX = (baseX + 338.0 * CGFloat(column)) * scale
                let rect = CGRect(x: centerX - radius, y: centerY - radius, width: radius * 2.0, height: radius * 2.0)
                if rect.maxX < 0.0 || rect.minX > size.width || rect.maxY < 0.0 || rect.minY > size.height {
                    continue
                }
                ctx.setFillColor(UIColor(white: 0.0, alpha: 0.10).cgColor)
                ctx.fillEllipse(in: rect)
                logo?.draw(in: rect.insetBy(dx: 6.0 * scale, dy: 6.0 * scale), blendMode: .normal, alpha: 0.06)
            }
        }

        // The dollar value, a vertical white-to-silver gradient with a soft shadow.
        var amountFontSize = 200.0 * scale
        var amountFont = pampGramSeendsRoundedFont(size: amountFontSize, weight: .heavy)
        var amountAttributes: [NSAttributedString.Key: Any] = [.font: amountFont, .foregroundColor: UIColor.white]
        var amountSize = (usdText as NSString).size(withAttributes: amountAttributes)
        let maxAmountWidth = 700.0 * scale
        if amountSize.width > maxAmountWidth {
            amountFontSize = amountFontSize * maxAmountWidth / amountSize.width
            amountFont = pampGramSeendsRoundedFont(size: amountFontSize, weight: .heavy)
            amountAttributes = [.font: amountFont, .foregroundColor: UIColor.white]
            amountSize = (usdText as NSString).size(withAttributes: amountAttributes)
        }
        let textBounds = CGRect(origin: .zero, size: CGSize(width: ceil(amountSize.width), height: ceil(amountSize.height)))
        let layerFormat = UIGraphicsImageRendererFormat.default()
        layerFormat.scale = 1.0
        let layerRenderer = UIGraphicsImageRenderer(size: textBounds.size, format: layerFormat)
        let textMask = layerRenderer.image { _ in
            (usdText as NSString).draw(at: .zero, withAttributes: amountAttributes)
        }
        let silverText = layerRenderer.image { layerContext in
            let silver = [
                UIColor(red: 243.0 / 255.0, green: 244.0 / 255.0, blue: 247.0 / 255.0, alpha: 1.0).cgColor,
                UIColor(red: 204.0 / 255.0, green: 206.0 / 255.0, blue: 212.0 / 255.0, alpha: 1.0).cgColor
            ]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: silver as CFArray, locations: [0.0, 1.0]) {
                layerContext.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0.0, y: textBounds.height), options: [])
            }
            textMask.draw(in: textBounds, blendMode: .destinationIn, alpha: 1.0)
        }
        // Centre the digits (not the line box) on y = 262 of the 900x561 design.
        let amountOrigin = CGPoint(
            x: floor((size.width - textBounds.width) / 2.0),
            y: 262.0 * scale + amountFont.capHeight / 2.0 - amountFont.ascender
        )
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0.0, height: 8.0 * scale), blur: 14.0 * scale, color: UIColor(white: 0.0, alpha: 0.35).cgColor)
        silverText.draw(at: amountOrigin)
        ctx.restoreGState()

        // The coin logo and the amount under it.
        let subFont = UIFont.systemFont(ofSize: 52.0 * scale, weight: .semibold)
        let subAttributes: [NSAttributedString.Key: Any] = [
            .font: subFont,
            .foregroundColor: UIColor(red: 241.0 / 255.0, green: 242.0 / 255.0, blue: 248.0 / 255.0, alpha: 1.0)
        ]
        let subSize = (amountText as NSString).size(withAttributes: subAttributes)
        let iconSize = 46.0 * scale
        let gap = 14.0 * scale
        let groupWidth = iconSize + gap + subSize.width
        let groupX = floor((size.width - groupWidth) / 2.0)
        let centerY = 402.0 * scale
        logo?.draw(in: CGRect(x: groupX, y: centerY - iconSize / 2.0, width: iconSize, height: iconSize))
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0.0, height: 3.0 * scale), blur: 6.0 * scale, color: UIColor(white: 0.0, alpha: 0.25).cgColor)
        (amountText as NSString).draw(at: CGPoint(x: groupX + iconSize + gap, y: centerY + subFont.capHeight / 2.0 - subFont.ascender), withAttributes: subAttributes)
        ctx.restoreGState()
    }
}

// MARK: - Insertion

private func pampGramPersistSeendsFile(data: Data, pathExtension: String) -> String? {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let dir = base.appendingPathComponent("PampGram/FakeMedia", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let ext = pathExtension.isEmpty ? "dat" : pathExtension
    let path = dir.appendingPathComponent("\(Int64.random(in: 1...Int64.max)).\(ext)")
    do {
        try data.write(to: path, options: .atomic)
        return path.path
    } catch {
        return nil
    }
}

/// `incoming` puts the check on the other side of the chat (from the interlocutor); otherwise it
/// is this account's own, outgoing one.
private func pampGramInsertSeendsMessage(context: AccountContext, peerId: EnginePeer.Id, incoming: Bool, text: String, attributes: [MessageAttribute], media: [Media]) -> Signal<EngineMessage.Id?, NoError> {
    return context.account.postbox.transaction { transaction -> EngineMessage.Id? in
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
            text: text,
            attributes: attributes,
            media: media
        )
        let insertedIds = transaction.addMessages([storeMessage], location: .Random)
        return insertedIds[globallyUniqueId]
    }
}
