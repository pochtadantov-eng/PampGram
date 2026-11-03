import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import AccountContext

/// «Фейк скриншот уведомление» — отправляет в секретный чат системное сообщение
/// «Сделан снимок экрана», хотя скриншота не было.
///
/// В секретных чатах Telegram показывает уведомление когда собеседник делает скриншот.
/// Эта функция отправляет такое уведомление без реального скриншота — собеседник видит
/// «[Имя] сделал(а) снимок экрана» и нервничает.
///
/// Telegram API: `messages.sendScreenshotNotification` — отправляет сервисное сообщение
/// типа `messageActionScreenshotTaken` в секретный чат. Доступно через
/// `TelegramEngine.messages`.
///
/// Integration point (в патче):
///
/// 1. Контекстное меню в секретном чате → «Фейк скриншот»:
///
///    ```swift
///    if peerId.namespace == Namespaces.Peer.SecretChat {
///        items.append(.action(ContextMenuActionItem(
///            text: "Фейк скриншот",
///            icon: { theme in generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Screenshot"), color: theme.contextMenu.primaryColor) },
///            action: { c, _ in
///                c?.dismiss(completion: {
///                    PampGramFakeScreenshotNotificationRuntime.shared.sendFakeScreenshotNotification(
///                        context: context,
///                        peerId: peerId
///                    )
///                })
///            }
///        )))
///    }
///    ```
///
/// 2. Можно добавить подтверждение: «Собеседник увидит что вы сделали скриншот. Продолжить?»
public final class PampGramFakeScreenshotNotificationRuntime {
    public static let shared = PampGramFakeScreenshotNotificationRuntime()

    private init() {}

    /// Отправляет фейковое уведомление о скриншоте в секретный чат.
    ///
    /// Использует штатный Telegram API `sendScreenshotNotification`. Работает ТОЛЬКО
    /// в секретных чатах — в обычных чатах Telegram не поддерживает такие уведомления.
    ///
    /// Собеседник увидит настоящее системное сообщение «[Имя] сделал(а) снимок экрана».
    /// Это НЕ локальное сообщение — оно реально отправляется через сервер.
    public func sendFakeScreenshotNotification(context: AccountContext, peerId: PeerId) {
        guard peerId.namespace == Namespaces.Peer.SecretChat else {
            return
        }

        let _ = context.engine.messages.sendScreenshotNotification(peerId: peerId).startStandalone()
    }

    /// Проверяет, является ли чат секретным (только в них работают уведомления о скриншотах).
    public func isSecretChat(peerId: PeerId) -> Bool {
        return peerId.namespace == Namespaces.Peer.SecretChat
    }
}
