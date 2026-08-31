import Foundation
import Postbox

/// Marks a message as a local reconstruction of one the other side deleted. The bubble
/// rendering patch checks for this attribute to dim the bubble and draw the small red
/// trash-can badge; nothing else in the app ever looks at it.
///
/// Registered with `declareEncodable` in `TelegramCore/Sources/Account/AccountManager.swift`
/// (see the patch) — without that, it would silently fail to survive a Postbox re-read after
/// the app relaunches.
public final class PampGramDeletedByRemoteAttribute: MessageAttribute {
    /// When PampGram noticed the deletion and rebuilt this message, as a unix timestamp.
    public let deletedAt: Int32

    public init(deletedAt: Int32) {
        self.deletedAt = deletedAt
    }

    public init(decoder: PostboxDecoder) {
        self.deletedAt = decoder.decodeInt32ForKey("da", orElse: 0)
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.deletedAt, forKey: "da")
    }
}
