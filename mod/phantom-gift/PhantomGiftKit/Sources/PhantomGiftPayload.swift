import Foundation
import TelegramCore

/// Data carried by a "Фантом" gift link. This is a cosmetic-only stand-in for a real
/// StarGift transfer: no purchase happens and no server-side gift record is created.
///
/// The whole `StarGift.Gift` value travels inside the link (it's already `Codable`), so
/// the receiving mod client can rebuild the exact same gift card entirely offline — no
/// catalog lookup, no network round trip, and it still renders correctly even if the
/// gift is later removed from the real catalog.
public struct PhantomGiftPayload: Codable, Equatable {
    public let gift: StarGift.Gift
    public let senderName: String

    public init(gift: StarGift.Gift, senderName: String) {
        self.gift = gift
        self.senderName = senderName
    }
}
