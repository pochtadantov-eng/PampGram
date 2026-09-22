import Foundation
import Postbox
import SwiftSignalKit

/// One row in a phantom wallet's own local activity list (separate from, but cross-posted
/// into, the shared `PampGramLocalLedgerStore` — see `PampGramPhantomWalletStore.send`).
public struct PampGramPhantomWalletTransaction: Codable, Equatable, Identifiable {
    public let id: Int64
    public let outgoing: Bool
    public let amountNanos: Int64
    public let comment: String
    public let date: Int32

    public init(id: Int64 = Int64.random(in: 1 ... (Int64.max / 4)), outgoing: Bool, amountNanos: Int64, comment: String, date: Int32 = Int32(Date().timeIntervalSince1970)) {
        self.id = id
        self.outgoing = outgoing
        self.amountNanos = amountNanos
        self.comment = comment
        self.date = date
    }
}

/// Stored half of the two-wallet LARP: "Кошелёк 1"'s balance stays exactly what it always
/// was — `PampGramSettings.fakeTonBalanceNanos`, the pre-existing play-money TON counter, so
/// every screen already reading/editing it (the Подарки settings row, the TON ledger, the
/// gift-driven fake transaction rows) keeps working unchanged. This struct only adds what
/// didn't exist before: a second local wallet, a cosmetic address for each, and each
/// wallet's own activity list. See `PampGramPhantomWalletStore.wallets` for the combined view.
public struct PampGramWalletState: Codable, Equatable {
    public var firstWalletAddress: String
    public var firstWalletTransactions: [PampGramPhantomWalletTransaction]
    public var secondWalletAddress: String
    public var secondWalletBalanceNanos: Int64
    public var secondWalletTransactions: [PampGramPhantomWalletTransaction]
    public var selectedWalletId: Int32

    public static var `default`: PampGramWalletState {
        return PampGramWalletState(
            firstWalletAddress: generatePampGramPhantomTonAddress(),
            firstWalletTransactions: [],
            secondWalletAddress: generatePampGramPhantomTonAddress(),
            secondWalletBalanceNanos: 0,
            secondWalletTransactions: [],
            selectedWalletId: 1
        )
    }

    public init(firstWalletAddress: String, firstWalletTransactions: [PampGramPhantomWalletTransaction], secondWalletAddress: String, secondWalletBalanceNanos: Int64, secondWalletTransactions: [PampGramPhantomWalletTransaction], selectedWalletId: Int32) {
        self.firstWalletAddress = firstWalletAddress
        self.firstWalletTransactions = firstWalletTransactions
        self.secondWalletAddress = secondWalletAddress
        self.secondWalletBalanceNanos = secondWalletBalanceNanos
        self.secondWalletTransactions = secondWalletTransactions
        self.selectedWalletId = selectedWalletId
    }

    /// Decoded field by field, like every other PampGram state struct: a newly-added field
    /// must never throw away an existing user's wallets on upgrade.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PampGramWalletState.default
        self.firstWalletAddress = try c.decodeIfPresent(String.self, forKey: .firstWalletAddress) ?? d.firstWalletAddress
        self.firstWalletTransactions = try c.decodeIfPresent([PampGramPhantomWalletTransaction].self, forKey: .firstWalletTransactions) ?? d.firstWalletTransactions
        self.secondWalletAddress = try c.decodeIfPresent(String.self, forKey: .secondWalletAddress) ?? d.secondWalletAddress
        self.secondWalletBalanceNanos = try c.decodeIfPresent(Int64.self, forKey: .secondWalletBalanceNanos) ?? d.secondWalletBalanceNanos
        self.secondWalletTransactions = try c.decodeIfPresent([PampGramPhantomWalletTransaction].self, forKey: .secondWalletTransactions) ?? d.secondWalletTransactions
        self.selectedWalletId = try c.decodeIfPresent(Int32.self, forKey: .selectedWalletId) ?? d.selectedWalletId
    }
}

/// A combined, read-only view of one phantom wallet — "Кошелёк 1"'s balance folded in from
/// `PampGramSettings.fakeTonBalanceNanos`, everything else from `PampGramWalletState` — so
/// the UI layer can treat both wallets uniformly instead of branching on which one is which.
public struct PampGramPhantomWalletView: Equatable {
    public let id: Int32
    public let title: String
    public let address: String
    public let balanceNanos: Int64
    public let transactions: [PampGramPhantomWalletTransaction]
    public let isSelected: Bool
}

/// A cosmetic, TON-address-shaped string for display only: the real user-friendly address
/// layout (1 flag byte + 1 workchain byte + 32 "account id" bytes + 2 checksum bytes, all
/// base64url, 48 characters) so it reads exactly like a real TonKeeper address at a glance —
/// `0x51 0x00` as the first two bytes lands on the same "UQ" prefix a real non-bounceable
/// mainnet address shows. But the last 2 bytes here are random, not the real CRC16-CCITT of
/// the rest, and the 32 "account id" bytes are random too, not derived from any real key
/// PampGram holds (it holds none). Every real TON wallet checks that checksum before letting
/// someone pay an address, so this string fails that check and can never be used to receive
/// real TON — nobody can lose real funds by sending to it, and there is no key anywhere that
/// could spend from it. No network call is made to produce it. See PampGramSettings
/// .fakeTonBalanceNanos and mod/README.md's "Главное правило" for the same rule applied to
/// the rest of PampGram.
public func generatePampGramPhantomTonAddress() -> String {
    var bytes: [UInt8] = [0x51, 0x00]
    bytes.reserveCapacity(36)
    for _ in 0 ..< 34 {
        bytes.append(UInt8.random(in: 0 ... 255))
    }
    let base64 = Data(bytes).base64EncodedString()
    return base64
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

/// Keeps a wallet's local activity list from growing without bound, same reasoning as
/// `PampGramLocalLedgerStore.add`'s 5000-row cap, just smaller: this is a per-wallet list
/// inside one Postbox preferences entry, not the shared cross-currency ledger.
private func pampGramCappedWalletTransactions(_ transactions: [PampGramPhantomWalletTransaction]) -> [PampGramPhantomWalletTransaction] {
    if transactions.count > 500 {
        return Array(transactions.prefix(500))
    }
    return transactions
}

public enum PampGramPhantomWalletStore {
    public static func rawState(transaction: Transaction) -> PampGramWalletState {
        if let existing = transaction.getPreferencesEntry(key: PampGramPreferencesKeys.phantomWallet)?.get(PampGramWalletState.self) {
            return existing
        }
        // First-ever read: generate both cosmetic addresses once and persist immediately, so
        // they stay stable — nothing here regenerates them on a later read.
        let seeded = PampGramWalletState.default
        transaction.setPreferencesEntry(key: PampGramPreferencesKeys.phantomWallet, value: PreferencesEntry(seeded))
        return seeded
    }

    public static func update(transaction: Transaction, _ f: (PampGramWalletState) -> PampGramWalletState) {
        let updated = f(self.rawState(transaction: transaction))
        transaction.setPreferencesEntry(key: PampGramPreferencesKeys.phantomWallet, value: PreferencesEntry(updated))
    }

    public static func signal(postbox: Postbox) -> Signal<PampGramWalletState, NoError> {
        return postbox.preferencesView(keys: [PampGramPreferencesKeys.phantomWallet])
        |> map { view -> PampGramWalletState in
            return view.values[PampGramPreferencesKeys.phantomWallet]?.get(PampGramWalletState.self) ?? PampGramWalletState.default
        }
        |> distinctUntilChanged
    }

    /// Ensures the wallet-state entry exists (and its addresses are therefore persisted)
    /// before anything reads the live `walletsSignal` below — that signal has no transaction
    /// of its own to seed through, so a screen should run this once, e.g. right after
    /// pushing, the same one-shot pattern `pampGramSettingsController` uses for its ban check.
    public static func ensureSeeded(postbox: Postbox) -> Signal<Never, NoError> {
        return postbox.transaction { transaction -> Void in
            let _ = self.rawState(transaction: transaction)
        }
        |> ignoreValues
    }

    public static func wallets(transaction: Transaction) -> [PampGramPhantomWalletView] {
        let state = self.rawState(transaction: transaction)
        let firstBalance = PampGramCore.rawSettings(transaction: transaction).fakeTonBalanceNanos
        return self.combinedWallets(state: state, firstBalanceNanos: firstBalance)
    }

    public static func walletsSignal(postbox: Postbox) -> Signal<[PampGramPhantomWalletView], NoError> {
        return combineLatest(self.signal(postbox: postbox), PampGramCore.rawSettingsSignal(postbox: postbox))
        |> map { state, settings -> [PampGramPhantomWalletView] in
            return self.combinedWallets(state: state, firstBalanceNanos: settings.fakeTonBalanceNanos)
        }
    }

    private static func combinedWallets(state: PampGramWalletState, firstBalanceNanos: Int64) -> [PampGramPhantomWalletView] {
        return [
            PampGramPhantomWalletView(id: 1, title: "Кошелёк 1", address: state.firstWalletAddress, balanceNanos: firstBalanceNanos, transactions: state.firstWalletTransactions, isSelected: state.selectedWalletId == 1),
            PampGramPhantomWalletView(id: 2, title: "Кошелёк 2", address: state.secondWalletAddress, balanceNanos: state.secondWalletBalanceNanos, transactions: state.secondWalletTransactions, isSelected: state.selectedWalletId != 1)
        ]
    }

    public static func selectWallet(transaction: Transaction, id: Int32) {
        self.update(transaction: transaction) { s in
            var s = s
            s.selectedWalletId = id
            return s
        }
    }

    /// Moves `amountNanos` from whichever wallet is currently selected to the other one.
    /// Both are local phantom wallets PampGram itself stores — there is no third-party
    /// recipient and nothing is ever sent over the network. Returns false (no change made)
    /// for a non-positive amount or an insufficient source balance.
    ///
    /// The debit/credit on "Кошелёк 1" is additionally posted through
    /// `PampGramLocalLedgerStore` with `kind: .transfer` — the operation kind already
    /// reserved for exactly this — so it keeps appearing in the existing TON ledger/history
    /// screen and the Подарки balance row exactly as before. "Кошелёк 2" has no such mirror:
    /// it is new money this screen itself introduces, tracked only in its own activity list.
    @discardableResult
    public static func send(transaction: Transaction, amountNanos: Int64, comment: String) -> Bool {
        guard amountNanos > 0 else {
            return false
        }
        let state = self.rawState(transaction: transaction)
        let firstBalance = PampGramCore.rawSettings(transaction: transaction).fakeTonBalanceNanos
        let fromIsFirst = state.selectedWalletId == 1
        let sourceBalance = fromIsFirst ? firstBalance : state.secondWalletBalanceNanos
        guard sourceBalance >= amountNanos else {
            return false
        }

        let date = Int32(Date().timeIntervalSince1970)
        let outgoingEntry = PampGramPhantomWalletTransaction(outgoing: true, amountNanos: amountNanos, comment: comment, date: date)
        let incomingEntry = PampGramPhantomWalletTransaction(outgoing: false, amountNanos: amountNanos, comment: comment, date: date)

        if fromIsFirst {
            PampGramLocalLedgerStore.addAndApply(transaction: transaction, currency: .ton, kind: .transfer, amount: -amountNanos, title: "Перевод на «Кошелёк 2»", details: comment)
            self.update(transaction: transaction) { s in
                var s = s
                s.secondWalletBalanceNanos += amountNanos
                s.firstWalletTransactions = pampGramCappedWalletTransactions([outgoingEntry] + s.firstWalletTransactions)
                s.secondWalletTransactions = pampGramCappedWalletTransactions([incomingEntry] + s.secondWalletTransactions)
                return s
            }
        } else {
            PampGramLocalLedgerStore.addAndApply(transaction: transaction, currency: .ton, kind: .transfer, amount: amountNanos, title: "Перевод с «Кошелёк 2»", details: comment)
            self.update(transaction: transaction) { s in
                var s = s
                s.secondWalletBalanceNanos -= amountNanos
                s.secondWalletTransactions = pampGramCappedWalletTransactions([outgoingEntry] + s.secondWalletTransactions)
                s.firstWalletTransactions = pampGramCappedWalletTransactions([incomingEntry] + s.firstWalletTransactions)
                return s
            }
        }
        return true
    }

    /// Adds new play-money TON to one wallet — "Кошелёк 1" through the shared ledger (so it
    /// also shows there, like every other top-up in the app), "Кошелёк 2" purely locally.
    public static func topUp(transaction: Transaction, walletId: Int32, amountNanos: Int64) {
        guard amountNanos > 0 else {
            return
        }
        let date = Int32(Date().timeIntervalSince1970)
        let entry = PampGramPhantomWalletTransaction(outgoing: false, amountNanos: amountNanos, comment: "Пополнение", date: date)
        if walletId == 1 {
            PampGramLocalLedgerStore.addAndApply(transaction: transaction, currency: .ton, kind: .topUp, amount: amountNanos, title: "Пополнение «Кошелёк 1»")
            self.update(transaction: transaction) { s in
                var s = s
                s.firstWalletTransactions = pampGramCappedWalletTransactions([entry] + s.firstWalletTransactions)
                return s
            }
        } else {
            self.update(transaction: transaction) { s in
                var s = s
                s.secondWalletBalanceNanos += amountNanos
                s.secondWalletTransactions = pampGramCappedWalletTransactions([entry] + s.secondWalletTransactions)
                return s
            }
        }
    }
}
