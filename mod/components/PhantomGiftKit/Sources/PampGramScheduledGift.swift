import Foundation
import Postbox
import TelegramCore
import PampGramCore

/// What a scheduled "Подарок мне" actually materializes into once its time comes — either a
/// catalog/resale `StarGift` (the original case) or a Telegram Premium subscription gifted
/// through the same fake flow (see `PampGramPhantomGiftManager.sendFakePremiumGift`/
/// `receiveFakePremiumGift`). `CurrencyAmount` can't represent Premium's price: it's always
/// Stars or TON (`CurrencyAmount.Currency`), while a Premium gift's real-currency leg is
/// priced in whatever Telegram's own catalog or the App Store/Google Play quotes (almost
/// always rubles for this account) — so `.premium` carries its own raw currency code + amount
/// instead of reusing `CurrencyAmount`.
public enum PampGramScheduledGiftPayload: Codable, Equatable {
    case starGift(StarGift, price: CurrencyAmount)
    case premium(months: Int32, currency: String, amount: Int64)
}

/// "Подарок мне" with a delay: the local, no-server replacement for the old P2P relay (which
/// depended on a shared Cloudflare Worker to deliver gifts between two devices — unreliable in
/// practice, and removed). Instead, a delayed "Подарок мне" just schedules the exact same
/// local materialization (`PampGramPhantomGiftManager.receiveGenericGift`/`receiveUniqueGift`/
/// `receiveFakePremiumGift`) for later, on this same device, picked up by
/// `PampGramScheduledGiftRuntime`. Nothing here ever touches a network.
public struct PampGramScheduledGift: Codable, Equatable, Identifiable {
    public let id: Int64
    public let peerId: EnginePeer.Id
    public let payload: PampGramScheduledGiftPayload
    /// Caption typed in the send composer, if any — entities aren't carried over (a scheduled
    /// gift's materialized message is always plain text), an accepted simplification since a
    /// "Подарок мне" caption is rarely formatted.
    public let text: String?
    public let fireDate: Int32

    public init(id: Int64, peerId: EnginePeer.Id, payload: PampGramScheduledGiftPayload, text: String?, fireDate: Int32) {
        self.id = id
        self.peerId = peerId
        self.payload = payload
        self.text = text
        self.fireDate = fireDate
    }
}

private struct PampGramScheduledGiftList: Codable {
    var gifts: [PampGramScheduledGift]
}

/// Persistent, entirely local storage for pending scheduled gifts — same Postbox-preferences
/// mechanism as `PampGramPhantomGiftStore`, under its own reserved key so it survives app
/// restarts (the whole point: a gift scheduled for "завтра" has to still be there tomorrow).
public enum PampGramScheduledGiftStore {
    public static func all(transaction: Transaction) -> [PampGramScheduledGift] {
        return transaction.getPreferencesEntry(key: PampGramPreferencesKeys.scheduledGifts)?.get(PampGramScheduledGiftList.self)?.gifts ?? []
    }

    public static func add(transaction: Transaction, gift: PampGramScheduledGift) {
        transaction.updatePreferencesEntry(key: PampGramPreferencesKeys.scheduledGifts, { entry in
            var list = entry?.get(PampGramScheduledGiftList.self) ?? PampGramScheduledGiftList(gifts: [])
            list.gifts.append(gift)
            return PreferencesEntry(list)
        })
    }

    public static func remove(transaction: Transaction, id: Int64) {
        transaction.updatePreferencesEntry(key: PampGramPreferencesKeys.scheduledGifts, { entry in
            var list = entry?.get(PampGramScheduledGiftList.self) ?? PampGramScheduledGiftList(gifts: [])
            list.gifts.removeAll(where: { $0.id == id })
            return PreferencesEntry(list)
        })
    }
}

/// "Подарок мне"'s send-later choices — label, and seconds from now. `nil` means deliver right
/// away, the original (and still default) behaviour.
public enum PampGramGiftDelay: CaseIterable {
    case immediate
    case fiveMinutes
    case fifteenMinutes
    case oneHour
    case tomorrow

    public var title: String {
        switch self {
        case .immediate:
            return "Сразу"
        case .fiveMinutes:
            return "Через 5 минут"
        case .fifteenMinutes:
            return "Через 15 минут"
        case .oneHour:
            return "Через час"
        case .tomorrow:
            return "Завтра"
        }
    }

    public var seconds: Int32? {
        switch self {
        case .immediate:
            return nil
        case .fiveMinutes:
            return 5 * 60
        case .fifteenMinutes:
            return 15 * 60
        case .oneHour:
            return 60 * 60
        case .tomorrow:
            return 24 * 60 * 60
        }
    }
}
