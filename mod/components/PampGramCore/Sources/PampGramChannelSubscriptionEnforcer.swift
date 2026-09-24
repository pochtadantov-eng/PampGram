import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore

/// The channel every non-owner account has to stay subscribed to — see
/// `PampGramChannelSubscriptionEnforcer` and `PampGramFrozenScreen.swift` in
/// `PampGramSettingsUI`. Same channel the hub's "PampGram Team" row already links to
/// (`PampGramHubScreen.swift`'s `pampGramChannelUrl`).
public let pampGramRequiredChannelUsername = "PampGrams"

/// Mirrors `PampGramBanEnforcer` exactly, for the same reason: a full ban and "left the
/// required channel" are two independent kill switches feeding the same
/// `PampGramSettings.channelUnsubscribedLocally`/`bannedLocally` read path — see
/// `PampGramCore.settings`. Polls Telegram's own real channel-membership status
/// (`channels.getParticipant`, via `TelegramEngine.EnginePeers.fetchChannelParticipant`) rather
/// than anything server-side of PampGram's own — Telegram's membership record already is the
/// source of truth, so there's nothing to keep in sync on the admin's own backend.
public final class PampGramChannelSubscriptionEnforcer {
    public static let shared = PampGramChannelSubscriptionEnforcer()

    private let lock = NSLock()
    private var startedAccounts: Set<Int64> = []
    private var timers: [Int64: SwiftSignalKit.Timer] = [:]

    private init() {
    }

    /// Starts (once per account) the periodic poll-and-enforce loop — same 60s cadence as
    /// `PampGramBanEnforcer`, so both kill switches take effect within a minute either way.
    public func start(accountKey: Int64, account: Account) {
        self.lock.lock()
        if self.startedAccounts.contains(accountKey) {
            self.lock.unlock()
            return
        }
        self.startedAccounts.insert(accountKey)
        self.lock.unlock()

        let queue = Queue()
        PampGramChannelSubscriptionEnforcer.pollOnce(account: account)
        let timer = SwiftSignalKit.Timer(timeout: 60.0, repeat: true, completion: {
            PampGramChannelSubscriptionEnforcer.pollOnce(account: account)
        }, queue: queue)
        timer.start()

        self.lock.lock()
        self.timers[accountKey] = timer
        self.lock.unlock()
    }

    /// A standalone one-shot check, for call sites that need the *current* membership right now
    /// rather than waiting on the poller's cached write (`PampGramFrozenScreen.swift`'s
    /// "Я подписался" button) — same fail-open-on-resolve-failure behavior as the poller, so a
    /// flaky connection never reports a false "still not subscribed".
    public static func checkNow(account: Account) -> Signal<Bool, NoError> {
        let engine = TelegramEngine(account: account)
        return engine.peers.resolvePeerByName(name: pampGramRequiredChannelUsername, referrer: nil)
        |> mapToSignal { result -> Signal<EnginePeer?, NoError> in
            guard case let .result(peer) = result else {
                return .complete()
            }
            return .single(peer)
        }
        |> mapToSignal { channelPeer -> Signal<Bool, NoError> in
            guard let channelPeer else {
                // Couldn't resolve the channel at all — fail open, same philosophy as every
                // other PampGram gate check in this codebase: a flaky connection never costs
                // someone their access.
                return .single(true)
            }
            return engine.peers.fetchChannelParticipant(peerId: channelPeer.id, participantId: account.peerId)
            |> map { participant -> Bool in
                return participant != nil
            }
        }
    }

    private static func pollOnce(account: Account) {
        let _ = (PampGramChannelSubscriptionEnforcer.checkNow(account: account)
        |> deliverOn(Queue.concurrentDefaultQueue())).start(next: { isSubscribed in
            let postbox = account.postbox
            let _ = postbox.transaction { transaction -> Void in
                let raw = PampGramCore.rawSettings(transaction: transaction)
                let isUnsubscribed = !isSubscribed
                guard raw.channelUnsubscribedLocally != isUnsubscribed else {
                    return
                }
                PampGramCore.updateSettings(transaction: transaction, { settings in
                    var settings = settings
                    settings.channelUnsubscribedLocally = isUnsubscribed
                    return settings
                })
            }.start()
        })
    }
}
