import Foundation
import Postbox
import SwiftSignalKit

/// "Фейк подписчики" — локально подменяет отображаемое число участников/подписчиков
/// в своих каналах и группах. На скриншоте «1.2M subscribers» на канале с 3 подписчиками.
///
/// Паттерн аналогичен `PampGramVideoMessageSaver`: синглтон подписывается на настройки
/// и зеркалит `fakeSubscribersEnabled` + `fakeSubscribersCount` для синхронного чтения.
///
/// Integration points (в патче):
///
/// 1. Инициализация:
///    ```swift
///    PampGramFakeSubscribersRuntime.shared.start(
///        accountKey: account.peerId.toInt64(),
///        postbox: account.postbox
///    )
///    ```
///
/// 2. В отображении числа подписчиков канала (`ChannelInfoHeaderNode`, `ChatTitleView`,
///    `PeerInfoScreen` и т.д.):
///    ```swift
///    if let overrideCount = PampGramFakeSubscribersRuntime.shared.overrideCount(
///        accountKey: context.account.peerId.toInt64()
///    ) {
///        // Показать overrideCount вместо настоящего memberCount
///        subtitle = presentationStringsFormattedNumber(Int32(clamping: overrideCount), groupingSeparator) + " subscribers"
///    }
///    ```
///
/// 3. Настройка числа — в «Дополнительно» → «Фейк подписчики»: тумблер + поле ввода числа.
public final class PampGramFakeSubscribersRuntime {
    public static let shared = PampGramFakeSubscribersRuntime()

    private let lock = NSLock()
    private var enabledByAccount: [Int64: Bool] = [:]
    private var countByAccount: [Int64: Int64] = [:]
    private var startedAccounts: Set<Int64> = []
    private var disposables: [Int64: Disposable] = [:]

    private init() {}

    public func isEnabled(accountKey: Int64) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.enabledByAccount[accountKey] ?? false
    }

    public func overrideCount(accountKey: Int64) -> Int64? {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard self.enabledByAccount[accountKey] == true else { return nil }
        return self.countByAccount[accountKey]
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
            self.enabledByAccount[accountKey] = settings.fakeSubscribersEnabled
            self.countByAccount[accountKey] = settings.fakeSubscribersCount
            self.lock.unlock()
        })

        self.lock.lock()
        self.disposables[accountKey] = disposable
        self.lock.unlock()
    }
}
