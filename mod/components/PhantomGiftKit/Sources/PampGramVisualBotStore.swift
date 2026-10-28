import Foundation
import Postbox
import SwiftSignalKit
import AccountContext
import PampGramCore

private struct PampGramVisualBotList: Codable {
    var bots: [PampGramVisualBot]
}

private struct PampGramVisualBotOperationList: Codable {
    var operations: [PampGramVisualBotOperation]
}

private struct PampGramVisualBotCheckList: Codable {
    var checks: [PampGramVisualBotCheck]
}

/// Outcome of a balance-moving call. Separates "the arithmetic succeeded and here is the row
/// it wrote" from "the arithmetic refused and nothing was persisted" without reaching for
/// throws — the single caller (settings/overlay UI) wants to render the error, not propagate
/// it, so a plain enum is cheaper and matches the pattern already used by the gift flow.
public enum PampGramVisualBotTransferResult: Equatable {
    case success(fromOperationId: Int64, toOperationId: Int64)
    case insufficientFunds
    case sameBot
    case unknownBot
}

public enum PampGramVisualBotCheckRedeemResult: Equatable {
    case success(operationId: Int64, botId: String, amount: Int64, currency: String)
    case alreadyRedeemed
    case unknownCode
    case targetBotDisabled
    case unknownTargetBot
}

/// Persistent store for every record the Visual Bots section owns — the bots themselves,
/// their operation history, and the pool of live visual checks. Same shape as
/// `PampGramPhantomGiftStore`: three `PreferencesEntry` blobs under reserved keys from
/// `PampGramPreferencesKeys`, one transaction-flavored read/write per operation, and matching
/// `Signal` views for live UI. Nothing in this file ever touches `account.network`.
///
/// Invariant: every change to a bot's balance goes through `apply(transaction:bot:kind:...)`
/// below. That one path adds the signed `minorUnits` to the bot, writes it back, appends a
/// `PampGramVisualBotOperation`, and (for check and transfer paths) does the paired write
/// atomically inside the same `Transaction`. UI code must not update `balances` by hand.
public enum PampGramVisualBotStore {
    // MARK: - Bots

    /// Every bot stored on this device, newest first by `createdDate`. Seeds the default pair
    /// (xRocket, Crypto Bot) the first time the device sees the store.
    public static func allBots(transaction: Transaction) -> [PampGramVisualBot] {
        let stored = transaction.getPreferencesEntry(key: PampGramPreferencesKeys.visualBots)?.get(PampGramVisualBotList.self)?.bots
        if let stored, !stored.isEmpty {
            return stored
        }
        let seed = PampGramVisualBot.defaultSeed(now: now())
        write(transaction: transaction, bots: seed)
        return seed
    }

    public static func bot(transaction: Transaction, id: String) -> PampGramVisualBot? {
        return allBots(transaction: transaction).first(where: { $0.id == id })
    }

    public static func bot(transaction: Transaction, username: String) -> PampGramVisualBot? {
        let lowered = username.lowercased()
        return allBots(transaction: transaction).first(where: { $0.username.lowercased() == lowered })
    }

    /// Writes `bot` back, matched by `id`. A no-op if `id` isn't found — the callers that need
    /// to add a brand-new bot go through `addBot` instead, which `apply` relies on.
    public static func updateBot(transaction: Transaction, _ bot: PampGramVisualBot) {
        transaction.updatePreferencesEntry(key: PampGramPreferencesKeys.visualBots, { entry in
            var list = entry?.get(PampGramVisualBotList.self) ?? PampGramVisualBotList(bots: [])
            if let index = list.bots.firstIndex(where: { $0.id == bot.id }) {
                list.bots[index] = bot
            }
            return PreferencesEntry(list)
        })
    }

    /// Appends a fresh bot. If `id` collides with an existing one the call is a no-op — rename
    /// the existing bot through `updateBot` instead of replacing it, so operation history
    /// doesn't accidentally re-point.
    public static func addBot(transaction: Transaction, _ bot: PampGramVisualBot) {
        transaction.updatePreferencesEntry(key: PampGramPreferencesKeys.visualBots, { entry in
            var list = entry?.get(PampGramVisualBotList.self) ?? PampGramVisualBotList(bots: [])
            if !list.bots.contains(where: { $0.id == bot.id }) {
                list.bots.append(bot)
            }
            return PreferencesEntry(list)
        })
    }

    public static func setBotEnabled(transaction: Transaction, id: String, enabled: Bool) {
        transaction.updatePreferencesEntry(key: PampGramPreferencesKeys.visualBots, { entry in
            var list = entry?.get(PampGramVisualBotList.self) ?? PampGramVisualBotList(bots: [])
            if let index = list.bots.firstIndex(where: { $0.id == id }) {
                list.bots[index].enabled = enabled
            }
            return PreferencesEntry(list)
        })
    }

    private static func write(transaction: Transaction, bots: [PampGramVisualBot]) {
        transaction.setPreferencesEntry(key: PampGramPreferencesKeys.visualBots, value: PreferencesEntry(PampGramVisualBotList(bots: bots)))
    }

    // MARK: - Operations

    public static func allOperations(transaction: Transaction) -> [PampGramVisualBotOperation] {
        return transaction.getPreferencesEntry(key: PampGramPreferencesKeys.visualBotOperations)?.get(PampGramVisualBotOperationList.self)?.operations ?? []
    }

    public static func operations(transaction: Transaction, botId: String) -> [PampGramVisualBotOperation] {
        return allOperations(transaction: transaction).filter { $0.botId == botId }
    }

    // MARK: - Checks

    public static func allChecks(transaction: Transaction) -> [PampGramVisualBotCheck] {
        return transaction.getPreferencesEntry(key: PampGramPreferencesKeys.visualBotChecks)?.get(PampGramVisualBotCheckList.self)?.checks ?? []
    }

    public static func check(transaction: Transaction, code: String) -> PampGramVisualBotCheck? {
        let normalized = code.uppercased()
        return allChecks(transaction: transaction).first(where: { $0.code.uppercased() == normalized })
    }

    // MARK: - Balance mutation

    /// The one path every balance change goes through. Reads the bot, applies the signed
    /// `minorUnits` delta, writes the bot back, and appends an operation row — all inside the
    /// caller's `Transaction` so partial writes aren't possible even if the app is killed
    /// mid-call. Returns the appended operation's id so paired writes can be stitched
    /// together (`transferOut` / `transferIn`, `checkCreated` / `checkRedeemed`).
    ///
    /// Debits are refused rather than clamped: a negative resulting balance is almost always a
    /// bug in the caller, and silently zero-filling would mask it. The `onSuccess` closure is
    /// a hook for the check/transfer helpers to persist their paired record under the same
    /// transaction before the first `apply` returns.
    @discardableResult
    public static func apply(
        transaction: Transaction,
        botId: String,
        kind: PampGramVisualBotOperationKind,
        currency: String,
        minorUnits: Int64,
        counterpartBotId: String? = nil,
        checkCode: String? = nil,
        note: String? = nil
    ) -> Int64? {
        guard let bot = self.bot(transaction: transaction, id: botId) else {
            return nil
        }
        let newBalance = bot.balance(currency: currency) + minorUnits
        if newBalance < 0 {
            return nil
        }
        let updated = bot.settingBalance(currency: currency, minorUnits: newBalance)
        updateBot(transaction: transaction, updated)

        let operationId = nextOperationId(transaction: transaction)
        let operation = PampGramVisualBotOperation(
            id: operationId,
            botId: botId,
            kind: kind,
            currency: currency,
            minorUnits: minorUnits,
            date: now(),
            counterpartBotId: counterpartBotId,
            checkCode: checkCode,
            note: note
        )
        transaction.updatePreferencesEntry(key: PampGramPreferencesKeys.visualBotOperations, { entry in
            var list = entry?.get(PampGramVisualBotOperationList.self) ?? PampGramVisualBotOperationList(operations: [])
            list.operations.append(operation)
            return PreferencesEntry(list)
        })
        return operationId
    }

    /// Move `minorUnits` of `currency` from one visual bot to another, atomically. Both bots
    /// must exist; the source must have the funds; `fromBotId == toBotId` is refused because
    /// that call shape is almost always a UI bug and would just append two no-op rows.
    public static func transfer(
        transaction: Transaction,
        fromBotId: String,
        toBotId: String,
        currency: String,
        minorUnits: Int64,
        note: String? = nil
    ) -> PampGramVisualBotTransferResult {
        guard minorUnits > 0 else {
            return .insufficientFunds
        }
        if fromBotId == toBotId {
            return .sameBot
        }
        guard let fromBot = self.bot(transaction: transaction, id: fromBotId), let _ = self.bot(transaction: transaction, id: toBotId) else {
            return .unknownBot
        }
        if fromBot.balance(currency: currency) < minorUnits {
            return .insufficientFunds
        }
        guard let outId = apply(transaction: transaction, botId: fromBotId, kind: .transferOut, currency: currency, minorUnits: -minorUnits, counterpartBotId: toBotId, checkCode: nil, note: note) else {
            return .insufficientFunds
        }
        guard let inId = apply(transaction: transaction, botId: toBotId, kind: .transferIn, currency: currency, minorUnits: minorUnits, counterpartBotId: fromBotId, checkCode: nil, note: note) else {
            // Shouldn't happen — the target is a credit, which can't fail — but if it did we'd
            // have a split-brain pair of rows and no partial-rollback primitive to undo the
            // debit. Reversing it right here keeps the invariant honest.
            apply(transaction: transaction, botId: fromBotId, kind: .manual, currency: currency, minorUnits: minorUnits, note: "rollback transferOut \(outId)")
            return .unknownBot
        }
        return .success(fromOperationId: outId, toOperationId: inId)
    }

    /// Create a visual check against `botId`'s balance. Returns `nil` if `minorUnits <= 0`, the
    /// bot doesn't exist, or the bot can't cover the amount. The funds are parked on the
    /// returned check and can be released by `redeemCheck`.
    public static func createCheck(
        transaction: Transaction,
        botId: String,
        currency: String,
        minorUnits: Int64,
        comment: String? = nil
    ) -> PampGramVisualBotCheck? {
        guard minorUnits > 0 else {
            return nil
        }
        guard let bot = self.bot(transaction: transaction, id: botId) else {
            return nil
        }
        if bot.balance(currency: currency) < minorUnits {
            return nil
        }
        let code = generateCheckCode(kind: bot.kind)
        let check = PampGramVisualBotCheck(
            code: code,
            botId: botId,
            currency: currency,
            minorUnits: minorUnits,
            createdDate: now(),
            redeemedDate: nil,
            redeemedByBotId: nil,
            comment: comment
        )
        guard apply(transaction: transaction, botId: botId, kind: .checkCreated, currency: currency, minorUnits: -minorUnits, counterpartBotId: nil, checkCode: code, note: comment) != nil else {
            return nil
        }
        transaction.updatePreferencesEntry(key: PampGramPreferencesKeys.visualBotChecks, { entry in
            var list = entry?.get(PampGramVisualBotCheckList.self) ?? PampGramVisualBotCheckList(checks: [])
            list.checks.append(check)
            return PreferencesEntry(list)
        })
        return check
    }

    /// Redeem a live visual check into `targetBotId`. Marks the check as redeemed in place and
    /// credits the target bot. A check code is case-insensitive on input; it's uppercased for
    /// storage so string comparison is boring.
    public static func redeemCheck(
        transaction: Transaction,
        code: String,
        targetBotId: String
    ) -> PampGramVisualBotCheckRedeemResult {
        guard let existing = self.check(transaction: transaction, code: code) else {
            return .unknownCode
        }
        if existing.isRedeemed {
            return .alreadyRedeemed
        }
        guard let targetBot = self.bot(transaction: transaction, id: targetBotId) else {
            return .unknownTargetBot
        }
        if !targetBot.enabled {
            return .targetBotDisabled
        }
        guard let opId = apply(transaction: transaction, botId: targetBotId, kind: .checkRedeemed, currency: existing.currency, minorUnits: existing.minorUnits, counterpartBotId: existing.botId, checkCode: existing.code, note: existing.comment) else {
            return .unknownTargetBot
        }
        transaction.updatePreferencesEntry(key: PampGramPreferencesKeys.visualBotChecks, { entry in
            var list = entry?.get(PampGramVisualBotCheckList.self) ?? PampGramVisualBotCheckList(checks: [])
            if let index = list.checks.firstIndex(where: { $0.code.uppercased() == existing.code.uppercased() }) {
                list.checks[index].redeemedDate = now()
                list.checks[index].redeemedByBotId = targetBotId
            }
            return PreferencesEntry(list)
        })
        return .success(operationId: opId, botId: targetBotId, amount: existing.minorUnits, currency: existing.currency)
    }

    // MARK: - Signals

    public static func botsSignal(context: AccountContext) -> Signal<[PampGramVisualBot], NoError> {
        return context.account.postbox.preferencesView(keys: [PampGramPreferencesKeys.visualBots])
        |> map { view -> [PampGramVisualBot] in
            return view.values[PampGramPreferencesKeys.visualBots]?.get(PampGramVisualBotList.self)?.bots ?? []
        }
    }

    public static func operationsSignal(context: AccountContext, botId: String? = nil) -> Signal<[PampGramVisualBotOperation], NoError> {
        return context.account.postbox.preferencesView(keys: [PampGramPreferencesKeys.visualBotOperations])
        |> map { view -> [PampGramVisualBotOperation] in
            let all = view.values[PampGramPreferencesKeys.visualBotOperations]?.get(PampGramVisualBotOperationList.self)?.operations ?? []
            let filtered = botId.map { id in all.filter { $0.botId == id } } ?? all
            return filtered.sorted(by: { $0.date > $1.date })
        }
    }

    public static func checksSignal(context: AccountContext) -> Signal<[PampGramVisualBotCheck], NoError> {
        return context.account.postbox.preferencesView(keys: [PampGramPreferencesKeys.visualBotChecks])
        |> map { view -> [PampGramVisualBotCheck] in
            let checks = view.values[PampGramPreferencesKeys.visualBotChecks]?.get(PampGramVisualBotCheckList.self)?.checks ?? []
            return checks.sorted(by: { $0.createdDate > $1.createdDate })
        }
    }

    // MARK: - Helpers

    /// Monotonic Int64 id for the next operation. Scanning the current list and adding 1 is
    /// enough — the list grows slowly and only on this device, so there is no race.
    private static func nextOperationId(transaction: Transaction) -> Int64 {
        let maxId = allOperations(transaction: transaction).map { $0.id }.max() ?? 0
        return maxId + 1
    }

    private static func now() -> Int32 {
        return Int32(Date().timeIntervalSince1970)
    }

    /// Mimics the real invoice prefixes xRocket (`CQ…`) and Crypto Bot (`CR…`) use, so the
    /// generated `t.me/<bot>?start=<code>` link reads at a glance. Random suffix is 10 chars
    /// of base-32-ish alphabet (no 0/O/1/I) — ~2^50 states, which is plenty for a per-device
    /// store that typically holds a handful of live checks at a time.
    private static func generateCheckCode(kind: PampGramVisualBotKind) -> String {
        let prefix: String
        switch kind {
        case .xrocket:
            prefix = "CQ"
        case .cryptobot:
            prefix = "CR"
        }
        let alphabet: [Character] = Array("23456789ABCDEFGHJKLMNPQRSTUVWXYZ")
        var suffix = ""
        for _ in 0..<10 {
            suffix.append(alphabet.randomElement()!)
        }
        return prefix + suffix
    }
}
