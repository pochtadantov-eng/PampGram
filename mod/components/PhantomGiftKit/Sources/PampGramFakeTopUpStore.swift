import Foundation
import Postbox
import SwiftSignalKit
import AccountContext
import PampGramCore

/// One local "top-up" — the play-money star (or TON) purchases PampGram's own "Купить звёзды"
/// screen makes against the local ruble card. Kept separately from the Phantom Gift store
/// because a top-up isn't a gift: it credits a balance rather than producing a chat card, but
/// it still has to show up in the (merged) Stars/TON transaction history as a пополнение, next
/// to the gift debits/credits. Persisted in Postbox under the mod's reserved key range, so it
/// survives restarts like everything else PampGram stores; never touches the network or the
/// real Stars balance.
public struct PampGramFakeTopUp: Codable, Equatable {
    public var id: Int64
    /// Which balance this credited: `false` = fake Stars, `true` = fake TON. Star purchases are
    /// always `false`; the field exists so the same store can back a TON top-up later.
    public var isTon: Bool
    /// Amount credited — whole Stars when `!isTon`, nanotons when `isTon`.
    public var amount: Int64
    /// What was "paid" for it, in ruble kopecks — kept only for display/receipts.
    public var fiatKopecks: Int64
    public var date: Int32

    public init(id: Int64, isTon: Bool, amount: Int64, fiatKopecks: Int64, date: Int32) {
        self.id = id
        self.isTon = isTon
        self.amount = amount
        self.fiatKopecks = fiatKopecks
        self.date = date
    }
}

private struct PampGramFakeTopUpList: Codable {
    var topUps: [PampGramFakeTopUp]
}

public enum PampGramFakeTopUpStore {
    public static func all(transaction: Transaction) -> [PampGramFakeTopUp] {
        return transaction.getPreferencesEntry(key: PampGramPreferencesKeys.fakeTopUps)?.get(PampGramFakeTopUpList.self)?.topUps ?? []
    }

    public static func add(transaction: Transaction, topUp: PampGramFakeTopUp) {
        transaction.updatePreferencesEntry(key: PampGramPreferencesKeys.fakeTopUps, { entry in
            var list = entry?.get(PampGramFakeTopUpList.self) ?? PampGramFakeTopUpList(topUps: [])
            list.topUps.append(topUp)
            return PreferencesEntry(list)
        })
    }

    public static func removeAll(transaction: Transaction) {
        transaction.setPreferencesEntry(key: PampGramPreferencesKeys.fakeTopUps, value: PreferencesEntry(PampGramFakeTopUpList(topUps: [])))
    }

    /// Convenience for the purchase flow: append one top-up in its own transaction.
    public static func record(context: AccountContext, isTon: Bool, amount: Int64, fiatKopecks: Int64) -> Signal<Never, NoError> {
        return context.account.postbox.transaction { transaction in
            self.add(transaction: transaction, topUp: PampGramFakeTopUp(
                id: Int64.random(in: 1...Int64.max),
                isTon: isTon,
                amount: amount,
                fiatKopecks: fiatKopecks,
                date: Int32(Date().timeIntervalSince1970)
            ))
        }
        |> ignoreValues
    }

    /// Live list of every top-up on this device, newest first.
    public static func allSignal(context: AccountContext) -> Signal<[PampGramFakeTopUp], NoError> {
        return context.account.postbox.preferencesView(keys: [PampGramPreferencesKeys.fakeTopUps])
        |> map { view -> [PampGramFakeTopUp] in
            let topUps = view.values[PampGramPreferencesKeys.fakeTopUps]?.get(PampGramFakeTopUpList.self)?.topUps ?? []
            return topUps.sorted(by: { $0.date > $1.date })
        }
    }
}
