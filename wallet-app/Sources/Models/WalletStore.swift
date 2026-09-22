import Foundation
import Combine

/// The app's one source of truth: two local wallets, persisted to `UserDefaults` as JSON.
/// No networking, no keychain, no real wallet SDK — a "send" is just this app moving a
/// number from one stored wallet to the other and appending two activity rows.
final class WalletStore: ObservableObject {
    @Published private(set) var state: WalletState

    private let defaultsKey = "com.pampgram.wallet.state"

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(WalletState.self, from: data) {
            self.state = decoded
        } else {
            self.state = WalletState.fresh()
        }
    }

    var selectedWallet: Wallet {
        state.wallets.first(where: { $0.id == state.selectedWalletId }) ?? state.wallets[0]
    }

    var otherWallet: Wallet? {
        state.wallets.first(where: { $0.id != state.selectedWalletId })
    }

    func selectWallet(id: UUID) {
        state.selectedWalletId = id
        persist()
    }

    /// Moves `amountNanos` from the selected wallet to the other one. Both wallets are
    /// local to this app — there is no third-party recipient and nothing is ever sent over
    /// a network. Returns false (no change made) for a non-positive amount or a balance
    /// that can't cover it.
    @discardableResult
    func send(amountNanos: Int64) -> Bool {
        guard amountNanos > 0 else {
            return false
        }
        guard let fromIndex = state.wallets.firstIndex(where: { $0.id == state.selectedWalletId }) else {
            return false
        }
        guard let toIndex = state.wallets.firstIndex(where: { $0.id != state.selectedWalletId }) else {
            return false
        }
        guard state.wallets[fromIndex].balanceNanos >= amountNanos else {
            return false
        }

        let date = Date()
        state.wallets[fromIndex].balanceNanos -= amountNanos
        state.wallets[toIndex].balanceNanos += amountNanos
        state.wallets[fromIndex].transactions.insert(WalletTransaction(outgoing: true, amountNanos: amountNanos, date: date), at: 0)
        state.wallets[toIndex].transactions.insert(WalletTransaction(outgoing: false, amountNanos: amountNanos, date: date), at: 0)
        persist()
        return true
    }

    /// Adds new play-money TON to the selected wallet — there is no real money behind this
    /// either, it's the same kind of manual balance edit the rest of the app already is.
    func topUp(amountNanos: Int64) {
        guard amountNanos > 0 else {
            return
        }
        guard let index = state.wallets.firstIndex(where: { $0.id == state.selectedWalletId }) else {
            return
        }
        state.wallets[index].balanceNanos += amountNanos
        state.wallets[index].transactions.insert(WalletTransaction(outgoing: false, amountNanos: amountNanos, date: Date()), at: 0)
        persist()
    }

    func resetAll() {
        state = WalletState.fresh()
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
