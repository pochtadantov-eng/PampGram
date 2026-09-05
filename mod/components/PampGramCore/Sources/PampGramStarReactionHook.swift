import Foundation
import Postbox
import SwiftSignalKit

/// The outcome of routing a paid-reaction ("отправить N звёзд") action on a channel post
/// through the fake-Stars ledger. Returned to the UI call site so it can decide what to do
/// without needing to know anything about PampGram's storage layout.
public enum PampGramStarReactionOutcome: Equatable {
    /// The gate is off — "Локальные звёзды" in the Подарки section (`fakeStarsDisplayEnabled`,
    /// possibly forced off by the master "Включить визуалку" switch) is what decides this,
    /// so a paid reaction hits fake or real Stars but never both. The caller should fall
    /// through to Telegram's real `sendStarsReaction` path unchanged.
    case notApplicable
    /// The fake Stars balance is smaller than the requested count. Nothing was debited,
    /// nothing was written to the ledger, and no reaction chip was bumped. The caller
    /// should NOT send the real reaction — the fake balance is what the user sees on the
    /// picker, so silently sending real Stars would be worse than showing no send at all.
    case insufficientFunds(currentBalance: Int64)
    /// The count was debited from `fakeStarsBalance`, appended to the local ledger, AND
    /// added to the fake star-reactions store for (peerId, messageId). The caller should
    /// NOT send anything to Telegram.
    case handled(balanceAfter: Int64, postTotalAfter: Int64)
}

/// Routes the "отправить звёзды на пост" gesture through PampGram's fake-Stars ledger
/// instead of Telegram's real paid-reactions API. Purely local: the debit only touches
/// `fakeStarsBalance`, the ledger row only shows up in this device's own Stars history
/// screen, and nothing here ever talks to `account.network` — no reaction is sent, no real
/// Stars are moved, no other user learns anything.
///
/// Lives in `PampGramCore` (not `PhantomGiftKit`) on purpose: `PampGramCore` is a low-level
/// module already depended on by `AccountContext`/`TelegramUI` in the patch, so the
/// paid-reaction send call sites can invoke this without any new module dependency.
public enum PampGramStarReactionHook {
    /// Debits `count` fake Stars for a paid reaction on `messageId` in `peerId`, in a single
    /// Postbox transaction that also appends the matching `.purchase` row to the local
    /// ledger and increments the on-post fake-reaction counter.
    ///
    /// `channelTitle` is the display name of the channel resolved by the caller from its
    /// own already-loaded peer view and shows up in this device's own history row only.
    /// Empty is fine — the ledger falls back to a generic "Реакция на пост".
    public static func spend(postbox: Postbox, peerId: PeerId, messageId: Int32, count: Int64, channelTitle: String) -> Signal<PampGramStarReactionOutcome, NoError> {
        // Count is what the user tapped on the reaction picker — the picker itself never
        // offers a value ≤ 0, but treating "0 or less" as a no-op keeps the hook safe under
        // future patch-site changes and matches how the real paid-reaction API rejects it.
        guard count > 0 else {
            return .single(.notApplicable)
        }
        return postbox.transaction { transaction -> PampGramStarReactionOutcome in
            // The paid-reaction path is gated by exactly the same switch as the fake Stars
            // balance display in the Подарки section (`fakeStarsDisplayEnabled`), so a tap
            // on ⭐ either always spends fake or always spends real — never a mix. `settings`
            // (not `rawSettings`) is read on purpose: when the master "Включить визуалку"
            // gate is off, every gift-visual feature — this one included, via
            // `withGiftsVisualsOff()` — reports as disabled, so the caller falls straight
            // through to Telegram's real paid-reaction API.
            let settings = PampGramCore.settings(transaction: transaction)
            guard settings.fakeStarsDisplayEnabled else {
                return .notApplicable
            }
            if settings.fakeStarsBalance < count {
                return .insufficientFunds(currentBalance: settings.fakeStarsBalance)
            }

            let details: String
            let trimmed = channelTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                details = "Реакция на пост в \(trimmed)"
            } else {
                details = "Реакция на пост"
            }

            // Debit + ledger row + reaction store all live in this one transaction so an
            // observer can never see two of the three updated without the third: the Stars
            // history screen, the top-right balance number, and the chip on the post all
            // move together, or none of them do.
            PampGramLocalLedgerStore.addAndApply(
                transaction: transaction,
                currency: .stars,
                kind: .purchase,
                amount: -count,
                title: "Звёзды на посте",
                details: details,
                peerId: peerId,
                giftId: Int64(messageId)
            )
            let postTotalAfter = PampGramStarReactionStore.increment(
                transaction: transaction,
                peerId: peerId,
                messageId: messageId,
                count: count
            )
            let balanceAfter = PampGramCore.settings(transaction: transaction).fakeStarsBalance
            return .handled(balanceAfter: balanceAfter, postTotalAfter: postTotalAfter)
        }
    }
}
