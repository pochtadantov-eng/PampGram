import Foundation
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import PampGramCore

/// Compact wire format for one real Telegram Stars/TON transaction pushed to `/sync-real-ledger`.
private struct PampGramRealTxWire: Codable {
    let id: String
    let currency: String
    let amount: Int64
    let date: Int32
    let title: String
    let description: String
    let peer: String
    let giftTitle: String
    let flags: [String]
}

private struct PampGramRealLedgerWire: Codable {
    let starsBalance: Int64
    let tonBalanceNanos: Int64
    let updatedAt: Int64
    let transactions: [PampGramRealTxWire]
}

/// Periodically reads this account's real Telegram Stars/TON history via
/// `payments.getStarsTransactions` (through `StarsTransactionsContext`) and pushes a summary
/// to the PampGram server so the admin card can show where they actually spent Stars — not
/// the local fake ledger.
///
/// Important: Telegram's `StarsTransactionsContext.loadMore` leaves `isLoading = true` forever
/// when the RPC errors (no error handler). Without a timeout that would stall the first sync
/// and permanently skip every later attempt via `inFlight`.
public final class PampGramRealStarsSyncRuntime {
    public static let shared = PampGramRealStarsSyncRuntime()

    private static let pollIntervalSeconds: Double = 60.0
    private static let collectTimeoutSeconds: Double = 25.0
    private static let maxPages = 4

    private let lock = NSLock()
    private var startedAccounts: Set<Int64> = []
    private var timers: [Int64: SwiftSignalKit.Timer] = [:]
    private var inFlight: Set<Int64> = []
    private var syncGeneration: [Int64: Int] = [:]

    private init() {
    }

    public func start(accountKey: Int64, context: AccountContext) {
        self.lock.lock()
        if self.startedAccounts.contains(accountKey) {
            self.lock.unlock()
            // Already running — still poke an immediate sync (e.g. after gift send).
            self.syncNow(accountKey: accountKey, context: context)
            return
        }
        self.startedAccounts.insert(accountKey)
        self.lock.unlock()

        self.syncNow(accountKey: accountKey, context: context)
        let queue = Queue.mainQueue()
        let timer = SwiftSignalKit.Timer(timeout: PampGramRealStarsSyncRuntime.pollIntervalSeconds, repeat: true, completion: { [weak self] in
            self?.syncNow(accountKey: accountKey, context: context)
        }, queue: queue)
        self.lock.lock()
        self.timers[accountKey] = timer
        self.lock.unlock()
        timer.start()
    }

    /// Public poke so UI / other runtimes can force a push without waiting for the timer.
    public func syncNow(accountKey: Int64, context: AccountContext) {
        self.lock.lock()
        if self.inFlight.contains(accountKey) {
            self.lock.unlock()
            return
        }
        self.inFlight.insert(accountKey)
        let generation = (self.syncGeneration[accountKey] ?? 0) + 1
        self.syncGeneration[accountKey] = generation
        self.lock.unlock()

        let peerId = context.account.peerId
        let starsCtx = context.engine.payments.peerStarsTransactionsContext(subject: .peer(peerId: peerId, ton: false), mode: .all)
        let tonCtx = context.engine.payments.peerStarsTransactionsContext(subject: .peer(peerId: peerId, ton: true), mode: .all)

        let starsSignal = self.collect(context: starsCtx)
        let tonSignal = self.collect(context: tonCtx)
        let starsBalanceSignal: Signal<StarsAmount?, NoError>
        if let starsContext = context.starsContext {
            starsBalanceSignal = starsContext.state |> map { $0?.balance } |> take(1)
        } else {
            starsBalanceSignal = .single(nil)
        }
        let tonBalanceSignal: Signal<StarsAmount?, NoError>
        if let tonContext = context.tonContext {
            tonBalanceSignal = tonContext.state |> map { $0?.balance } |> take(1)
        } else {
            tonBalanceSignal = .single(nil)
        }

        let _ = (combineLatest(starsSignal, tonSignal, starsBalanceSignal, tonBalanceSignal)
        |> take(1)
        |> deliverOnMainQueue).start(next: { [weak self] starsTx, tonTx, starsBalance, tonBalance in
            guard let self else {
                return
            }
            self.lock.lock()
            let stillCurrent = self.syncGeneration[accountKey] == generation
            self.inFlight.remove(accountKey)
            self.lock.unlock()
            guard stillCurrent else {
                return
            }

            var wires: [PampGramRealTxWire] = []
            wires.append(contentsOf: starsTx.map { Self.wire(from: $0, currency: "stars") })
            wires.append(contentsOf: tonTx.map { Self.wire(from: $0, currency: "ton") })
            wires.sort { lhs, rhs in
                if lhs.date != rhs.date {
                    return lhs.date > rhs.date
                }
                return lhs.id > rhs.id
            }
            if wires.count > 400 {
                wires = Array(wires.prefix(400))
            }

            let payload = PampGramRealLedgerWire(
                starsBalance: starsBalance?.value ?? 0,
                tonBalanceNanos: tonBalance?.value ?? 0,
                updatedAt: Int64(Date().timeIntervalSince1970 * 1000.0),
                transactions: wires
            )
            guard let data = try? JSONEncoder().encode(payload) else {
                return
            }
            // Push even an empty transaction list so the admin card leaves the
            // "client hasn't synced yet" empty state and shows "updated at".
            PampGramSubscriptionAPI.syncRealLedger(id: accountKey, payload: data, completion: { _ in })
        })

        // Hard ceiling: if collect/balance hang (RPC error leaves isLoading stuck), free inFlight
        // so the next timer tick can retry.
        let watchdog = SwiftSignalKit.Timer(timeout: PampGramRealStarsSyncRuntime.collectTimeoutSeconds + 10.0, repeat: false, completion: { [weak self] in
            guard let self else {
                return
            }
            self.lock.lock()
            if self.syncGeneration[accountKey] == generation {
                self.inFlight.remove(accountKey)
            }
            self.lock.unlock()
        }, queue: Queue.mainQueue())
        watchdog.start()
    }

    /// Loads up to `maxPages` pages, or whatever is available before `collectTimeoutSeconds`.
    private func collect(context: StarsTransactionsContext) -> Signal<[StarsContext.State.Transaction], NoError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            var pages = 0
            var lastCount = -1
            var finished = false

            let finish: ([StarsContext.State.Transaction]) -> Void = { transactions in
                if finished {
                    return
                }
                finished = true
                subscriber.putNext(transactions)
                subscriber.putCompletion()
            }

            let timeout = SwiftSignalKit.Timer(timeout: PampGramRealStarsSyncRuntime.collectTimeoutSeconds, repeat: false, completion: {
                let fallback = context.currentState?.transactions ?? []
                finish(fallback)
            }, queue: Queue.mainQueue())
            timeout.start()

            // Defer reload until after we subscribe, so we don't miss the loading→loaded transition.
            disposable.set((context.state
            |> deliverOnMainQueue).start(next: { state in
                if finished {
                    return
                }
                if state.isLoading {
                    return
                }
                let count = state.transactions.count
                if state.canLoadMore && pages < PampGramRealStarsSyncRuntime.maxPages && count != lastCount {
                    lastCount = count
                    pages += 1
                    context.loadMore()
                    return
                }
                timeout.invalidate()
                finish(state.transactions)
            }))

            context.reload()

            return ActionDisposable {
                timeout.invalidate()
                disposable.dispose()
            }
        }
    }

    private static func wire(from tx: StarsContext.State.Transaction, currency: String) -> PampGramRealTxWire {
        var flags: [String] = []
        if tx.flags.contains(.isRefund) { flags.append("refund") }
        if tx.flags.contains(.isPending) { flags.append("pending") }
        if tx.flags.contains(.isFailed) { flags.append("failed") }
        if tx.flags.contains(.isGift) { flags.append("gift") }
        if tx.flags.contains(.isReaction) { flags.append("reaction") }
        if tx.flags.contains(.isStarGiftUpgrade) { flags.append("gift_upgrade") }
        if tx.flags.contains(.isPaidMessage) { flags.append("paid_message") }
        if tx.flags.contains(.isBusinessTransfer) { flags.append("business_transfer") }
        if tx.flags.contains(.isStarGiftResale) { flags.append("gift_resale") }
        if tx.flags.contains(.isPostsSearch) { flags.append("posts_search") }
        if tx.flags.contains(.isStarGiftPrepaidUpgrade) { flags.append("gift_prepaid_upgrade") }
        if tx.flags.contains(.isStarGiftDropOriginalDetails) { flags.append("gift_drop_details") }
        if tx.flags.contains(.isStarGiftAuctionBid) { flags.append("gift_auction") }
        if tx.flags.contains(.isLiveStreamPaidMessage) { flags.append("livestream_paid") }
        if tx.flags.contains(.isStarGiftOffer) { flags.append("gift_offer") }

        let giftTitle: String
        if let starGift = tx.starGift {
            switch starGift {
            case let .generic(gift):
                giftTitle = gift.title ?? ""
            case let .unique(gift):
                giftTitle = gift.title
            }
        } else {
            giftTitle = ""
        }

        let amount: Int64
        switch tx.count.currency {
        case .stars:
            amount = tx.count.amount.value
        case .ton:
            amount = tx.count.amount.value
        }

        return PampGramRealTxWire(
            id: tx.id,
            currency: currency,
            amount: amount,
            date: tx.date,
            title: tx.title ?? "",
            description: tx.description ?? "",
            peer: Self.peerLabel(tx.peer),
            giftTitle: giftTitle,
            flags: flags
        )
    }

    private static func peerLabel(_ peer: StarsContext.State.Transaction.Peer) -> String {
        switch peer {
        case .appStore:
            return "App Store"
        case .playMarket:
            return "Play Market"
        case .fragment:
            return "Fragment"
        case .premiumBot:
            return "Premium Bot"
        case .ads:
            return "Ads"
        case .apiLimitExtension:
            return "API limit"
        case .unsupported:
            return "—"
        case let .peer(enginePeer):
            if let name = enginePeer.addressName, !name.isEmpty {
                return "@\(name)"
            }
            return enginePeer.compactDisplayTitle
        }
    }
}
