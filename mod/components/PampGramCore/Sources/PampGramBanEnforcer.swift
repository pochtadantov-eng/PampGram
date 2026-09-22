import Foundation
import Postbox
import SwiftSignalKit

/// Turns a full ban from the admin panel's server into a real, on-device kill switch, not just
/// a locked settings screen. Polls `PampGramSubscriptionAPI.fetchBanStatus` on a timer and, the
/// moment it first sees a full ban, writes `PampGramSettings.bannedLocally = true` in the same
/// transaction that zeroes the visual balances (`fakeStarsBalance`/`fakeTonBalanceNanos`/
/// `localRublesBalanceKopecks`) — after that, `PampGramCore.settings`/`settingsSignal` (the read
/// path every feature-effect and display call site already goes through) report every toggle as
/// off on their own, with no further changes needed anywhere else. Clears `bannedLocally` back
/// to `false` the same way once the server reports the ban lifted; the zeroed balances stay
/// zeroed, since zeroing them was the point.
///
/// Deliberately a poller, not a push: the ban-status endpoint has no way to notify a specific
/// device, so this is the same "ask periodically" approach `PampGramSubscriptionAPI.fetchStatus`
/// callers already use for tier, just kept running instead of one-shot. A 60s interval means a
/// ban takes effect within a minute of being issued — sections' own `pampGramGateSection` check,
/// which already runs on every hub/section open, still gives the immediate UI-level lock in the
/// meantime.
public final class PampGramBanEnforcer {
    public static let shared = PampGramBanEnforcer()

    private let lock = NSLock()
    private var startedAccounts: Set<Int64> = []
    private var timers: [Int64: SwiftSignalKit.Timer] = [:]

    private init() {
    }

    /// Starts (once per account) the periodic poll-and-enforce loop. `userId` is the plain
    /// Telegram account id `PampGramSubscriptionAPI` calls expect (`peerId.id._internalGetInt64Value()`),
    /// separate from `accountKey` (`peerId.toInt64()`), which is only ever used as this class's
    /// own in-memory dictionary key, same as every other `PampGramXDisplay.start(accountKey:...)`.
    public func start(accountKey: Int64, userId: Int64, postbox: Postbox) {
        self.lock.lock()
        if self.startedAccounts.contains(accountKey) {
            self.lock.unlock()
            return
        }
        self.startedAccounts.insert(accountKey)
        self.lock.unlock()

        let queue = Queue()
        PampGramBanEnforcer.pollOnce(userId: userId, postbox: postbox)
        let timer = SwiftSignalKit.Timer(timeout: 60.0, repeat: true, completion: {
            PampGramBanEnforcer.pollOnce(userId: userId, postbox: postbox)
        }, queue: queue)
        timer.start()

        self.lock.lock()
        self.timers[accountKey] = timer
        self.lock.unlock()
    }

    private static func pollOnce(userId: Int64, postbox: Postbox) {
        let _ = (PampGramSubscriptionAPI.fetchBanStatus(userId: userId)
        |> deliverOn(Queue.concurrentDefaultQueue())).start(next: { status in
            let isBanned = status.full != nil
            let _ = postbox.transaction { transaction -> Void in
                let raw = PampGramCore.rawSettings(transaction: transaction)
                guard raw.bannedLocally != isBanned else {
                    return
                }
                PampGramCore.updateSettings(transaction: transaction, { settings in
                    var settings = settings
                    if isBanned {
                        settings.fakeStarsBalance = 0
                        settings.fakeTonBalanceNanos = 0
                        settings.localRublesBalanceKopecks = 0
                    }
                    settings.bannedLocally = isBanned
                    return settings
                })
            }.start()
        })
    }
}
