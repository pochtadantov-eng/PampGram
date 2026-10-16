import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore
import AccountContext

/// Tracks, per chat, which message (if any) "Изменить текст" (the "PampGram" long-press menu)
/// currently has queued for a local text edit — set the moment that menu item is tapped, read
/// and cleared by the Send-button interception in `ChatControllerNode.sendCurrentMessage` (see
/// the patch). One at a time per chat, same as stock Telegram's own real edit mode: picking
/// "Изменить текст" on a different message, or leaving the chat, simply overwrites/drops
/// whatever was pending without needing an explicit cancel path.
public final class PampGramVisualEditRuntime {
    public static let shared = PampGramVisualEditRuntime()

    private let lock = NSLock()
    private var pendingByPeer: [Int64: MessageId] = [:]

    private init() {
    }

    public func setPending(peerId: Int64, messageId: MessageId) {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.pendingByPeer[peerId] = messageId
    }

    public func pending(peerId: Int64) -> MessageId? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.pendingByPeer[peerId]
    }

    public func clearPending(peerId: Int64) {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.pendingByPeer.removeValue(forKey: peerId)
    }
}

/// Reached from a message's long-press menu ("PampGram" → "Изменить текст"), by way of the
/// chat's own message input field instead of a separate screen: picking the item pre-fills the
/// composer with the message's current text and arms `PampGramVisualEditRuntime`; typing
/// normally and tapping Send (see the `sendCurrentMessage` interception in the patch) calls
/// this with whatever the composer held, rewriting the message's text as stored in this
/// device's own Postbox via `Transaction.updateMessage`. Nothing is sent, the sender's own copy
/// is untouched. An empty result (the whole composer was cleared before sending) is a no-op —
/// there is no "clear a message's text" affordance here, only edits to something.
public func pampGramApplyVisualEditDirect(context: AccountContext, messageId: MessageId, text: String, entities: [MessageTextEntity] = [], inlineMedia: [Media] = []) {
    // `text` arrives already trimmed (the entity ranges refer to it), so it is stored as is.
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return
    }
    let _ = context.account.postbox.transaction { transaction -> Void in
        // The custom-emoji stickers the entities point at have to be in the media table for the
        // chat to draw them — the real send path stores them the same way.
        for file in inlineMedia {
            transaction.storeMediaIfNotPresent(media: file)
        }
        transaction.updateMessage(messageId, update: { message -> PostboxUpdateMessage in
            var attributes = message.attributes.filter { !($0 is TextEntitiesMessageAttribute) }
            if !entities.isEmpty {
                attributes.append(TextEntitiesMessageAttribute(entities: entities))
            }
            let updatedMessage = StoreMessage(
                id: messageId,
                customStableId: nil,
                globallyUniqueId: message.globallyUniqueId,
                groupingKey: message.groupingKey,
                threadId: message.threadId,
                timestamp: message.timestamp,
                flags: StoreMessageFlags(message.flags),
                tags: message.tags,
                globalTags: message.globalTags,
                localTags: message.localTags,
                forwardInfo: message.forwardInfo.map(StoreMessageForwardInfo.init),
                authorId: message.author?.id,
                text: text,
                attributes: attributes,
                media: message.media
            )
            return .update(updatedMessage)
        })
    }.start()
}
