import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore
import AccountContext
import PampGramCore

public extension PampGramPhantomGiftManager {
    /// This account's own visual gifts of one collection, shaped for Telegram's craft screen
    /// (each with a `.slug` reference, the same kind the screen already uses for the gift it
    /// was opened from).
    static func craftCandidates(context: AccountContext, giftId: Int64) -> Signal<[ProfileGiftsContext.State.StarGift], NoError> {
        return PampGramPhantomGiftStore.profileGiftsSignal(context: context)
        |> map { gifts -> [ProfileGiftsContext.State.StarGift] in
            var result: [ProfileGiftsContext.State.StarGift] = []
            for gift in gifts {
                if gift.soldDate != nil {
                    continue
                }
                if case let .unique(uniqueGift) = gift.gift, uniqueGift.giftId == giftId {
                    result.append(gift.asProfileGift(fromPeer: nil, reference: .slug(slug: uniqueGift.slug)))
                }
            }
            return result
        }
    }

    /// Local crafting: the gifts put on the table are used up; with the summed success chance
    /// of the selected gifts (Telegram's own per-gift craft chance, 22% when a gift has none)
    /// one new gift of the collection appears, otherwise the result is "Crafting Failed".
    static func craftLocally(context: AccountContext, giftId: Int64, references: [StarGiftReference]) -> Signal<ProfileGiftsContext.State.StarGift, CraftStarGiftError> {
        var slugs: [String] = []
        for reference in references {
            if case let .slug(slug) = reference {
                slugs.append(slug)
            }
        }
        let selfPeerId = context.account.peerId
        return context.account.postbox.transaction { transaction -> PampGramPhantomGift? in
            let own = PampGramPhantomGiftStore.gifts(transaction: transaction, peerId: selfPeerId)
            var used: [PampGramPhantomGift] = []
            for slug in slugs {
                for candidate in own {
                    if case let .unique(candidateUnique) = candidate.gift, candidateUnique.slug == slug, candidateUnique.giftId == giftId {
                        used.append(candidate)
                        break
                    }
                }
            }
            guard let primary = used.first else {
                return nil
            }
            var permille: Int32 = 0
            for gift in used {
                if case let .unique(uniqueGift) = gift.gift {
                    permille += uniqueGift.craftChancePermille ?? 220
                }
            }
            permille = min(permille, 1000)
            let success = Int32.random(in: 0 ..< 1000) < permille
            for gift in used {
                PampGramPhantomGiftStore.remove(transaction: transaction, id: gift.id)
            }
            if !success {
                return nil
            }
            let crafted = PampGramPhantomGift(id: Int64.random(in: 1 ... (Int64.max / 4)), peerId: primary.peerId, gift: primary.gift, price: primary.price, date: Int32(Date().timeIntervalSince1970), localMessageId: nil)
            PampGramPhantomGiftStore.add(transaction: transaction, gift: crafted)
            return crafted
        }
        |> castError(CraftStarGiftError.self)
        |> mapToSignal { crafted -> Signal<ProfileGiftsContext.State.StarGift, CraftStarGiftError> in
            guard let crafted = crafted, case let .unique(uniqueGift) = crafted.gift else {
                return .fail(.craftFailed)
            }
            return .single(crafted.asProfileGift(fromPeer: nil, reference: .slug(slug: uniqueGift.slug)))
        }
    }
}
