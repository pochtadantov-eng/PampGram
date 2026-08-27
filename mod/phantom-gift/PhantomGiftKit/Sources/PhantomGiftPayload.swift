import Foundation

/// Data carried by a "Фантом" gift link. This is a cosmetic-only stand-in for a real
/// StarGift transfer: no purchase happens and no server-side gift record is created.
///
/// Only the real gift's catalog id is transmitted — the receiving mod client looks the
/// full gift (art, title, colors) up from `context.engine.payments.cachedStarGifts()`,
/// the same public real-gift catalog the sender picked it from. Nothing about the
/// gift's visuals needs to travel over the wire.
public struct PhantomGiftPayload: Codable, Equatable {
    public let giftId: Int64
    public let senderName: String

    public init(giftId: Int64, senderName: String) {
        self.giftId = giftId
        self.senderName = senderName
    }
}
