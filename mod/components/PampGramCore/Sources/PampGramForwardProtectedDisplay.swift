import Foundation
import Postbox
import SwiftSignalKit

public final class PampGramForwardProtectedDisplay {
    public static let shared = PampGramForwardProtectedDisplay()

    private let lock = NSLock()
    private var enabledByAccount: [Int64: Bool] = [:]
    private var startedAccounts: Set<Int64> = []
    private var disposables: [Int64: Disposable] = [:]

    /// Injected by AccountContext startup (has TelegramCore access).
    /// Copies the message into Saved Messages via enqueueMessages.
    public var saveToSavedMessagesHandler: ((_ accountPeerId: PeerId, _ message: Message, _ postbox: Postbox) -> Void)?

    private init() {}

    public func isEnabled(accountKey: Int64) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.enabledByAccount[accountKey] ?? false
    }

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
            guard let self else { return }
            self.lock.lock()
            self.enabledByAccount[accountKey] = settings.forwardProtectedToSavedEnabled
            self.lock.unlock()
        })

        self.lock.lock()
        self.disposables[accountKey] = disposable
        self.lock.unlock()
    }

    public func saveToSavedMessages(accountPeerId: PeerId, message: Message, postbox: Postbox) {
        saveToSavedMessagesHandler?(accountPeerId, message, postbox)
    }
}
