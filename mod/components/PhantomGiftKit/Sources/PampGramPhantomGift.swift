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
    /// What the fake balance was actually charged — Stars or TON, matching whichever
    /// currency the real resale listing was priced in.
    public let price: CurrencyAmount
    public let date: Int32
    /// The id of the local-only chat message this gift is attached to, if one was created
    /// (see `PampGramPhantomGiftMessage.insertLocalUniqueGiftMessage`). Namespace is always
    /// `Namespaces.Message.Local` — never a real, syncable id. `nil` for a self-purchase
    /// (buying for your own collection never inserts a chat message, real or fake).
    public let localMessageId: EngineMessage.Id?
    /// True for the "Подарок мне" / "От него" flows (`receiveUniqueGift`/`receiveGenericGift`):
    /// nothing was ever deducted for these, so they never produce a debit in the Stars/TON
    /// transaction history. False (the default, including every gift saved before this field
    /// existed) means this gift was actually bought/sent and did debit `price` from the fake
    /// balance.
    public let isReceived: Bool
    /// Profile-grid state, meaningful only while `peerId == context.account.peerId` (that's
    /// the only case the gift is shown in the profile gifts grid at all). Mirrors
    /// `ProfileGiftsContext.State.StarGift.pinnedToTop`/`savedToProfile`.
    public let pinnedToTop: Bool
    public let savedToProfile: Bool
    /// Set when "Продать" was used on this gift (local-only stand-in for
    /// `convertStarGift`). The gift record itself is kept — deleting it would also erase
    /// the original purchase from the transaction history — just hidden from the grid via
    /// `savedToProfile = false`, with this timestamp marking when the matching "sale"
    /// credit transaction happened.
    public let soldDate: Int32?

    public init(id: Int64, peerId: EnginePeer.Id, gift: StarGift, price: CurrencyAmount, date: Int32, localMessageId: EngineMessage.Id?, isReceived: Bool = false, pinnedToTop: Bool = false, savedToProfile: Bool = true, soldDate: Int32? = nil) {
        self.id = id
        self.peerId = peerId
        self.gift = gift
        self.price = price
        self.date = date
        self.localMessageId = localMessageId
        self.isReceived = isReceived
        self.pinnedToTop = pinnedToTop
        self.savedToProfile = savedToProfile
        self.soldDate = soldDate
    }

    /// Decoded field by field, like `PampGramSettings`: a gift saved before `isReceived`/
    /// `pinnedToTop`/`savedToProfile` existed must still decode instead of throwing and
    /// silently discarding every previously-saved gift (a single failing array element fails
    /// the whole `[PampGramPhantomGift]` decode).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int64.self, forKey: .id)
        self.peerId = try container.decode(EnginePeer.Id.self, forKey: .peerId)
        self.gift = try container.decode(StarGift.self, forKey: .gift)
        self.price = try container.decode(CurrencyAmount.self, forKey: .price)
        self.date = try container.decode(Int32.self, forKey: .date)
        self.localMessageId = try container.decodeIfPresent(EngineMessage.Id.self, forKey: .localMessageId)
        self.isReceived = try container.decodeIfPresent(Bool.self, forKey: .isReceived) ?? false
        self.pinnedToTop = try container.decodeIfPresent(Bool.self, forKey: .pinnedToTop) ?? false
        self.savedToProfile = try container.decodeIfPresent(Bool.self, forKey: .savedToProfile) ?? true
        self.soldDate = try container.decodeIfPresent(Int32.self, forKey: .soldDate)
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

    public func withPinnedToTop(_ pinnedToTop: Bool) -> PampGramPhantomGift {
        return PampGramPhantomGift(id: self.id, peerId: self.peerId, gift: self.gift, price: self.price, date: self.date, localMessageId: self.localMessageId, isReceived: self.isReceived, pinnedToTop: pinnedToTop, savedToProfile: self.savedToProfile, soldDate: self.soldDate)
    }

    public func withSavedToProfile(_ savedToProfile: Bool) -> PampGramPhantomGift {
        return PampGramPhantomGift(id: self.id, peerId: self.peerId, gift: self.gift, price: self.price, date: self.date, localMessageId: self.localMessageId, isReceived: self.isReceived, pinnedToTop: self.pinnedToTop, savedToProfile: savedToProfile, soldDate: self.soldDate)
    }

    public func withSold(date: Int32) -> PampGramPhantomGift {
        return PampGramPhantomGift(id: self.id, peerId: self.peerId, gift: self.gift, price: self.price, date: self.date, localMessageId: self.localMessageId, isReceived: self.isReceived, pinnedToTop: false, savedToProfile: false, soldDate: date)
    }
}
