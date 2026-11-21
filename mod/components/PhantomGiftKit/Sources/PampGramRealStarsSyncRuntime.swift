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
public final class PampGramRealStarsSyncRuntime {
    public static let shared = PampGramRealStarsSyncRuntime()

    private static let pollIntervalSeconds: Double = 5 * 60.0
    private static let maxPages = 4

    private let lock = NSLock()
    private var startedAccounts: Set<Int64> = []
    private var timers: [Int64: SwiftSignalKit.Timer] = [:]
    private var inFlight: Set<Int64> = []

    private init() {
    }

    public func start(accountKey: Int64, context: AccountContext) {
        self.lock.lock()
        if self.startedAccounts.contains(accountKey) {
            self.lock.unlock()
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

    private func syncNow(accountKey: Int64, context: AccountContext) {
        self.lock.lock()
        if self.inFlight.contains(accountKey) {
            self.lock.unlock()
            return
        }
        self.inFlight.insert(accountKey)
        self.lock.unlock()

        let peerId = context.account.peerId
        let starsCtx = context.engine.payments.peerStarsTransactionsContext(subject: .peer(peerId: peerId, ton: false), mode: .all)
        let tonCtx = context.engine.payments.peerStarsTransactionsContext(subject: .peer(peerId: peerId, ton: true), mode: .all)

        let starsSignal = self.collect(context: starsCtx)
        let tonSignal = self.collect(context: tonCtx)
        let starsBalanceSignal: Signal<StarsAmount?, NoError>
        if let starsContext = context.starsContext {
            starsBalanceSignal = starsContext.state |> map { Optional($0.balance) }
        } else {
            starsBalanceSignal = .single(nil)
        }
        let tonBalanceSignal: Signal<StarsAmount?, NoError>
        if let tonContext = context.tonContext {
            tonBalanceSignal = tonContext.state |> map { Optional($0.balance) }
        } else {
            tonBalanceSignal = .single(nil)
        }

        let _ = (combineLatest(starsSignal, tonSignal, starsBalanceSignal, tonBalanceSignal)
        |> take(1)
        |> deliverOnMainQueue).start(next: { [weak self] starsTx, tonTx, starsBalance, tonBalance in
            defer {
                self?.lock.lock()
                self?.inFlight.remove(accountKey)
                self?.lock.unlock()
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
            PampGramSubscriptionAPI.syncRealLedger(id: accountKey, payload: data, completion: { _ in })
        })
    }

    /// Loads up to `maxPages` pages from a transactions context.
    private func collect(context: StarsTransactionsContext) -> Signal<[StarsContext.State.Transaction], NoError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            var pages = 0
            var lastCount = -1

            let pump: () -> Void = {
                context.reload()
            }
            pump()

            disposable.set((context.state
            |> deliverOnMainQueue).start(next: { state in
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
                subscriber.putNext(state.transactions)
                subscriber.putCompletion()
            }))

            return disposable
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
