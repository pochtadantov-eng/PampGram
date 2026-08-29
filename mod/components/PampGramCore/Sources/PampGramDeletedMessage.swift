import Foundation
import Postbox

/// A record of a message the other side deleted, kept so it doesn't just vanish from view.
/// The resurrected copy the user actually sees lives as an ordinary local-only message in the
/// chat itself (built in `TelegramCore`'s deletion pipeline — see the patch to
/// `AccountStateManagementUtils.swift` — since only that module has the message-content types
/// needed to rebuild one); this record is bookkeeping for the "Сообщения" history screen and
/// for finding/removing that local message later.
///
/// Deliberately spelled with the raw Postbox `PeerId`/`MessageId` rather than TelegramCore's
/// `EnginePeer.Id`/`EngineMessage.Id` aliases: this file has to stay reachable from
/// `TelegramCore` itself (which captures the deletion), and `PampGramCore` must never depend
/// on `TelegramCore` in turn, or the module graph cycles.
public struct PampGramDeletedMessage: Codable, Equatable, Identifiable {
    public let id: Int64
    public let peerId: PeerId
    public let authorId: PeerId?
    /// When the original message was sent, before it was deleted.
    public let originalTimestamp: Int32
    /// When PampGram noticed the deletion and captured this copy.
    public let deletedAt: Int32
    /// Short plain-text preview for the history list (a media type name for a media-only
    /// message, e.g. "Фото").
    public let textPreview: String
    /// The resurrected local-only message this record is attached to. Namespace is always
    /// the reserved local one — deleting it removes only this device's copy.
    public let localMessageId: MessageId

    public init(id: Int64, peerId: PeerId, authorId: PeerId?, originalTimestamp: Int32, deletedAt: Int32, textPreview: String, localMessageId: MessageId) {
        self.id = id
        self.peerId = peerId
        self.authorId = authorId
        self.originalTimestamp = originalTimestamp
        self.deletedAt = deletedAt
        self.textPreview = textPreview
        self.localMessageId = localMessageId
    }
}
