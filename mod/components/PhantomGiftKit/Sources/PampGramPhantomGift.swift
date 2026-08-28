import Foundation
import TelegramCore

/// A gift that exists ONLY on this device: never purchased, never sent to Telegram's
/// servers, never visible to the peer's own account. `reference == nil` on the embedded
/// `ProfileGiftsContext.State.StarGift` (when one is built from this) is what marks it as
/// non-real everywhere it's consumed — real gifts always carry a server `StarGiftReference`.
public struct PampGramPhantomGift: Codable, Equatable, Identifiable {
    public let id: Int64
    public let peerId: EnginePeer.Id
    public let gift: StarGift
    public let starPrice: Int64
    public let date: Int32
    /// The id of the local-only chat message this gift is attached to, if one was created
    /// (see `PampGramPhantomGiftMessage.insertLocalGiftMessage`). Namespace is always
    /// `Namespaces.Message.Local` — never a real, syncable id.
    public let localMessageId: EngineMessage.Id?

    public init(id: Int64, peerId: EnginePeer.Id, gift: StarGift, starPrice: Int64, date: Int32, localMessageId: EngineMessage.Id?) {
        self.id = id
        self.peerId = peerId
        self.gift = gift
        self.starPrice = starPrice
        self.date = date
        self.localMessageId = localMessageId
    }

    public var title: String {
        switch self.gift {
        case let .generic(gift):
            return gift.title ?? "Gift"
        case let .unique(gift):
            return gift.title
        }
    }

    public var number: Int32? {
        switch self.gift {
        case .generic:
            return nil
        case let .unique(gift):
            return gift.number
        }
    }
}
