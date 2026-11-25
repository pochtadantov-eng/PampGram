import Foundation
import Postbox
import SwiftSignalKit

/// Synchronous, in-memory mirror of "Обход одноразовых"/"Обход с таймером" (Дополнительно), so
/// chat media rendering (`ChatMessageInteractiveMediaNode`, in the patch) can check either
/// setting without an async Postbox read — its layout closures run off the main thread and
/// can't open a transaction there. Warmed once per account at `AccountContextImpl` init (see the
/// patch), same pattern as `PampGramFakeAdminRuntime`.
public final class PampGramTemporaryMediaDisplay {
    public static let shared = PampGramTemporaryMediaDisplay()

    private let lock = NSLock()
    private var viewOnceEnabledByAccount: [Int64: Bool] = [:]
    private var timedEnabledByAccount: [Int64: Bool] = [:]
    private var startedAccounts: Set<Int64> = []
    private var disposables: [Int64: Disposable] = [:]

    private init() {
    }

    /// True when the account behind `accountKey` (`account.peerId.toInt64()`) has "Обход
    /// одноразовых" on — view-once photos/videos (`minAutoremoveOrClearTimeout == viewOnceTimeout`).
    public func isViewOnceEnabled(accountKey: Int64) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.viewOnceEnabledByAccount[accountKey] ?? false
    }

    /// True when the account behind `accountKey` has "Обход с таймером" on — short-timer
    /// self-destruct photos/videos (`minAutoremoveOrClearTimeout` set but not `viewOnceTimeout`).
    public func isTimedEnabled(accountKey: Int64) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.timedEnabledByAccount[accountKey] ?? false
    }

    /// Whether `seed` / the first settingsSignal emission has already written values for this
    /// account. Layout code uses this to distinguish "toggles are off" from "mirror not warmed".
    public func isSeeded(accountKey: Int64) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.viewOnceEnabledByAccount[accountKey] != nil
    }

    /// Immediate write — used by the settings toggles so the mirror flips before the Postbox
    /// transaction finishes, and by `PampGramTemporaryMediaBypass` when it reads settings inside
    /// a transaction (so layout/open paths that still consult the mirror see the same values).
    public func seed(accountKey: Int64, viewOnceEnabled: Bool, timedEnabled: Bool) {
        self.lock.lock()
        self.viewOnceEnabledByAccount[accountKey] = viewOnceEnabled
        self.timedEnabledByAccount[accountKey] = timedEnabled
        self.lock.unlock()
    }

    /// Starts (once per account) the subscription that keeps both flags current.
    public func start(accountKey: Int64, postbox: Postbox) {
        self.lock.lock()
        if self.startedAccounts.contains(accountKey) {
            self.lock.unlock()
            return
        }
        self.startedAccounts.insert(accountKey)
        self.lock.unlock()

        // Seed from Postbox as soon as a transaction can run — do not wait for preferencesView
        // wiring, otherwise the first layouts / gallery opens still see the default `false`.
        let _ = (postbox.transaction { transaction -> PampGramSettings in
            return PampGramCore.settings(transaction: transaction)
        }).startStandalone(next: { [weak self] settings in
            self?.seed(accountKey: accountKey, viewOnceEnabled: settings.bypassViewOnceMediaEnabled, timedEnabled: settings.bypassTimedMediaEnabled)
        })

        let disposable = (PampGramCore.settingsSignal(postbox: postbox)
        |> deliverOn(Queue.concurrentDefaultQueue())).start(next: { [weak self] settings in
            self?.seed(accountKey: accountKey, viewOnceEnabled: settings.bypassViewOnceMediaEnabled, timedEnabled: settings.bypassTimedMediaEnabled)
        })

        self.lock.lock()
        self.disposables[accountKey] = disposable
        self.lock.unlock()
    }
}
