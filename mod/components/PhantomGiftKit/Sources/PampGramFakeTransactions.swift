import Foundation
import TelegramCore
import SwiftSignalKit
import AccountContext
import PampGramCore

/// Turns this device's Phantom Gifts into rows for the real Stars/TON transaction-history
/// screen. Deliberately never touches `StarsContext`/`StarsTransactionsContext` — merging
/// happens purely at the UI layer (see the patch to `StarsTransactionsListPanelComponent`),
/// so nothing here can perturb the real balance shown elsewhere in the app or get wiped by
/// a real reload of the real transaction list. Persistence, in turn, comes for free: these
/// rows are derived from the same Postbox-backed Phantom Gift store the profile grid reads,
/// so they survive app restarts and stay put even if the mod's display toggles are turned
/// off later — only the gift records themselves (never cleared by a toggle) decide what
/// shows here.
public extension PampGramPhantomGiftStore {
    /// - A credit for every gift "received" from someone (`isReceived`, the "Подарок мне"/
    ///   "От него" flow) — shows as a top-up, `peer` being whoever supposedly sent it.
    /// - A debit for every gift actually bought/sent (`!isReceived`).
    /// - A matching credit, same date, when a *sent* gift's `peerId` is this account's own —
    ///   sending a gift to yourself shows up both as the payment and as it "arriving".
    /// - A credit when a gift already in the profile was later sold (`soldDate != nil`),
    ///   whether it was originally bought or received.
    static func fakeTransactionsSignal(context: AccountContext, ton: Bool, mode: StarsTransactionsContext.Mode) -> Signal<[StarsContext.State.Transaction], NoError> {
        let currency: CurrencyAmount.Currency = ton ? .ton : .stars
        let ledgerCurrency: PampGramLocalCurrency = ton ? .ton : .stars
        let selfPeerId = context.account.peerId

        return combineLatest(self.allGiftsSignal(context: context), PampGramLocalLedgerStore.signal(postbox: context.account.postbox))
        |> mapToSignal { gifts, operations -> Signal<[StarsContext.State.Transaction], NoError> in
            let relevant = gifts.filter { $0.price.currency == currency }

            // Ledger rows with no matching gift record — e.g. Stars bought with the local
            // ruble card (PampGramStarsHook) — so a spend/top-up never goes missing from the
            // real Stars/TON history just because it didn't come from a gift purchase. Every
            // gift-derived row below carries a `giftId`, so filtering those out here never
            // duplicates one. `visibleInRealHistory == false` opts a row out of this real-feed
            // mirror entirely — used for raw balance overwrites (manual edit in Settings,
            // "Сбросить балансы") that never happened as an actual transaction anywhere, so
            // they'd otherwise show up here mislabeled as an App Store top-up. Those rows still
            // show in PampGram's own ledger screen, which reads straight from the store.
            let ledgerTransactions: [StarsContext.State.Transaction] = operations
                .filter { $0.currency == ledgerCurrency && $0.giftId == nil && $0.visibleInRealHistory != false }
                .map { operation in
                    self.fakeTransaction(
                        id: "pampgram_ledger_\(operation.id)",
                        flags: [],
                        amount: StarsAmount(value: operation.amount, nanos: 0),
                        currency: currency,
                        date: operation.date,
                        peer: .appStore,
                        title: operation.title,
                        starGift: nil
                    )
                }

            if relevant.isEmpty && ledgerTransactions.isEmpty {
                return .single([])
            }
            let peerIds = Array(Set(relevant.map { $0.peerId }))
            return context.engine.data.get(EngineDataMap(peerIds.map(TelegramEngine.EngineData.Item.Peer.Peer.init(id:))))
            |> map { result -> [StarsContext.State.Transaction] in
                var peers: [EnginePeer.Id: EnginePeer] = [:]
                for peerId in peerIds {
                    if let maybePeer = result[peerId], let peer = maybePeer {
                        peers[peerId] = peer
                    }
                }

                var transactions: [StarsContext.State.Transaction] = []
                for gift in relevant {
                    guard let peer = peers[gift.peerId] else {
                        continue
                    }

                    let isUnique: Bool
                    switch gift.gift {
                    case .unique:
                        isUnique = true
                    case .generic:
                        isUnique = false
                    }

                    if gift.isReceived {
                        transactions.append(self.fakeTransaction(
                            id: "pampgram_\(gift.id)_received",
                            flags: [.isGift],
                            amount: gift.price.amount,
                            currency: currency,
                            date: gift.date,
                            peer: .peer(peer),
                            title: gift.title,
                            starGift: gift.gift
                        ))
                    } else {
                        var debitFlags: StarsContext.State.Transaction.Flags = [.isGift]
                        if isUnique {
                            debitFlags.insert(.isStarGiftResale)
                        }
                        transactions.append(self.fakeTransaction(
                            id: "pampgram_\(gift.id)_debit",
                            flags: debitFlags,
                            amount: StarsAmount(value: -gift.price.amount.value, nanos: -gift.price.amount.nanos),
                            currency: currency,
                            date: gift.date,
                            peer: .peer(peer),
                            title: nil,
                            starGift: gift.gift
                        ))

                        if gift.peerId == selfPeerId {
                            transactions.append(self.fakeTransaction(
                                id: "pampgram_\(gift.id)_credit",
                                flags: [.isGift],
                                amount: gift.price.amount,
                                currency: currency,
                                date: gift.date,
                                peer: .peer(peer),
                                title: gift.title,
                                starGift: nil
                            ))
                        }
                    }

                    if let soldDate = gift.soldDate {
                        transactions.append(self.fakeTransaction(
                            id: "pampgram_\(gift.id)_sold",
                            flags: [.isStarGiftResale],
                            amount: gift.price.amount,
                            currency: currency,
                            date: soldDate,
                            peer: .peer(peer),
                            title: gift.title,
                            starGift: gift.gift
                        ))
                    }
                }

                transactions.append(contentsOf: ledgerTransactions)

                switch mode {
                case .all:
                    break
                case .incoming:
                    transactions.removeAll(where: { $0.count.amount <= StarsAmount.zero })
                case .outgoing:
                    transactions.removeAll(where: { $0.count.amount > StarsAmount.zero })
                }

                return transactions.sorted(by: { $0.date > $1.date })
            }
        }
    }

    private static func fakeTransaction(id: String, flags: StarsContext.State.Transaction.Flags, amount: StarsAmount, currency: CurrencyAmount.Currency, date: Int32, peer: StarsContext.State.Transaction.Peer, title: String?, starGift: StarGift?) -> StarsContext.State.Transaction {
        return StarsContext.State.Transaction(
            flags: flags,
            id: id,
            count: CurrencyAmount(amount: amount, currency: currency),
            date: date,
            peer: peer,
            title: title,
            description: nil,
            photo: nil,
            transactionDate: nil,
            transactionUrl: nil,
            paidMessageId: nil,
            giveawayMessageId: nil,
            media: [],
            subscriptionPeriod: nil,
            starGift: starGift,
            floodskipNumber: nil,
            starrefCommissionPermille: nil,
            starrefPeerId: nil,
            starrefAmount: nil,
            paidMessageCount: nil,
            premiumGiftMonths: nil,
            adsProceedsFromDate: nil,
            adsProceedsToDate: nil
        )
    }
}
