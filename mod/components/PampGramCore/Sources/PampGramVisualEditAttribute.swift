import Foundation
import Postbox

/// Marks a message whose text was changed only on this device, via "Изменить визуально" —
/// the bubble rendering patch checks for this attribute to draw a small pencil badge, so an
/// edited copy of the other side's message never looks indistinguishable from what they
/// actually sent (the same rule phantom gifts and resurrected deletions follow).
///
/// Registered with `declareEncodable` in `TelegramCore/Sources/Account/AccountManager.swift`
/// (see the patch) — without that, it would silently fail to survive a Postbox re-read after
/// the app relaunches.
public final class PampGramVisualEditAttribute: MessageAttribute {
    /// When the visual edit was made, as a unix timestamp.
    public let editedAt: Int32

    public init(editedAt: Int32) {
        self.editedAt = editedAt
    }

    public init(decoder: PostboxDecoder) {
        self.editedAt = decoder.decodeInt32ForKey("ea", orElse: 0)
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.editedAt, forKey: "ea")
    }
}
