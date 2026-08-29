import Foundation
import TelegramCore
import SwiftSignalKit
import AccountContext

public enum PampGramPhantomGiftManager {
    public struct BuyResult {
        public let phantomGift: PampGramPhantomGift
        public let remainingBalance: CurrencyAmount
    }

    /// What the balance-and-store transaction hands to the message-insert step. A named
    /// type rather than a tuple: `Result`'s `success` takes exactly one associated value,
    /// so a tuple there cannot be destructured in a `case let .success(a, b)` pattern.
    private struct PendingBuy {
        let newBalance: Int64
        let phantomGift: PampGramPhantomGift
    }

    /// Local-only stand-in for a real resale purchase: deducts the matching fake balance
    /// (Stars or TON, whichever the real listing was priced in), records the gift, and —
    /// unless this is a self-purchase, which never produces a chat message either way —
    /// inserts the local-only chat message using the *real* `uniqueGift` straight from the
    /// market. Never calls `context.engine.payments.buyStarGift` or any other network API;
    /// the real listing this was matched against is untouched and stays exactly where it
    /// was in the real market.
    ///
    /// Callers are expected to have already confirmed the fake balance covers `price` —
    /// this always deducts unconditionally, matching how `buyStarGiftImpl` in
    /// `GiftViewBuyGift.swift` checks and alerts *before* ever calling this.
    public static func buyUniqueGift(context: AccountContext, peerId: EnginePeer.Id, uniqueGift: StarGift.UniqueGift, price: CurrencyAmount) -> Signal<BuyResult, NoError> {
        return context.account.postbox.transaction { transaction -> PendingBuy in
            let newBalance: Int64
            switch price.currency {
            case .stars:
                newBalance = PampGramPhantomGiftStore.fakeStarsBalance(transaction: transaction) - price.amount.value
                PampGramPhantomGiftStore.setFakeStarsBalance(transaction: transaction, stars: newBalance)
            case .ton:
                newBalance = PampGramPhantomGiftStore.fakeTonBalanceNanos(transaction: transaction) - price.amount.value
                PampGramPhantomGiftStore.setFakeTonBalanceNanos(transaction: transaction, nanos: newBalance)
            }

            let phantomGift = PampGramPhantomGift(
                id: Int64.random(in: 1...Int64.max),
                peerId: peerId,
                gift: .unique(uniqueGift),
                price: price,
                date: Int32(Date().timeIntervalSince1970),
                localMessageId: nil
            )
            PampGramPhantomGiftStore.add(transaction: transaction, gift: phantomGift)
            return PendingBuy(newBalance: newBalance, phantomGift: phantomGift)
        }
        |> mapToSignal { pending -> Signal<BuyResult, NoError> in
            let newBalance = pending.newBalance
            let phantomGift = pending.phantomGift

            // A self-purchase (buying for your own collection, not gifting someone) never
            // gets a chat message — there's no chat to put it in, real purchases don't
            // create one either.
            guard peerId != context.account.peerId else {
                return .single(BuyResult(phantomGift: phantomGift, remainingBalance: CurrencyAmount(amount: StarsAmount(value: newBalance, nanos: 0), currency: price.currency)))
            }

            return PampGramPhantomGiftMessage.insertLocalUniqueGiftMessage(context: context, peerId: peerId, uniqueGift: uniqueGift)
            |> map { messageId -> BuyResult in
                let finalGift: PampGramPhantomGift
                if let messageId {
                    finalGift = PampGramPhantomGift(id: phantomGift.id, peerId: phantomGift.peerId, gift: phantomGift.gift, price: phantomGift.price, date: phantomGift.date, localMessageId: messageId)
                    let _ = context.account.postbox.transaction { transaction in
                        PampGramPhantomGiftStore.remove(transaction: transaction, id: phantomGift.id)
                        PampGramPhantomGiftStore.add(transaction: transaction, gift: finalGift)
                    }.start()
                } else {
                    finalGift = phantomGift
                }
                return BuyResult(phantomGift: finalGift, remainingBalance: CurrencyAmount(amount: StarsAmount(value: newBalance, nanos: 0), currency: price.currency))
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
