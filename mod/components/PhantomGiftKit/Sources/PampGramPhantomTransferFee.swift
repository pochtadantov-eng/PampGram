import Foundation
import PampGramCore

public extension PampGramPhantomGiftManager {
    /// Called right before Telegram's own transfer screen opens for a local visual gift.
    static func markPhantomTransfer(slug: String) {
        PampGramPhantomTransferMarker.shared.mark(slug: slug)
    }
}
