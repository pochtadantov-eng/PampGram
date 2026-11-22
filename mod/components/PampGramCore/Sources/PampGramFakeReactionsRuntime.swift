import Foundation
import Postbox

/// "Фейк реакции" — локально показывает произвольные реакции с любым количеством на любом
/// сообщении. Реальные реакции на сервере не меняются — всё только на этом устройстве.
///
/// Хранит маппинг `MessageId → [(emoji, count)]` в памяти. При рендеринге реакций под пузырём
/// патч проверяет, есть ли фейковые реакции, и рисует их вместо (или поверх) настоящих.
///
/// Integration points (в патче):
///
/// 1. Контекстное меню сообщения — добавить пункт «Фейк реакции»:
///    ```swift
///    items.append(.action(ContextMenuActionItem(
///        text: "Фейк реакции",
///        icon: { theme in generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Reactions"), color: theme.contextMenu.primaryColor) },
///        action: { c, _ in
///            c?.dismiss(completion: {
///                // Открыть пикер эмодзи + ввод количества, затем:
///                PampGramFakeReactionsRuntime.shared.addReaction(
///                    messageId: message.id,
///                    reaction: "🔥",
///                    count: 50000
///                )
///                // Перерисовать ячейку
///            })
///        }
///    )))
///    ```
///
/// 2. В рендеринге реакций (`ChatMessageReactionsFooterContentNode` или аналог):
///    ```swift
///    let fakeReactions = PampGramFakeReactionsRuntime.shared.getReactions(messageId: message.id)
///    if !fakeReactions.isEmpty {
///        // Рисовать фейковые реакции (можно мержить с настоящими)
///    }
///    ```
///
/// 3. Сброс — контекстное меню «Убрать фейк реакции»:
///    ```swift
///    PampGramFakeReactionsRuntime.shared.clearReactions(messageId: message.id)
///    ```
public final class PampGramFakeReactionsRuntime {
    public static let shared = PampGramFakeReactionsRuntime()

    public struct FakeReaction {
        public let emoji: String
        public let count: Int

        public init(emoji: String, count: Int) {
            self.emoji = emoji
            self.count = count
        }
    }

    private let lock = NSLock()
    private var reactions: [MessageId: [FakeReaction]] = [:]

    private init() {}

    public func addReaction(messageId: MessageId, reaction: String, count: Int) {
        self.lock.lock()
        var existing = self.reactions[messageId] ?? []
        if let index = existing.firstIndex(where: { $0.emoji == reaction }) {
            existing[index] = FakeReaction(emoji: reaction, count: count)
        } else {
            existing.append(FakeReaction(emoji: reaction, count: count))
        }
        self.reactions[messageId] = existing
        self.lock.unlock()
    }

    public func setReactions(messageId: MessageId, reactions: [(String, Int)]) {
        self.lock.lock()
        self.reactions[messageId] = reactions.map { FakeReaction(emoji: $0.0, count: $0.1) }
        self.lock.unlock()
    }

    public func getReactions(messageId: MessageId) -> [FakeReaction] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.reactions[messageId] ?? []
    }

    public func hasReactions(messageId: MessageId) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return !(self.reactions[messageId]?.isEmpty ?? true)
    }

    public func removeReaction(messageId: MessageId, emoji: String) {
        self.lock.lock()
        self.reactions[messageId]?.removeAll(where: { $0.emoji == emoji })
        if self.reactions[messageId]?.isEmpty == true {
            self.reactions.removeValue(forKey: messageId)
        }
        self.lock.unlock()
    }

    public func clearReactions(messageId: MessageId) {
        self.lock.lock()
        self.reactions.removeValue(forKey: messageId)
        self.lock.unlock()
    }

    public func clearAll() {
        self.lock.lock()
        self.reactions.removeAll()
        self.lock.unlock()
    }
}
