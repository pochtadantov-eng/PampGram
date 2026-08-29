import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import AccountContext

public enum PampGramPhantomGiftMessage {
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
    /// resulting card is indistinguishable from a genuine purchase. `transferStars` is left
    /// nil: that field captions a peer-to-peer *transfer*, not a market purchase, and a real
    /// purchase's bubble doesn't restate the price either — the buy confirmation and the
    /// success toast already showed it.
    public static func insertLocalUniqueGiftMessage(context: AccountContext, peerId: EnginePeer.Id, uniqueGift: StarGift.UniqueGift) -> Signal<EngineMessage.Id?, NoError> {
        return self.insert(context: context, peerId: peerId, actionType: .starGiftUnique(
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
        return self.insert(context: context, peerId: peerId, actionType: .starGift(
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

    private static func insert(context: AccountContext, peerId: EnginePeer.Id, actionType: TelegramMediaActionType) -> Signal<EngineMessage.Id?, NoError> {
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
                flags: StoreMessageFlags(),
                tags: [],
                globalTags: [],
                localTags: [],
                forwardInfo: nil,
                authorId: context.account.peerId,
                text: "",
                attributes: [],
                media: [action]
            )

            let insertedIds = transaction.addMessages([storeMessage], location: .Random)
            return insertedIds[globallyUniqueId]
        }
    }
}
