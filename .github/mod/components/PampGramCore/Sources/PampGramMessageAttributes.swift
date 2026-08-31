import Foundation
import Postbox

public struct PampGramEditRevision: Equatable {
    public let timestamp: Int32
    public let text: String

    public init(timestamp: Int32, text: String) {
        self.timestamp = timestamp
        self.text = text
    }
}

/// Attached only to messages edited locally through PampGram. Keeps a compact edit history
/// in the message itself, so the pencil badge can open the exact previous texts without a
/// second database and without any network state.
public final class PampGramVisualEditHistoryAttribute: MessageAttribute {
    public let revisions: [PampGramEditRevision]

    public init(revisions: [PampGramEditRevision]) {
        self.revisions = Array(revisions.suffix(50))
    }

    public init(decoder: PostboxDecoder) {
        let count = Int(decoder.decodeInt32ForKey("c", orElse: 0))
        var revisions: [PampGramEditRevision] = []
        for i in 0 ..< max(0, min(count, 50)) {
            let text = decoder.decodeStringForKey("t\(i)", orElse: "")
            let timestamp = decoder.decodeInt32ForKey("d\(i)", orElse: 0)
            revisions.append(PampGramEditRevision(timestamp: timestamp, text: text))
        }
        self.revisions = revisions
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(Int32(self.revisions.count), forKey: "c")
        for (i, revision) in self.revisions.enumerated() {
            encoder.encodeString(revision.text, forKey: "t\(i)")
            encoder.encodeInt32(revision.timestamp, forKey: "d\(i)")
        }
    }
}

/// Marks a message that only exists in this device's Postbox (fake-admin post, visual text
/// insertion, etc.). It is intentionally not rendered as a permanent badge in the bubble;
/// the context menu shows "Локально" when the user long-presses it.
public final class PampGramLocalOnlyMessageAttribute: MessageAttribute {
    public let source: String

    public init(source: String) {
        self.source = source
    }

    public init(decoder: PostboxDecoder) {
        self.source = decoder.decodeStringForKey("s", orElse: "PampGram")
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeString(self.source, forKey: "s")
    }
}
