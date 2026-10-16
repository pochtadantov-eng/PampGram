import Foundation
import Postbox
import SwiftSignalKit

/// Synchronous, in-memory mirror of "Фейковый криптобот", so the web-app presenter can decide
/// without an async Postbox read whether to swap @CryptoBot's mini app for the local visual.
/// Started once per account at `AccountContextImpl` init; follows the (ban-gated)
/// `PampGramCore.settingsSignal`, so a locally banned account never gets the replacement.
public final class PampGramFakeCryptoBotRuntime {
    public static let shared = PampGramFakeCryptoBotRuntime()

    /// Telegram user id of the official @CryptoBot.
    private static let officialBotUserId: Int64 = 1559501630

    private let lock = NSLock()
    private var enabledByAccount: [Int64: Bool] = [:]
    private var startedAccounts: Set<Int64> = []
    private var disposables: [Int64: Disposable] = [:]
    private var controllerFactory: ((AnyObject) -> AnyObject?)?

    private init() {
    }

    /// Registered once at launch by the app target, which can see both the account context and
    /// the screen; this module can't (it must not depend on TelegramCore / Display). The argument
    /// is the `AccountContext`, the result the screen's `ViewController`.
    public func setControllerFactory(_ factory: @escaping (AnyObject) -> AnyObject?) {
        self.lock.lock()
        self.controllerFactory = factory
        self.lock.unlock()
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
        |> map { settings -> Bool in
            return settings.fakeCryptoBotEnabled
        }
        |> distinctUntilChanged
        |> deliverOn(Queue.concurrentDefaultQueue())).start(next: { [weak self] enabled in
            guard let self else {
                return
            }
            self.lock.lock()
            self.enabledByAccount[accountKey] = enabled
            self.lock.unlock()
        })

        self.lock.lock()
        self.disposables[accountKey] = disposable
        self.lock.unlock()
    }

    /// The replacement screen when `botUserId` / `botName` is the official CryptoBot and the
    /// feature is on for this account; `nil` means "open the real mini app".
    public func replacementController(accountKey: Int64, context: AnyObject, botUserId: Int64, botName: String) -> AnyObject? {
        self.lock.lock()
        let enabled = self.enabledByAccount[accountKey] ?? false
        let factory = self.controllerFactory
        self.lock.unlock()
        guard enabled, let factory else {
            return nil
        }
        let name = botName.trimmingCharacters(in: .whitespaces).lowercased()
        guard botUserId == PampGramFakeCryptoBotRuntime.officialBotUserId || name == "crypto bot" || name == "cryptobot" else {
            return nil
        }
        return factory(context)
    }
}
