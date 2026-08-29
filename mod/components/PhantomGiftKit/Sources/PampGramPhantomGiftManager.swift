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

            return PampGramPhantomGiftMessage.insertLocalUniqueGiftMessage(context: context, peerId: peerId, uniqueGift: uniqueGift, price: price)
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

    /// Same as `buyUniqueGift`, for the "Подарок" tab's other real entry point: sending a
    /// fresh (non-unique) gift straight from the catalog (see GiftSetupScreen.swift), rather
    /// than buying a specific numbered instance off the resale market. Always Stars-priced —
    /// the plain gift catalog has no TON listings. Callers are expected to have already
    /// confirmed the fake balance covers `starPrice`, same as `buyUniqueGift`.
    ///
    /// Unlike `buyUniqueGift`, a self-purchase here still inserts a chat message: the real
    /// send flow (GiftSetupScreen.swift) treats "gift to self" and "gift to someone else" as
    /// the same case — both navigate to a chat (Saved Messages for self) and expect the
    /// gift card to already be there, unlike the resale-market flow's self-purchase, which
    /// shows a plain toast with no chat involved at all.
    public static func sendGenericGift(context: AccountContext, peerId: EnginePeer.Id, gift: StarGift.Gift, starPrice: Int64, text: String? = nil, entities: [MessageTextEntity]? = nil, nameHidden: Bool = false) -> Signal<Never, NoError> {
        return context.account.postbox.transaction { transaction -> PendingBuy in
            let newBalance = PampGramPhantomGiftStore.fakeStarsBalance(transaction: transaction) - starPrice
            PampGramPhantomGiftStore.setFakeStarsBalance(transaction: transaction, stars: newBalance)

            let phantomGift = PampGramPhantomGift(
                id: Int64.random(in: 1...Int64.max),
                peerId: peerId,
                gift: .generic(gift),
                price: CurrencyAmount(amount: StarsAmount(value: starPrice, nanos: 0), currency: .stars),
                date: Int32(Date().timeIntervalSince1970),
                localMessageId: nil
            )
            PampGramPhantomGiftStore.add(transaction: transaction, gift: phantomGift)
            return PendingBuy(newBalance: newBalance, phantomGift: phantomGift)
        }
        |> mapToSignal { pending -> Signal<Never, NoError> in
            let phantomGift = pending.phantomGift
            return PampGramPhantomGiftMessage.insertLocalGenericGiftMessage(context: context, peerId: peerId, gift: gift, text: text, entities: entities, nameHidden: nameHidden)
            |> mapToSignal { messageId -> Signal<Never, NoError> in
                guard let messageId else {
                    return .complete()
                }
                let finalGift = PampGramPhantomGift(id: phantomGift.id, peerId: phantomGift.peerId, gift: phantomGift.gift, price: phantomGift.price, date: phantomGift.date, localMessageId: messageId)
                return context.account.postbox.transaction { transaction in
                    PampGramPhantomGiftStore.remove(transaction: transaction, id: phantomGift.id)
                    PampGramPhantomGiftStore.add(transaction: transaction, gift: finalGift)
                }
                |> ignoreValues
            }
        }
    }

    /// "Подарок мне": local-only stand-in for *receiving* a unique gift — records it and
    /// inserts the local-only chat message with `insertLocalUniqueGiftMessageFromPeer`, so it
    /// reads as `peerId` having sent it to this account. Unlike `buyUniqueGift`, no balance is
    /// touched: nobody spent anything in this direction, real or fake. `price` is kept only
    /// for the phantom-gift record (the "Фантом-подарков на устройстве" list) — informational,
    /// never deducted.
    public static func receiveUniqueGift(context: AccountContext, peerId: EnginePeer.Id, uniqueGift: StarGift.UniqueGift, price: CurrencyAmount) -> Signal<PampGramPhantomGift, NoError> {
        return context.account.postbox.transaction { transaction -> PampGramPhantomGift in
            let phantomGift = PampGramPhantomGift(
                id: Int64.random(in: 1...Int64.max),
                peerId: peerId,
                gift: .unique(uniqueGift),
                price: price,
                date: Int32(Date().timeIntervalSince1970),
                localMessageId: nil,
                isReceived: true
            )
            PampGramPhantomGiftStore.add(transaction: transaction, gift: phantomGift)
            return phantomGift
        }
        |> mapToSignal { phantomGift -> Signal<PampGramPhantomGift, NoError> in
            return PampGramPhantomGiftMessage.insertLocalUniqueGiftMessageFromPeer(context: context, peerId: peerId, uniqueGift: uniqueGift)
            |> mapToSignal { messageId -> Signal<PampGramPhantomGift, NoError> in
                guard let messageId else {
                    return .single(phantomGift)
                }
                let finalGift = PampGramPhantomGift(id: phantomGift.id, peerId: phantomGift.peerId, gift: phantomGift.gift, price: phantomGift.price, date: phantomGift.date, localMessageId: messageId, isReceived: true)
                return context.account.postbox.transaction { transaction -> PampGramPhantomGift in
                    PampGramPhantomGiftStore.remove(transaction: transaction, id: phantomGift.id)
                    PampGramPhantomGiftStore.add(transaction: transaction, gift: finalGift)
                    return finalGift
                }
            }
        }
    }

    /// Same as `receiveUniqueGift`, for the plain (non-unique) gift catalog — "Подарок мне"'s
    /// other entry point, mirroring `sendGenericGift`.
    public static func receiveGenericGift(context: AccountContext, peerId: EnginePeer.Id, gift: StarGift.Gift, text: String? = nil, entities: [MessageTextEntity]? = nil) -> Signal<Never, NoError> {
        return context.account.postbox.transaction { transaction -> PampGramPhantomGift in
            let phantomGift = PampGramPhantomGift(
                id: Int64.random(in: 1...Int64.max),
                peerId: peerId,
                gift: .generic(gift),
                price: CurrencyAmount(amount: StarsAmount(value: gift.price, nanos: 0), currency: .stars),
                date: Int32(Date().timeIntervalSince1970),
                localMessageId: nil,
                isReceived: true
            )
            PampGramPhantomGiftStore.add(transaction: transaction, gift: phantomGift)
            return phantomGift
        }
        |> mapToSignal { phantomGift -> Signal<Never, NoError> in
            return PampGramPhantomGiftMessage.insertLocalGenericGiftMessageFromPeer(context: context, peerId: peerId, gift: gift, text: text, entities: entities)
            |> mapToSignal { messageId -> Signal<Never, NoError> in
                guard let messageId else {
                    return .complete()
                }
                let finalGift = PampGramPhantomGift(id: phantomGift.id, peerId: phantomGift.peerId, gift: phantomGift.gift, price: phantomGift.price, date: phantomGift.date, localMessageId: messageId, isReceived: true)
                return context.account.postbox.transaction { transaction in
                    PampGramPhantomGiftStore.remove(transaction: transaction, id: phantomGift.id)
                    PampGramPhantomGiftStore.add(transaction: transaction, gift: finalGift)
                }
                |> ignoreValues
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

    /// Finds the Phantom Gift a `ProfileGiftsContext.State.StarGift` from the profile grid
    /// was built from. The grid item itself never carries the Phantom Gift's `id` (it's a
    /// `reference: nil` value built fresh by `PampGramPhantomGift.asProfileGift` every time
    /// the grid re-renders — that's deliberate: `reference == nil` is the signal every real,
    /// network-backed consumer of this type checks before acting, so nothing here piggybacks
    /// an id onto one of its fields and risks a real screen misreading it as real data).
    /// Matched on this account's own gifts by exact `gift`+`date`, which a Phantom Gift never
    /// shares with another one (each gets its own `Date()` at creation).
    private static func findPhantomGift(transaction: Transaction, selfPeerId: EnginePeer.Id, matching gift: ProfileGiftsContext.State.StarGift) -> PampGramPhantomGift? {
        return PampGramPhantomGiftStore.allGifts(transaction: transaction).first(where: { $0.peerId == selfPeerId && $0.gift == gift.gift && $0.date == gift.date })
    }

    /// "Закрепить" in the profile gifts grid, for a Phantom Gift — a pure local flag flip,
    /// same as the real `ProfileGiftsContext.updateStarGiftPinnedToTop`'s optimistic-update
    /// half, but without also firing the real network call that method always sends
    /// alongside it (there's no server-side pin to make for a gift that was never real).
    public static func setPinnedToTop(context: AccountContext, matching gift: ProfileGiftsContext.State.StarGift, pinnedToTop: Bool) -> Signal<Never, NoError> {
        return context.account.postbox.transaction { transaction -> Void in
            guard let match = self.findPhantomGift(transaction: transaction, selfPeerId: context.account.peerId, matching: gift) else {
                return
            }
            PampGramPhantomGiftStore.update(transaction: transaction, id: match.id, { $0.withPinnedToTop(pinnedToTop) })
        }
        |> ignoreValues
    }

    /// "Показать на странице" / "Скрыть с страницы" — same local-only flag flip as
    /// `setPinnedToTop`, standing in for `ProfileGiftsContext.updateStarGiftAddedToProfile`.
    public static func setSavedToProfile(context: AccountContext, matching gift: ProfileGiftsContext.State.StarGift, savedToProfile: Bool) -> Signal<Never, NoError> {
        return context.account.postbox.transaction { transaction -> Void in
            guard let match = self.findPhantomGift(transaction: transaction, selfPeerId: context.account.peerId, matching: gift) else {
                return
            }
            PampGramPhantomGiftStore.update(transaction: transaction, id: match.id, { $0.withSavedToProfile(savedToProfile) })
        }
        |> ignoreValues
    }

    /// "Продать" — local stand-in for `convertStarGift`. Credits the fake balance with what
    /// the gift was originally worth (its `price`, in whichever currency it was paid in) and
    /// marks it sold: it disappears from the grid via `savedToProfile = false`, same as
    /// `delete` would, but the record itself — and the debit it originally produced in the
    /// transaction history — is kept, and the sale becomes its own credit entry there,
    /// exactly like a real "sold for Stars" transaction would.
    public static func sell(context: AccountContext, matching gift: ProfileGiftsContext.State.StarGift) -> Signal<Never, NoError> {
        return context.account.postbox.transaction { transaction -> Void in
            guard let match = self.findPhantomGift(transaction: transaction, selfPeerId: context.account.peerId, matching: gift) else {
                return
            }
            switch match.price.currency {
            case .stars:
                let newBalance = PampGramPhantomGiftStore.fakeStarsBalance(transaction: transaction) + match.price.amount.value
                PampGramPhantomGiftStore.setFakeStarsBalance(transaction: transaction, stars: newBalance)
            case .ton:
                let newBalance = PampGramPhantomGiftStore.fakeTonBalanceNanos(transaction: transaction) + match.price.amount.value
                PampGramPhantomGiftStore.setFakeTonBalanceNanos(transaction: transaction, nanos: newBalance)
            }
            PampGramPhantomGiftStore.update(transaction: transaction, id: match.id, { $0.withSold(date: Int32(Date().timeIntervalSince1970)) })
        }
        |> ignoreValues
    }
}
