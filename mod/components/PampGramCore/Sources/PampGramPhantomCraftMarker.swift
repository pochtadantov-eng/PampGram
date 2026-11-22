import Foundation

/// Which collection (gift id) is being crafted from a local visual gift right now. Telegram's own
/// craft screen is opened as usual; while this is set for its gift id, the screen's data source
/// and the craft itself are answered locally (see PhantomGiftKit's `craftCandidates` /
/// `craftLocally`) instead of by the server.
public final class PampGramPhantomCraftMarker {
    public static let shared = PampGramPhantomCraftMarker()

    private let lock = NSLock()
    private var activeGiftId: Int64?

    private init() {
    }

    public func begin(giftId: Int64) {
        self.lock.lock()
        self.activeGiftId = giftId
        self.lock.unlock()
    }

    public func end() {
        self.lock.lock()
        self.activeGiftId = nil
        self.lock.unlock()
    }

    public func isActive(giftId: Int64) -> Bool {
        self.lock.lock()
        let result = self.activeGiftId == giftId
        self.lock.unlock()
        return result
    }
}
