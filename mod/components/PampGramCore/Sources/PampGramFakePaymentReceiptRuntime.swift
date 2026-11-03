import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import AccountContext

/// «Генератор платёжных чеков» — создаёт реалистичные чеки об оплате Stars, TON, Premium.
///
/// Выглядит как настоящий чек от @StarsBot / системы платежей Telegram:
/// «Вы успешно перевели 50 000 Stars» с деталями транзакции, хешем, датой.
/// Локально — ничего никуда не отправляется.
///
/// Integration point (в патче):
///
/// 1. Контекстное меню чата → «Фейк чек»:
///
///    ```swift
///    items.append(.action(ContextMenuActionItem(
///        text: "Фейк чек",
///        icon: { theme in generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Reactions"), color: theme.contextMenu.primaryColor) },
///        action: { c, _ in
///            c?.dismiss(completion: {
///                // Показать выбор типа чека и суммы, затем:
///                PampGramFakePaymentReceiptRuntime.shared.generateReceipt(
///                    context: context,
///                    peerId: peerId,
///                    type: .starsTransfer(amount: 50000)
///                )
///            })
///        }
///    )))
///    ```
///
/// 2. Чек вставляется как локальное сообщение с форматированным текстом, имитирующим
///    настоящий платёжный чек Telegram.
public final class PampGramFakePaymentReceiptRuntime {
    public static let shared = PampGramFakePaymentReceiptRuntime()

    public enum ReceiptType {
        case starsTransfer(amount: Int64)
        case tonTransfer(amount: Double)
        case premiumGift(months: Int)
        case giftPurchase(name: String, stars: Int64)
    }

    private init() {}

    /// Генерирует фейковый платёжный чек и вставляет в чат как локальное сообщение.
    public func generateReceipt(context: AccountContext, peerId: PeerId, type: ReceiptType) {
        let text = formatReceipt(type: type)

        let _ = enqueueMessages(
            account: context.account,
            peerId: peerId,
            messages: [
                .message(
                    text: text,
                    attributes: [],
                    inlineStickers: [:],
                    mediaReference: nil,
                    threadId: nil,
                    replyToMessageId: nil,
                    replyToStoryId: nil,
                    localGroupingKey: nil,
                    correlationId: nil,
                    bubbleUpEmojiOrStickersets: []
                )
            ]
        ).start()
    }

    private func formatReceipt(type: ReceiptType) -> String {
        let txHash = generateTransactionHash()
        let dateStr = formatCurrentDate()

        switch type {
        case let .starsTransfer(amount):
            let formatted = formatNumber(amount)
            return """
            ⭐️ Перевод Stars

            Вы успешно перевели \(formatted) Stars

            Транзакция: \(txHash)
            Дата: \(dateStr)
            Статус: ✅ Подтверждено
            Комиссия: 0 Stars
            """

        case let .tonTransfer(amount):
            let formatted = String(format: "%.2f", amount)
            return """
            💎 Перевод TON

            Вы успешно перевели \(formatted) TON

            Транзакция: \(txHash)
            Дата: \(dateStr)
            Статус: ✅ Подтверждено
            Сеть: TON Blockchain
            Комиссия: 0.01 TON
            """

        case let .premiumGift(months):
            let word: String
            switch months {
            case 1: word = "1 месяц"
            case 3: word = "3 месяца"
            case 6: word = "6 месяцев"
            case 12: word = "12 месяцев"
            default: word = "\(months) мес."
            }
            return """
            ⭐️ Telegram Premium

            Вы подарили Telegram Premium на \(word)

            Транзакция: \(txHash)
            Дата: \(dateStr)
            Статус: ✅ Активировано
            """

        case let .giftPurchase(name, stars):
            let formatted = formatNumber(stars)
            return """
            🎁 Покупка подарка

            Вы приобрели «\(name)» за \(formatted) Stars

            Транзакция: \(txHash)
            Дата: \(dateStr)
            Статус: ✅ Доставлено
            """
        }
    }

    private func generateTransactionHash() -> String {
        let chars = "0123456789abcdef"
        return String((0..<16).map { _ in chars.randomElement()! })
    }

    private func formatCurrentDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        formatter.locale = Locale(identifier: "ru_RU")
        return formatter.string(from: Date())
    }

    private func formatNumber(_ value: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
