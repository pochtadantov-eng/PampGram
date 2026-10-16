import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import AccountContext
import PampGramCore

/// A visual Premium gift that is still in force: `peerId` shows Telegram's Premium star next to
/// their name until `expiry`. `originalWasPremium` is what the peer record said when the first gift
/// landed, so letting the gift lapse puts back exactly that (a person who really has Premium keeps it).
private struct PampGramLocalPremiumRecord: Codable, Equatable {
    var peerId: EnginePeer.Id
    var expiry: Int32
    var originalWasPremium: Bool
}

private struct PampGramLocalPremiumList: Codable {
    var records: [PampGramLocalPremiumRecord]
}

/// Makes the visual Premium gift ("Подарок ему" on the Premium tile) do what the real one does to the
/// recipient: the standard Premium star appears next to their name everywhere Telegram draws it —
/// chat list, chat header, profile — right away.
///
/// Local-only, like every other PampGram visual: the flag is written onto this device's copy of the
/// person's record, never sent anywhere. Telegram overwrites that record whenever it re-syncs the
/// user, so this is a reconcile loop (same idea as `PampGramWornGiftRuntime`) rather than a one-shot
/// write: any change to one of those records, or to the list itself, re-checks the flag and only
/// writes when it is missing.
public final class PampGramLocalPremiumRuntime {
    public static let shared = PampGramLocalPremiumRuntime()

    private let lock = NSLock()
    private var startedAccounts: Set<Int64> = []
    private var disposables: [Int64: Disposable] = [:]

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

        let postbox = context.account.postbox
        let records = postbox.preferencesView(keys: [PampGramPreferencesKeys.localPremiumPeers])
        |> map { view -> [PampGramLocalPremiumRecord] in
            return view.values[PampGramPreferencesKeys.localPremiumPeers]?.get(PampGramLocalPremiumList.self)?.records ?? []
        }
        |> distinctUntilChanged

        // For every peer on the list, re-run the reconcile whenever the peer's own record changes.
        // `mapToQueue` so a second trigger waits for the first instead of cancelling it half-way.
        let disposable = (records
        |> mapToSignal { records -> Signal<Void, NoError> in
            if records.isEmpty {
                return .single(Void())
            }
            let flags: [Signal<Bool, NoError>] = records.map { record in
                return postbox.peerView(id: record.peerId)
                |> map { view -> Bool in
                    return (view.peers[record.peerId] as? TelegramUser)?.flags.contains(.isPremium) ?? false
                }
                |> distinctUntilChanged
            }
            return combineLatest(queue: Queue.mainQueue(), flags)
            |> map { _ -> Void in
                return Void()
            }
        }
        |> mapToQueue { _ -> Signal<Never, NoError> in
            return PampGramLocalPremiumRuntime.reconcile(postbox: postbox)
        }).start()

        self.lock.lock()
        self.disposables[accountKey] = disposable
        self.lock.unlock()
    }

    /// Adds `months` of visual Premium to `peerId` (stacking on a gift that is still running) and puts
    /// the star on their record right away. Call inside a Postbox transaction.
    public static func grant(transaction: Transaction, peerId: EnginePeer.Id, months: Int32) {
        let now = Int32(Date().timeIntervalSince1970)
        let user = transaction.getPeer(peerId) as? TelegramUser
        var list = transaction.getPreferencesEntry(key: PampGramPreferencesKeys.localPremiumPeers)?.get(PampGramLocalPremiumList.self) ?? PampGramLocalPremiumList(records: [])
        let duration = months * 30 * 24 * 60 * 60
        if let index = list.records.firstIndex(where: { $0.peerId == peerId }) {
            list.records[index].expiry = max(list.records[index].expiry, now) + duration
        } else {
            list.records.append(PampGramLocalPremiumRecord(peerId: peerId, expiry: now + duration, originalWasPremium: user?.flags.contains(.isPremium) ?? false))
        }
        transaction.setPreferencesEntry(key: PampGramPreferencesKeys.localPremiumPeers, value: PreferencesEntry(list))
        if let user, !user.flags.contains(.isPremium) {
            updatePeersCustom(transaction: transaction, peers: [user.withUpdatedFlags(user.flags.union(.isPremium))], update: { _, updated in
                return updated
            })
        }
    }

    private static func reconcile(postbox: Postbox) -> Signal<Never, NoError> {
        return postbox.transaction { transaction -> Void in
            guard var list = transaction.getPreferencesEntry(key: PampGramPreferencesKeys.localPremiumPeers)?.get(PampGramLocalPremiumList.self), !list.records.isEmpty else {
                return
            }
            let now = Int32(Date().timeIntervalSince1970)
            var remaining: [PampGramLocalPremiumRecord] = []
            for record in list.records {
                let user = transaction.getPeer(record.peerId) as? TelegramUser
                if record.expiry > now {
                    remaining.append(record)
                    if let user, !user.flags.contains(.isPremium) {
                        updatePeersCustom(transaction: transaction, peers: [user.withUpdatedFlags(user.flags.union(.isPremium))], update: { _, updated in
                            return updated
                        })
                    }
                } else if let user, !record.originalWasPremium, user.flags.contains(.isPremium) {
                    // The gift ran out: put back what the record said before it.
                    updatePeersCustom(transaction: transaction, peers: [user.withUpdatedFlags(user.flags.subtracting(.isPremium))], update: { _, updated in
                        return updated
                    })
                }
            }
            if remaining != list.records {
                list.records = remaining
                transaction.setPreferencesEntry(key: PampGramPreferencesKeys.localPremiumPeers, value: PreferencesEntry(list))
            }
        }
        |> ignoreValues
    }
}
