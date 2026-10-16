import Foundation
import UIKit
import Postbox
import SwiftSignalKit
import TelegramCore
import AccountContext

/// Поддержка префикса "@seends ..." в поле ввода чата: любой текст вида
/// "@seends <сумма><валюта> <режим>" (например, "@seends 100$ чек" или
/// "@seends 110gram получено") превращается в локально вставленное входящее
/// фото-сообщение с визуальным чеком CryptoBot. Настоящая отправка на сервер
/// при этом не выполняется — работает ровно так же, как остальные локальные
/// вставки PampGram (см. PampGramFakeContentInsert.swift).
///
/// Возвращает `true`, если текст был командой @seends и был обработан — тогда
/// вызывающий код обязан не отправлять исходное сообщение.

private struct PampGramSeendsPayload {
    enum Mode {
        case issued      // "чек" — визуальный чек на отправку/активацию
        case received    // "получено" — визуальный чек на получение
    }
    let amount: String
    let currency: String
    let mode: Mode
}

public func pampGramTryHandleSeendsCommand(context: AccountContext, peerId: EnginePeer.Id, text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let payload = pampGramParseSeends(trimmed) else {
        return false
    }
    guard let image = pampGramRenderCryptoBotCheck(payload: payload),
          let data = image.jpegData(compressionQuality: 0.95),
          let path = pampGramPersistSeendsFile(data: data, pathExtension: "jpg") else {
        return false
    }
    let pixelSize: CGSize
    if let cg = image.cgImage {
        pixelSize = CGSize(width: cg.width, height: cg.height)
    } else {
        pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }
    let resource = LocalFileReferenceMediaResource(
        localFilePath: path,
        randomId: Int64.random(in: Int64.min...Int64.max),
        isUniquelyReferencedTemporaryFile: false,
        size: Int64(data.count)
    )
    let representation = TelegramMediaImageRepresentation(
        dimensions: PixelDimensions(pixelSize),
        resource: resource,
        progressiveSizes: [],
        immediateThumbnailData: nil,
        hasVideo: false,
        isPersonal: false
    )
    let media = TelegramMediaImage(
        imageId: MediaId(namespace: Namespaces.Media.LocalImage, id: Int64.random(in: Int64.min...Int64.max)),
        representations: [representation],
        immediateThumbnailData: nil,
        reference: nil,
        partialReference: nil,
        flags: []
    )

    let _ = pampGramInsertSeendsIncoming(context: context, peerId: peerId, media: [media]).start()
    return true
}

private func pampGramParseSeends(_ text: String) -> PampGramSeendsPayload? {
    let lower = text.lowercased()
    guard lower.hasPrefix("@seends") else { return nil }
    let rest = text.dropFirst("@seends".count).trimmingCharacters(in: .whitespacesAndNewlines)
    if rest.isEmpty { return nil }

    let parts = rest.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    guard let first = parts.first else { return nil }

    // Из первого слова вытаскиваем число + возможную валюту ("100$", "110gram", "0.5btc").
    var amountChars = ""
    var unitChars = ""
    var seenDigit = false
    for ch in first {
        if ch.isNumber {
            if unitChars.isEmpty {
                amountChars.append(ch)
                seenDigit = true
            } else {
                unitChars.append(ch)
            }
        } else if (ch == "." || ch == ",") && seenDigit && unitChars.isEmpty && !amountChars.contains(".") {
            amountChars.append(".")
        } else {
            unitChars.append(ch)
        }
    }
    guard seenDigit else { return nil }
    if amountChars.hasSuffix(".") {
        amountChars = String(amountChars.dropLast())
    }

    // Если валюту не приклеили к числу, пробуем взять её следующим токеном.
    var currencyRaw = unitChars
    var modeTokenIndex = 1
    if currencyRaw.isEmpty, parts.count >= 2 {
        currencyRaw = parts[1]
        modeTokenIndex = 2
    }
    let currency = pampGramNormalizeSeendsCurrency(currencyRaw)

    var mode: PampGramSeendsPayload.Mode = .issued
    if parts.count > modeTokenIndex {
        let modeToken = parts[modeTokenIndex].lowercased()
        if modeToken.contains("получ") || modeToken.contains("recei") || modeToken.contains("пришл") || modeToken.contains("пришёл") {
            mode = .received
        }
    }

    return PampGramSeendsPayload(amount: amountChars, currency: currency, mode: mode)
}

private func pampGramNormalizeSeendsCurrency(_ raw: String) -> String {
    let lower = raw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " .,:;!?"))
    switch lower {
    case "", "$", "usd", "usdt", "дол", "долл", "доллар", "долларов":
        return "USDT"
    case "₽", "р", "руб", "рубль", "рублей", "rub":
        return "RUB"
    case "€", "eur", "евро":
        return "EUR"
    case "ton", "тон":
        return "TON"
    case "btc", "биткоин", "bitcoin":
        return "BTC"
    case "eth", "эфир", "ethereum":
        return "ETH"
    case "ltc", "litecoin", "лайткоин":
        return "LTC"
    case "trx", "tron", "трон":
        return "TRX"
    case "usdc":
        return "USDC"
    case "bnb":
        return "BNB"
    case "sol", "solana", "солана":
        return "SOL"
    case "doge":
        return "DOGE"
    case "gram", "грам", "грамм", "грамма", "граммов", "g", "gr", "гр":
        return "GRAM"
    case "pepe", "пепе":
        return "PEPE"
    default:
        return raw.uppercased()
    }
}

private func pampGramRenderCryptoBotCheck(payload: PampGramSeendsPayload) -> UIImage? {
    let size = CGSize(width: 900, height: 1180)
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 2.0
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    return renderer.image { rendererContext in
        let ctx = rendererContext.cgContext

        // Фоновый градиент: синий для чека на отправку, зелёный — для «получено».
        let bgColors: [CGColor]
        switch payload.mode {
        case .issued:
            bgColors = [
                UIColor(red: 0.17, green: 0.59, blue: 0.96, alpha: 1.0).cgColor,
                UIColor(red: 0.10, green: 0.44, blue: 0.86, alpha: 1.0).cgColor
            ]
        case .received:
            bgColors = [
                UIColor(red: 0.22, green: 0.80, blue: 0.50, alpha: 1.0).cgColor,
                UIColor(red: 0.11, green: 0.59, blue: 0.35, alpha: 1.0).cgColor
            ]
        }
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bgColors as CFArray, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }

        // Белая карточка.
        let cardRect = CGRect(x: 60, y: 220, width: size.width - 120, height: size.height - 440)
        let cardPath = UIBezierPath(roundedRect: cardRect, cornerRadius: 36)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 30, color: UIColor(white: 0, alpha: 0.25).cgColor)
        UIColor.white.setFill()
        cardPath.fill()
        ctx.restoreGState()

        // Круглый логотип над карточкой.
        let logoSize: CGFloat = 160
        let logoRect = CGRect(x: (size.width - logoSize) / 2, y: cardRect.minY - logoSize / 2, width: logoSize, height: logoSize)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 6), blur: 18, color: UIColor(white: 0, alpha: 0.35).cgColor)
        UIColor.white.setFill()
        UIBezierPath(ovalIn: logoRect).fill()
        ctx.restoreGState()

        let innerRect = logoRect.insetBy(dx: 14, dy: 14)
        ctx.saveGState()
        ctx.addPath(UIBezierPath(ovalIn: innerRect).cgPath)
        ctx.clip()
        let innerColors: [CGColor] = [
            UIColor(red: 0.14, green: 0.65, blue: 0.98, alpha: 1).cgColor,
            UIColor(red: 0.06, green: 0.42, blue: 0.86, alpha: 1).cgColor
        ]
        if let innerGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: innerColors as CFArray, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(innerGradient, start: innerRect.origin, end: CGPoint(x: innerRect.minX, y: innerRect.maxY), options: [])
        }
        let glyphAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 86, weight: .heavy),
            .foregroundColor: UIColor.white
        ]
        let glyph: NSString = "₿"
        let glyphSize = glyph.size(withAttributes: glyphAttrs)
        glyph.draw(at: CGPoint(x: innerRect.midX - glyphSize.width / 2, y: innerRect.midY - glyphSize.height / 2 - 4), withAttributes: glyphAttrs)
        ctx.restoreGState()

        // Заголовок / подпись.
        let titleText: String
        let buttonText: String
        switch payload.mode {
        case .issued:
            titleText = "💰 Чек"
            buttonText = "Активировать"
        case .received:
            titleText = "✅ Получено"
            buttonText = "В кошелёк"
        }
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 46, weight: .semibold),
            .foregroundColor: UIColor(white: 0.10, alpha: 1)
        ]
        let title: NSString = titleText as NSString
        let titleSize = title.size(withAttributes: titleAttrs)
        title.draw(at: CGPoint(x: cardRect.midX - titleSize.width / 2, y: logoRect.maxY + 30), withAttributes: titleAttrs)

        // Крупная сумма.
        let amountString = "\(payload.amount) \(payload.currency)"
        let amountAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 96, weight: .heavy),
            .foregroundColor: payload.mode == .received
                ? UIColor(red: 0.11, green: 0.59, blue: 0.35, alpha: 1)
                : UIColor(red: 0.09, green: 0.45, blue: 0.86, alpha: 1)
        ]
        let amountNS: NSString = amountString as NSString
        let amountSize = amountNS.size(withAttributes: amountAttrs)
        amountNS.draw(at: CGPoint(x: cardRect.midX - amountSize.width / 2, y: logoRect.maxY + 110), withAttributes: amountAttrs)

        // Разделитель.
        ctx.setStrokeColor(UIColor(white: 0.9, alpha: 1).cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: cardRect.minX + 60, y: logoRect.maxY + 260))
        ctx.addLine(to: CGPoint(x: cardRect.maxX - 60, y: logoRect.maxY + 260))
        ctx.strokePath()

        // «от @CryptoBot».
        let fromAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 30, weight: .regular),
            .foregroundColor: UIColor(white: 0.5, alpha: 1)
        ]
        let fromText: NSString = (payload.mode == .received ? "зачислено от @CryptoBot" : "от @CryptoBot") as NSString
        let fromSize = fromText.size(withAttributes: fromAttrs)
        fromText.draw(at: CGPoint(x: cardRect.midX - fromSize.width / 2, y: logoRect.maxY + 290), withAttributes: fromAttrs)

        // Кнопка.
        let buttonRect = CGRect(x: cardRect.minX + 60, y: cardRect.maxY - 150, width: cardRect.width - 120, height: 92)
        let buttonPath = UIBezierPath(roundedRect: buttonRect, cornerRadius: 22)
        let btnColor: UIColor = payload.mode == .received
            ? UIColor(red: 0.19, green: 0.78, blue: 0.49, alpha: 1)
            : UIColor(red: 0.11, green: 0.52, blue: 0.95, alpha: 1)
        btnColor.setFill()
        buttonPath.fill()
        let btnAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 36, weight: .semibold),
            .foregroundColor: UIColor.white
        ]
        let btnTextNS: NSString = buttonText as NSString
        let btnTextSize = btnTextNS.size(withAttributes: btnAttrs)
        btnTextNS.draw(at: CGPoint(x: buttonRect.midX - btnTextSize.width / 2, y: buttonRect.midY - btnTextSize.height / 2), withAttributes: btnAttrs)

        // Нижняя подпись.
        let footerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 28, weight: .regular),
            .foregroundColor: UIColor(white: 1, alpha: 0.9)
        ]
        let footerText: NSString = "@CryptoBot — Crypto Pay"
        let footerSize = footerText.size(withAttributes: footerAttrs)
        footerText.draw(at: CGPoint(x: (size.width - footerSize.width) / 2, y: size.height - 90), withAttributes: footerAttrs)
    }
}

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

private func pampGramInsertSeendsIncoming(context: AccountContext, peerId: EnginePeer.Id, media: [Media]) -> Signal<EngineMessage.Id?, NoError> {
    return context.account.postbox.transaction { transaction -> EngineMessage.Id? in
        let globallyUniqueId = Int64.random(in: Int64.min ... Int64.max)
        let storeMessage = StoreMessage(
            id: .Partial(peerId, Namespaces.Message.Local),
            customStableId: nil,
            globallyUniqueId: globallyUniqueId,
            groupingKey: nil,
            threadId: nil,
            timestamp: Int32(Date().timeIntervalSince1970),
            flags: StoreMessageFlags.Incoming,
            tags: [],
            globalTags: [],
            localTags: [],
            forwardInfo: nil,
            authorId: peerId,
            text: "",
            attributes: [],
            media: media
        )
        let insertedIds = transaction.addMessages([storeMessage], location: .Random)
        return insertedIds[globallyUniqueId]
    }
}
