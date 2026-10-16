import Foundation
import Postbox
import SwiftSignalKit

/// What gets pushed to/restored from the server by `PampGramLedgerSyncRuntime` — the fake
/// Stars/TON balance plus the full local operations list, the same two pieces of state
/// `PampGramLocalLedgerStore.addAndApply` always changes together (see its own doc comment for
/// why those two can never drift apart locally; this is that same pair, just also mirrored off
/// this one device).
public struct PampGramLedgerSyncPayload: Codable {
    public let starsBalance: Int64
    public let tonBalanceNanos: Int64
    public let operations: [PampGramLocalOperation]

    public init(starsBalance: Int64, tonBalanceNanos: Int64, operations: [PampGramLocalOperation]) {
        self.starsBalance = starsBalance
        self.tonBalanceNanos = tonBalanceNanos
        self.operations = operations
    }
}

/// Backs the fake Stars/TON balance and the full local operations history up to PampGram's
/// server, tied to this Telegram account's id, so they survive the one thing purely local
/// Postbox storage never can on its own — deleting and reinstalling the app (iOS wipes local
/// storage along with it). Switching tiers or turning a feature off already never touched this
/// data locally (`allFeaturesOff()`/`withGiftsVisualsOff()` only gate *display*, see
/// `PampGramSettings.swift`), so nothing extra was needed there. Started once per account at
/// `AccountContextImpl.init`, same pattern as every other `*Runtime`/`*Display` class here.
///
/// **Push**: any change to the local ledger (`PampGramLocalLedgerStore.signal` firing past its
/// first, subscription-time emission — see `isFirstLedgerEmission` below) schedules a push 4
/// seconds later of the *complete* current state to `/sync-ledger`, debounced so a burst of
/// edits collapses into one request instead of one per operation.
///
/// **Restore**: once, at start, only if this device's local ledger is still completely empty —
/// a fresh install/reinstall, or an account that's genuinely never done anything yet (either
/// way, restoring is safe: the second case just restores nothing, since the server has nothing
/// either). Fetches whatever this account last pushed from any device and writes it into this
/// device's own Postbox, re-checking "still empty" right before writing in case real local
/// activity happened while the network round trip was in flight — restoring must never clobber
/// activity that just actually happened on this device. A device with existing local history
/// never fetches from the server at all; from then on it's push-only.
public final class PampGramLedgerSyncRuntime {
    public static let shared = PampGramLedgerSyncRuntime()

    private let lock = NSLock()
    private var startedAccounts: Set<Int64> = []
    private var disposables: [Int64: Disposable] = [:]
    private var pushTimers: [Int64: SwiftSignalKit.Timer] = [:]

    private init() {
    }

    public func start(accountKey: Int64, postbox: Postbox) {
        self.lock.lock()
        if self.startedAccounts.contains(accountKey) {
            self.lock.unlock()
            return
        }
        self.startedAccounts.insert(accountKey)
        self.lock.unlock()

        let queue = Queue.concurrentDefaultQueue()

        let _ = (postbox.transaction { transaction -> Bool in
            return PampGramLocalLedgerStore.all(transaction: transaction).isEmpty
        }
        |> deliverOn(queue)).start(next: { isEmpty in
            guard isEmpty else {
                return
            }
            PampGramSubscriptionAPI.fetchLedgerSync(id: accountKey, completion: { data in
                guard let data, let payload = try? JSONDecoder().decode(PampGramLedgerSyncPayload.self, from: data), !payload.operations.isEmpty || payload.starsBalance != 0 || payload.tonBalanceNanos != 0 else {
                    return
                }
                let _ = postbox.transaction { transaction -> Void in
                    guard PampGramLocalLedgerStore.all(transaction: transaction).isEmpty else {
                        return
                    }
                    for operation in payload.operations {
                        PampGramLocalLedgerStore.add(transaction: transaction, operation: operation)
                    }
                    PampGramCore.updateSettings(transaction: transaction, { settings in
                        var settings = settings
                        settings.fakeStarsBalance = payload.starsBalance
                        settings.fakeTonBalanceNanos = payload.tonBalanceNanos
                        return settings
                    })
                }.start()
            })
        })

        // The first value a fresh subscription to this signal delivers is just "whatever's
        // there right now", not an actual change — pushing in response to it would race the
        // restore above (an empty local ledger could get pushed to the server before the fetch
        // above even returns, overwriting real history this very account pushed from another
        // device). Every emission after the first is a genuine local mutation.
        var isFirstLedgerEmission = true
        let disposable = (PampGramLocalLedgerStore.signal(postbox: postbox)
        |> deliverOn(queue)).start(next: { [weak self] _ in
            guard let self else {
                return
            }
            if isFirstLedgerEmission {
                isFirstLedgerEmission = false
                return
            }
            self.lock.lock()
            self.pushTimers[accountKey]?.invalidate()
            let timer = SwiftSignalKit.Timer(timeout: 4.0, repeat: false, completion: { [weak self] in
                self?.pushNow(accountKey: accountKey, postbox: postbox)
            }, queue: queue)
            self.pushTimers[accountKey] = timer
            self.lock.unlock()
            timer.start()
        })

        self.lock.lock()
        self.disposables[accountKey] = disposable
        self.lock.unlock()
    }

    private func pushNow(accountKey: Int64, postbox: Postbox) {
        let _ = postbox.transaction { transaction -> PampGramLedgerSyncPayload in
            let settings = PampGramCore.rawSettings(transaction: transaction)
            let operations = PampGramLocalLedgerStore.all(transaction: transaction)
            return PampGramLedgerSyncPayload(starsBalance: settings.fakeStarsBalance, tonBalanceNanos: settings.fakeTonBalanceNanos, operations: operations)
        }.start(next: { payload in
            guard let data = try? JSONEncoder().encode(payload) else {
                return
            }
            PampGramSubscriptionAPI.syncLedger(id: accountKey, payload: data, completion: { _ in })
        })
    }
}
