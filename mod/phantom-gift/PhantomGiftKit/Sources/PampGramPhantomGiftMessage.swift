import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import AccountContext

public enum PampGramPhantomGiftMessage {
    /// Stashed in the synthetic action's otherwise-unused `prepaidUpgradeHash` slot so
    /// `ChatMessageGiftBubbleContentNode` can tell a phantom card from a real one and swap
    /// the ribbon text to "Фантом". No real StarGift ever carries this exact value.
    public static let ribbonMarker = "pampgram-phantom-gift-marker"

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
                // The marker lives in `prepaidUpgradeHash` — a field only `.starGift` has.
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
                    prepaidUpgradeHash: ribbonMarker,
                    giftMessageId: nil,
                    upgradeSeparate: false,
                    isAuctionAcquired: false,
                    toPeerId: nil,
                    number: nil
                )
            case .unique:
                // Collectible instances (Model/Backdrop/Symbol rows) only render for
                // .starGiftUnique — .starGift silently drops a .unique gift value. This
                // case has no spare field, so PampGramUniqueGiftGenerator tags the gift's
                // own `slug` instead (checked in ChatMessageGiftBubbleContentNode).
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

            let storeMessage = StoreMessage(
                id: .Partial(peerId, Namespaces.Message.Local),
                customStableId: nil,
                globallyUniqueId: nil,
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
            return insertedIds.values.first
        }
    }
}
