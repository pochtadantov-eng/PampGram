import Foundation
import Postbox

/// «Машина времени чата» — локально меняет отображаемый timestamp у любого сообщения.
///
/// Сообщение от вчера становится от месяца назад, или от 3:00 ночи. Реальный timestamp
/// на сервере не меняется — только отображение на этом устройстве. Идеально для
/// скриншотов с нужными датами.
///
/// Integration points (в патче):
///
/// 1. Контекстное меню на любом сообщении → «Изменить время»:
///
///    ```swift
///    items.append(.action(ContextMenuActionItem(
///        text: "Изменить время",
///        icon: { theme in generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Timer"), color: theme.contextMenu.primaryColor) },
///        action: { c, _ in
///            c?.dismiss(completion: {
///                // Открыть date/time picker, затем:
///                PampGramChatTimeMachineRuntime.shared.setOverrideTimestamp(
///                    messageId: message.id,
///                    timestamp: Int32(selectedDate.timeIntervalSince1970)
///                )
///                // Обновить отображение чата
///            })
///        }
///    )))
///    ```
///
/// 2. В рендеринге времени сообщения (`ChatMessageDateAndStatusNode`, `ChatMessageItem` и т.п.):
///
///    ```swift
///    let displayTimestamp: Int32
///    if let override = PampGramChatTimeMachineRuntime.shared.getOverrideTimestamp(messageId: message.id) {
///        displayTimestamp = override
///    } else {
///        displayTimestamp = message.timestamp
///    }
///    ```
///
/// 3. В контекстном меню, если время уже изменено, добавить «Сбросить время»:
///
///    ```swift
///    if PampGramChatTimeMachineRuntime.shared.getOverrideTimestamp(messageId: message.id) != nil {
///        items.append(.action(ContextMenuActionItem(
///            text: "Сбросить время",
///            action: { c, _ in
///                c?.dismiss(completion: {
///                    PampGramChatTimeMachineRuntime.shared.clearOverride(messageId: message.id)
///                })
///            }
///        )))
///    }
///    ```
public final class PampGramChatTimeMachineRuntime {
    public static let shared = PampGramChatTimeMachineRuntime()

    private let lock = NSLock()
    private var overrides: [MessageId: Int32] = [:]

    private init() {}

    /// Устанавливает кастомный timestamp для сообщения.
    /// `timestamp` — unix time (секунды с 1970).
    public func setOverrideTimestamp(messageId: MessageId, timestamp: Int32) {
        self.lock.lock()
        self.overrides[messageId] = timestamp
        self.lock.unlock()
    }

    /// Возвращает кастомный timestamp для сообщения, или nil если не установлен.
    public func getOverrideTimestamp(messageId: MessageId) -> Int32? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.overrides[messageId]
    }

    /// Убирает кастомный timestamp — сообщение снова показывает реальное время.
    public func clearOverride(messageId: MessageId) {
        self.lock.lock()
        self.overrides.removeValue(forKey: messageId)
        self.lock.unlock()
    }

    /// Проверяет, есть ли переопределённое время для данного сообщения.
    public func hasOverride(messageId: MessageId) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.overrides[messageId] != nil
    }

    /// Количество сообщений с изменённым временем.
    public var overrideCount: Int {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.overrides.count
    }

    /// Сбрасывает все переопределения времени.
    public func clearAll() {
        self.lock.lock()
        self.overrides.removeAll()
        self.lock.unlock()
    }

    /// Сбрасывает все переопределения для конкретного чата.
    public func clearAll(peerId: PeerId) {
        self.lock.lock()
        self.overrides = self.overrides.filter { $0.key.peerId != peerId }
        self.lock.unlock()
    }
}
