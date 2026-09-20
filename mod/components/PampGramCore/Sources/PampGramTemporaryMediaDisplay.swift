import Foundation
import Postbox
import SwiftSignalKit

/// Synchronous, in-memory mirror of "Показывать временную медиа" (Дополнительно), so chat media
/// rendering (`ChatMessageInteractiveMediaNode`, in the patch) can check the setting without an
/// async Postbox read — its layout closures run off the main thread and can't open a transaction
/// there. Warmed once per account at `AccountContextImpl` init (see the patch), same pattern as
/// `PampGramFakeAdminRuntime`.
public final class PampGramTemporaryMediaDisplay {
    public static let shared = PampGramTemporaryMediaDisplay()

    private let lock = NSLock()
    private var enabledByAccount: [Int64: Bool] = [:]
    private var startedAccounts: Set<Int64> = []
    private var disposables: [Int64: Disposable] = [:]

    private init() {
    }

    /// True when the account behind `accountKey` (`account.peerId.toInt64()`) has "Показывать
    /// временную медиа" on.
    public func isEnabled(accountKey: Int64) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.enabledByAccount[accountKey] ?? false
    }

    /// Starts (once per account) the subscription that keeps the flag current.
    public func start(accountKey: Int64, postbox: Postbox) {
        self.lock.lock()
        if self.startedAccounts.contains(accountKey) {
            self.lock.unlock()
            return
        }
        self.startedAccounts.insert(accountKey)
        self.lock.unlock()

        let disposable = (PampGramCore.settingsSignal(postbox: postbox)
        |> deliverOn(Queue.concurrentDefaultQueue())).start(next: { [weak self] settings in
            guard let self else {
                return
            }
            self.lock.lock()
            self.enabledByAccount[accountKey] = settings.showTemporaryMediaEnabled
            self.lock.unlock()
        })

        self.lock.lock()
        self.disposables[accountKey] = disposable
        self.lock.unlock()
    }
}
