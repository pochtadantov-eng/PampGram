import Foundation

/// Which real bot a `PampGramVisualBot` locally imitates — chosen at creation and never
/// changed. The raw value doubles as the stable key stored in `balances`/`operations` keyed
/// records, so adding a new case here is additive and old records keep decoding.
public enum PampGramVisualBotKind: String {
    /// `@xrocket`.
    case xrocket
    /// `@CryptoBot` / `@send`.
    case cryptobot
}

/// See `PampGramVoicePreset`'s matching extension for why this can't use the compiler's
/// default raw-value Codable synthesis (Postbox's own coder rejects single-value containers).
extension PampGramVisualBotKind: Codable {
    private enum CodingKeys: String, CodingKey {
        case value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(String.self, forKey: .value)
        self = PampGramVisualBotKind(rawValue: raw) ?? .xrocket
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.rawValue, forKey: .value)
    }
}

/// A single currency slot inside a visual bot's wallet. Amounts are stored as integer
/// "minor units" (the currency's smallest whole unit — satoshis for BTC, nanotons for TON,
/// 10^-6 USD for USDT, etc.) so arithmetic — most of all the add/subtract pair that moves
/// money between two bots — stays exact and never collects floating-point rounding error.
/// Formatting back to a human-readable number is a UI concern; the store never does it.
public struct PampGramVisualBotBalance: Codable, Equatable {
    /// Uppercase currency code, e.g. `"USDT"`, `"TON"`, `"BTC"`, `"ETH"`. Treated as an opaque
    /// key by the store — a bot can hold any set of currencies, and new codes are added just
    /// by writing a balance with a new string.
    public var currency: String
    /// How many of this currency's smallest whole units the wallet holds. Non-negative in
    /// steady state; a transient negative is a bug and `debit` refuses to produce one.
    public var minorUnits: Int64

    public init(currency: String, minorUnits: Int64) {
        self.currency = currency
        self.minorUnits = minorUnits
    }
}

/// One visual bot entry — exactly one row per real username the user has turned on. The
/// `id` is the primary key for every other table (`PampGramVisualBotOperation.botId`,
/// `PampGramVisualBotCheck.botId`, …) and never changes once the bot is created; `username`
/// and `displayName` are UI copy that may be renamed without rewriting history.
public struct PampGramVisualBot: Codable, Equatable {
    /// Stable primary key, usually equal to `kind.rawValue` for the two seeded bots. A user who
    /// later toggles a bot off and back on gets the same id, so operation history stays joined.
    public var id: String
    public var kind: PampGramVisualBotKind
    /// Telegram username **without** the leading `@`. Case-insensitive match: the chat overlay
    /// resolves peers by `username.lowercased()`.
    public var username: String
    /// What the overlay prints in the header and in operation rows ("xRocket", "Crypto Bot").
    public var displayName: String
    /// Per-bot enable switch — independent of `PampGramSettings.visualBotsEnabled`, which gates
    /// the whole section. Both must be on for the overlay to render.
    public var enabled: Bool
    /// Wallet contents. One entry per currency actually held; a currency that has never been
    /// seen on this bot is simply absent (treat as 0) rather than stored as a 0 row.
    public var balances: [PampGramVisualBotBalance]
    /// Seconds since epoch when the record was first written. Used only for stable ordering in
    /// the settings list; the overlay doesn't display it.
    public var createdDate: Int32

    public init(id: String, kind: PampGramVisualBotKind, username: String, displayName: String, enabled: Bool, balances: [PampGramVisualBotBalance], createdDate: Int32) {
        self.id = id
        self.kind = kind
        self.username = username
        self.displayName = displayName
        self.enabled = enabled
        self.balances = balances
        self.createdDate = createdDate
    }

    /// Current balance in minor units for one currency on this bot. Absent entries read as 0,
    /// so callers can ask about any currency without pre-checking.
    public func balance(currency: String) -> Int64 {
        return self.balances.first(where: { $0.currency == currency })?.minorUnits ?? 0
    }

    /// Returns a copy with `currency`'s row set to `minorUnits`. Adds the row if missing,
    /// removes it if the result is 0 — keeping the balances array free of zero-amount
    /// placeholders that would otherwise fill up over time.
    public func settingBalance(currency: String, minorUnits: Int64) -> PampGramVisualBot {
        var bot = self
        if let index = bot.balances.firstIndex(where: { $0.currency == currency }) {
            if minorUnits == 0 {
                bot.balances.remove(at: index)
            } else {
                bot.balances[index].minorUnits = minorUnits
            }
        } else if minorUnits != 0 {
            bot.balances.append(PampGramVisualBotBalance(currency: currency, minorUnits: minorUnits))
        }
        return bot
    }

    /// Default seed set — the two bots the user asked for. Called the first time the store is
    /// read on a device that has none; after that, additions and renames come from the user.
    public static func defaultSeed(now: Int32) -> [PampGramVisualBot] {
        return [
            PampGramVisualBot(
                id: PampGramVisualBotKind.xrocket.rawValue,
                kind: .xrocket,
                username: "xrocket",
                displayName: "xRocket",
                enabled: false,
                balances: [],
                createdDate: now
            ),
            PampGramVisualBot(
                id: PampGramVisualBotKind.cryptobot.rawValue,
                kind: .cryptobot,
                username: "CryptoBot",
                displayName: "Crypto Bot",
                enabled: false,
                balances: [],
                createdDate: now
            )
        ]
    }
}

extension PampGramVisualBot {
    private enum CodingKeys: String, CodingKey {
        case id, kind, username, displayName, enabled, balances, createdDate
    }

    /// Field-by-field decoding with `decodeIfPresent` for the same reason `PampGramSettings`
    /// uses it — adding a field in a later build must not reset the record to the empty seed.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.kind = try container.decodeIfPresent(PampGramVisualBotKind.self, forKey: .kind) ?? .xrocket
        self.username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        self.displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? self.username
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        self.balances = try container.decodeIfPresent([PampGramVisualBotBalance].self, forKey: .balances) ?? []
        self.createdDate = try container.decodeIfPresent(Int32.self, forKey: .createdDate) ?? 0
    }
}

/// What kind of entry a `PampGramVisualBotOperation` represents. The six kinds come in
/// symmetric pairs (deposit/withdraw, send/receive, transfer in/out, check created/redeemed),
/// so a row's sign (`minorUnits > 0` vs `< 0`) is implied by the kind rather than stored
/// twice. `manual` is for direct balance edits from the settings screen.
public enum PampGramVisualBotOperationKind: String {
    case deposit            // outside world → this bot (credit)
    case withdraw           // this bot → outside world (debit)
    case sendOut            // transfer to a Telegram user via the bot (debit)
    case receiveIn          // transfer from another user via the bot (credit)
    case transferOut        // between two visual bots on this device (debit; counterpart is credit)
    case transferIn         // paired half of `transferOut`
    case checkCreated       // issued a visual check — funds held, counts as a debit until redeemed/expired
    case checkRedeemed      // activated a visual check from this device (credit)
    case manual             // direct edit from the settings screen (signed)
}

extension PampGramVisualBotOperationKind: Codable {
    private enum CodingKeys: String, CodingKey {
        case value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(String.self, forKey: .value)
        self = PampGramVisualBotOperationKind(rawValue: raw) ?? .manual
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.rawValue, forKey: .value)
    }
}

/// One row of a visual bot's local operation history. Every balance change goes through
/// `PampGramVisualBotStore.apply`, which appends exactly one of these; the balances array on
/// `PampGramVisualBot` is a cached projection of these rows and could be recomputed from
/// scratch if a future migration needed to.
public struct PampGramVisualBotOperation: Codable, Equatable {
    public var id: Int64
    public var botId: String
    public var kind: PampGramVisualBotOperationKind
    public var currency: String
    /// Signed. Positive = credit, negative = debit. Matches how the row renders in history.
    public var minorUnits: Int64
    public var date: Int32
    /// The other visual bot in a `transferOut`/`transferIn` pair. Nil for every other kind.
    public var counterpartBotId: String?
    /// The check code for `checkCreated` / `checkRedeemed`. Nil otherwise.
    public var checkCode: String?
    /// Short free-form label — "Пополнение с карты", "Чек от Crypto Bot", etc. UI copy, never
    /// matched against.
    public var note: String?

    public init(id: Int64, botId: String, kind: PampGramVisualBotOperationKind, currency: String, minorUnits: Int64, date: Int32, counterpartBotId: String?, checkCode: String?, note: String?) {
        self.id = id
        self.botId = botId
        self.kind = kind
        self.currency = currency
        self.minorUnits = minorUnits
        self.date = date
        self.counterpartBotId = counterpartBotId
        self.checkCode = checkCode
        self.note = note
    }
}

extension PampGramVisualBotOperation {
    private enum CodingKeys: String, CodingKey {
        case id, botId, kind, currency, minorUnits, date, counterpartBotId, checkCode, note
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int64.self, forKey: .id)
        self.botId = try container.decode(String.self, forKey: .botId)
        self.kind = try container.decodeIfPresent(PampGramVisualBotOperationKind.self, forKey: .kind) ?? .manual
        self.currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? ""
        self.minorUnits = try container.decodeIfPresent(Int64.self, forKey: .minorUnits) ?? 0
        self.date = try container.decodeIfPresent(Int32.self, forKey: .date) ?? 0
        self.counterpartBotId = try container.decodeIfPresent(String.self, forKey: .counterpartBotId)
        self.checkCode = try container.decodeIfPresent(String.self, forKey: .checkCode)
        self.note = try container.decodeIfPresent(String.self, forKey: .note)
    }
}

/// A visual "check" (чек) — the local counterpart to a real xRocket / Crypto Bot invoice
/// link. On creation the funds are debited from the issuing bot and parked here; on redeem
/// (opening the matching `t.me/<bot>?start=<code>` link on the SAME device) they credit the
/// bot the user activates it into. A check scanned on a different device is a dead URL —
/// nothing on the server knows about it.
public struct PampGramVisualBotCheck: Codable, Equatable {
    /// The random short string that goes into the link's `start=` parameter. Human-readable
    /// enough to recite ("CQxxxxxx" / "CRxxxxxx" shapes), but 10+ chars so collisions are
    /// vanishingly unlikely for a per-device store.
    public var code: String
    /// The bot that issued the check (its funds were debited at creation time).
    public var botId: String
    public var currency: String
    /// Positive. The amount parked on the check — unchanged after creation.
    public var minorUnits: Int64
    public var createdDate: Int32
    /// Nil while the check is live; set once redeemed, after which the check is locked.
    public var redeemedDate: Int32?
    /// The visual bot into whose balance the funds were released. Nil while the check is live.
    public var redeemedByBotId: String?
    /// Free-form sender-side label, like a real Crypto Bot invoice comment. Shown on both
    /// ends of the flow.
    public var comment: String?

    public init(code: String, botId: String, currency: String, minorUnits: Int64, createdDate: Int32, redeemedDate: Int32?, redeemedByBotId: String?, comment: String?) {
        self.code = code
        self.botId = botId
        self.currency = currency
        self.minorUnits = minorUnits
        self.createdDate = createdDate
        self.redeemedDate = redeemedDate
        self.redeemedByBotId = redeemedByBotId
        self.comment = comment
    }

    public var isRedeemed: Bool {
        return self.redeemedDate != nil
    }
}

extension PampGramVisualBotCheck {
    private enum CodingKeys: String, CodingKey {
        case code, botId, currency, minorUnits, createdDate, redeemedDate, redeemedByBotId, comment
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.code = try container.decode(String.self, forKey: .code)
        self.botId = try container.decode(String.self, forKey: .botId)
        self.currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? ""
        self.minorUnits = try container.decodeIfPresent(Int64.self, forKey: .minorUnits) ?? 0
        self.createdDate = try container.decodeIfPresent(Int32.self, forKey: .createdDate) ?? 0
        self.redeemedDate = try container.decodeIfPresent(Int32.self, forKey: .redeemedDate)
        self.redeemedByBotId = try container.decodeIfPresent(String.self, forKey: .redeemedByBotId)
        self.comment = try container.decodeIfPresent(String.self, forKey: .comment)
    }
}
