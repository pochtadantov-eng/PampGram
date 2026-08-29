import Foundation
import TelegramCore

/// A record of a message the other side deleted, kept so it doesn't just vanish from view.
/// The resurrected copy the user actually sees lives as an ordinary local-only message in
/// the chat itself (see `PampGramDeletedMessageCapture`); this record is bookkeeping for the
/// "Сообщения" history screen and for finding/removing that local message later.
public struct PampGramDeletedMessage: Codable, Equatable, Identifiable {
    public let id: Int64
    public let peerId: EnginePeer.Id
    public let authorId: EnginePeer.Id?
    /// When the original message was sent, before it was deleted.
    public let originalTimestamp: Int32
    /// When PampGram noticed the deletion and captured this copy.
    public let deletedAt: Int32
    /// Short plain-text preview for the history list (empty for a media-only message).
    public let textPreview: String
    /// The resurrected local-only message this record is attached to. Namespace is always
    /// `Namespaces.Message.Local` — deleting it removes only this device's copy.
    public let localMessageId: EngineMessage.Id

    public init(id: Int64, peerId: EnginePeer.Id, authorId: EnginePeer.Id?, originalTimestamp: Int32, deletedAt: Int32, textPreview: String, localMessageId: EngineMessage.Id) {
        self.id = id
        self.peerId = peerId
        self.authorId = authorId
        self.originalTimestamp = originalTimestamp
        self.deletedAt = deletedAt
        self.textPreview = textPreview
        self.localMessageId = localMessageId
    }
}
