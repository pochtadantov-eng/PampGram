import Foundation
import Postbox
import SwiftSignalKit

/// «Фейк „удалил аккаунт"» — ваш профиль локально выглядит как «Deleted Account».
///
/// Серая аватарка, пустое имя «Deleted Account», скрыт номер, био и username.
/// На скриншоте выглядит как будто вы удалили аккаунт. Собеседник ничего не видит —
/// его клиент показывает ваш настоящий профиль.
///
/// Паттерн: зеркалирует настройку `fakeDeletedAccountEnabled` из Postbox в thread-safe
/// in-memory кеш, точно как `PampGramFakeBadgeRuntime` / `PampGramTemporaryMediaDisplay`.
///
/// Integration points (в патче):
///
/// 1. В `PeerInfoScreen.swift` / отображении собственного профиля:
///
///    ```swift
///    if PampGramFakeDeletedAccountRuntime.shared.isEnabled(accountKey: context.account.peerId.toInt64()),
///       peer.id == context.account.peerId {
///        // Заменить отображение:
///        nameLabel.text = "Deleted Account"
///        avatarNode.setImage(PampGramFakeDeletedAccountRuntime.deletedAccountAvatar)
///        phoneLabel.isHidden = true
///        bioLabel.isHidden = true
///        usernameLabel.isHidden = true
///    }
///    ```
///
/// 2. В списке чатов / заголовке навбара, если это ваш собственный профиль:
///
///    ```swift
///    let displayName: String
///    if PampGramFakeDeletedAccountRuntime.shared.isEnabled(accountKey: accountKey),
///       peer.id == context.account.peerId {
///        displayName = "Deleted Account"
///    } else {
///        displayName = peer.displayTitle
///    }
///    ```
public final class PampGramFakeDeletedAccountRuntime {
    public static let shared = PampGramFakeDeletedAccountRuntime()

    private let lock = NSLock()
    private var enabledByAccount: [Int64: Bool] = [:]
    private var startedAccounts: Set<Int64> = [:]
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
            self.enabledByAccount[accountKey] = settings.fakeDeletedAccountEnabled
            self.lock.unlock()
        })

        self.lock.lock()
        self.disposables[accountKey] = disposable
        self.lock.unlock()
    }

    /// Текст для отображения вместо имени.
    public static let deletedAccountName = "Deleted Account"

    /// Цвет аватарки удалённого аккаунта (серый, как в Telegram).
    /// Используется для генерации placeholder-аватарки.
    public static let deletedAccountAvatarColorHex: UInt32 = 0x9e9e9e
}
