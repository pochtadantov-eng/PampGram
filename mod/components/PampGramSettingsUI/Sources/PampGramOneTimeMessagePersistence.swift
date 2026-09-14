import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import AccountContext

/**
 PampGramOneTimeMessagePersistence — сохранение одноразовых сообщений
 ===================================================================

 Что это ДЕЙСТВИТЕЛЬНО делает (и чего не делает):

 - Копирует уже загруженный на это устройство ресурс одноразового
   фото/голосового (то, что Telegram уже скачал в свой mediaBox для
   показа) в собственную постоянную папку PampGram — независимо от
   дальнейшей судьбы исходного сообщения или кеша Telegram.
 - Снимает `AutoremoveTimeoutMessageAttribute` с самого сообщения, чтобы
   локальный планировщик Telegram не попытался удалить его из истории
   чата на этом устройстве.

 Чего здесь НЕТ и быть не может: собственного сервера для одноразовых
 медиа. "Одноразовость" в Telegram — это в первую очередь поведение
 СЕРВЕРА (после просмотра контент помечается использованным и сервер
 вправе его больше не отдавать); клиентский мод не может ретроактивно
 заставить чужой сервер хранить то, что он уже решил не хранить. Эта
 функция может сохранить то, что телефон уже успел скачать, — не больше.
 */

struct OneTimeMessageMetadata {
    let messageId: MessageId
    let isPersistent: Bool
    let savedFilePath: String?
    let savedAt: Date
}

private let oneTimeMessageStorageKey = "PampGram.OneTimeMessages"

private var oneTimeMessageStore: [String: OneTimeMessageMetadata] = {
    if let data = UserDefaults.standard.data(forKey: oneTimeMessageStorageKey),
       let decoded = try? JSONDecoder().decode([String: OneTimeMessageMetadata].self, from: data) {
        return decoded
    }
    return [:]
}()

private func pampGramOneTimeMessageKey(_ messageId: MessageId) -> String {
    return "\(messageId.peerId.toInt64())_\(messageId.namespace)_\(messageId.id)"
}

private func pampGramPersistOneTimeStore() {
    if let encoded = try? JSONEncoder().encode(oneTimeMessageStore) {
        UserDefaults.standard.set(encoded, forKey: oneTimeMessageStorageKey)
    }
}

private func pampGramExtractMediaResource(_ media: Media?) -> MediaResource? {
    if let image = media as? TelegramMediaImage {
        return image.representations.last?.resource
    } else if let file = media as? TelegramMediaFile {
        return file.resource
    }
    return nil
}

private func pampGramSuggestedExtension(for media: Media?) -> String {
    if media is TelegramMediaImage {
        return "jpg"
    } else if let file = media as? TelegramMediaFile {
        if file.isVoice {
            return "ogg"
        }
        if let fileName = file.fileName, let ext = fileName.split(separator: ".").last {
            return String(ext)
        }
        return "dat"
    }
    return "dat"
}

private func pampGramOneTimeMediaDirectory() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let dir = base.appendingPathComponent("PampGram/SavedOneTimeMedia", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func pampGramPersistOneTimeMediaFile(data: Data, suggestedExtension: String) -> String? {
    let dir = pampGramOneTimeMediaDirectory()
    let safeExtension = suggestedExtension.isEmpty ? "dat" : suggestedExtension
    let path = dir.appendingPathComponent("\(Int64.random(in: 1...Int64.max)).\(safeExtension)")
    do {
        try data.write(to: path, options: .atomic)
        return path.path
    } catch {
        return nil
    }
}

/// Снимает флаг самоуничтожения, чтобы локальный планировщик Telegram не
/// удалил сообщение из истории чата на этом устройстве.
private func pampGramRemoveOneTimeDestructFlag(context: AccountContext, messageId: MessageId) {
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

/// "PampGram" → "Сохранить одноразовое": копирует уже скачанный ресурс
/// фото/голосового в постоянную папку PampGram и снимает таймер
/// самоуничтожения. Лучше вызывать сразу при получении/открытии, пока
/// Telegram ещё не удалил локальный кеш ресурса.
public func pampGramSaveOneTimeMessage(context: AccountContext, messageId: MessageId, isPersistent: Bool = true) {
    let postbox = context.account.postbox
    let _ = (postbox.transaction { transaction -> Media? in
        return transaction.getMessage(messageId)?.media.first
    }
    |> mapToSignal { media -> Signal<String?, NoError> in
        guard let resource = pampGramExtractMediaResource(media) else {
            return .single(nil)
        }
        return postbox.mediaBox.resourceData(resource, option: .complete(waitUntilFetchStatus: false), attemptSynchronously: true)
        |> take(1)
        |> map { resourceData -> String? in
            guard resourceData.complete, let data = try? Data(contentsOf: URL(fileURLWithPath: resourceData.path)) else {
                return nil
            }
            return pampGramPersistOneTimeMediaFile(data: data, suggestedExtension: pampGramSuggestedExtension(for: media))
        }
    }
    |> deliverOnMainQueue).startStandalone(next: { savedFilePath in
        let metadata = OneTimeMessageMetadata(
            messageId: messageId,
            isPersistent: isPersistent,
            savedFilePath: savedFilePath,
            savedAt: Date()
        )
        oneTimeMessageStore[pampGramOneTimeMessageKey(messageId)] = metadata
        pampGramPersistOneTimeStore()

        if isPersistent {
            pampGramRemoveOneTimeDestructFlag(context: context, messageId: messageId)
        }
    })
}

/// Получает все сохранённые метаданные одноразовых сообщений.
public func pampGramGetOneTimeMessages() -> [OneTimeMessageMetadata] {
    return Array(oneTimeMessageStore.values)
}

/// Получает информацию о конкретном сообщении.
public func pampGramGetOneTimeMessageInfo(messageId: MessageId) -> OneTimeMessageMetadata? {
    return oneTimeMessageStore[pampGramOneTimeMessageKey(messageId)]
}

/// Удаляет запись из локального хранилища (сам скопированный файл не трогает).
public func pampGramRemoveOneTimeMessage(messageId: MessageId) {
    oneTimeMessageStore.removeValue(forKey: pampGramOneTimeMessageKey(messageId))
    pampGramPersistOneTimeStore()
}

// Codable conformance. `MessageId` is already `Codable` on its own (encodes
// peerId, namespace and id together), so it is stored as one nested value
// instead of being split into separate fields that would have to be
// reassembled (and could lose the namespace) by hand.
extension OneTimeMessageMetadata: Codable {
    enum CodingKeys: String, CodingKey {
        case messageId
        case isPersistent
        case savedFilePath
        case savedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.messageId = try container.decode(MessageId.self, forKey: .messageId)
        self.isPersistent = try container.decode(Bool.self, forKey: .isPersistent)
        self.savedFilePath = try container.decodeIfPresent(String.self, forKey: .savedFilePath)
        self.savedAt = try container.decode(Date.self, forKey: .savedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(messageId, forKey: .messageId)
        try container.encode(isPersistent, forKey: .isPersistent)
        try container.encodeIfPresent(savedFilePath, forKey: .savedFilePath)
        try container.encode(savedAt, forKey: .savedAt)
    }
}
