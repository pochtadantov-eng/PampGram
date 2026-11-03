import Foundation
import Postbox
import SwiftSignalKit

/// "Фейк Premium / Верификация" — локально показывает звёздочку Premium и/или галочку
/// верификации рядом с именем в профиле и в списке чатов. На скриншоте неотличимо от
/// настоящего Premium или верифицированного аккаунта.
///
/// Паттерн аналогичен `PampGramVideoMessageSaver`: синглтон подписывается на настройки
/// через `PampGramCore.settingsSignal` и зеркалит `fakePremiumBadgeEnabled` в потокобезопасное
/// in-memory хранилище для синхронного чтения из UI-кода.
///
/// Integration points (в патче):
///
/// 1. Инициализация (в `AccountContextImpl.init` или `PampGramBootstrap`):
///    ```swift
///    PampGramFakeBadgeRuntime.shared.start(
///        accountKey: account.peerId.toInt64(),
///        postbox: account.postbox
///    )
///    ```
///
/// 2. В рендеринге имени пользователя (профиль, шапка чата, список чатов):
///    ```swift
///    if PampGramFakeBadgeRuntime.shared.isEnabled(accountKey: context.account.peerId.toInt64()) {
///        // Если это свой аккаунт:
///        //   - Добавить звёздочку Premium рядом с именем
///        //   - Или галочку верификации (в зависимости от настроек)
///        // peer.isPremium уже true визуально
///    }
///    ```
///
/// 3. В `PeerInfoHeaderNode` / `ChatTitleView` — подменить `peer.isPremium` / `peer.isVerified`:
///    ```swift
///    let showPremium = peer.isPremium || (
///        peer.id == context.account.peerId &&
///        PampGramFakeBadgeRuntime.shared.isEnabled(accountKey: context.account.peerId.toInt64())
///    )
///    ```
public final class PampGramFakeBadgeRuntime {
    public static let shared = PampGramFakeBadgeRuntime()

    private let lock = NSLock()
    private var enabledByAccount: [Int64: Bool] = [:]
    private var startedAccounts: Set<Int64> = []
    private var disposables: [Int64: Disposable] = [:]

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
            self.enabledByAccount[accountKey] = settings.fakePremiumBadgeEnabled
            self.lock.unlock()
        })

        self.lock.lock()
        self.disposables[accountKey] = disposable
        self.lock.unlock()
    }
}
