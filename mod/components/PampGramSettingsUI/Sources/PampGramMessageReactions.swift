import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import AccountContext

/**
 PampGramMessageReactions — реакции эмодзи на сообщения
 ======================================================

 Позволяет добавлять эмодзи-реакции к любому сообщению (текст, фото, голос, стикер).
 Реакции сохраняются локально и видны только на этом устройстве.
 */

struct MessageReaction {
    let emoji: String
    let messageId: MessageId
    let addedAt: Date

    var key: String {
        return "\(messageId.peerId.namespace)_\(messageId.id)_\(emoji)"
    }
}

private let messageReactionsStorageKey = "PampGram.MessageReactions"

private var messageReactionsStore: [String: MessageReaction] = {
    if let data = UserDefaults.standard.data(forKey: messageReactionsStorageKey),
       let decoded = try? JSONDecoder().decode([String: MessageReaction].self, from: data) {
        return decoded
    }
    return [:]
}()

/// Добавляет реакцию к сообщению
public func pampGramAddMessageReaction(
    messageId: MessageId,
    emoji: String
) {
    let reaction = MessageReaction(
        emoji: emoji,
        messageId: messageId,
        addedAt: Date()
    )

    messageReactionsStore[reaction.key] = reaction
    saveReactions()
}

/// Удаляет реакцию со сообщения
public func pampGramRemoveMessageReaction(
    messageId: MessageId,
    emoji: String
) {
    let key = "\(messageId.peerId.namespace)_\(messageId.id)_\(emoji)"
    messageReactionsStore.removeValue(forKey: key)
    saveReactions()
}

/// Получает все реакции для сообщения
public func pampGramGetMessageReactions(messageId: MessageId) -> [String] {
    return messageReactionsStore.values
        .filter { $0.messageId == messageId }
        .map { $0.emoji }
}

/// Проверяет есть ли реакция на сообщении
public func pampGramHasMessageReaction(messageId: MessageId, emoji: String) -> Bool {
    let key = "\(messageId.peerId.namespace)_\(messageId.id)_\(emoji)"
    return messageReactionsStore[key] != nil
}

/// Получает все реакции
public func pampGramGetAllMessageReactions() -> [MessageReaction] {
    return Array(messageReactionsStore.values)
}

/// Переключает реакцию (добавляет или удаляет)
public func pampGramToggleMessageReaction(messageId: MessageId, emoji: String) {
    if pampGramHasMessageReaction(messageId: messageId, emoji: emoji) {
        pampGramRemoveMessageReaction(messageId: messageId, emoji: emoji)
    } else {
        pampGramAddMessageReaction(messageId: messageId, emoji: emoji)
    }
}

/// Удаляет все реакции со сообщения
public func pampGramClearMessageReactions(messageId: MessageId) {
    let reactionsToRemove = messageReactionsStore.values
        .filter { $0.messageId == messageId }
        .map { $0.key }

    for key in reactionsToRemove {
        messageReactionsStore.removeValue(forKey: key)
    }

    saveReactions()
}

/// Сохраняет реакции в UserDefaults
private func saveReactions() {
    if let encoded = try? JSONEncoder().encode(messageReactionsStore) {
        UserDefaults.standard.set(encoded, forKey: messageReactionsStorageKey)
    }
}

/// Получает популярные эмодзи
public func pampGramGetPopularEmojis() -> [String] {
    return [
        "👍", "❤️", "😂", "😮", "😢", "😡", "🔥", "👏", "🙏", "💯",
        "✨", "🎉", "🎈", "🎁", "🌹", "💐", "⭐", "💫", "🌟", "💥",
        "😍", "😘", "😌", "😎", "🤔", "🤨", "😏", "😋", "😜", "🤣",
        "🥰", "😇", "🤗", "😏", "💩", "👻", "🤐", "😈", "🤡", "🎭"
    ]
}

// Codable conformance
extension MessageReaction: Codable {
    enum CodingKeys: String, CodingKey {
        case emoji
        case peerId
        case messageId
        case addedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let emoji = try container.decode(String.self, forKey: .emoji)
        let peerIdValue = try container.decode(Int64.self, forKey: .peerId)
        let messageIdValue = try container.decode(Int32.self, forKey: .messageId)
        let addedAt = try container.decode(Date.self, forKey: .addedAt)

        self.emoji = emoji
        self.messageId = MessageId(peerId: PeerId(peerIdValue), namespace: Namespaces.Message.Local, id: messageIdValue)
        self.addedAt = addedAt
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(emoji, forKey: .emoji)
        try container.encode(messageId.peerId.toInt64(), forKey: .peerId)
        try container.encode(messageId.id, forKey: .messageId)
        try container.encode(addedAt, forKey: .addedAt)
    }
}
