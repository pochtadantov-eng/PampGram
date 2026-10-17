import Foundation
import UIKit
import Postbox
import SwiftSignalKit

/// The page that stands in for @CryptoBot's mini app inside Telegram's own web-app window. It is a
/// plain view: the window around it (header, close/back button, "⋯" menu, the bottom bar, the
/// transitions) stays Telegram's, and only the web page is replaced.
public protocol PampGramFakeMiniAppContent: UIView {
    /// Called with `true` while the page is showing a sub-screen, so the window can turn its
    /// "Закрыть" button into "Назад".
    var onBackStateChanged: ((Bool) -> Void)? { get set }
    /// The page's background in the current light/dark theme: the window paints its header and its
    /// own background with it.
    var pageColor: UIColor { get }
    /// Called when the app's theme switches while the page is open, with the new `pageColor`.
    var onPageColorChanged: ((UIColor) -> Void)? { get set }
    /// The window's back button was pressed.
    func goBack()
}

/// Synchronous, in-memory mirror of "Фейковый криптобот", so the web-app window can decide
/// without an async Postbox read whether to show the local page instead of @CryptoBot's.
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
    private var contentFactory: ((AnyObject, AnyObject) -> PampGramFakeMiniAppContent?)?

    private init() {
    }

    /// Registered once at launch by the app target, which can see both the account context and
    /// the page; this module can't (it must not depend on TelegramCore / Display). The arguments
    /// are the `AccountContext` and the web-app window (a `ViewController`) that will show it.
    public func setContentFactory(_ factory: @escaping (AnyObject, AnyObject) -> PampGramFakeMiniAppContent?) {
        self.lock.lock()
        self.contentFactory = factory
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

    /// The page to show when `botUserId` / `botName` is the official CryptoBot and the feature is
    /// on for this account; `nil` means "load the real mini app".
    public func replacementContent(accountKey: Int64, context: AnyObject, presenter: AnyObject, botUserId: Int64, botName: String) -> PampGramFakeMiniAppContent? {
        self.lock.lock()
        let enabled = self.enabledByAccount[accountKey] ?? false
        let factory = self.contentFactory
        self.lock.unlock()
        guard enabled, let factory else {
            return nil
        }
        let name = botName.trimmingCharacters(in: .whitespaces).lowercased()
        guard botUserId == PampGramFakeCryptoBotRuntime.officialBotUserId || name == "crypto bot" || name == "cryptobot" else {
            return nil
        }
        return factory(context, presenter)
    }
}
