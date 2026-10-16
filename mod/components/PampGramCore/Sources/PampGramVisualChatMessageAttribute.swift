import Foundation
import Postbox

/// Marks a message as one inserted by "Сделать визуальный чат" (long-press the peer avatar in
/// a chat's nav bar) — a local-only message whose side (incoming/outgoing) can be flipped after
/// the fact by tapping the avatar-shaped button this attribute makes `ChatMessageItemImpl`/
/// `ChatMessageDateHeader` show to its left, instead of picking the side up front. Carries no
/// data of its own: the side itself already lives in the message's own `StoreMessageFlags`/
/// `authorId`, exactly like every other PampGram local insert.
///
/// Registered with `declareEncodable` in `TelegramCore/Sources/Account/AccountManager.swift`
/// (see the patch), same as `PampGramDeletedByRemoteAttribute` — without that, it would
/// silently fail to survive a Postbox re-read after the app relaunches.
public final class PampGramVisualChatMessageAttribute: MessageAttribute {
    public init() {
    }

    public init(decoder: PostboxDecoder) {
    }

    public func encode(_ encoder: PostboxEncoder) {
    }
}
