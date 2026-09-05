import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import AccountContext
import PampGramCore

/// The outcome of routing a paid-reaction ("отправить N звёзд") action on a channel post
/// through the fake-stars ledger. Returned to the tg-ios call site (the patch hunk that
/// wraps `sendStarsReaction` / `MessageReaction.Reaction.stars`) so it can decide what to
/// do without needing to know anything about PampGram's storage layout.
public enum PampGramStarReactionOutcome: Equatable {
    /// The gate is off — "Фейковые звёзды" in the Подарки section (`fakeStarsDisplayEnabled`,
    /// possibly forced off by the master "Включить визуалку" switch) is what decides this,
    /// so a paid reaction hits fake or real Stars but never both. The caller should fall
    /// through to the real Telegram paid-reaction path unchanged.
    case notApplicable
    /// The fake Stars balance is smaller than the requested count. Nothing was debited,
    /// nothing was written to the ledger, and no reaction chip was bumped. The caller
    /// should NOT send the real reaction and should show a "недостаточно звёзд" state —
    /// the fake balance is what the user sees.
    case insufficientFunds(currentBalance: Int64)
    /// The count was debited from `fakeStarsBalance`, appended to the local ledger, AND
    /// added to the fake star-reactions store for (peerId, messageId) — so the chip on the
    /// post now shows `postTotalAfter` cumulative fake stars, and stays that way across
    /// restarts. The caller should NOT send anything to Telegram; the visual bump on the
    /// post comes from `PampGramStarReactionStore.countSignal` on the same message id.
    case handled(balanceAfter: Int64, postTotalAfter: Int64)
}

/// Routes the "отправить звёзды на пост" gesture through PampGram's fake-Stars ledger
/// instead of Telegram's real paid-reactions API. Purely local: the debit only touches
/// `fakeStarsBalance`, the ledger row only shows up in this device's own Stars history
/// screen, and nothing here ever talks to `account.network` — no reaction is sent, no real
/// Stars are moved, no other user learns anything.
///
/// The call site (a patch hunk in the tg-ios paid-reactions send path, added in a later
/// commit) passes the channel `peerId`, the post `messageId`, and a display title read
/// straight from the resolved channel peer — every field this file writes into the ledger
/// row is either that peer/message reference or PampGram's own local balance, so nothing
/// about the real post is fabricated in place.
public enum PampGramStarReactionHook {
    /// Debits `count` fake Stars for a paid reaction on `messageId` in `peerId`, in a single
    /// Postbox transaction that also appends the matching `.purchase` row to the local
    /// ledger. `channelTitle` is the display name of the channel (resolved by the caller from
    /// its own already-loaded peer view) and only ever shows up in this device's own history
    /// row — it is never sent anywhere.
    ///
    /// If the fake-star-reactions feature is off, or the master gifts-visual gate is off, the
    /// signal resolves to `.notApplicable` without touching the balance or the ledger. If the
    /// balance is smaller than `count`, it resolves to `.insufficientFunds` and, again, does
    /// not mutate anything.
    public static func spend(context: AccountContext, peerId: EnginePeer.Id, messageId: EngineMessage.Id, count: Int64, channelTitle: String) -> Signal<PampGramStarReactionOutcome, NoError> {
        // Count is what the user tapped on the reaction picker — the picker itself never
        // offers a value ≤ 0, but treating "0 or less" as a no-op keeps the hook safe under
        // future patch-site changes and matches how the real paid-reaction API rejects it.
        guard count > 0 else {
            return .single(.notApplicable)
        }
        return context.account.postbox.transaction { transaction -> PampGramStarReactionOutcome in
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
                giftId: Int64(messageId.id)
            )
            let postTotalAfter = PampGramStarReactionStore.increment(
                transaction: transaction,
                peerId: peerId,
                messageId: messageId.id,
                count: count
            )
            let balanceAfter = PampGramCore.settings(transaction: transaction).fakeStarsBalance
            return .handled(balanceAfter: balanceAfter, postTotalAfter: postTotalAfter)
        }
    }
}
