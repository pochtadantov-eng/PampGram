import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import AccountContext

public enum PampGramPhantomGiftMessage {
    /// `uniqueGift` is read straight from the real resale market, so its own `owner`/
    /// `resellAmounts` still reflect whoever actually lists it for sale there in reality —
    /// opening the gift card later (`GiftViewScreen`, reached by tapping the bubble) reads
    /// those same fields straight off the message and would show the real owner still
    /// selling it, undoing the whole illusion of a completed gift. This produces a copy with
    /// ownership reassigned to `newOwnerPeerId` and the resale listing cleared, exactly as a
    /// real purchase would leave it — every other field (model/backdrop/pattern/value/etc.)
    /// stays the genuine market data.
    private static func fakedOwnership(of uniqueGift: StarGift.UniqueGift, newOwnerPeerId: EnginePeer.Id) -> StarGift.UniqueGift {
        return StarGift.UniqueGift(
            id: uniqueGift.id,
            giftId: uniqueGift.giftId,
            title: uniqueGift.title,
            number: uniqueGift.number,
            slug: uniqueGift.slug,
            owner: .peerId(newOwnerPeerId),
            attributes: uniqueGift.attributes,
            availability: uniqueGift.availability,
            giftAddress: uniqueGift.giftAddress,
            resellAmounts: nil,
            resellForTonOnly: uniqueGift.resellForTonOnly,
            releasedBy: uniqueGift.releasedBy,
            valueAmount: uniqueGift.valueAmount,
            valueCurrency: uniqueGift.valueCurrency,
            valueUsdAmount: uniqueGift.valueUsdAmount,
            flags: uniqueGift.flags,
            themePeerId: uniqueGift.themePeerId,
            peerColor: uniqueGift.peerColor,
            hostPeerId: uniqueGift.hostPeerId,
            minOfferStars: uniqueGift.minOfferStars,
            craftChancePermille: uniqueGift.craftChancePermille
        )
    }

    /// Inserts a gift-card message into `peerId`'s local chat history — a real message the
    /// existing `ChatMessageGiftBubbleContentNode` will render exactly like a genuine one —
    /// but purely as a local Postbox transaction. `Namespaces.Message.Local` is the message
    /// id namespace Postbox reserves specifically for locally-generated messages (see e.g.
    /// `submodules/TelegramCore/Sources/Utils/StoredMessageFromSearchPeer.swift`); nothing
    /// in this call reaches `account.network`, so nothing is sent, and the standard "Delete
    /// Message" action already skips the server-side delete request for this namespace
    /// (`submodules/TelegramCore/Sources/TelegramEngine/Messages/DeleteMessagesInteractively.swift`),
    /// so deleting it later is also purely local for free.
    ///
    /// `uniqueGift` is always the real object read straight from the real market — its
    /// title, number, model/backdrop/pattern attributes are never fabricated here, so the
    /// resulting card is indistinguishable from a genuine purchase. `price` becomes
    /// `resaleAmount` — the field `ServiceMessageStrings.swift` checks to pick the caption:
    /// with it set, a purchase sent to someone else reads "Вы подарили {title} за {price}",
    /// matching the real resale-purchase text exactly; leaving it nil (as an earlier version
    /// of this function did) instead falls through to the *transfer* caption ("Вы передали
    /// уникальный коллекционный подарок"), which is wrong here — nothing was transferred,
    /// it was bought. `transferStars` stays nil regardless: that field is for a genuine
    /// peer-to-peer transfer of an already-owned gift, a different action entirely.
    public static func insertLocalUniqueGiftMessage(context: AccountContext, peerId: EnginePeer.Id, uniqueGift: StarGift.UniqueGift, price: CurrencyAmount) -> Signal<EngineMessage.Id?, NoError> {
        let uniqueGift = self.fakedOwnership(of: uniqueGift, newOwnerPeerId: peerId)
        return self.insert(context: context, peerId: peerId, authorId: context.account.peerId, incoming: false, actionType: .starGiftUnique(
            gift: .unique(uniqueGift),
            isUpgrade: false,
            isTransferred: false,
            savedToProfile: true,
            canExportDate: nil,
            transferStars: nil,
            isRefunded: false,
            isPrepaidUpgrade: false,
            peerId: nil,
            senderId: nil,
            savedId: nil,
            resaleAmount: price,
            canTransferDate: nil,
            canResaleDate: nil,
            dropOriginalDetailsStars: nil,
            assigned: true,
            fromOffer: false,
            canCraftAt: nil,
            isCrafted: false
        ))
    }

    /// "Подарок мне": same real, un-fabricated `uniqueGift`, but authored by the *other*
    /// side and flagged incoming, so the real rendering pipeline treats it exactly like a
    /// unique gift this account actually received — same card, same reveal/confetti, same
    /// left-aligned incoming bubble. `resaleAmount` is left nil on purpose: with it set,
    /// `ServiceMessageStrings.swift` picks the "bought it for you" caption, but a gift someone
    /// already owns handing it to you reads as a transfer ("X передал(а) вам подарок"), which
    /// is the caption real Telegram uses for exactly this situation.
    public static func insertLocalUniqueGiftMessageFromPeer(context: AccountContext, peerId: EnginePeer.Id, uniqueGift: StarGift.UniqueGift) -> Signal<EngineMessage.Id?, NoError> {
        let uniqueGift = self.fakedOwnership(of: uniqueGift, newOwnerPeerId: context.account.peerId)
        return self.insert(context: context, peerId: peerId, authorId: peerId, incoming: true, actionType: .starGiftUnique(
            gift: .unique(uniqueGift),
            isUpgrade: false,
            isTransferred: false,
            savedToProfile: true,
            canExportDate: nil,
            transferStars: nil,
            isRefunded: false,
            isPrepaidUpgrade: false,
            peerId: nil,
            senderId: nil,
            savedId: nil,
            resaleAmount: nil,
            canTransferDate: nil,
            canResaleDate: nil,
            dropOriginalDetailsStars: nil,
            assigned: true,
            fromOffer: false,
            canCraftAt: nil,
            isCrafted: false
        ))
    }

    /// Same as `insertLocalUniqueGiftMessage`, for the plain (non-unique) gift catalog —
    /// the "Подарок" tab's send-a-fresh-gift path (see GiftSetupScreen.swift), as opposed to
    /// buying a specific numbered instance off the resale market. `gift` is the real
    /// `StarGift.Gift` from the real catalog, so `convertStars` (the "или обменять на N
    /// звёзд" line) comes from Telegram's own real catalog value, not the price paid — a
    /// gift's convert value is usually lower than its price, exactly like a real purchase.
    public static func insertLocalGenericGiftMessage(context: AccountContext, peerId: EnginePeer.Id, gift: StarGift.Gift, text: String?, entities: [MessageTextEntity]?, nameHidden: Bool) -> Signal<EngineMessage.Id?, NoError> {
        return self.insert(context: context, peerId: peerId, authorId: context.account.peerId, incoming: false, actionType: .starGift(
            gift: .generic(gift),
            convertStars: gift.convertStars,
            text: text,
            entities: entities,
            nameHidden: nameHidden,
            savedToProfile: true,
            converted: false,
            upgraded: false,
            canUpgrade: false,
            upgradeStars: nil,
            isRefunded: false,
            isPrepaidUpgrade: false,
            upgradeMessageId: nil,
            peerId: nil,
            senderId: nil,
            savedId: nil,
            prepaidUpgradeHash: nil,
            giftMessageId: nil,
            upgradeSeparate: false,
            isAuctionAcquired: false,
            toPeerId: nil,
            number: nil
        ))
    }

    /// Same reversal as `insertLocalUniqueGiftMessageFromPeer`, for the plain (non-unique)
    /// gift catalog. `nameHidden` isn't offered here — hiding the sender's name would hide
    /// the exact person this whole feature exists to show as the sender, defeating the point.
    public static func insertLocalGenericGiftMessageFromPeer(context: AccountContext, peerId: EnginePeer.Id, gift: StarGift.Gift, text: String?, entities: [MessageTextEntity]?) -> Signal<EngineMessage.Id?, NoError> {
        return self.insert(context: context, peerId: peerId, authorId: peerId, incoming: true, actionType: .starGift(
            gift: .generic(gift),
            convertStars: gift.convertStars,
            text: text,
            entities: entities,
            nameHidden: false,
            savedToProfile: true,
            converted: false,
            upgraded: false,
            canUpgrade: false,
            upgradeStars: nil,
            isRefunded: false,
            isPrepaidUpgrade: false,
            upgradeMessageId: nil,
            peerId: nil,
            senderId: nil,
            savedId: nil,
            prepaidUpgradeHash: nil,
            giftMessageId: nil,
            upgradeSeparate: false,
            isAuctionAcquired: false,
            toPeerId: nil,
            number: nil
        ))
    }

    private static func insert(context: AccountContext, peerId: EnginePeer.Id, authorId: EnginePeer.Id, incoming: Bool, actionType: TelegramMediaActionType) -> Signal<EngineMessage.Id?, NoError> {
        return context.account.postbox.transaction { transaction -> EngineMessage.Id? in
            let action = TelegramMediaAction(action: actionType)

            // Postbox returns the assigned MessageId keyed by globallyUniqueId, and only for
            // messages that actually carry one (MessageHistoryTable.addMessages) — with nil
            // here the result map comes back empty and we'd never learn the id, so deleting
            // the gift later could not also remove its chat message. Real locally-created
            // messages set this too; it is a purely local dedup key.
            let globallyUniqueId = Int64.random(in: Int64.min ... Int64.max)
            let storeMessage = StoreMessage(
                id: .Partial(peerId, Namespaces.Message.Local),
                customStableId: nil,
                globallyUniqueId: globallyUniqueId,
                groupingKey: nil,
                threadId: nil,
                timestamp: Int32(Date().timeIntervalSince1970),
                flags: incoming ? StoreMessageFlags.Incoming : StoreMessageFlags(),
                tags: [],
                globalTags: [],
                localTags: [],
                forwardInfo: nil,
                authorId: authorId,
                text: "",
                attributes: [],
                media: [action]
            )

            let insertedIds = transaction.addMessages([storeMessage], location: .Random)
            return insertedIds[globallyUniqueId]
        }
    }
}
