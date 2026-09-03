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
            let ledgerCurrency: PampGramLocalCurrency = price.currency == .stars ? .stars : .ton
            PampGramLocalLedgerStore.add(transaction: transaction, operation: PampGramLocalOperation(
                currency: ledgerCurrency,
                kind: .purchase,
                amount: -price.amount.value,
                title: "Покупка подарка",
                details: phantomGift.title,
                peerId: peerId,
                giftId: phantomGift.id,
                balanceAfter: newBalance
            ))
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

            // Gifting someone: the sender gets their own "Вы подарили …" gift card (same as a real
            // gift send), and the invisible carrier is delivered so a recipient running PampGram
            // turns it into a proper "X передал вам подарок" card and materializes the gift into
            // their own collection. Only the carrier crosses the network.
            let senderCard = PampGramPhantomGiftMessage.insertLocalUniqueGiftMessage(context: context, peerId: peerId, uniqueGift: uniqueGift, price: price)
            let deliver = deliverGiftMessage(context: context, peerId: peerId, gift: .unique(uniqueGift), price: price, title: phantomGift.title)
            return senderCard
            |> mapToSignal { _ in deliver }
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
            PampGramLocalLedgerStore.add(transaction: transaction, operation: PampGramLocalOperation(
                currency: .stars,
                kind: .purchase,
                amount: -starPrice,
                title: "Покупка подарка",
                details: phantomGift.title,
                peerId: peerId,
                giftId: phantomGift.id,
                balanceAfter: newBalance
            ))
            return PendingBuy(newBalance: newBalance, phantomGift: phantomGift)
        }
        |> mapToSignal { pending -> Signal<Never, NoError> in
            let phantomGift = pending.phantomGift

            // Gifting someone else: the sender gets their own "Вы подарили …" gift card, and the
            // invisible carrier is delivered so a recipient running PampGram turns it into a proper
            // "X передал вам подарок" card and materializes the gift into their own collection.
            if peerId != context.account.peerId {
                let senderCard = PampGramPhantomGiftMessage.insertLocalGenericGiftMessage(context: context, peerId: peerId, gift: gift, text: text, entities: entities, nameHidden: nameHidden)
                let deliver = deliverGiftMessage(context: context, peerId: peerId, gift: .generic(gift), price: phantomGift.price, title: phantomGift.title)
                return senderCard
                |> mapToSignal { _ in deliver }
                |> ignoreValues
            }

            // Gift to self (Saved Messages): stays a local-only card, nothing to send anywhere.
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
    /// reads as `peerId` having sent it to this account. Credits the matching fake balance
    /// (Stars or TON) by the gift's `price` and logs a `.topUp` in the ledger, so a gift you
    /// "received" shows up as a пополнение — the behaviour the user asked for — rather than
    /// silently doing nothing to the balance.
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

            let ledgerCurrency: PampGramLocalCurrency = price.currency == .stars ? .stars : .ton
            let balanceAfter: Int64
            switch price.currency {
            case .stars:
                balanceAfter = PampGramPhantomGiftStore.fakeStarsBalance(transaction: transaction) + price.amount.value
                PampGramPhantomGiftStore.setFakeStarsBalance(transaction: transaction, stars: balanceAfter)
            case .ton:
                balanceAfter = PampGramPhantomGiftStore.fakeTonBalanceNanos(transaction: transaction) + price.amount.value
                PampGramPhantomGiftStore.setFakeTonBalanceNanos(transaction: transaction, nanos: balanceAfter)
            }
            PampGramLocalLedgerStore.add(transaction: transaction, operation: PampGramLocalOperation(
                currency: ledgerCurrency,
                kind: .topUp,
                amount: price.amount.value,
                title: "Подарок мне",
                details: phantomGift.title,
                peerId: peerId,
                giftId: phantomGift.id,
                balanceAfter: balanceAfter
            ))
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

            // Received gift → пополнение (Stars), same as receiveUniqueGift.
            let balanceAfter = PampGramPhantomGiftStore.fakeStarsBalance(transaction: transaction) + gift.price
            PampGramPhantomGiftStore.setFakeStarsBalance(transaction: transaction, stars: balanceAfter)
            PampGramLocalLedgerStore.add(transaction: transaction, operation: PampGramLocalOperation(
                currency: .stars,
                kind: .topUp,
                amount: gift.price,
                title: "Подарок мне",
                details: phantomGift.title,
                peerId: peerId,
                giftId: phantomGift.id,
                balanceAfter: balanceAfter
            ))
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
            let salePrice = match.marketPrice ?? match.price
            let newBalance: Int64
            let ledgerCurrency: PampGramLocalCurrency
            switch salePrice.currency {
            case .stars:
                newBalance = PampGramPhantomGiftStore.fakeStarsBalance(transaction: transaction) + salePrice.amount.value
                PampGramPhantomGiftStore.setFakeStarsBalance(transaction: transaction, stars: newBalance)
                ledgerCurrency = .stars
            case .ton:
                newBalance = PampGramPhantomGiftStore.fakeTonBalanceNanos(transaction: transaction) + salePrice.amount.value
                PampGramPhantomGiftStore.setFakeTonBalanceNanos(transaction: transaction, nanos: newBalance)
                ledgerCurrency = .ton
            }
            PampGramLocalLedgerStore.add(transaction: transaction, operation: PampGramLocalOperation(
                currency: ledgerCurrency,
                kind: .sale,
                amount: salePrice.amount.value,
                title: "Продажа подарка",
                details: match.title,
                peerId: match.peerId,
                giftId: match.id,
                balanceAfter: newBalance
            ))
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

    // MARK: - Cross-device visual transfer (mod-to-mod)
    //
    // A local gift is carried to another user inside a normal Telegram text message — the only
    // channel that reaches another device. The gift data rides along as invisible Unicode "tag"
    // characters appended after a clean, human-readable line, so the message looks like an
    // ordinary short note on both sides (and to non-PampGram clients). A recipient running
    // PampGram detects it automatically (observeIncomingGiftTransfers) and materializes a real
    // local phantom gift they then own and manage like any other — no button, no extra step. For
    // unique gifts only the slug travels and the recipient fetches the real art from Telegram by
    // slug. Nothing here moves real gifts, Stars, or money; only an ordinary text message is sent.

    // Only tiny identifiers travel, never the whole gift object: a unique gift's slug, or a generic
    // catalog gift's id (resolved from the recipient's own cached catalog). Keeping the payload
    // small is what lets it survive intact inside the hidden channel — an embedded gift object was
    // large enough to be truncated in transit, which broke decoding on the recipient side.
    private struct TransferPayload: Codable {
        let v: Int
        let slug: String?
        let genericGiftId: Int64?
        let priceStars: Bool
        let priceAmount: Int64
        let title: String
    }

    // The payload is hidden using Unicode variation selectors: each UTF-8 byte of the base64 token
    // maps to exactly one selector (0…15 → U+FE00…U+FE0F, 16…255 → U+E0100…U+E01EF). Variation
    // selectors render completely invisibly — they only ever tweak the *preceding* character's
    // glyph variant and are silently ignored when no such variant exists — yet survive Telegram's
    // servers and copy/paste. The Unicode Tag block used before was drawn as visible .notdef boxes
    // by Telegram's text renderer (the row of "⍰" squares), which is exactly what this replaces.
    private static func hide(_ token: String) -> String {
        var scalars = String.UnicodeScalarView()
        for byte in Array(token.utf8) {
            let value: UInt32 = byte < 16 ? (0xFE00 + UInt32(byte)) : (0xE0100 + UInt32(byte) - 16)
            if let scalar = Unicode.Scalar(value) {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    private static func reveal(_ text: String) -> String? {
        var bytes: [UInt8] = []
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if value >= 0xFE00 && value <= 0xFE0F {
                bytes.append(UInt8(value - 0xFE00))
            } else if value >= 0xE0100 && value <= 0xE01EF {
                bytes.append(UInt8(value - 0xE0100 + 16))
            }
        }
        if bytes.isEmpty {
            return nil
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    /// The hidden base64 gift token in a message's text, if it carries one.
    public static func transferToken(inText text: String) -> String? {
        return reveal(text)
    }

    private static func decodePayload(token: String) -> TransferPayload? {
        guard let data = Data(base64Encoded: token) else {
            return nil
        }
        return try? PropertyListDecoder().decode(TransferPayload.self, from: data)
    }

    /// Encodes a gift into the base64 transfer token carried (hidden) inside a message.
    private static func encodeTransferToken(gift: StarGift, price: CurrencyAmount, title: String) -> String? {
        var slug: String?
        var genericGiftId: Int64?
        switch gift {
        case let .unique(uniqueGift):
            slug = uniqueGift.slug
        case let .generic(genericGift):
            genericGiftId = genericGift.id
        }
        let payload = TransferPayload(v: 1, slug: slug, genericGiftId: genericGiftId, priceStars: price.currency == .stars, priceAmount: price.amount.value, title: title)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let data = try? encoder.encode(payload) else {
            return nil
        }
        return data.base64EncodedString()
    }

    /// Delivers a gift to `peerId` by sending a real Telegram message that carries the gift as an
    /// invisible payload after a single visible "🎁". The visible character matters: a message made
    /// only of invisible characters is trimmed to empty and never sends (and a variation-selector
    /// run needs a base character to attach to), so "🎁" is the minimum that reliably reaches the
    /// recipient. A recipient running PampGram turns it into a proper received-gift card and
    /// materializes the gift into their collection; the sender's own copy of the carrier is deleted
    /// for the sender only, once it has had time to send. The message is the sole thing that crosses
    /// the network; the gift only appears for a recipient who also runs PampGram.
    public static func deliverGiftMessage(context: AccountContext, peerId: EnginePeer.Id, gift: StarGift, price: CurrencyAmount, title: String) -> Signal<Bool, NoError> {
        guard let token = encodeTransferToken(gift: gift, price: price, title: title) else {
            return .single(false)
        }
        let text = "🎁" + hide(token)
        let message: EnqueueMessage = .message(text: text, attributes: [], inlineStickers: [:], mediaReference: nil, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
        return enqueueMessages(account: context.account, peerId: peerId, messages: [message])
        |> map { ids -> Bool in
            let sentIds = ids.compactMap { $0 }
            if !sentIds.isEmpty {
                // Give the carrier time to actually reach the server (deleting a still-sending
                // message would cancel delivery), then remove only the sender's own copy so the
                // invisible carrier never shows as an empty bubble next to the gift card.
                Queue.mainQueue().after(8.0, {
                    let _ = context.engine.messages.deleteMessagesInteractively(messageIds: sentIds, type: .forLocalPeer).start()
                })
            }
            return true
        }
    }

    /// Sends a phantom gift to `peerId` as a real Telegram message carrying the (hidden) gift,
    /// then removes it from this account's own collection. Returns true once enqueued.
    public static func sendGiftToPeer(context: AccountContext, giftId: Int64, peerId: EnginePeer.Id) -> Signal<Bool, NoError> {
        return context.account.postbox.transaction { transaction -> (token: String, title: String)? in
            guard let gift = PampGramPhantomGiftStore.allGifts(transaction: transaction).first(where: { $0.id == giftId }) else {
                return nil
            }
            guard let token = encodeTransferToken(gift: gift.gift, price: gift.price, title: gift.title) else {
                return nil
            }
            PampGramPhantomGiftStore.remove(transaction: transaction, id: giftId)
            if let messageId = gift.localMessageId {
                transaction.deleteMessages([messageId], forEachMedia: nil)
            }
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
            return (token, gift.title)
        }
        |> mapToSignal { encoded -> Signal<Bool, NoError> in
            guard let encoded else {
                return .single(false)
            }
            let text = "🎁 Подарок «\(encoded.title)» передан." + hide(encoded.token)
            let message: EnqueueMessage = .message(text: text, attributes: [], inlineStickers: [:], mediaReference: nil, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
            return enqueueMessages(account: context.account, peerId: peerId, messages: [message])
            |> map { _ in true }
        }
    }

    // In-memory fast-path guard so the same message isn't re-fetched twice in one session. The
    // durable guard is the deterministic gift id below: the materialized gift's id is derived from
    // the carrier message id, so re-processing the same message (a later chat open, a relaunch)
    // resolves to a gift that already exists and is skipped — no duplicates across launches.
    private static var processedTransferMessageIds = Set<MessageId>()
    private static let processedLock = NSLock()

    private static func deterministicGiftId(for messageId: MessageId) -> Int64 {
        let key = "pgtransfer:\(messageId.peerId.toInt64()):\(messageId.namespace):\(messageId.id)"
        var hash: UInt64 = 1469598103934665603
        for byte in key.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1099511628211
        }
        return Int64(hash & 0x7FFF_FFFF_FFFF_FFFF)
    }

    /// Subscribes to incoming messages account-wide and materializes any carried gift into this
    /// account's own collection automatically — no user action. Owned by the account context.
    ///
    /// This live signal only fires for messages processed through the update loop while the app is
    /// running; it can miss a transfer that arrived while the app was closed or in a background
    /// account. So it is a best-effort fast path — the reliable path is scanPeerForIncomingGiftTransfers,
    /// which runs every time the recipient opens the chat.
    public static func observeIncomingGiftTransfers(account: Account) -> Disposable {
        return (account.stateManager.notificationMessages
        |> deliverOnMainQueue).start(next: { batches in
            for (messages, _, _, _) in batches {
                for message in messages {
                    guard message.flags.contains(.Incoming), message.author?.id != account.peerId else {
                        continue
                    }
                    guard let token = reveal(message.text) else {
                        continue
                    }
                    // Best-effort quick materialization into the collection while online. The gift
                    // card and carrier cleanup are done when the chat is opened
                    // (scanPeerForIncomingGiftTransfers, which has the AccountContext); the gift-id
                    // dedup keeps this from double-adding. No processed-set marking here, so a failed
                    // fetch never blocks the chat-open handler from retrying.
                    let _ = materializeGift(account: account, token: token, fromPeerId: message.id.peerId, sourceMessageId: message.id).start()
                }
            }
        })
    }

    /// Scans the most recent messages of a chat the recipient just opened and materializes any
    /// gift transfer carried by an incoming message. This is the reliable entry point (called from
    /// navigateToChatControllerImpl): whenever the recipient opens the chat with the sender, any
    /// transfer that has arrived — even while the app was closed — is picked up. Duplicates are
    /// prevented by the deterministic gift id, so re-opening the chat is harmless.
    public static func scanPeerForIncomingGiftTransfers(context: AccountContext, peerId: EnginePeer.Id) {
        let account = context.account
        let _ = (account.postbox.transaction { transaction -> [(MessageId, String)] in
            var found: [(MessageId, String)] = []
            guard let topId = transaction.getTopPeerMessageId(peerId: peerId, namespace: Namespaces.Message.Cloud) else {
                return found
            }
            // The carrier message is the newest thing the sender sent, so it sits at (or very near)
            // the top; walking back a bounded window from the top id is cheap and catches it.
            var currentId = topId.id
            var steps = 0
            while steps < 60 && currentId > 0 && found.count < 10 {
                let messageId = MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: currentId)
                if let message = transaction.getMessage(messageId),
                   message.flags.contains(.Incoming),
                   message.author?.id != account.peerId,
                   let token = reveal(message.text) {
                    found.append((messageId, token))
                }
                currentId -= 1
                steps += 1
            }
            return found
        }
        |> deliverOnMainQueue).start(next: { found in
            for (messageId, token) in found {
                handleIncomingCarrier(context: context, peerId: peerId, messageId: messageId, token: token)
            }
        })
    }

    /// Resolves the carried gift (fetching a unique gift's real art by slug, or decoding a generic
    /// gift), adds it to this account's own collection unless it's already there (deduped by the
    /// deterministic id derived from the carrier message), and returns the resolved gift so the
    /// caller can build a received-gift card. Returns nil if the gift could not be resolved.
    private static func materializeGift(account: Account, token: String, fromPeerId: EnginePeer.Id, sourceMessageId: MessageId) -> Signal<StarGift?, NoError> {
        guard let payload = decodePayload(token: token) else {
            return .single(nil)
        }
        let giftId = deterministicGiftId(for: sourceMessageId)
        let price = CurrencyAmount(amount: StarsAmount(value: payload.priceAmount, nanos: 0), currency: payload.priceStars ? .stars : .ton)

        let giftSignal: Signal<StarGift?, NoError>
        if let slug = payload.slug {
            giftSignal = TelegramEngine(account: account).payments.getUniqueStarGift(slug: slug)
            |> map { uniqueGift -> StarGift? in
                return .unique(uniqueGift)
            }
            |> `catch` { _ -> Signal<StarGift?, NoError> in
                return .single(nil)
            }
        } else if let genericGiftId = payload.genericGiftId {
            // Resolve a generic catalog gift from the recipient's own cached star-gift catalog by id,
            // so only the tiny id had to travel.
            giftSignal = TelegramEngine(account: account).payments.cachedStarGifts()
            |> take(1)
            |> map { gifts -> StarGift? in
                guard let gifts else {
                    return nil
                }
                for candidate in gifts {
                    if case let .generic(genericGift) = candidate, genericGift.id == genericGiftId {
                        return .generic(genericGift)
                    }
                }
                return nil
            }
        } else {
            giftSignal = .single(nil)
        }

        return giftSignal
        |> mapToSignal { starGift -> Signal<StarGift?, NoError> in
            guard let starGift else {
                return .single(nil)
            }
            return account.postbox.transaction { transaction -> StarGift? in
                // Durable dedup: the id is derived from the carrier message, so if this transfer
                // was already materialized (earlier this session, or before a relaunch) the gift
                // already exists and we don't add it again — but we still return it so the card is
                // shown once when the chat is opened.
                if !PampGramPhantomGiftStore.allGifts(transaction: transaction).contains(where: { $0.id == giftId }) {
                    let phantomGift = PampGramPhantomGift(
                        id: giftId,
                        peerId: account.peerId,
                        gift: starGift,
                        price: price,
                        date: Int32(Date().timeIntervalSince1970),
                        localMessageId: nil,
                        isReceived: true
                    )
                    PampGramPhantomGiftStore.add(transaction: transaction, gift: phantomGift)
                    PampGramLocalLedgerStore.add(transaction: transaction, operation: PampGramLocalOperation(
                        currency: price.currency == .stars ? .stars : .ton,
                        kind: .credit,
                        amount: 0,
                        title: "Получен подарок",
                        details: payload.title,
                        peerId: fromPeerId,
                        giftId: phantomGift.id,
                        balanceAfter: nil
                    ))
                }
                return starGift
            }
        }
    }

    /// Full recipient-side handling, run on chat open: materializes the gift, drops a proper
    /// "X передал(а) вам подарок" gift card into the chat (the same card a real received gift
    /// shows), and deletes the invisible carrier message for this user so only the card remains.
    /// Deleting the carrier also makes this idempotent — it's never scanned again.
    private static func handleIncomingCarrier(context: AccountContext, peerId: EnginePeer.Id, messageId: MessageId, token: String) {
        // Dedup within a session; the durable dedup is the deleted carrier below (a handled carrier
        // is never scanned again) plus the deterministic gift id. Crucially, a failed resolution
        // clears the mark so a later open retries — a transient failure never blocks it forever.
        processedLock.lock()
        if processedTransferMessageIds.contains(messageId) {
            processedLock.unlock()
            return
        }
        processedTransferMessageIds.insert(messageId)
        processedLock.unlock()

        let account = context.account
        let _ = (materializeGift(account: account, token: token, fromPeerId: peerId, sourceMessageId: messageId)
        |> deliverOnMainQueue).start(next: { starGift in
            guard let starGift else {
                processedLock.lock()
                processedTransferMessageIds.remove(messageId)
                processedLock.unlock()
                return
            }
            let cardSignal: Signal<EngineMessage.Id?, NoError>
            switch starGift {
            case let .unique(uniqueGift):
                cardSignal = PampGramPhantomGiftMessage.insertLocalUniqueGiftMessageFromPeer(context: context, peerId: peerId, uniqueGift: uniqueGift)
            case let .generic(genericGift):
                cardSignal = PampGramPhantomGiftMessage.insertLocalGenericGiftMessageFromPeer(context: context, peerId: peerId, gift: genericGift, text: nil, entities: nil)
            }
            let _ = cardSignal.start()
            let _ = context.engine.messages.deleteMessagesInteractively(messageIds: [messageId], type: .forLocalPeer).start()
        })
    }
}
