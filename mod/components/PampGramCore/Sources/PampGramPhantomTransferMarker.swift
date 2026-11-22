import Foundation

/// Remembers which unique gifts (by slug) are being transferred through Telegram's own
/// "Transfer" screen as local visual gifts. The original confirm alert then shows the visual
/// 25-Star fee ("Transfer for ⭐25") without Telegram checking the real Stars balance for it —
/// the local fee is charged and checked by `PampGramPhantomGiftManager.sendGiftToPeer`.
public final class PampGramPhantomTransferMarker {
    public static let shared = PampGramPhantomTransferMarker()

    private let lock = NSLock()
    private var slugs = Set<String>()

    private init() {
    }

    public func mark(slug: String) {
        self.lock.lock()
        self.slugs.insert(slug)
        self.lock.unlock()
    }

    public func contains(slug: String) -> Bool {
        self.lock.lock()
        let result = self.slugs.contains(slug)
        self.lock.unlock()
        return result
    }
}
