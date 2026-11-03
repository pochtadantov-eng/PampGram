import Foundation
import UIKit
import Postbox
import SwiftSignalKit

/// «Фейковый Portals» — визуальная копия мини-аппа @portals внутри Telegram.
///
/// Portals — бот для покупки/продажи подарков с витрин пользователей.
/// Эта функция перехватывает открытие @portals (и любых ботов, добавленных
/// в «Фейковые боты» с пометкой Portals) и показывает локальную копию
/// интерфейса с визуальным балансом и фейковой покупкой подарков.
///
/// Паттерн полностью повторяет `PampGramFakeCryptoBotRuntime`:
/// - `PampGramFakeMiniAppContent` протокол для содержимого окна
/// - `replacementContent(...)` возвращает локальную страницу вместо настоящей
/// - Балансы хранятся в `PampGramSettings.fakePortalsBalanceTonNanos` и `.fakePortalsBalanceStars`
///
/// Integration point (в патче):
///
/// В `standaloneWebAppController` (или где перехватывается CryptoBot):
/// ```swift
/// if let portalsContent = PampGramFakePortalsRuntime.shared.replacementContent(
///     accountKey: context.account.peerId.toInt64(),
///     context: context as AnyObject,
///     presenter: controller as AnyObject,
///     botUserId: botUser.id.id._internalGetInt64Value(),
///     botName: botUser.debugDisplayTitle
/// ) {
///     // Показать portalsContent вместо настоящего мини-аппа
/// }
/// ```
public final class PampGramFakePortalsRuntime {
    public static let shared = PampGramFakePortalsRuntime()

    public static let officialPortalsBotUserId: Int64 = 7632945498

    private let lock = NSLock()
    private var enabledByAccount: [Int64: Bool] = [:]
    private var startedAccounts: Set<Int64> = []
    private var disposables: [Int64: Disposable] = [:]
    private var contentFactory: ((AnyObject, AnyObject) -> PampGramFakeMiniAppContent?)?

    private init() {}

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
        |> map { $0.fakePortalsEnabled }
        |> distinctUntilChanged
        |> deliverOn(Queue.concurrentDefaultQueue())).start(next: { [weak self] enabled in
            guard let self else { return }
            self.lock.lock()
            self.enabledByAccount[accountKey] = enabled
            self.lock.unlock()
        })

        self.lock.lock()
        self.disposables[accountKey] = disposable
        self.lock.unlock()
    }

    public func replacementContent(accountKey: Int64, context: AnyObject, presenter: AnyObject, botUserId: Int64, botName: String) -> PampGramFakeMiniAppContent? {
        self.lock.lock()
        let enabled = self.enabledByAccount[accountKey] ?? false
        let factory = self.contentFactory
        self.lock.unlock()

        guard enabled, let factory else { return nil }

        let name = botName.trimmingCharacters(in: .whitespaces).lowercased()
        let isPortals = botUserId == PampGramFakePortalsRuntime.officialPortalsBotUserId
            || name == "portals"
            || name.contains("portal")

        guard isPortals else { return nil }
        return factory(context, presenter)
    }

    public func isEnabled(accountKey: Int64) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.enabledByAccount[accountKey] ?? false
    }
}
