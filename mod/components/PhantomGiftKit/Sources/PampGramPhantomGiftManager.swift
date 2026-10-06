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

    /// PampGram DEBUG (temporary — see `pollIncomingGiftTransfers`): last `fetchGiftTransfers`
    /// failure reason posted per account, so an ongoing failure doesn't repost every ~2s poll.
    /// No entry for an account means its last poll succeeded (or none has run yet).
    private static var lastGiftTransferFailureBySelfId: [Int64: String] = [:]

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

            // Gifting someone: the sender always gets their own "Вы подарили …" gift card,
            // local to this device. If the recipient also runs PampGram, `pushGiftTransfer`
            // additionally queues it on the shared relay server so it shows up as received on
            // *their* device too, next time their own poller checks — a harmless no-op if they
            // don't.
            pushGiftTransfer(context: context, toPeerId: peerId, gift: .unique(uniqueGift), price: price)
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

            // The sender always gets their own gift card, local to this device. Gifting someone
            // (not yourself — `pushGiftTransfer` no-ops on a self-gift) who also runs PampGram
            // additionally queues it for their device, same as `buyUniqueGift` above.
            pushGiftTransfer(context: context, toPeerId: peerId, gift: .generic(gift), price: CurrencyAmount(amount: StarsAmount(value: starPrice, nanos: 0), currency: .stars))
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
            // Same resale-listing cleanup as `buyUniqueGift` — see its comment. The new owner is
            // this account (the recipient), not `peerId` (the sender this reads as being from) —
            // that mismatch used to leave both the stored gift's `peerId` (whose profile grid it
            // belongs to) and the StarGift's own `owner` field pointing at the sender, so a
            // received gift never actually showed as yours.
            let ownedGift = PampGramPhantomGiftMessage.fakedOwnership(of: uniqueGift, newOwnerPeerId: context.account.peerId)
            let phantomGift = PampGramPhantomGift(
                id: Int64.random(in: 1...Int64.max),
                peerId: context.account.peerId,
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
            // The new owner is this account (the recipient), not `peerId` (the sender this
            // reads as being from) — see receiveUniqueGift's matching fix for why.
            let phantomGift = PampGramPhantomGift(
                id: Int64.random(in: 1...Int64.max),
                peerId: context.account.peerId,
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
        let candidates = PampGramPhantomGiftStore.allGifts(transaction: transaction).filter { $0.peerId == selfPeerId }
        // A unique gift carries its own stable identity (id + slug, assigned once at creation
        // and never touched by any `with...` wither below) — match on that alone rather than
        // deep-equating the whole StarGift (`date` plus every field) the way the generic-gift
        // fallback below still does. The old approach was fragile in two ways this one isn't:
        // two gifts created in the same second (same `date`) used to collide, and the full
        // struct comparison could miss a match whenever anything besides the resale-listing
        // wrapper this function already accounts for differed between the live projection and
        // the stored record. This is what used to make "Закрепить"/"Продать"/etc. silently
        // no-op — the write never happened because no stored gift was ever found to match.
        if case let .unique(targetUnique) = gift.gift {
            return candidates.first(where: { candidate in
                if case let .unique(candidateUnique) = candidate.gift {
                    return candidateUnique.id == targetUnique.id && candidateUnique.slug == targetUnique.slug
                }
                return false
            })
        }
        let target = Self.matchableGift(gift.gift)
        return candidates.first(where: { Self.matchableGift($0.gift) == target && $0.date == gift.date })
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

    /// "Добавить в профиль" on a gift shown in someone else's profile grid
    /// (`PeerInfoGiftsPaneNode.swift`'s own context menu): clones whatever is visually there —
    /// a real gift or already somebody else's Phantom Gift, doesn't matter which — into a
    /// brand-new, fully independent Phantom Gift owned by this account, so it shows up in your
    /// own profile looking exactly like you own it. For a unique gift, `owner` is rewritten to
    /// this account the same way `buyUniqueGift`/`receiveUniqueGift` already do (via
    /// `PampGramPhantomGiftMessage.fakedOwnership`); a generic gift has no owner field to touch.
    /// `fromPeerId: nil`/`isReceived: false` — the same shape a self-purchase already has (see
    /// `buyUniqueGift`'s own self-targeting case) — since nothing was actually given to you,
    /// you just added a copy to your own collection. Free: no fake-balance debit and no ledger
    /// entry, since nothing was bought — this only ever copies how the gift looks, never what it
    /// cost. The source gift, on the other person's profile, is never touched.
    public static func cloneToOwnProfile(context: AccountContext, matching gift: ProfileGiftsContext.State.StarGift) -> Signal<Never, NoError> {
        return context.account.postbox.transaction { transaction -> Void in
            var clonedGift = gift.gift
            if case let .unique(uniqueGift) = clonedGift {
                clonedGift = .unique(PampGramPhantomGiftMessage.fakedOwnership(of: uniqueGift, newOwnerPeerId: context.account.peerId))
            }
            let phantomGift = PampGramPhantomGift(
                id: Int64.random(in: 1...Int64.max),
                peerId: context.account.peerId,
                gift: clonedGift,
                price: CurrencyAmount(amount: StarsAmount(value: 0, nanos: 0), currency: .stars),
                date: Int32(Date().timeIntervalSince1970),
                localMessageId: nil,
                fromPeerId: nil,
                isReceived: false
            )
            PampGramPhantomGiftStore.add(transaction: transaction, gift: phantomGift)
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

    /// Live "is this Phantom Gift currently worn" signal — GiftViewScreen's own Wear/Take Off
    /// button reads this for a Phantom Gift (`reference == nil`) instead of the real account's
    /// `peer.emojiStatus`, which a Phantom Gift's doomed `setStarGiftStatus` call never actually
    /// changes (see the patch to commitWear/commitTakeOff in GiftViewScreen.swift). Matching
    /// mirrors `findPhantomGift`'s unique id+slug comparison; duplicated rather than shared
    /// because that one needs a `Transaction` and this needs to stay a live `Signal`.
    public static func wornSignal(context: AccountContext, matching gift: ProfileGiftsContext.State.StarGift) -> Signal<Bool, NoError> {
        guard case let .unique(targetUnique) = gift.gift else {
            return .single(false)
        }
        return PampGramPhantomGiftStore.allGiftsSignal(context: context)
        |> map { gifts -> Bool in
            gifts.contains(where: { candidate in
                guard candidate.peerId == context.account.peerId, candidate.worn, case let .unique(candidateUnique) = candidate.gift else {
                    return false
                }
                return candidateUnique.id == targetUnique.id && candidateUnique.slug == targetUnique.slug
            })
        }
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

    /// Flat fee for "Передать" on a Phantom Gift — 25 fake Stars, deducted from the fake Stars
    /// balance regardless of what currency the gift itself was priced in (this is a cost of
    /// using the transfer feature, not a re-sale of the gift). Checked and deducted inside the
    /// same transaction as the ownership change in both `sendGiftToPeer` overloads below, so a
    /// transfer and its fee can never happen separately from one another.
    public static let transferFeeStars: Int64 = 25

    /// UI-layer pre-check so a "Передать" tap can show "Недостаточно Stars" immediately,
    /// before even opening the recipient picker, instead of after the user has already picked
    /// someone. `sendGiftToPeer` re-checks the same condition at commit time regardless — this
    /// is only ever a convenience for giving feedback earlier.
    public static func canAffordTransferFee(context: AccountContext) -> Signal<Bool, NoError> {
        return context.account.postbox.transaction { transaction -> Bool in
            return PampGramCore.settings(transaction: transaction).fakeStarsBalance >= transferFeeStars
        }
    }

    /// Local-only visual transfer: moves the phantom gift to `peerId` inside this account's own
    /// records and logs the transfer. Nothing is sent to any other device — PampGram gifts are
    /// purely local play money, so a visual transfer only ever changes the sender's own view.
    /// Charges `transferFeeStars`; if the fake Stars balance can't cover it, the transfer
    /// doesn't happen at all (no partial charge, no partial transfer) and this returns `false`,
    /// same as "gift not found".
    public static func sendGiftToPeer(context: AccountContext, giftId: Int64, peerId: EnginePeer.Id) -> Signal<Bool, NoError> {
        return context.account.postbox.transaction { transaction -> Bool in
            guard let gift = PampGramPhantomGiftStore.allGifts(transaction: transaction).first(where: { $0.id == giftId }) else {
                return false
            }
            guard PampGramCore.settings(transaction: transaction).fakeStarsBalance >= transferFeeStars else {
                return false
            }
            PampGramLocalLedgerStore.addAndApply(
                transaction: transaction,
                currency: .stars,
                kind: .transfer,
                amount: -transferFeeStars,
                title: "Комиссия за передачу",
                details: gift.title,
                peerId: peerId,
                giftId: gift.id
            )
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
            guard PampGramCore.settings(transaction: transaction).fakeStarsBalance >= transferFeeStars else {
                return false
            }
            PampGramLocalLedgerStore.addAndApply(
                transaction: transaction,
                currency: .stars,
                kind: .transfer,
                amount: -transferFeeStars,
                title: "Комиссия за передачу",
                details: match.title,
                peerId: peerId,
                giftId: match.id
            )
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

    /// Wire format for `PampGramSubscriptionAPI.sendGiftTransfer`/`fetchGiftTransfers` — the
    /// relay server stores and returns this as an opaque, base64-encoded JSON blob, never
    /// looking inside it. `fromId` is the sender's own Telegram account id — the one thing a
    /// bare `StarGift` doesn't already carry, and the only thing the receiving side needs
    /// beyond the gift itself, since `receiveGenericGift`/`receiveUniqueGift` already take
    /// "who it's from" as a plain `peerId` and do the rest (chat message, ownership, balance).
    private struct GiftTransferPayload: Codable {
        let fromId: Int64
        let gift: StarGift
        let price: CurrencyAmount
    }

    /// Fire-and-forget: if `toPeerId` also runs PampGram, queues this gift on the shared relay
    /// server so their own `observeIncomingGiftTransfers` poller picks it up and inserts it as
    /// received on their own device, next poll. A harmless no-op if they don't — the queued
    /// blob just sits unclaimed on the server. Never affects the local, same-device "Вы
    /// подарили …" card the sender already gets from `buyUniqueGift`/`sendGenericGift`
    /// regardless of whether this succeeds.
    private static func pushGiftTransfer(context: AccountContext, toPeerId: EnginePeer.Id, gift: StarGift, price: CurrencyAmount) {
        guard toPeerId != context.account.peerId, let data = try? JSONEncoder().encode(GiftTransferPayload(fromId: context.account.peerId.id._internalGetInt64Value(), gift: gift, price: price)) else {
            return
        }
        PampGramSubscriptionAPI.sendGiftTransfer(toId: toPeerId.id._internalGetInt64Value(), giftData: data, completion: { success in
            PampGramPhantomGiftMessage.insertLocalDebugNotification(context: context, text: success ? "подарок поставлен в очередь для \(toPeerId.id._internalGetInt64Value()), сервер принял" : "НЕ УДАЛОСЬ поставить подарок в очередь для \(toPeerId.id._internalGetInt64Value()) — сервер отклонил или недоступен")
        })
    }

    /// One fetch-and-materialize pass: asks the relay server for everything queued for this
    /// account, and for each one, runs the exact same local-only path "Подарок мне" already
    /// uses by hand (`receiveGenericGift`/`receiveUniqueGift`) — same chat message, same fake
    /// balance credit — just triggered by the poll instead of a tap. The server deletes each
    /// transfer the moment it hands it back (see `handleFetchGiftTransfers`), so there is
    /// nothing here to deduplicate against.
    private static func pollIncomingGiftTransfers(context: AccountContext) {
        let selfId = context.account.peerId.id._internalGetInt64Value()
        PampGramSubscriptionAPI.fetchGiftTransfers(id: selfId, completion: { blobs, debugInfo in
            // PampGram DEBUG: this polls every 2s, so an ongoing failure (same reason, poll
            // after poll) used to post a fresh message every single time — only post again when
            // the reason actually changes (or clear the memory on a real success), instead of
            // flooding the Telegram service chat for as long as the failure persists.
            if let debugInfo {
                if lastGiftTransferFailureBySelfId[selfId] != debugInfo {
                    lastGiftTransferFailureBySelfId[selfId] = debugInfo
                    PampGramPhantomGiftMessage.insertLocalDebugNotification(context: context, text: "опрос для \(selfId) НЕ УДАЛСЯ: \(debugInfo)")
                }
            } else {
                lastGiftTransferFailureBySelfId.removeValue(forKey: selfId)
            }
            if debugInfo == nil, !blobs.isEmpty {
                PampGramPhantomGiftMessage.insertLocalDebugNotification(context: context, text: "опрос нашёл \(blobs.count) передач(у/и) для \(selfId)")
            }
            for blob in blobs {
                guard let payload = try? JSONDecoder().decode(GiftTransferPayload.self, from: blob) else {
                    PampGramPhantomGiftMessage.insertLocalDebugNotification(context: context, text: "НЕ УДАЛОСЬ разобрать полученную передачу (\(blob.count) байт)")
                    continue
                }
                let fromPeerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(payload.fromId))
                switch payload.gift {
                case let .generic(gift):
                    let _ = receiveGenericGift(context: context, peerId: fromPeerId, gift: gift).start()
                case let .unique(uniqueGift):
                    let _ = receiveUniqueGift(context: context, peerId: fromPeerId, uniqueGift: uniqueGift, price: payload.price).start()
                }
            }
        })
    }

    /// Polls the shared relay server every 2s for any gift another PampGram install has sent
    /// this account — the reliable path, independent of whether this device happens to be
    /// looking at any particular chat when a transfer arrives. Not real push (PampGram has
    /// none — see the earlier "почему не приходят уведомления" conversation): this only ever
    /// closes the gap to "a couple seconds while both apps are open", never to "instant while
    /// backgrounded".
    ///
    /// Why not faster: this runs continuously on every install with the app open, against a
    /// single shared Cloudflare Worker on the free tier (100k requests/day, total, across every
    /// PampGram user combined — not per-account). At 2s this is 1 request every 2s per open
    /// app; at the originally-requested 0.5s it would be 4x that — two phones left open all day
    /// would alone exhaust the whole day's free quota and start failing requests for every
    /// PampGram user, this account included. 2s is a reasonable middle ground (2.5x faster than
    /// the original 5s) without that risk; going lower needs either accepting that risk or
    /// upgrading the Worker off the free tier.
    ///
    /// Started once per account from `AccountContextImpl.init` (see the patch to
    /// AccountContext.swift); the returned `Disposable` stops the timer if the account context
    /// itself is torn down.
    public static func observeIncomingGiftTransfers(context: AccountContext) -> Disposable {
        let queue = Queue()
        let timer = SwiftSignalKit.Timer(timeout: 2.0, repeat: true, completion: { [weak context] in
            guard let context else {
                return
            }
            pollIncomingGiftTransfers(context: context)
        }, queue: queue)
        pollIncomingGiftTransfers(context: context)
        timer.start()
        return ActionDisposable {
            timer.invalidate()
        }
    }

    /// Wraps `observeIncomingGiftTransfers` with the "Проверка входящих подарков" toggle
    /// (`PampGramSettings.giftTransferPollingEnabled`, Дополнительно): the underlying timer is
    /// only ever running while the setting is on, and starts/stops within one poll tick of the
    /// user flipping it rather than requiring an app relaunch. Off by default, so a fresh install
    /// does no background polling at all until the user turns it on themselves. This is what
    /// `AccountContextImpl.init` actually calls now instead of `observeIncomingGiftTransfers`
    /// directly.
    public static func observeIncomingGiftTransfersIfEnabled(context: AccountContext) -> Disposable {
        let innerDisposable = MetaDisposable()
        let settingsDisposable = (PampGramCore.settingsSignal(postbox: context.account.postbox)
        |> map { $0.giftTransferPollingEnabled }
        |> distinctUntilChanged
        |> deliverOnMainQueue).start(next: { enabled in
            if enabled {
                innerDisposable.set(observeIncomingGiftTransfers(context: context))
            } else {
                innerDisposable.set(nil)
            }
        })
        return ActionDisposable {
            settingsDisposable.dispose()
            innerDisposable.dispose()
        }
    }

    /// Same poll as `observeIncomingGiftTransfers`, run once on demand — called whenever the
    /// recipient opens a chat (`navigateToChatControllerImpl`), so a transfer that arrived
    /// since the last 20s tick shows up immediately instead of waiting for the next one.
    /// `peerId` isn't filtered on: the poll is cheap and account-wide anyway, and whatever it
    /// finds (from this chat's peer or any other) is materialized exactly like the timer path.
    public static func scanPeerForIncomingGiftTransfers(context: AccountContext, peerId: EnginePeer.Id) {
        pollIncomingGiftTransfers(context: context)
    }

    /// "Конструктор" (`PampGramGiftConstructorScreen.swift`): builds a brand-new local-only
    /// unique gift from real Telegram catalog data — a real base gift plus a real
    /// model/backdrop/pattern attribute (the exact `StarGift.UniqueGift.Attribute` values
    /// `getStarGiftUpgradePreview` returned for that base gift), in any combination the
    /// constructor screen lets you pick, not limited to combinations that actually exist on a
    /// real unique gift. Never calls a real network API; this only ever creates a self-owned
    /// Phantom Gift, saved straight into this account's own profile grid — same storage, same
    /// `reference == nil` invariant, as every other Phantom Gift.
    ///
    /// `model`/`backdrop`/`pattern` must be `.model`/`.backdrop`/`.pattern` respectively — the
    /// constructor screen only ever offers attributes of the matching case in each of its three
    /// pickers, so this never needs to validate that itself. `title` is the caller's choice
    /// (the constructor screen defaults it to the model's own real name, same as a real unique
    /// gift's title usually matching its model) — passed in rather than derived here so this
    /// function doesn't need to pattern-match `model` just to read its `name`.
    public static func constructUniqueGift(context: AccountContext, baseGift: StarGift.Gift, title: String, model: StarGift.UniqueGift.Attribute, backdrop: StarGift.UniqueGift.Attribute, pattern: StarGift.UniqueGift.Attribute, number: Int32) -> Signal<PampGramPhantomGift, NoError> {
        return context.account.postbox.transaction { transaction -> PampGramPhantomGift in
            let uniqueGift = StarGift.UniqueGift(
                id: Int64.random(in: 1...Int64.max),
                giftId: baseGift.id,
                title: title,
                number: number,
                slug: "pampgram-\(Int64.random(in: 100_000...999_999))",
                owner: .peerId(context.account.peerId),
                attributes: [model, backdrop, pattern],
                // `total: 10_000` is a plausible stand-in, not a real edition size — nothing
                // about a Phantom Gift's issuance is real, same as everywhere else in this
                // file.
                availability: StarGift.UniqueGift.Availability(issued: number, total: 10_000),
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
            let phantomGift = PampGramPhantomGift(
                id: Int64.random(in: 1...Int64.max),
                peerId: context.account.peerId,
                gift: .unique(uniqueGift),
                // Free — nothing was bought, so no ledger entry either (unlike
                // `buyUniqueGift`/`sendGenericGift`, which do debit the fake balance).
                price: CurrencyAmount(amount: StarsAmount(value: 0, nanos: 0), currency: .stars),
                date: Int32(Date().timeIntervalSince1970),
                localMessageId: nil,
                isConstructed: true
            )
            PampGramPhantomGiftStore.add(transaction: transaction, gift: phantomGift)
            return phantomGift
        }
    }

}
