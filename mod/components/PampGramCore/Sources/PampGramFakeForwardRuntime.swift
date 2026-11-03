import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import AccountContext

/// "Фейк пересылка от..." — локально помечает любое сообщение как пересланное от выбранного
/// пользователя или канала. На скриншоте выглядит неотличимо от настоящей пересылки.
///
/// Хранит маппинг `MessageId → FakeForwardInfo` в памяти. При рендеринге пузыря патч
/// проверяет, есть ли для данного сообщения фейковая пересылка, и рисует шапку
/// "Переслано от <имя>" вместо (или поверх) настоящей.
///
/// Integration points (в патче):
///
/// 1. Контекстное меню сообщения — добавить пункт «Фейк пересылка от...»:
///    ```swift
///    items.append(.action(ContextMenuActionItem(
///        text: "Фейк пересылка от...",
///        icon: { theme in generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Forward"), color: theme.contextMenu.primaryColor) },
///        action: { c, _ in
///            c?.dismiss(completion: {
///                // Открыть пикер контактов/каналов, затем:
///                PampGramFakeForwardRuntime.shared.setFakeForward(
///                    messageId: message.id,
///                    fromPeerId: selectedPeer.id,
///                    fromName: selectedPeer.displayTitle
///                )
///                // Перерисовать ячейку
///            })
///        }
///    )))
///    ```
///
/// 2. В рендеринге пузыря (`ChatMessageBubbleItemNode` или `ChatMessageForwardInfoNode`):
///    ```swift
///    if let fakeForward = PampGramFakeForwardRuntime.shared.getFakeForward(messageId: message.id) {
///        // Рисовать шапку "Переслано от <fakeForward.fromName>" вместо настоящей
///    }
///    ```
///
/// 3. Сброс — контекстное меню «Убрать фейк пересылку»:
///    ```swift
///    PampGramFakeForwardRuntime.shared.clearFakeForward(messageId: message.id)
///    ```
public final class PampGramFakeForwardRuntime {
    public static let shared = PampGramFakeForwardRuntime()

    public struct FakeForwardInfo {
        public let fromPeerId: PeerId?
        public let fromName: String
        public let date: Int32

        public init(fromPeerId: PeerId?, fromName: String, date: Int32 = Int32(Date().timeIntervalSince1970)) {
            self.fromPeerId = fromPeerId
            self.fromName = fromName
            self.date = date
        }
    }

    private let lock = NSLock()
    private var forwards: [MessageId: FakeForwardInfo] = [:]

    private init() {}

    public func setFakeForward(messageId: MessageId, fromPeerId: PeerId?, fromName: String) {
        let info = FakeForwardInfo(fromPeerId: fromPeerId, fromName: fromName)
        self.lock.lock()
        self.forwards[messageId] = info
        self.lock.unlock()
    }

    public func getFakeForward(messageId: MessageId) -> FakeForwardInfo? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.forwards[messageId]
    }

    public func hasFakeForward(messageId: MessageId) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.forwards[messageId] != nil
    }

    public func clearFakeForward(messageId: MessageId) {
        self.lock.lock()
        self.forwards.removeValue(forKey: messageId)
        self.lock.unlock()
    }

    public func clearAll() {
        self.lock.lock()
        self.forwards.removeAll()
        self.lock.unlock()
    }
}
