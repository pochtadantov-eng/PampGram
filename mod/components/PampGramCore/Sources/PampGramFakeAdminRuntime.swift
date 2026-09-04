import Foundation
import Postbox
import SwiftSignalKit

/// Synchronous, in-memory mirror of which channels have PampGram "фейк админ" enabled, so the
/// chat UI can decide — without an async Postbox read — whether to show the real composer in a
/// broadcast channel the user can't actually post to. It is warmed once per account at
/// `AccountContextImpl` init (see the patch), long before any channel is opened, and kept up to
/// date by a live `PampGramFakeAdminStore.allSignal` subscription.
public final class PampGramFakeAdminRuntime {
    public static let shared = PampGramFakeAdminRuntime()

    private let lock = NSLock()
    private var enabledByAccount: [Int64: Set<Int64>] = [:]
    private var startedAccounts: Set<Int64> = []
    private var disposables: [Int64: Disposable] = [:]

    private init() {
    }

    /// True when `peerId` (a channel) is a fake-admin channel for the given account. `accountKey`
    /// is the account's own peer id (`account.peerId.toInt64()`); `peerId` is `channelPeerId.toInt64()`.
    public func isEnabled(accountKey: Int64, peerId: Int64) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.enabledByAccount[accountKey]?.contains(peerId) ?? false
    }

    /// Starts (once per account) the subscription that keeps the enabled-channel set current.
    public func start(accountKey: Int64, postbox: Postbox) {
        self.lock.lock()
        if self.startedAccounts.contains(accountKey) {
            self.lock.unlock()
            return
        }
        self.startedAccounts.insert(accountKey)
        self.lock.unlock()

        let disposable = (PampGramFakeAdminStore.allSignal(postbox: postbox)
        |> deliverOn(Queue.concurrentDefaultQueue())).start(next: { [weak self] states in
            guard let self else {
                return
            }
            let ids = Set(states.filter { $0.enabled }.map { $0.peerId.toInt64() })
            self.lock.lock()
            self.enabledByAccount[accountKey] = ids
            self.lock.unlock()
        })

        self.lock.lock()
        self.disposables[accountKey] = disposable
        self.lock.unlock()
    }
}
