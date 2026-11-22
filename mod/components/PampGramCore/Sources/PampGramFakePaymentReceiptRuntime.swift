import Foundation
import Postbox
import SwiftSignalKit

public final class PampGramFakePaymentReceiptRuntime {
    public static let shared = PampGramFakePaymentReceiptRuntime()

    public enum ReceiptType {
        case starsTransfer(amount: Int64)
        case tonTransfer(amount: Double)
        case premiumGift(months: Int)
        case giftPurchase(name: String, stars: Int64)
    }

    public var enqueueMessageHandler: ((_ peerId: PeerId, _ text: String) -> Void)?

    private init() {}

    public func generateReceipt(peerId: PeerId, type: ReceiptType) {
        let text = formatReceipt(type: type)
        enqueueMessageHandler?(peerId, text)
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
