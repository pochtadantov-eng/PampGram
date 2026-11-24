import Foundation
import Postbox
import SwiftSignalKit

/// Synchronous, in-memory mirror of "Сохранение историй" (Дополнительно), so
/// `StoryItemContentComponent` and `StoryItemSetContainerComponent` can check the setting
/// without an async Postbox read — their layout runs off the main thread and can't open a
/// transaction there. Warmed once per account at `AccountContextImpl` init (see the patch),
/// same pattern as `PampGramTemporaryMediaDisplay`.
public final class PampGramStorySavingDisplay {
    public static let shared = PampGramStorySavingDisplay()

    private let lock = NSLock()
    private var enabledByAccount: [Int64: Bool] = [:]
    private var startedAccounts: Set<Int64> = []
    private var disposables: [Int64: Disposable] = [:]

    private init() {
    }

    public func isEnabled(accountKey: Int64) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.enabledByAccount[accountKey] ?? false
    }

    public func seed(accountKey: Int64, enabled: Bool) {
        self.lock.lock()
        self.enabledByAccount[accountKey] = enabled
        self.lock.unlock()
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

        let _ = (postbox.transaction { transaction -> PampGramSettings in
            return PampGramCore.settings(transaction: transaction)
        }).startStandalone(next: { [weak self] settings in
            self?.seed(accountKey: accountKey, enabled: settings.storySavingEnabled)
        })

        let disposable = (PampGramCore.settingsSignal(postbox: postbox)
        |> deliverOn(Queue.concurrentDefaultQueue())).start(next: { [weak self] settings in
            self?.seed(accountKey: accountKey, enabled: settings.storySavingEnabled)
        })

        self.lock.lock()
        self.disposables[accountKey] = disposable
        self.lock.unlock()
    }
}
