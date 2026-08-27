import Foundation
import TelegramCore
import SwiftSignalKit
import AccountContext

/// Turns a base catalog gift (e.g. "Candy Cane") into one specific numbered "collectible"
/// instance — a Model/Backdrop/Symbol combination and a number — purely for local display.
///
/// The one real network call here (`context.engine.payments.starGiftUpgradePreview`) is a
/// read-only fetch of the same public sample-attribute art Telegram itself shows when you
/// preview upgrading a real gift (used by the real `GiftCraftScreen`); it uploads nothing
/// and identifies no phantom gift to the server — it's the same kind of read the "Фантом"
/// catalog already relies on via `cachedStarGifts()`. If it's unavailable (offline, or the
/// base gift has no upgrade attributes), sending falls back to a plain (non-collectible)
/// phantom gift instead of failing.
public enum PampGramUniqueGiftGenerator {
    public static func randomUniqueInstance(context: AccountContext, baseGift: StarGift.Gift) -> Signal<StarGift.UniqueGift?, NoError> {
        return context.engine.payments.starGiftUpgradePreview(giftId: baseGift.id)
        |> map { preview -> StarGift.UniqueGift? in
            guard let preview, !preview.attributes.isEmpty else {
                return nil
            }
            let models = preview.attributes.filter { if case .model = $0 { return true } else { return false } }
            let backdrops = preview.attributes.filter { if case .backdrop = $0 { return true } else { return false } }
            let patterns = preview.attributes.filter { if case .pattern = $0 { return true } else { return false } }
            guard let model = models.randomElement(), let backdrop = backdrops.randomElement() else {
                return nil
            }
            var attributes: [StarGift.UniqueGift.Attribute] = [model, backdrop]
            if let pattern = patterns.randomElement() {
                attributes.append(pattern)
            }

            let number = Int32.random(in: 1...999_999)
            return StarGift.UniqueGift(
                id: Int64.random(in: 1...Int64.max),
                giftId: baseGift.id,
                title: baseGift.title ?? "Gift",
                number: number,
                slug: "pampgram-phantom-\(number)",
                owner: nil,
                attributes: attributes,
                availability: StarGift.UniqueGift.Availability(issued: number, total: baseGift.availability?.total ?? number),
                giftAddress: nil,
                resellAmounts: nil,
                resellForTonOnly: false,
                releasedBy: nil,
                valueAmount: nil,
                valueCurrency: nil,
                valueUsdAmount: nil,
                flags: [],
                themePeerId: nil,
                peerColor: nil,
                hostPeerId: nil,
                minOfferStars: nil,
                craftChancePermille: nil
            )
        }
    }
}
