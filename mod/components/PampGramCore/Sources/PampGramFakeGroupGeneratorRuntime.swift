import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import AccountContext

/// «Генератор фейк-группы» — создаёт целый фейковый групповой чат с участниками,
/// аватарками, сообщениями и медиа. Не настоящая группа Telegram — визуальная копия,
/// отображаемая как visual chat.
///
/// Workflow:
/// 1. Пользователь открывает «Генератор группы» (Дополнительно → Тёмные штуки).
/// 2. Задаёт: название группы, список участников (имя + цвет аватарки + роль),
///    и сообщения (от кого, текст, время, реакции).
/// 3. «Создать» — рантайм генерирует набор данных, которые visual-chat слой
///    отображает как обычный групповой чат.
///
/// Integration point (в патче):
///
/// Экран настройки группы в `PampGramSettingsUI`:
/// ```swift
/// let config = PampGramFakeGroupGeneratorRuntime.FakeGroupChat(
///     name: "Бизнес-клуб",
///     members: [
///         .init(name: "Дмитрий", avatarColorHex: 0x007aff, isAdmin: true),
///         .init(name: "Мария", avatarColorHex: 0xff2d55, isAdmin: false),
///     ],
///     messages: [
///         .init(senderIndex: 0, text: "Всем привет!", timestamp: 1700000000, reactions: [("👍", 3)]),
///         .init(senderIndex: 1, text: "Здравствуйте!", timestamp: 1700000060, reactions: []),
///     ],
///     memberCount: 1247
/// )
/// PampGramFakeGroupGeneratorRuntime.shared.setActiveGroup(config)
/// ```
///
/// В отображении чата:
/// ```swift
/// if let group = PampGramFakeGroupGeneratorRuntime.shared.activeGroup {
///     // Рендерим group.messages как visual-chat сообщения
///     // group.members[msg.senderIndex].name — имя отправителя
///     // group.name — название группы в навбаре
///     // group.memberCount — число участников под названием
/// }
/// ```
public final class PampGramFakeGroupGeneratorRuntime {
    public static let shared = PampGramFakeGroupGeneratorRuntime()

    public struct FakeGroupMember {
        public let name: String
        public let avatarColorHex: UInt32
        public let isAdmin: Bool

        public init(name: String, avatarColorHex: UInt32, isAdmin: Bool) {
            self.name = name
            self.avatarColorHex = avatarColorHex
            self.isAdmin = isAdmin
        }
    }

    public struct FakeGroupMessage {
        public let senderIndex: Int
        public let text: String
        public let timestamp: Int32
        public let reactions: [(String, Int)]

        public init(senderIndex: Int, text: String, timestamp: Int32, reactions: [(String, Int)]) {
            self.senderIndex = senderIndex
            self.text = text
            self.timestamp = timestamp
            self.reactions = reactions
        }
    }

    public struct FakeGroupChat {
        public let name: String
        public let members: [FakeGroupMember]
        public let messages: [FakeGroupMessage]
        public let memberCount: Int

        public init(name: String, members: [FakeGroupMember], messages: [FakeGroupMessage], memberCount: Int) {
            self.name = name
            self.members = members
            self.messages = messages
            self.memberCount = memberCount
        }
    }

    private let lock = NSLock()
    private var _activeGroup: FakeGroupChat?

    private init() {}

    public var activeGroup: FakeGroupChat? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self._activeGroup
    }

    public func setActiveGroup(_ group: FakeGroupChat?) {
        self.lock.lock()
        self._activeGroup = group
        self.lock.unlock()
    }

    public func clearActiveGroup() {
        setActiveGroup(nil)
    }

    public var hasActiveGroup: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self._activeGroup != nil
    }
}
