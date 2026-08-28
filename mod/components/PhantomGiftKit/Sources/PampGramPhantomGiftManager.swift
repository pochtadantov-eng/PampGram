import Foundation
import TelegramCore
import SwiftSignalKit
import AccountContext

public enum PampGramPhantomGiftManager {
    /// Conforms to Error because it is carried in a `Result<SendResult, SendError>`, and
    /// Result's failure type is constrained to Error.
    public enum SendError: Error {
        case insufficientBalance(have: Int64, need: Int64)
    }

    public struct SendResult {
        public let phantomGift: PampGramPhantomGift
        public let remainingBalance: Int64
    }

    /// Full local send flow, in order: check the fake balance, optionally mint a random
    /// collectible instance of the base gift (best-effort — falls back to the plain generic
    /// gift if that fails or isn't requested), insert the local-only chat message, save the
    /// gift record, and deduct the fake balance. Every step is either a pure local Postbox
    /// transaction or the one read-only attribute-preview fetch documented in
    /// `PampGramUniqueGiftGenerator` — nothing here calls a payment, gift-send, or
    /// gift-transfer API.
    public static func send(context: AccountContext, peerId: EnginePeer.Id, baseGift: StarGift.Gift, starPrice: Int64, asCollectible: Bool) -> Signal<Result<SendResult, SendError>, NoError> {
        let resolvedGift: Signal<StarGift, NoError>
        if asCollectible {
            resolvedGift = PampGramUniqueGiftGenerator.randomUniqueInstance(context: context, baseGift: baseGift)
            |> map { unique -> StarGift in
                if let unique {
                    return .unique(unique)
                } else {
                    return .generic(baseGift)
                }
            }
        } else {
            resolvedGift = .single(.generic(baseGift))
        }

        return resolvedGift
        |> mapToSignal { gift -> Signal<Result<SendResult, SendError>, NoError> in
            return context.account.postbox.transaction { transaction -> Result<(Int64, PampGramPhantomGift), SendError> in
                let currentBalance = PampGramPhantomGiftStore.fakeStarsBalance(transaction: transaction)
                guard currentBalance >= starPrice else {
                    return .failure(.insufficientBalance(have: currentBalance, need: starPrice))
                }
                let newBalance = currentBalance - starPrice
                PampGramPhantomGiftStore.setFakeStarsBalance(transaction: transaction, stars: newBalance)

                let phantomGift = PampGramPhantomGift(
                    id: Int64.random(in: 1...Int64.max),
                    peerId: peerId,
                    gift: gift,
                    starPrice: starPrice,
                    date: Int32(Date().timeIntervalSince1970),
                    localMessageId: nil
                )
                PampGramPhantomGiftStore.add(transaction: transaction, gift: phantomGift)
                return .success((newBalance, phantomGift))
            }
            |> mapToSignal { result -> Signal<Result<SendResult, SendError>, NoError> in
                switch result {
                case let .failure(error):
                    return .single(.failure(error))
                case let .success(newBalance, phantomGift):
                    return PampGramPhantomGiftMessage.insertLocalGiftMessage(context: context, peerId: peerId, gift: phantomGift.gift, starPrice: starPrice)
                    |> map { messageId -> Result<SendResult, SendError> in
                        let finalGift: PampGramPhantomGift
                        if let messageId {
                            finalGift = PampGramPhantomGift(id: phantomGift.id, peerId: phantomGift.peerId, gift: phantomGift.gift, starPrice: phantomGift.starPrice, date: phantomGift.date, localMessageId: messageId)
                            let _ = context.account.postbox.transaction { transaction in
                                PampGramPhantomGiftStore.remove(transaction: transaction, id: phantomGift.id)
                                PampGramPhantomGiftStore.add(transaction: transaction, gift: finalGift)
                            }.start()
                        } else {
                            finalGift = phantomGift
                        }
                        return .success(SendResult(phantomGift: finalGift, remainingBalance: newBalance))
                    }
                }
            }
        }
    }

    /// Removes every Phantom Gift on this device, and the local-only chat messages they
    /// created, in a single transaction. Same local-only guarantees as `delete`.
    public static func deleteAll(context: AccountContext) -> Signal<Never, NoError> {
        return context.account.postbox.transaction { transaction -> Void in
            let gifts = PampGramPhantomGiftStore.allGifts(transaction: transaction)
            let messageIds = gifts.compactMap { $0.localMessageId }
            for gift in gifts {
                PampGramPhantomGiftStore.remove(transaction: transaction, id: gift.id)
            }
            if !messageIds.isEmpty {
                transaction.deleteMessages(messageIds, forEachMedia: nil)
            }
        }
        |> ignoreValues
    }

    /// Removes a Phantom Gift: its local chat message (if it still exists — same "delete
    /// message" path used everywhere else, which already skips the server for
    /// `Namespaces.Message.Local`) and its store entry. Never touches the network.
    public static func delete(context: AccountContext, gift: PampGramPhantomGift) -> Signal<Never, NoError> {
        return context.account.postbox.transaction { transaction -> Void in
            PampGramPhantomGiftStore.remove(transaction: transaction, id: gift.id)
            if let messageId = gift.localMessageId {
                transaction.deleteMessages([messageId], forEachMedia: nil)
            }
        }
        |> ignoreValues
    }
}
