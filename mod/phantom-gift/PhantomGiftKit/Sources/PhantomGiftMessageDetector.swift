import Foundation
import TelegramCore

/// Turns a plain-text "Фантом" message back into a fake-but-locally-rendered
/// `TelegramMediaAction.starGift` so the chat bubble list (`ChatMessageBubbleItemNode`)
/// can reuse the real, polished `ChatMessageGiftBubbleContentNode` for it — same card
/// layout, same ribbon mechanics — without ever touching a real StarGift purchase or a
/// real server-issued action. Nothing here is sent anywhere; it only exists for the
/// duration of one layout pass, on-device, from data the message text already carries.
public enum PhantomGiftMessageDetector {
    /// Stashed in the synthetic action's otherwise-unused `prepaidUpgradeHash` slot so
    /// `ChatMessageGiftBubbleContentNode` can tell a phantom card from a real one and
    /// swap the ribbon text to "Фантом". No real StarGift ever carries this value.
    public static let ribbonMarker = "pampgram-phantom-gift-marker"

    public static func detectPayload(text: String, attributes: [EngineMessage.Attribute]) -> PhantomGiftPayload? {
        guard !text.isEmpty else {
            return nil
        }
        for attribute in attributes {
            guard let entitiesAttribute = attribute as? TextEntitiesMessageAttribute else {
                continue
            }
            for entity in entitiesAttribute.entities {
                if case let .TextUrl(urlString) = entity.type, let url = URL(string: urlString), let payload = PhantomGiftLink.payload(from: url) {
                    return payload
                }
            }
        }
        return nil
    }

    public static func syntheticAction(for payload: PhantomGiftPayload, authorId: EnginePeer.Id?) -> TelegramMediaAction {
        return TelegramMediaAction(action: .starGift(
            gift: .generic(payload.gift),
            convertStars: nil,
            text: nil,
            entities: nil,
            nameHidden: false,
            savedToProfile: false,
            converted: false,
            upgraded: false,
            canUpgrade: false,
            upgradeStars: nil,
            isRefunded: false,
            isPrepaidUpgrade: false,
            upgradeMessageId: nil,
            peerId: nil,
            senderId: authorId,
            savedId: nil,
            prepaidUpgradeHash: ribbonMarker,
            giftMessageId: nil,
            upgradeSeparate: false,
            isAuctionAcquired: false,
            toPeerId: nil,
            number: nil
        ))
    }
}
