import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import AccountContext

/**
 PampGramOneTimeMessagePersistence — сохранение одноразовых сообщений
 ===================================================================

 Позволяет сохранять одноразовые (self-destructing) фото и голосовые сообщения,
 чтобы они не удалялись и оставались на сервере.
 */

struct OneTimeMessageMetadata {
    let messageId: MessageId
    let isPersistent: Bool
    let originalTTL: Int32?
    let savedAt: Date
}

/// Хранилище метаданных одноразовых сообщений
private let oneTimeMessageStorageKey = "PampGram.OneTimeMessages"

private var oneTimeMessageStore: [String: OneTimeMessageMetadata] = {
    if let data = UserDefaults.standard.data(forKey: oneTimeMessageStorageKey),
       let decoded = try? JSONDecoder().decode([String: OneTimeMessageMetadata].self, from: data) {
        return decoded
    }
    return [:]
}()

/// Сохраняет одноразовое сообщение
public func pampGramSaveOneTimeMessage(
    context: AccountContext,
    messageId: MessageId,
    isPersistent: Bool = false
) {
    let metadata = OneTimeMessageMetadata(
        messageId: messageId,
        isPersistent: isPersistent,
        originalTTL: nil,
        savedAt: Date()
    )

    let key = "\(messageId.peerId.namespace)_\(messageId.id)"
    oneTimeMessageStore[key] = metadata

    if let encoded = try? JSONEncoder().encode(oneTimeMessageStore) {
        UserDefaults.standard.set(encoded, forKey: oneTimeMessageStorageKey)
    }

    // Если сообщение должно быть постоянным, удаляем флаг self-destruct
    if isPersistent {
        pampGramRemoveOneTimeDestructFlag(context: context, messageId: messageId)
    }
}

/// Удаляет флаг самоуничтожения сообщения
private func pampGramRemoveOneTimeDestructFlag(
    context: AccountContext,
    messageId: MessageId
) {
    let _ = context.account.postbox.transaction { transaction -> Void in
        transaction.updateMessage(messageId, update: { currentMessage -> PostboxUpdateMessage in
            let attributes = currentMessage.attributes.filter { !($0 is AutoremoveTimeoutMessageAttribute) }

            let updatedMessage = StoreMessage(
                id: messageId,
                customStableId: currentMessage.customStableId,
                globallyUniqueId: currentMessage.globallyUniqueId,
                groupingKey: currentMessage.groupingKey,
                threadId: currentMessage.threadId,
                timestamp: currentMessage.timestamp,
                flags: StoreMessageFlags(currentMessage.flags),
                tags: currentMessage.tags,
                globalTags: currentMessage.globalTags,
                localTags: currentMessage.localTags,
                forwardInfo: currentMessage.forwardInfo.map(StoreMessageForwardInfo.init),
                authorId: currentMessage.author?.id,
                text: currentMessage.text,
                attributes: attributes,
                media: currentMessage.media
            )

            return .update(updatedMessage)
        })
    }.start()
}

/// Получает все сохраненные одноразовые сообщения
public func pampGramGetOneTimeMessages() -> [OneTimeMessageMetadata] {
    return Array(oneTimeMessageStore.values)
}

/// Получает информацию о конкретном сообщении
public func pampGramGetOneTimeMessageInfo(messageId: MessageId) -> OneTimeMessageMetadata? {
    let key = "\(messageId.peerId.namespace)_\(messageId.id)"
    return oneTimeMessageStore[key]
}

/// Удаляет сообщение из хранилища
public func pampGramRemoveOneTimeMessage(messageId: MessageId) {
    let key = "\(messageId.peerId.namespace)_\(messageId.id)"
    oneTimeMessageStore.removeValue(forKey: key)

    if let encoded = try? JSONEncoder().encode(oneTimeMessageStore) {
        UserDefaults.standard.set(encoded, forKey: oneTimeMessageStorageKey)
    }
}

/// Помечает сообщение как персистентное (не удаляется)
public func pampGramMakeOneTimeMessagePersistent(
    context: AccountContext,
    messageId: MessageId
) {
    let key = "\(messageId.peerId.namespace)_\(messageId.id)"

    if var metadata = oneTimeMessageStore[key] {
        metadata = OneTimeMessageMetadata(
            messageId: messageId,
            isPersistent: true,
            originalTTL: metadata.originalTTL,
            savedAt: metadata.savedAt
        )
        oneTimeMessageStore[key] = metadata

        if let encoded = try? JSONEncoder().encode(oneTimeMessageStore) {
            UserDefaults.standard.set(encoded, forKey: oneTimeMessageStorageKey)
        }

        pampGramRemoveOneTimeDestructFlag(context: context, messageId: messageId)
    }
}

/// Восстанавливает одноразовое сообщение из кэша
public func pampGramRestoreOneTimeMessage(
    context: AccountContext,
    messageId: MessageId
) -> Signal<Bool, NoError> {
    return context.account.postbox.transaction { transaction -> Bool in
        return transaction.getMessage(messageId) != nil
    }
}

// Codable conformance for storage
extension OneTimeMessageMetadata: Codable {
    enum CodingKeys: String, CodingKey {
        case peerId
        case messageId
        case isPersistent
        case originalTTL
        case savedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let peerIdValue = try container.decode(Int64.self, forKey: .peerId)
        let idValue = try container.decode(Int32.self, forKey: .messageId)

        self.messageId = MessageId(peerId: PeerId(peerIdValue), namespace: Namespaces.Message.Local, id: idValue)
        self.isPersistent = try container.decode(Bool.self, forKey: .isPersistent)
        self.originalTTL = try container.decodeIfPresent(Int32.self, forKey: .originalTTL)
        self.savedAt = try container.decode(Date.self, forKey: .savedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(messageId.peerId.toInt64(), forKey: .peerId)
        try container.encode(messageId.id, forKey: .messageId)
        try container.encode(isPersistent, forKey: .isPersistent)
        try container.encodeIfPresent(originalTTL, forKey: .originalTTL)
        try container.encode(savedAt, forKey: .savedAt)
    }
}
