import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import AccountContext

/// "Спам реакциями" — быстро ставит и снимает реакцию на сообщение в цикле.
///
/// У собеседника телефон непрерывно вибрирует от уведомлений о реакциях — каждый тогл
/// (поставить → снять → поставить) генерирует отдельный пуш. Интервал по умолчанию 1 секунда.
///
/// Паттерн аналогичен `PampGramFakeActivityRuntime`: таймер на `Queue.mainQueue()`,
/// управление через `start`/`stop`/`isActive`.
///
/// ⚠️ Агрессивная функция: Telegram может ограничить аккаунт при чрезмерном использовании.
/// Рекомендуется не держать спаммер включённым долго.
///
/// Integration points (в патче):
///
/// 1. Контекстное меню сообщения — пункт «Спам реакциями 💣»:
///    ```swift
///    items.append(.action(ContextMenuActionItem(
///        text: PampGramReactionSpammerRuntime.shared.isActive(messageId: message.id)
///            ? "Стоп спам реакциями"
///            : "Спам реакциями 💣",
///        icon: { theme in generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Reactions"), color: theme.contextMenu.primaryColor) },
///        action: { c, _ in
///            c?.dismiss(completion: {
///                if PampGramReactionSpammerRuntime.shared.isActive(messageId: message.id) {
///                    PampGramReactionSpammerRuntime.shared.stop(messageId: message.id)
///                } else {
///                    // Показать пикер эмодзи, затем:
///                    PampGramReactionSpammerRuntime.shared.start(
///                        context: context,
///                        messageId: message.id,
///                        peerId: message.id.peerId,
///                        reaction: "🔥"
///                    )
///                }
///            })
///        }
///    )))
///    ```
///
/// 2. При выходе из чата — остановить все спаммеры для этого peer:
///    ```swift
///    PampGramReactionSpammerRuntime.shared.stopAll(forPeerId: peerId)
///    ```
public final class PampGramReactionSpammerRuntime {
    public static let shared = PampGramReactionSpammerRuntime()

    private struct ActiveSpammer {
        let messageId: MessageId
        let reaction: String
        let timer: SwiftSignalKit.Timer
        let disposable: Disposable
    }

    private let lock = NSLock()
    private var spammers: [MessageId: ActiveSpammer] = [:]

    private init() {}

    /// Начать спам реакцией на сообщение.
    /// `interval` — период тогла в секундах (по умолчанию 1.0).
    public func start(context: AccountContext, messageId: MessageId, peerId: PeerId, reaction: String, interval: Double = 1.0) {
        stop(messageId: messageId)

        var isSet = false

        let toggleReaction: () -> Void = {
            let reactionValue: MessageReaction.Reaction = .builtin(reaction)
            if isSet {
                let _ = context.engine.messages.setMessageReaction(
                    id: messageId,
                    reaction: nil
                ).startStandalone()
            } else {
                let _ = context.engine.messages.setMessageReaction(
                    id: messageId,
                    reaction: reactionValue
                ).startStandalone()
            }
            isSet = !isSet
        }

        toggleReaction()

        let timer = SwiftSignalKit.Timer(timeout: interval, repeat: true, completion: {
            toggleReaction()
        }, queue: Queue.mainQueue())
        timer.start()

        let disposable = ActionDisposable {
            timer.invalidate()
        }

        self.lock.lock()
        self.spammers[messageId] = ActiveSpammer(
            messageId: messageId,
            reaction: reaction,
            timer: timer,
            disposable: disposable
        )
        self.lock.unlock()
    }

    public func stop(messageId: MessageId) {
        self.lock.lock()
        let spammer = self.spammers.removeValue(forKey: messageId)
        self.lock.unlock()
        spammer?.disposable.dispose()
    }

    public func stopAll(forPeerId peerId: PeerId) {
        self.lock.lock()
        let matching = self.spammers.filter { $0.key.peerId == peerId }
        for key in matching.keys {
            self.spammers.removeValue(forKey: key)
        }
        self.lock.unlock()
        for (_, spammer) in matching {
            spammer.disposable.dispose()
        }
    }

    public func stopAll() {
        self.lock.lock()
        let all = self.spammers
        self.spammers.removeAll()
        self.lock.unlock()
        for (_, spammer) in all {
            spammer.disposable.dispose()
        }
    }

    public func isActive(messageId: MessageId) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.spammers[messageId] != nil
    }

    public func activeCount() -> Int {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.spammers.count
    }
}
