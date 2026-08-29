import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import AccountContext
import PampGramCore

private struct PampGramPhantomGiftList: Codable {
    var gifts: [PampGramPhantomGift]
}

/// Persistent, entirely local storage for Phantom Gifts. Backed by Postbox's own
/// `PreferencesEntry` mechanism under the mod's reserved key range (see
/// `PampGramPreferencesKeys`), so it survives app restarts for free and needs no separate
/// file or database of its own. Nothing in this file ever touches `account.network` —
/// every operation is a local Postbox transaction.
///
/// The fake Stars balance lives in `PampGramSettings` rather than here, so the PampGram
/// settings screen and the gift flow read and write exactly one value.
public enum PampGramPhantomGiftStore {
    public static var defaultFakeStarsBalance: Int64 {
        return PampGramSettings.defaultFakeStarsBalance
    }

    public static func allGifts(transaction: Transaction) -> [PampGramPhantomGift] {
        return transaction.getPreferencesEntry(key: PampGramPreferencesKeys.phantomGifts)?.get(PampGramPhantomGiftList.self)?.gifts ?? []
    }

    public static func gifts(transaction: Transaction, peerId: EnginePeer.Id) -> [PampGramPhantomGift] {
        return self.allGifts(transaction: transaction).filter { $0.peerId == peerId }
    }

    public static func add(transaction: Transaction, gift: PampGramPhantomGift) {
        transaction.updatePreferencesEntry(key: PampGramPreferencesKeys.phantomGifts, { entry in
            var list = entry?.get(PampGramPhantomGiftList.self) ?? PampGramPhantomGiftList(gifts: [])
            list.gifts.append(gift)
            return PreferencesEntry(list)
        })
    }

    public static func remove(transaction: Transaction, id: Int64) {
        transaction.updatePreferencesEntry(key: PampGramPreferencesKeys.phantomGifts, { entry in
            var list = entry?.get(PampGramPhantomGiftList.self) ?? PampGramPhantomGiftList(gifts: [])
            list.gifts.removeAll(where: { $0.id == id })
            return PreferencesEntry(list)
        })
    }

    public static func fakeStarsBalance(transaction: Transaction) -> Int64 {
        return PampGramCore.settings(transaction: transaction).fakeStarsBalance
    }

    public static func setFakeStarsBalance(transaction: Transaction, stars: Int64) {
        PampGramCore.updateSettings(transaction: transaction, { settings in
            var settings = settings
            settings.fakeStarsBalance = stars
            return settings
        })
    }

    public static func fakeTonBalanceNanos(transaction: Transaction) -> Int64 {
        return PampGramCore.settings(transaction: transaction).fakeTonBalanceNanos
    }

    public static func setFakeTonBalanceNanos(transaction: Transaction, nanos: Int64) {
        PampGramCore.updateSettings(transaction: transaction, { settings in
            var settings = settings
            settings.fakeTonBalanceNanos = nanos
            return settings
        })
    }

    /// Live fake balance, for display (e.g. the "⭐ 50 000" label in the composer).
    public static func fakeStarsBalanceSignal(context: AccountContext) -> Signal<Int64, NoError> {
        return PampGramCore.settingsSignal(postbox: context.account.postbox)
        |> map { $0.fakeStarsBalance }
        |> distinctUntilChanged
    }

    /// Live list of every Phantom Gift on this device, newest first.
    public static func allGiftsSignal(context: AccountContext) -> Signal<[PampGramPhantomGift], NoError> {
        return context.account.postbox.preferencesView(keys: [PampGramPreferencesKeys.phantomGifts])
        |> map { view -> [PampGramPhantomGift] in
            let gifts = view.values[PampGramPreferencesKeys.phantomGifts]?.get(PampGramPhantomGiftList.self)?.gifts ?? []
            return gifts.sorted(by: { $0.date > $1.date })
        }
    }
}
