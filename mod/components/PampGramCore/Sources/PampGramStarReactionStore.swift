import Foundation
import Postbox
import SwiftSignalKit

/// One accumulated fake star-reaction record: for a given (channel, post) pair, how many
/// stars this device has virtually placed and when the last tap happened. Deliberately
/// device-local — never sent to the channel, never synced to other devices, never seen by
/// anyone else on the post. Tapping the star chip again on the same post just increments
/// `count` in place rather than adding a new row.
public struct PampGramStarReactionRecord: Codable, Equatable {
    public let peerId: PeerId
    public let messageId: Int32
    public var count: Int64
    public var updatedAt: Int32

    public init(peerId: PeerId, messageId: Int32, count: Int64, updatedAt: Int32) {
        self.peerId = peerId
        self.messageId = messageId
        self.count = count
        self.updatedAt = updatedAt
    }
}

private struct PampGramStarReactionList: Codable {
    var records: [PampGramStarReactionRecord]
}

/// Persistent, entirely local storage for PampGram's fake star reactions on channel posts.
/// Backed by Postbox's own `PreferencesEntry` mechanism under the mod's reserved key range,
/// same pattern as `PampGramDeletedMessageStore` / `PampGramLocalLedgerStore` — survives
/// app restarts for free, never touches `account.network`. The paid-reactions send hook
/// (see `PampGramStarReactionHook`) writes here in the same Postbox transaction that
/// debits `fakeStarsBalance` and appends the ledger row, so the reaction chip on the post,
/// the balance, and the Stars history can never diverge.
public enum PampGramStarReactionStore {
    public static func all(transaction: Transaction) -> [PampGramStarReactionRecord] {
        return transaction.getPreferencesEntry(key: PampGramPreferencesKeys.starReactions)?.get(PampGramStarReactionList.self)?.records ?? []
    }

    /// Cumulative fake stars this device has virtually placed on `messageId` in `peerId`.
    /// Zero when no record exists yet — no allocation, no autovivification.
    public static func count(transaction: Transaction, peerId: PeerId, messageId: Int32) -> Int64 {
        return self.all(transaction: transaction).first(where: { $0.peerId == peerId && $0.messageId == messageId })?.count ?? 0
    }

    /// Adds `count` to the record for (peerId, messageId), creating one if needed, and
    /// returns the new cumulative total. `count` is expected to be > 0 — negative or zero
    /// values are treated as a no-op and return the current stored total unchanged, so
    /// the caller can pass through user-picked values without a pre-check.
    @discardableResult
    public static func increment(transaction: Transaction, peerId: PeerId, messageId: Int32, count: Int64) -> Int64 {
        var newTotal: Int64 = self.count(transaction: transaction, peerId: peerId, messageId: messageId)
        guard count > 0 else {
            return newTotal
        }
        let now = Int32(Date().timeIntervalSince1970)
        transaction.updatePreferencesEntry(key: PampGramPreferencesKeys.starReactions, { entry in
            var list = entry?.get(PampGramStarReactionList.self) ?? PampGramStarReactionList(records: [])
            if let index = list.records.firstIndex(where: { $0.peerId == peerId && $0.messageId == messageId }) {
                list.records[index].count += count
                list.records[index].updatedAt = now
                newTotal = list.records[index].count
            } else {
                newTotal = count
                list.records.append(PampGramStarReactionRecord(peerId: peerId, messageId: messageId, count: count, updatedAt: now))
            }
            return PreferencesEntry(list)
        })
        return newTotal
    }

    /// Removes the record for (peerId, messageId), if any. Used by the "Clear PampGram
    /// reactions on this post" context-menu action; the debited stars are NOT refunded to
    /// the fake balance, matching how a real paid reaction cannot be un-paid.
    public static func remove(transaction: Transaction, peerId: PeerId, messageId: Int32) {
        transaction.updatePreferencesEntry(key: PampGramPreferencesKeys.starReactions, { entry in
            var list = entry?.get(PampGramStarReactionList.self) ?? PampGramStarReactionList(records: [])
            list.records.removeAll(where: { $0.peerId == peerId && $0.messageId == messageId })
            return PreferencesEntry(list)
        })
    }

    /// Live signal of every fake star-reaction record, sorted newest-first. The reactions
    /// UI subscribes to this to redraw the chip on every post it renders.
    public static func allSignal(postbox: Postbox) -> Signal<[PampGramStarReactionRecord], NoError> {
        return postbox.preferencesView(keys: [PampGramPreferencesKeys.starReactions])
        |> map { view -> [PampGramStarReactionRecord] in
            let records = view.values[PampGramPreferencesKeys.starReactions]?.get(PampGramStarReactionList.self)?.records ?? []
            return records.sorted(by: { $0.updatedAt > $1.updatedAt })
        }
    }

    /// Live signal of just this one post's cumulative fake-star count, distinct-until-changed
    /// so the chip only redraws when the number actually moves. Zero for posts that have
    /// never received a fake tap.
    public static func countSignal(postbox: Postbox, peerId: PeerId, messageId: Int32) -> Signal<Int64, NoError> {
        return postbox.preferencesView(keys: [PampGramPreferencesKeys.starReactions])
        |> map { view -> Int64 in
            let records = view.values[PampGramPreferencesKeys.starReactions]?.get(PampGramStarReactionList.self)?.records ?? []
            return records.first(where: { $0.peerId == peerId && $0.messageId == messageId })?.count ?? 0
        }
        |> distinctUntilChanged
    }
}
