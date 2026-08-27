import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import AccountContext

/// Reserved, PampGram-private preference key range. Deliberately NOT added to the shared
/// `ApplicationSpecificPreferencesKeys` enum in TelegramUIPreferences — these two keys live
/// entirely inside this mod's own module so there's no chance of colliding with a real key
/// upstream adds later, and no shared file to merge-conflict on.
private func pampGramPreferencesKey(_ value: Int32) -> ValueBoxKey {
    let key = ValueBoxKey(length: 4)
    key.setInt32(0, value: value)
    return key
}

private let phantomGiftsKey = pampGramPreferencesKey(900_100)
private let fakeStarsBalanceKey = pampGramPreferencesKey(900_101)

private struct PampGramPhantomGiftList: Codable {
    var gifts: [PampGramPhantomGift]
}

private struct PampGramFakeStarsBalanceValue: Codable {
    var stars: Int64
}

/// Persistent, entirely local storage for Phantom Gifts and the fake Stars balance.
/// Backed by Postbox's own `PreferencesEntry` mechanism (the same one used for e.g. media
/// auto-save settings — see `submodules/TelegramUI/Sources/StoreDownloadedMedia.swift`), so
/// it survives app restarts for free and needs no separate file/database of its own.
/// Nothing in this file ever touches `account.network` — every operation is a local Postbox
/// transaction.
public enum PampGramPhantomGiftStore {
    public static let defaultFakeStarsBalance: Int64 = 50_000

    public static func allGifts(transaction: Transaction) -> [PampGramPhantomGift] {
        return transaction.getPreferencesEntry(key: phantomGiftsKey)?.get(PampGramPhantomGiftList.self)?.gifts ?? []
    }

    public static func gifts(transaction: Transaction, peerId: EnginePeer.Id) -> [PampGramPhantomGift] {
        return self.allGifts(transaction: transaction).filter { $0.peerId == peerId }
    }

    public static func add(transaction: Transaction, gift: PampGramPhantomGift) {
        transaction.updatePreferencesEntry(key: phantomGiftsKey, { entry in
            var list = entry?.get(PampGramPhantomGiftList.self) ?? PampGramPhantomGiftList(gifts: [])
            list.gifts.append(gift)
            return PreferencesEntry(list)
        })
    }

    public static func remove(transaction: Transaction, id: Int64) {
        transaction.updatePreferencesEntry(key: phantomGiftsKey, { entry in
            var list = entry?.get(PampGramPhantomGiftList.self) ?? PampGramPhantomGiftList(gifts: [])
            list.gifts.removeAll(where: { $0.id == id })
            return PreferencesEntry(list)
        })
    }

    public static func fakeStarsBalance(transaction: Transaction) -> Int64 {
        return transaction.getPreferencesEntry(key: fakeStarsBalanceKey)?.get(PampGramFakeStarsBalanceValue.self)?.stars ?? self.defaultFakeStarsBalance
    }

    public static func setFakeStarsBalance(transaction: Transaction, stars: Int64) {
        transaction.setPreferencesEntry(key: fakeStarsBalanceKey, value: PreferencesEntry(PampGramFakeStarsBalanceValue(stars: stars)))
    }

    /// One-shot read of the fake balance, for display (e.g. the "⭐ 50 000" label in the
    /// composer). Not a live subscription — this key isn't registered with
    /// `TelegramEngine.EngineData` (that registry lives in TelegramUIPreferences, which we
    /// deliberately don't touch — see the comment above), so callers re-read after any
    /// action that might change the balance instead of observing it continuously.
    public static func fakeStarsBalanceSignal(context: AccountContext) -> Signal<Int64, NoError> {
        return context.account.postbox.transaction { transaction in
            return self.fakeStarsBalance(transaction: transaction)
        }
    }
}
