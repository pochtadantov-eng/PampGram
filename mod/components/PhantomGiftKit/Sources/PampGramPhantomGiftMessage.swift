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
    public static func insertLocalGiftMessage(context: AccountContext, peerId: EnginePeer.Id, gift: StarGift, starPrice: Int64) -> Signal<EngineMessage.Id?, NoError> {
        return context.account.postbox.transaction { transaction -> EngineMessage.Id? in
            let actionType: TelegramMediaActionType
            switch gift {
            case .generic:
                actionType = .starGift(
                    gift: gift,
                    convertStars: starPrice,
                    text: nil,
                    entities: nil,
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
                )
            case .unique:
                // Collectible instances (Model/Backdrop/Symbol rows) only render for
                // .starGiftUnique — .starGift silently drops a .unique gift value.
                actionType = .starGiftUnique(
                    gift: gift,
                    isUpgrade: false,
                    isTransferred: false,
                    savedToProfile: true,
                    canExportDate: nil,
                    transferStars: starPrice,
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
                )
            }
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
