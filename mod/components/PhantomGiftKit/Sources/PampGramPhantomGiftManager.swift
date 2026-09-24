import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import AccountContext
import PampGramCore

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
            // `uniqueGift` is read straight off a real resale-market listing (that's how it was
            // found to "buy"), so its own `resellAmounts` is still non-empty — left as-is, the
            // real, unmodified grid card component reads that field directly and would paint a
            // green "Продажа" ribbon on this gift forever, on this profile and on every profile
            // it's later transferred to, regardless of PampGram's own market listing being off.
            // Same cleanup `insertLocalUniqueGiftMessage` already applies to the chat message.
            let ownedGift = PampGramPhantomGiftMessage.fakedOwnership(of: uniqueGift, newOwnerPeerId: peerId)
            let phantomGift = PampGramPhantomGift(
                id: Int64.random(in: 1...Int64.max),
                peerId: peerId,
                gift: .unique(ownedGift),
                price: price,
                date: Int32(Date().timeIntervalSince1970),
                localMessageId: nil,
                fromPeerId: peerId == context.account.peerId ? nil : context.account.peerId
            )
            PampGramPhantomGiftStore.add(transaction: transaction, gift: phantomGift)
            let ledgerCurrency: PampGramLocalCurrency = price.currency == .stars ? .stars : .ton
            let newBalance = PampGramLocalLedgerStore.addAndApply(
                transaction: transaction,
                currency: ledgerCurrency,
                kind: .purchase,
                amount: -price.amount.value,
                title: "Покупка подарка",
                details: phantomGift.title,
                peerId: peerId,
                giftId: phantomGift.id
            )
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

            // Gifting someone: local-only visual. The sender gets their own "Вы подарили …" gift
            // card; nothing is sent to the other device. (A recipient can't receive a purely local
            // gift, by design — see PampGram's local-only gift policy.)
            return PampGramPhantomGiftMessage.insertLocalUniqueGiftMessage(context: context, peerId: peerId, uniqueGift: uniqueGift, price: price)
            |> map { _ -> BuyResult in
                return BuyResult(phantomGift: phantomGift, remainingBalance: CurrencyAmount(amount: StarsAmount(value: newBalance, nanos: 0), currency: price.currency))
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
            let phantomGift = PampGramPhantomGift(
                id: Int64.random(in: 1...Int64.max),
                peerId: peerId,
                gift: .generic(gift),
                price: CurrencyAmount(amount: StarsAmount(value: starPrice, nanos: 0), currency: .stars),
                date: Int32(Date().timeIntervalSince1970),
                localMessageId: nil,
                fromPeerId: peerId == context.account.peerId ? nil : context.account.peerId
            )
            PampGramPhantomGiftStore.add(transaction: transaction, gift: phantomGift)
            let newBalance = PampGramLocalLedgerStore.addAndApply(
                transaction: transaction,
                currency: .stars,
                kind: .purchase,
                amount: -starPrice,
                title: "Покупка подарка",
                details: phantomGift.title,
                peerId: peerId,
                giftId: phantomGift.id
            )
            return PendingBuy(newBalance: newBalance, phantomGift: phantomGift)
        }
        |> mapToSignal { pending -> Signal<Never, NoError> in
            let phantomGift = pending.phantomGift

            // Local-only visual, whether gifting someone or yourself: the sender gets their own
            // gift card and nothing is sent to any other device.
            return PampGramPhantomGiftMessage.insertLocalGenericGiftMessage(context: context, peerId: peerId, gift: gift, text: text, entities: entities, nameHidden: nameHidden)
            |> mapToSignal { messageId -> Signal<Never, NoError> in
                guard let messageId else {
                    return .complete()
                }
                let finalGift = PampGramPhantomGift(id: phantomGift.id, peerId: phantomGift.peerId, gift: phantomGift.gift, price: phantomGift.price, date: phantomGift.date, localMessageId: messageId, fromPeerId: phantomGift.fromPeerId)
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
    /// reads as `peerId` having sent it to this account. Credits the matching fake balance
    /// (Stars or TON) by the gift's `price` and logs a `.topUp` in the ledger, so a gift you
    /// "received" shows up as a пополнение — the behaviour the user asked for — rather than
    /// silently doing nothing to the balance.
    public static func receiveUniqueGift(context: AccountContext, peerId: EnginePeer.Id, uniqueGift: StarGift.UniqueGift, price: CurrencyAmount) -> Signal<PampGramPhantomGift, NoError> {
        return context.account.postbox.transaction { transaction -> PampGramPhantomGift in
            // Same resale-listing cleanup as `buyUniqueGift` — see its comment.
            let ownedGift = PampGramPhantomGiftMessage.fakedOwnership(of: uniqueGift, newOwnerPeerId: peerId)
            let phantomGift = PampGramPhantomGift(
                id: Int64.random(in: 1...Int64.max),
                peerId: peerId,
                gift: .unique(ownedGift),
                price: price,
                date: Int32(Date().timeIntervalSince1970),
                localMessageId: nil,
                fromPeerId: peerId,
                isReceived: true
            )
            PampGramPhantomGiftStore.add(transaction: transaction, gift: phantomGift)

            let ledgerCurrency: PampGramLocalCurrency = price.currency == .stars ? .stars : .ton
            let _ = PampGramLocalLedgerStore.addAndApply(
                transaction: transaction,
                currency: ledgerCurrency,
                kind: .topUp,
                amount: price.amount.value,
                title: "Подарок мне",
                details: phantomGift.title,
                peerId: peerId,
                giftId: phantomGift.id
            )
            return phantomGift
        }
        |> mapToSignal { phantomGift -> Signal<PampGramPhantomGift, NoError> in
            return PampGramPhantomGiftMessage.insertLocalUniqueGiftMessageFromPeer(context: context, peerId: peerId, uniqueGift: uniqueGift)
            |> mapToSignal { messageId -> Signal<PampGramPhantomGift, NoError> in
                guard let messageId else {
                    return .single(phantomGift)
                }
                let finalGift = PampGramPhantomGift(id: phantomGift.id, peerId: phantomGift.peerId, gift: phantomGift.gift, price: phantomGift.price, date: phantomGift.date, localMessageId: messageId, fromPeerId: phantomGift.fromPeerId, isReceived: true)
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
                fromPeerId: peerId,
                isReceived: true
            )
            PampGramPhantomGiftStore.add(transaction: transaction, gift: phantomGift)

            // Received gift → пополнение (Stars), same as receiveUniqueGift.
            let _ = PampGramLocalLedgerStore.addAndApply(
                transaction: transaction,
                currency: .stars,
                kind: .topUp,
                amount: gift.price,
                title: "Подарок мне",
                details: phantomGift.title,
                peerId: peerId,
                giftId: phantomGift.id
            )
            return phantomGift
        }
        |> mapToSignal { phantomGift -> Signal<Never, NoError> in
            return PampGramPhantomGiftMessage.insertLocalGenericGiftMessageFromPeer(context: context, peerId: peerId, gift: gift, text: text, entities: entities)
            |> mapToSignal { messageId -> Signal<Never, NoError> in
                guard let messageId else {
                    return .complete()
                }
                let finalGift = PampGramPhantomGift(id: phantomGift.id, peerId: phantomGift.peerId, gift: phantomGift.gift, price: phantomGift.price, date: phantomGift.date, localMessageId: messageId, fromPeerId: phantomGift.fromPeerId, isReceived: true)
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

    /// Removes a visual gift from the account owner's own profile grid. Matching is
    /// deliberately scoped to `context.account.peerId`, so a recipient profile cannot be
    /// modified through this local control.
    public static func delete(context: AccountContext, matching gift: ProfileGiftsContext.State.StarGift) -> Signal<Never, NoError> {
        return context.account.postbox.transaction { transaction -> Void in
            guard let match = self.findPhantomGift(transaction: transaction, selfPeerId: context.account.peerId, matching: gift) else {
                return
            }
            PampGramPhantomGiftStore.remove(transaction: transaction, id: match.id)
            if let messageId = match.localMessageId {
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
    /// shares with another one (each gets its own `Date()` at creation). Both sides go
    /// through `matchableGift` first: `asProfileGift` layers a local market listing onto its
    /// `.unique` projection's `resellAmounts`/`resellForTonOnly` purely for display (see its
    /// own doc comment), so comparing the raw `StarGift` values would fail to match a
    /// currently-listed gift against its own stored record.
    private static func findPhantomGift(transaction: Transaction, selfPeerId: EnginePeer.Id, matching gift: ProfileGiftsContext.State.StarGift) -> PampGramPhantomGift? {
        let target = Self.matchableGift(gift.gift)
        return PampGramPhantomGiftStore.allGifts(transaction: transaction).first(where: { $0.peerId == selfPeerId && Self.matchableGift($0.gift) == target && $0.date == gift.date })
    }

    private static func matchableGift(_ gift: StarGift) -> StarGift {
        guard case let .unique(uniqueGift) = gift, uniqueGift.resellAmounts != nil || uniqueGift.resellForTonOnly else {
            return gift
        }
        return .unique(StarGift.UniqueGift(
            id: uniqueGift.id,
            giftId: uniqueGift.giftId,
            title: uniqueGift.title,
            number: uniqueGift.number,
            slug: uniqueGift.slug,
            owner: uniqueGift.owner,
            attributes: uniqueGift.attributes,
            availability: uniqueGift.availability,
            giftAddress: uniqueGift.giftAddress,
            resellAmounts: nil,
            resellForTonOnly: false,
            releasedBy: uniqueGift.releasedBy,
            valueAmount: uniqueGift.valueAmount,
            valueCurrency: uniqueGift.valueCurrency,
            valueUsdAmount: uniqueGift.valueUsdAmount,
            flags: uniqueGift.flags,
            themePeerId: uniqueGift.themePeerId,
            peerColor: uniqueGift.peerColor,
            hostPeerId: uniqueGift.hostPeerId,
            minOfferStars: uniqueGift.minOfferStars,
            craftChancePermille: uniqueGift.craftChancePermille
        ))
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
            let salePrice = match.marketPrice ?? match.price
            let ledgerCurrency: PampGramLocalCurrency = salePrice.currency == .stars ? .stars : .ton
            let _ = PampGramLocalLedgerStore.addAndApply(
                transaction: transaction,
                currency: ledgerCurrency,
                kind: .sale,
                amount: salePrice.amount.value,
                title: "Продажа подарка",
                details: match.title,
                peerId: match.peerId,
                giftId: match.id
            )
            PampGramPhantomGiftStore.update(transaction: transaction, id: match.id, { $0.withSold(date: Int32(Date().timeIntervalSince1970)) })
        }
        |> ignoreValues
    }

    /// Marks one local gift as the profile decoration currently being worn. Only one self-gift
    /// is worn at a time; this is local PampGram state and never calls Telegram.
    public static func setWorn(context: AccountContext, giftId: Int64, worn: Bool) -> Signal<Never, NoError> {
        return context.account.postbox.transaction { transaction -> Void in
            let gifts = PampGramPhantomGiftStore.allGifts(transaction: transaction)
            if worn {
                for gift in gifts where gift.peerId == context.account.peerId && gift.worn && gift.id != giftId {
                    PampGramPhantomGiftStore.update(transaction: transaction, id: gift.id, { $0.withWorn(false) })
                }
            }
            PampGramPhantomGiftStore.update(transaction: transaction, id: giftId, { $0.withWorn(worn) })
        }
        |> ignoreValues
    }

    /// The profile-card equivalent of `setWorn`; it can act only on a self-owned visual
    /// gift, never on an entry rendered in somebody else's profile.
    public static func setWorn(context: AccountContext, matching gift: ProfileGiftsContext.State.StarGift, worn: Bool) -> Signal<Never, NoError> {
        return context.account.postbox.transaction { transaction -> Void in
            guard let match = self.findPhantomGift(transaction: transaction, selfPeerId: context.account.peerId, matching: gift) else {
                return
            }
            let gifts = PampGramPhantomGiftStore.allGifts(transaction: transaction)
            if worn {
                for current in gifts where current.peerId == context.account.peerId && current.worn && current.id != match.id {
                    PampGramPhantomGiftStore.update(transaction: transaction, id: current.id, { $0.withWorn(false) })
                }
            }
            PampGramPhantomGiftStore.update(transaction: transaction, id: match.id, { $0.withWorn(worn) })
        }
        |> ignoreValues
    }

    /// Local marketplace listing. A nil price removes the listing; no real Stars/TON or
    /// Telegram marketplace state is touched.
    public static func setMarketListing(context: AccountContext, giftId: Int64, price: CurrencyAmount?) -> Signal<Never, NoError> {
        return context.account.postbox.transaction { transaction -> Void in
            PampGramPhantomGiftStore.update(transaction: transaction, id: giftId, { $0.withMarketPrice(price) })
        }
        |> ignoreValues
    }

    /// The GiftViewScreen `updateResellStars:` override for a Phantom Gift: sets or clears
    /// the local marketplace listing price, resolved from the profile-grid item the same way
    /// every other `matching:` entry point here is. This is what makes "Продать" on a real
    /// gift-card screen work for one of these instead of hitting the real, network-backed
    /// `updateStarGiftResalePrice` with a reference nothing on the server recognizes.
    public static func setMarketListing(context: AccountContext, matching gift: ProfileGiftsContext.State.StarGift, price: CurrencyAmount?) -> Signal<Never, NoError> {
        return context.account.postbox.transaction { transaction -> Void in
            guard let match = self.findPhantomGift(transaction: transaction, selfPeerId: context.account.peerId, matching: gift) else {
                return
            }
            PampGramPhantomGiftStore.update(transaction: transaction, id: match.id, { $0.withMarketPrice(price) })
        }
        |> ignoreValues
    }

    /// Moves a local gift to another local profile/chat owner. This changes only the
    /// PampGram record and intentionally clears pin/wear/market state.
    public static func transfer(context: AccountContext, giftId: Int64, to peerId: EnginePeer.Id) -> Signal<Never, NoError> {
        return context.account.postbox.transaction { transaction -> Void in
            guard let gift = PampGramPhantomGiftStore.allGifts(transaction: transaction).first(where: { $0.id == giftId }) else {
                return
            }
            PampGramPhantomGiftStore.update(transaction: transaction, id: giftId, { $0.withPeerId(peerId) })
            PampGramLocalLedgerStore.add(transaction: transaction, operation: PampGramLocalOperation(
                currency: gift.price.currency == .stars ? .stars : .ton,
                kind: .transfer,
                amount: 0,
                title: "Передача подарка",
                details: gift.title,
                peerId: peerId,
                giftId: gift.id,
                balanceAfter: nil
            ))
        }
        |> ignoreValues
    }

    /// Local-only visual transfer: moves the phantom gift to `peerId` inside this account's own
    /// records and logs the transfer. Nothing is sent to any other device — PampGram gifts are
    /// purely local play money, so a visual transfer only ever changes the sender's own view.
    public static func sendGiftToPeer(context: AccountContext, giftId: Int64, peerId: EnginePeer.Id) -> Signal<Bool, NoError> {
        return context.account.postbox.transaction { transaction -> Bool in
            guard let gift = PampGramPhantomGiftStore.allGifts(transaction: transaction).first(where: { $0.id == giftId }) else {
                return false
            }
            PampGramPhantomGiftStore.update(transaction: transaction, id: giftId, { $0.withPeerId(peerId) })
            PampGramLocalLedgerStore.add(transaction: transaction, operation: PampGramLocalOperation(
                currency: gift.price.currency == .stars ? .stars : .ton,
                kind: .transfer,
                amount: 0,
                title: "Передача подарка",
                details: gift.title,
                peerId: peerId,
                giftId: gift.id,
                balanceAfter: nil
            ))
            return true
        }
    }

    /// The GiftViewScreen `transferGift:` override for a Phantom Gift: moves the gift to
    /// `peerId` inside this account's own records and logs the transfer, exactly like
    /// `sendGiftToPeer(context:giftId:peerId:)`, but resolved from the profile-grid item the
    /// same way every other `matching:` entry point here is. This is what makes "Передать" on
    /// a real gift-card screen work for one of these instead of hitting the real,
    /// network-backed `transferStarGift` with a reference nothing on the server recognizes.
    public static func sendGiftToPeer(context: AccountContext, matching gift: ProfileGiftsContext.State.StarGift, peerId: EnginePeer.Id) -> Signal<Bool, NoError> {
        return context.account.postbox.transaction { transaction -> Bool in
            guard let match = self.findPhantomGift(transaction: transaction, selfPeerId: context.account.peerId, matching: gift) else {
                return false
            }
            PampGramPhantomGiftStore.update(transaction: transaction, id: match.id, { $0.withPeerId(peerId) })
            PampGramLocalLedgerStore.add(transaction: transaction, operation: PampGramLocalOperation(
                currency: match.price.currency == .stars ? .stars : .ton,
                kind: .transfer,
                amount: 0,
                title: "Передача подарка",
                details: match.title,
                peerId: peerId,
                giftId: match.id,
                balanceAfter: nil
            ))
            return true
        }
    }

    /// "Fake покупка TG": confirms that a self-listed phantom gift (`marketPrice != nil`) has
    /// been "bought" by someone on the visual market. Credits the fake balance with the listed
    /// price, marks the gift sold (same bookkeeping as `sell(context:matching:)`), and posts a
    /// local "your gift was sold" notification into the Telegram service chat so it looks like
    /// a genuine resale completed — nothing here calls any real Telegram or TON endpoint.
    public static func confirmFakeMarketSale(context: AccountContext, giftId: Int64) -> Signal<Never, NoError> {
        return context.account.postbox.transaction { transaction -> (PampGramPhantomGift, CurrencyAmount)? in
            guard let gift = PampGramPhantomGiftStore.allGifts(transaction: transaction).first(where: { $0.id == giftId }), let salePrice = gift.marketPrice else {
                return nil
            }
            let ledgerCurrency: PampGramLocalCurrency = salePrice.currency == .stars ? .stars : .ton
            let _ = PampGramLocalLedgerStore.addAndApply(
                transaction: transaction,
                currency: ledgerCurrency,
                kind: .sale,
                amount: salePrice.amount.value,
                title: "Продажа на маркете",
                details: gift.title,
                peerId: gift.peerId,
                giftId: gift.id
            )
            PampGramPhantomGiftStore.update(transaction: transaction, id: gift.id, { $0.withSold(date: Int32(Date().timeIntervalSince1970)) })
            return (gift, salePrice)
        }
        |> mapToSignal { result -> Signal<Never, NoError> in
            guard let (gift, salePrice) = result else {
                return .complete()
            }
            return PampGramPhantomGiftMessage.insertLocalGiftSoldNotification(context: context, giftTitle: gift.title, price: salePrice)
            |> ignoreValues
        }
    }

    /// Subscribes to incoming messages account-wide and materializes any carried gift into this
    /// account's own collection automatically — no user action. Owned by the account context.
    ///
    /// This live signal only fires for messages processed through the update loop while the app is
    /// running; it can miss a transfer that arrived while the app was closed or in a background
    /// account. So it is a best-effort fast path — the reliable path is scanPeerForIncomingGiftTransfers,
    /// which runs every time the recipient opens the chat.
    public static func observeIncomingGiftTransfers(account: Account) -> Disposable {
        // PampGram gifts are local-only — nothing is ever sent to another device, so there is
        // nothing to receive. Inert no-op, kept so the account-context hook needs no change.
        return EmptyDisposable
    }

    /// Scans the most recent messages of a chat the recipient just opened and materializes any
    /// gift transfer carried by an incoming message. This is the reliable entry point (called from
    /// navigateToChatControllerImpl): whenever the recipient opens the chat with the sender, any
    /// transfer that has arrived — even while the app was closed — is picked up. Duplicates are
    /// prevented by the deterministic gift id, so re-opening the chat is harmless.
    public static func scanPeerForIncomingGiftTransfers(context: AccountContext, peerId: EnginePeer.Id) {
        // PampGram gifts are local-only — nothing is ever sent to another device, so there is
        // nothing to scan for. Inert no-op, kept so the navigate hook needs no change.
    }

}
