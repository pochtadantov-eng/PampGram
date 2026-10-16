import Foundation
import Postbox
import SwiftSignalKit

/// Synchronous, in-memory mirror of "Обход защиты от скриншотов" (Дополнительно), so the chat
/// media/content-protection code (`ChatMessageInteractiveMediaNode.swift`,
/// `ChatControllerNode.swift`, `ChatController.swift`,
/// `ChatControllerOpenMessageContextMenu.swift`) can check the setting without an async Postbox
/// read — their layout runs off the main thread and can't open a transaction there. Warmed once
/// per account at `AccountContextImpl` init (see the patch), same pattern as
/// `PampGramStorySavingDisplay`/`PampGramTemporaryMediaDisplay`.
///
/// Deliberately only ever ANDed against the copy-protection terms (`copyProtectionEnabled`,
/// `myCopyProtectionEnabled`, a channel/group's own protected-content flag) at every call site
/// this patches — never against the separate `peerId.namespace == Namespaces.Peer.SecretChat`
/// (or `isVerificationCodes`) term those same conditions are `||`-combined with upstream. Real
/// secret chats keep their screenshot protection exactly as stock Telegram ships it, on purpose:
/// unlike copy-protected channels/groups (paid/private content, no notification either way),
/// a secret chat's screenshot handling is the one place Telegram gives the *other person* an
/// actual signal about sensitive content being captured, and this mod never touches that signal.
public final class PampGramScreenshotBypassDisplay {
    public static let shared = PampGramScreenshotBypassDisplay()

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
            self.enabledByAccount[accountKey] = settings.bypassScreenshotProtectionEnabled
            self.lock.unlock()
        })

        self.lock.lock()
        self.disposables[accountKey] = disposable
        self.lock.unlock()
    }
}
