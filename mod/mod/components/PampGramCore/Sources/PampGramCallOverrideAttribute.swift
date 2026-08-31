import Foundation
import Postbox

/// A purely local, cosmetic override for how one specific call history entry displays —
/// its duration and whether it reads as missed. Attached directly to that call's own message
/// (the same `Transaction.updateMessage` mechanism "Изменить визуально" already uses for
/// text), so reading it back is just an ordinary message attribute lookup — no separate store,
/// no extra Postbox key range. Never touches the real call, the other side, or anything sent
/// over the network; purely what this device's own call list/bubble render.
///
/// Registered with `declareEncodable` in `TelegramCore/Sources/Account/AccountManager.swift`
/// (see the patch), same as `PampGramDeletedByRemoteAttribute` — without that it would
/// silently fail to survive a Postbox re-read after the app relaunches.
public final class PampGramCallOverrideAttribute: MessageAttribute {
    public let durationSeconds: Int32
    public let showAsMissed: Bool

    public init(durationSeconds: Int32, showAsMissed: Bool) {
        self.durationSeconds = durationSeconds
        self.showAsMissed = showAsMissed
    }

    public init(decoder: PostboxDecoder) {
        self.durationSeconds = decoder.decodeInt32ForKey("ds", orElse: 0)
        self.showAsMissed = decoder.decodeInt32ForKey("sm", orElse: 0) != 0
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.durationSeconds, forKey: "ds")
        encoder.encodeInt32(self.showAsMissed ? 1 : 0, forKey: "sm")
    }
}
