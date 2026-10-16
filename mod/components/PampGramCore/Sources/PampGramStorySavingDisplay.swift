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
            self.enabledByAccount[accountKey] = settings.storySavingEnabled
            self.lock.unlock()
        })

        self.lock.lock()
        self.disposables[accountKey] = disposable
        self.lock.unlock()
    }
}
