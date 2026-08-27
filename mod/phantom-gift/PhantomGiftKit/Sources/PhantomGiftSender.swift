import Foundation
import SwiftSignalKit
import TelegramCore
import AccountContext

/// Sends a "Фантом" gift: a completely ordinary chat message (no Stars charge, no
/// StarGift purchase, no server-side gift record) whose gift emoji carries a hidden
/// `phantomgift://` link. A stock Telegram client just shows the message text — the
/// emoji happens to be a link, tapping it does nothing recognizable. A mod client
/// intercepts that link (see `OpenUrl.swift`) and shows the full-screen reveal instead.
public enum PhantomGiftSender {
    private static let giftEmoji = "🎁"

    public static func send(context: AccountContext, peerId: EnginePeer.Id, gift: StarGift.Gift, senderName: String) -> Signal<Never, NoError> {
        guard let url = PhantomGiftLink.urlString(for: PhantomGiftPayload(giftId: gift.id, senderName: senderName)) else {
            return .complete()
        }

        let title = gift.title ?? "Gift"
        let text = "\(giftEmoji) Фантом-подарок «\(title)» — визуальный, ничего не покупалось и не передавалось по-настоящему."

        let emojiRange = NSRange(text.range(of: giftEmoji)!, in: text)
        let entity = MessageTextEntity(range: emojiRange.location ..< (emojiRange.location + emojiRange.length), type: .TextUrl(url: url))

        let message: EnqueueMessage = .message(
            text: text,
            attributes: [TextEntitiesMessageAttribute(entities: [entity])],
            inlineStickers: [:],
            mediaReference: nil,
            threadId: nil,
            replyToMessageId: nil,
            replyToStoryId: nil,
            localGroupingKey: nil,
            correlationId: nil,
            bubbleUpEmojiOrStickersets: []
        )

        return enqueueMessages(account: context.account, peerId: peerId, messages: [message])
        |> ignoreValues
    }
}
