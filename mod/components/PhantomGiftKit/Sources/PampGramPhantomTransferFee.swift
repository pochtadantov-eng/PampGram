import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore
import AccountContext
import PampGramCore

public extension PampGramPhantomGiftManager {
    /// Called right before Telegram's own transfer screen opens for a local visual gift.
    static func markPhantomTransfer(slug: String) {
        PampGramPhantomTransferMarker.shared.mark(slug: slug)
    }

    /// Local transfer of the visual gift that `uniqueGift` represents (found among this
    /// account's own visual gifts by its unique id and slug) — used when the gift screen was
    /// opened from a chat message rather than from the profile grid. `false` when no such
    /// visual gift exists or the 25-Star fee can't be covered.
    static func sendUniqueGiftToPeer(context: AccountContext, uniqueGift: StarGift.UniqueGift, peerId: EnginePeer.Id) -> Signal<Bool, NoError> {
        let selfPeerId = context.account.peerId
        return context.account.postbox.transaction { transaction -> Int64? in
            for candidate in PampGramPhantomGiftStore.gifts(transaction: transaction, peerId: selfPeerId) {
                if case let .unique(candidateUnique) = candidate.gift, candidateUnique.id == uniqueGift.id, candidateUnique.slug == uniqueGift.slug {
                    return candidate.id
                }
            }
            return nil
        }
        |> mapToSignal { giftId -> Signal<Bool, NoError> in
            guard let giftId = giftId else {
                return .single(false)
            }
            return PampGramPhantomGiftManager.sendGiftToPeer(context: context, giftId: giftId, peerId: peerId)
        }
    }
}
