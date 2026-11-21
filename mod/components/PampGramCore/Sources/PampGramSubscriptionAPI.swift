import Foundation
import Postbox
import SwiftSignalKit
import CryptoKit

/// The one part of PampGram with an actual server behind it. Every other file in this module
/// changes only what this device shows its own owner — but a subscription an admin grants (or
/// a key someone redeems) has to show up on the *other* person's device too, and there is no
/// way to make that true without a server both copies of the app can ask. See
/// `server/pampgram-subs-worker/` at the repo root for that server's source and deployment
/// instructions.
public enum PampGramSubscriptionTier: String, Codable {
    case standard
    case pro
}

/// `fetchStatus`'s result: a tier plus, when the admin granted it (or a key granting it was
/// redeemed) for a limited time rather than permanently, the moment it runs out. `expiresAt ==
/// nil` covers both "standard" and a permanent "pro" grant — the server itself already folds
/// an expired grant back to `.standard` before this ever reaches the client, so there's no
/// "expired but still reporting pro" state to represent here.
public struct PampGramSubscriptionStatus: Equatable {
    public let tier: PampGramSubscriptionTier
    public let expiresAt: Date?

    public init(tier: PampGramSubscriptionTier, expiresAt: Date?) {
        self.tier = tier
        self.expiresAt = expiresAt
    }
}

/// The PampGram hub sections an admin can ban independently of a full-account ban. Raw values
/// are the server's own section keys — see `server/pampgram-subs-worker/src/index.js`.
public enum PampGramBanSection: String, Codable, CaseIterable {
    case gifts
    case messages
    case ghost

    public var displayName: String {
        switch self {
        case .gifts:
            return "Подарки"
        case .messages:
            return "Сообщения"
        case .ghost:
            return "Ghost"
        }
    }
}

/// One account's ban state as the server sees it: an optional full-account reason, plus
/// independent per-section reasons that still apply even without a full ban.
public struct PampGramBanStatus: Codable, Equatable {
    public var full: String?
    public var sections: [String: String]

    public static let none = PampGramBanStatus(full: nil, sections: [:])

    public init(full: String?, sections: [String: String]) {
        self.full = full
        self.sections = sections
    }

    public func reason(for section: PampGramBanSection) -> String? {
        return self.sections[section.rawValue]
    }
}

/// What an unban call should lift — mirrors the server's own three `/unban` scopes exactly.
public enum PampGramUnbanScope {
    case full
    case section(PampGramBanSection)
    case all
}

/// One ban — a reason and when it was set. `at` is `nil` for a ban set before this field
/// existed (the server normalizes an old plain-string record to this shape with `at: nil` on
/// read; see `server/pampgram-subs-worker/src/index.js`'s own storage doc).
public struct PampGramBanEntry: Codable, Equatable {
    public let reason: String
    public let at: Int64?

    public init(reason: String, at: Int64?) {
        self.reason = reason
        self.at = at
    }
}

/// One row of the admin panel's "Пользователи" list — any account PampGram's server knows
/// about at all (has ever called `/status`, or has ever been banned even if it hasn't), its
/// current tier and when that was last changed, when it was last seen, and its full ban
/// picture. Replaces the old separate "Разбанить" list — this is the one merged source for
/// both ban management and subscription info. Profile fields (`username`/`name`/`appVersion`/
/// `firstSeen`/`sessionsCount`) come from the server's `u:<id>` profile when present.
public struct PampGramUserSummary: Codable, Equatable {
    public let id: String
    public let tier: PampGramSubscriptionTier
    public let tierChangedAt: Int64?
    public let lastSeen: Int64
    public let full: PampGramBanEntry?
    public let sections: [String: PampGramBanEntry]
    public let username: String
    public let name: String
    public let appVersion: String
    public let firstSeen: Int64
    public let sessionsCount: Int

    public init(id: String, tier: PampGramSubscriptionTier, tierChangedAt: Int64?, lastSeen: Int64, full: PampGramBanEntry?, sections: [String: PampGramBanEntry], username: String = "", name: String = "", appVersion: String = "", firstSeen: Int64 = 0, sessionsCount: Int = 0) {
        self.id = id
        self.tier = tier
        self.tierChangedAt = tierChangedAt
        self.lastSeen = lastSeen
        self.full = full
        self.sections = sections
        self.username = username
        self.name = name
        self.appVersion = appVersion
        self.firstSeen = firstSeen
        self.sessionsCount = sessionsCount
    }

    /// Everything this account is currently banned from, as (section, reason) pairs — `nil`
    /// section means the full-account ban. Empty when it isn't banned at all.
    public var activeBans: [(section: PampGramBanSection?, entry: PampGramBanEntry)] {
        var result: [(section: PampGramBanSection?, entry: PampGramBanEntry)] = []
        if let full {
            result.append((nil, full))
        }
        for section in PampGramBanSection.allCases {
            if let entry = self.sections[section.rawValue] {
                result.append((section, entry))
            }
        }
        return result
    }
}

/// One local ledger row as the admin `/user-detail` endpoint returns it (plain strings, no
/// PeerId) — enough to show spend/credit/NFT history without needing Telegram peer resolution.
public struct PampGramAdminLedgerOperation: Equatable {
    public let id: Int64
    public let currency: String
    public let kind: String
    public let amount: Int64
    public let date: Int32
    public let title: String
    public let details: String
    public let giftId: Int64?
    public let isGift: Bool
}

/// One NFT/gift event derived from a ledger row (name = gift title from `details`).
public struct PampGramAdminNftEvent: Equatable {
    public let name: String
    public let action: String
    public let currency: String
    public let amount: Int64
    public let date: Int32
    public let giftId: Int64?
}

/// Aggregated fake Stars/TON/rubles + NFT state last pushed by that install via `/sync-ledger`.
public struct PampGramAdminLedgerSnapshot: Equatable {
    public let starsBalance: Int64
    public let tonBalanceNanos: Int64
    public let rublesBalanceKopecks: Int64
    public let starsSpent: Int64
    public let starsReceived: Int64
    public let tonSpentNanos: Int64
    public let tonReceivedNanos: Int64
    public let rublesSpent: Int64
    public let rublesReceived: Int64
    public let nftReceived: Int
    public let nftBought: Int
    public let nftSold: Int
    public let nftTransferred: Int
    public let nfts: [PampGramAdminNftEvent]
    public let operationCount: Int
    public let operations: [PampGramAdminLedgerOperation]
}

/// One real Telegram Stars/TON transaction as `/user-detail` returns it.
public struct PampGramAdminRealTransaction: Equatable {
    public let id: String
    public let currency: String
    public let amount: Int64
    public let date: Int32
    public let title: String
    public let description: String
    public let peer: String
    public let giftTitle: String
    public let flags: [String]
}

/// Real Telegram Stars/TON history last pushed via `/sync-real-ledger`.
public struct PampGramAdminRealLedgerSnapshot: Equatable {
    public let starsBalance: Int64
    public let tonBalanceNanos: Int64
    public let updatedAt: Int64
    public let starsSpent: Int64
    public let starsReceived: Int64
    public let tonSpentNanos: Int64
    public let tonReceivedNanos: Int64
    public let giftOps: Int
    public let transactionCount: Int
    public let transactions: [PampGramAdminRealTransaction]
}

/// Full admin card for one account: profile + sessions + tier/ban + local + real ledger.
public struct PampGramUserDetail: Equatable {
    public let id: String
    public let username: String
    public let name: String
    public let appVersion: String
    public let appBuild: String
    public let firstSeen: Int64
    public let lastSeen: Int64
    public let sessions: [Int64]
    public let tier: PampGramSubscriptionTier
    public let tierChangedAt: Int64?
    public let expiresAt: Int64?
    public let full: PampGramBanEntry?
    public let sections: [String: PampGramBanEntry]
    public let ledger: PampGramAdminLedgerSnapshot?
    public let real: PampGramAdminRealLedgerSnapshot?

    public var summary: PampGramUserSummary {
        PampGramUserSummary(
            id: self.id,
            tier: self.tier,
            tierChangedAt: self.tierChangedAt,
            lastSeen: self.lastSeen,
            full: self.full,
            sections: self.sections,
            username: self.username,
            name: self.name,
            appVersion: self.appVersion,
            firstSeen: self.firstSeen,
            sessionsCount: self.sessions.count
        )
    }
}

/// The admin's proof-of-identity token, stored ONLY in this device's own local Postbox —
/// never hardcoded in source, never committed to the repo. It has to match the server's own
/// `ADMIN_TOKEN` secret (`wrangler secret put ADMIN_TOKEN`) for a grant to be accepted; the
/// admin pastes the same value into both places once, from the admin screen's own "Задать
/// админ-токен" row. Reusing `PreferencesEntry` the same way `PampGramSettings` does — see
/// `PampGramCore` below.
private struct PampGramAdminTokenEntry: Codable, Equatable {
    var token: String
}

public enum PampGramSubscriptionAPI {
    /// Telegram's own numeric account id for @kopimastera — not the username, which can
    /// change. The admin screen in PampGramSettingsUI only shows itself when the signed-in
    /// account's id equals this. That's a client-side UI gate, not the real security boundary
    /// — the admin token (stored locally, see above) is what the server actually checks.
    public static let adminAccountId: Int64 = 8557314630

    /// The deployed `server/pampgram-subs-worker/` instance (see its README).
    private static let baseURL = "https://pampgram.pochtadantov.workers.dev"

    /// Shared with the server's `RESPONSE_SIGNING_KEY` secret (`hmacSign` in
    /// `server/pampgram-subs-worker/src/index.js`) — verifies `/status`, `/ban-status`, and
    /// `/min-version` actually came from that server rather than a proxy on this device
    /// rewriting the JSON to claim "pro"/"not banned"/"no minimum" for free. Not a defense
    /// against someone who fully reverse-engineers this binary (nothing baked into a client
    /// ever is) — it closes the much easier route that needs no access to the binary at all.
    /// Rotate by generating a new `openssl rand -hex 32`, setting it as the server secret, and
    /// changing this constant to match in the same build.
    private static let responseSigningKey = "00b78acae40c265d6b68038d5922283d153e7a18f8b150e27b84e02804b605b1"

    /// `true` when `sig` is the HMAC-SHA256 (hex) of `message` under `responseSigningKey` —
    /// the exact same computation `hmacSign` runs server-side, so `message` must be built
    /// identically to how each route's handler builds it (see each `fetch*` call site below).
    private static func verifySignature(_ sig: String, message: String) -> Bool {
        let key = SymmetricKey(data: Data(responseSigningKey.utf8))
        let expected = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        let expectedHex = expected.map { String(format: "%02x", $0) }.joined()
        // Fixed-time compare: a signature check is exactly the kind of secret-dependent
        // branch where an early-exit `==` could, in principle, leak timing information.
        return expectedHex.utf8.count == sig.utf8.count && safeCompare(expectedHex, sig)
    }

    private static func safeCompare(_ a: String, _ b: String) -> Bool {
        var result: UInt8 = 0
        for (x, y) in zip(a.utf8, b.utf8) {
            result |= x ^ y
        }
        return result == 0
    }

    /// This build's own number, bumped by one in source each time a build is shipped that
    /// should be able to retire everything before it. Compared against the server's
    /// `min_version` (see `fetchMinVersion`/`setMinVersion`) — a build below that number shows
    /// "update required" instead of opening PampGram. Nothing reads this from the server; it's
    /// baked into the binary at compile time, same as `adminAccountId`.
    public static let currentBuildVersion: Int = 4

    private struct StatusResponse: Decodable {
        let tier: String
        // Int64, not Double — has to format back to the exact same digit string the server
        // signed (`${expiresAt ?? "null"}` over a value it already rounds to a whole
        // millisecond), and a Double risks a different textual form for the same value.
        let expiresAt: Int64?
        let sig: String
    }

    private struct GrantRequestBody: Encodable {
        let id: Int64
        let tier: String
        let token: String
        let durationHours: Double?
    }

    private static let telemetryLock = NSLock()
    private static var telemetryVersion: String?
    private static var telemetryProfiles: [Int64: (username: String, name: String)] = [:]

    /// Self-reported details sent along with every `/status` call so the admin's bot can show
    /// which version each account runs and who it is. Informational only (the route is public),
    /// never a basis for access. Set once at startup from `AccountContextImpl`.
    public static func setTelemetry(version: String, userId: Int64, username: String?, name: String?) {
        telemetryLock.lock()
        telemetryVersion = version
        telemetryProfiles[userId] = (username ?? "", name ?? "")
        telemetryLock.unlock()
    }

    private static func telemetryQuery(userId: Int64) -> String {
        telemetryLock.lock()
        let version = telemetryVersion
        let profile = telemetryProfiles[userId]
        telemetryLock.unlock()

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        func item(_ key: String, _ value: String?) -> String {
            guard let value, !value.isEmpty, let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) else {
                return ""
            }
            return "&\(key)=\(encoded)"
        }
        var query = item("v", version.map { $0.hasPrefix("v") ? String($0.dropFirst()) : $0 })
        query += item("b", Bundle.main.infoDictionary?["CFBundleVersion"] as? String)
        query += item("u", profile?.username)
        query += item("n", profile?.name)
        return query
    }

    /// Live-ish (one-shot per subscription) read of `userId`'s tier and, for a time-limited
    /// grant or redeemed key, when it runs out. Never fails outward: any network problem, bad
    /// response, or the baseURL placeholder still being unfilled all resolve to
    /// `.standard`/`nil` — the safe default — rather than erroring the screen that asked.
    public static func fetchStatus(userId: Int64) -> Signal<PampGramSubscriptionStatus, NoError> {
        // @kopimastera's own account is always PRO, permanently, without a round trip to the
        // server or a stored grant that could lapse or get overwritten — this is the one id the
        // tier system itself always treats as fully subscribed.
        if userId == adminAccountId {
            return .single(PampGramSubscriptionStatus(tier: .pro, expiresAt: nil))
        }
        return Signal { subscriber in
            guard let url = URL(string: "\(baseURL)/status?id=\(userId)\(telemetryQuery(userId: userId))") else {
                subscriber.putNext(PampGramSubscriptionStatus(tier: .standard, expiresAt: nil))
                subscriber.putCompletion()
                return EmptyDisposable
            }
            let task = URLSession.shared.dataTask(with: url) { data, _, _ in
                var status = PampGramSubscriptionStatus(tier: .standard, expiresAt: nil)
                if let data, let decoded = try? JSONDecoder().decode(StatusResponse.self, from: data) {
                    let message = "\(userId)|\(decoded.tier)|\(decoded.expiresAt.map(String.init) ?? "null")"
                    if verifySignature(decoded.sig, message: message) {
                        let tier = PampGramSubscriptionTier(rawValue: decoded.tier) ?? .standard
                        let expiresAt = decoded.expiresAt.map { Date(timeIntervalSince1970: Double($0) / 1000) }
                        status = PampGramSubscriptionStatus(tier: tier, expiresAt: expiresAt)
                    }
                    // An invalid signature falls through to the same safe `.standard`/`nil`
                    // default a network failure already uses above — a forged response is
                    // indistinguishable from one that never arrived, which is exactly the point.
                }
                subscriber.putNext(status)
                subscriber.putCompletion()
            }
            task.resume()
            return ActionDisposable {
                task.cancel()
            }
        }
    }

    /// Convenience wrapper around `fetchStatus` for the many call sites that only ever care
    /// about the tier itself, not its expiry — same never-fails-outward contract.
    public static func fetchTier(userId: Int64) -> Signal<PampGramSubscriptionTier, NoError> {
        return self.fetchStatus(userId: userId)
        |> map { $0.tier }
    }

    /// Admin-only: sets `userId`'s tier on the server, either permanently (`durationHours ==
    /// nil`) or until `durationHours` hours from the moment the server accepts this call.
    /// Called only from the admin screen, which is itself only ever shown to `adminAccountId`.
    /// `adminToken` is read from this device's local storage (see
    /// `adminToken(transaction:)`/`setAdminToken`) — never a source-code constant. `completion`
    /// reports whether the server actually accepted it, always dispatched on the main queue.
    public static func grantTier(userId: Int64, tier: PampGramSubscriptionTier, durationHours: Double?, adminToken: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(baseURL)/grant") else {
            completion(false)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(GrantRequestBody(id: userId, tier: tier.rawValue, token: adminToken, durationHours: durationHours))

        URLSession.shared.dataTask(with: request) { _, response, error in
            let ok = error == nil && (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async {
                completion(ok)
            }
        }.resume()
    }

    private struct BanRequestBody: Encodable {
        let id: Int64
        let token: String
        let scope: String
        let section: String?
        let reason: String
    }

    private struct UnbanRequestBody: Encodable {
        let id: Int64
        let token: String
        let scope: String
        let section: String?
    }

    /// Live-ish read of `userId`'s ban state. Same never-fails-outward contract as
    /// `fetchTier`: any network or decode problem resolves to `.none` (not banned) rather than
    /// erroring the screen that asked — a banned section only ever locks because the server
    /// said so, never because a request happened to fail.
    private struct BanStatusResponse: Decodable {
        let full: String?
        let sections: [String: String]
        let sig: String
    }

    public static func fetchBanStatus(userId: Int64) -> Signal<PampGramBanStatus, NoError> {
        return Signal { subscriber in
            guard let url = URL(string: "\(baseURL)/ban-status?id=\(userId)") else {
                subscriber.putNext(.none)
                subscriber.putCompletion()
                return EmptyDisposable
            }
            let task = URLSession.shared.dataTask(with: url) { data, _, _ in
                var status = PampGramBanStatus.none
                if let data, let decoded = try? JSONDecoder().decode(BanStatusResponse.self, from: data) {
                    // Same canonical, order-independent form the server signs over — see
                    // `hmacSign`'s call site in `handleBanStatus`.
                    let sectionsCanonical = decoded.sections.keys.sorted().map { "\($0):\(decoded.sections[$0]!)" }.joined(separator: ",")
                    let message = "\(userId)|\(decoded.full ?? "null")|\(sectionsCanonical)"
                    if verifySignature(decoded.sig, message: message) {
                        status = PampGramBanStatus(full: decoded.full, sections: decoded.sections)
                    }
                }
                subscriber.putNext(status)
                subscriber.putCompletion()
            }
            task.resume()
            return ActionDisposable {
                task.cancel()
            }
        }
    }

    /// Admin-only: bans `userId` either everywhere (`section: nil`) or in one hub section.
    public static func banUser(userId: Int64, section: PampGramBanSection?, reason: String, adminToken: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(baseURL)/ban") else {
            completion(false)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(BanRequestBody(id: userId, token: adminToken, scope: section == nil ? "full" : "section", section: section?.rawValue, reason: reason))

        URLSession.shared.dataTask(with: request) { _, response, error in
            let ok = error == nil && (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async {
                completion(ok)
            }
        }.resume()
    }

    /// Admin-only: lifts a ban. `.full` clears only the full-account ban (any section bans
    /// stay); `.section` clears only that one section; `.all` clears everything at once —
    /// three distinct server scopes, not two, since "the account is fully banned" and "this
    /// account also happens to carry section reasons from before" are independent facts.
    public static func unbanUser(userId: Int64, scope: PampGramUnbanScope, adminToken: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(baseURL)/unban") else {
            completion(false)
            return
        }
        let scopeString: String
        let sectionString: String?
        switch scope {
        case .full:
            scopeString = "full"
            sectionString = nil
        case let .section(section):
            scopeString = "section"
            sectionString = section.rawValue
        case .all:
            scopeString = "all"
            sectionString = nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(UnbanRequestBody(id: userId, token: adminToken, scope: scopeString, section: sectionString))

        URLSession.shared.dataTask(with: request) { _, response, error in
            let ok = error == nil && (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async {
                completion(ok)
            }
        }.resume()
    }

    private struct MinVersionResponse: Decodable {
        let minVersion: Int
        let sig: String
    }

    private struct SetMinVersionRequestBody: Encodable {
        let minVersion: Int
        let token: String
    }

    /// Live-ish read of the server's current minimum build number. Same never-fails-outward
    /// contract as `fetchTier`/`fetchBanStatus`: any network or decode problem resolves to `0`
    /// ("no minimum set") rather than erroring — a network hiccup can never falsely lock
    /// somebody out of a build the admin never actually retired.
    public static func fetchMinVersion() -> Signal<Int, NoError> {
        return Signal { subscriber in
            guard let url = URL(string: "\(baseURL)/min-version") else {
                subscriber.putNext(0)
                subscriber.putCompletion()
                return EmptyDisposable
            }
            let task = URLSession.shared.dataTask(with: url) { data, _, _ in
                var minVersion = 0
                if let data, let decoded = try? JSONDecoder().decode(MinVersionResponse.self, from: data), verifySignature(decoded.sig, message: "\(decoded.minVersion)") {
                    minVersion = decoded.minVersion
                }
                subscriber.putNext(minVersion)
                subscriber.putCompletion()
            }
            task.resume()
            return ActionDisposable {
                task.cancel()
            }
        }
    }

    /// Admin-only: raises (or clears, with 0) the server's minimum build number. Every install
    /// whose own `currentBuildVersion` falls below this — including ones already sitting on
    /// someone's device right now — starts showing "update required" instead of PampGram's
    /// real content the next time they check, with nothing needing to change on their end.
    public static func setMinVersion(_ minVersion: Int, adminToken: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(baseURL)/set-min-version") else {
            completion(false)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(SetMinVersionRequestBody(minVersion: minVersion, token: adminToken))

        URLSession.shared.dataTask(with: request) { _, response, error in
            let ok = error == nil && (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async {
                completion(ok)
            }
        }.resume()
    }

    private struct UsersListRequestBody: Encodable {
        let token: String
    }

    private struct UsersListBanEntryResponse: Decodable {
        let reason: String
        let at: Int64?
    }

    private struct UsersListUserResponse: Decodable {
        let id: String
        let tier: String
        let tierChangedAt: Int64?
        let lastSeen: Int64
        let username: String?
        let name: String?
        let appVersion: String?
        let firstSeen: Int64?
        let sessionsCount: Int?
        let full: UsersListBanEntryResponse?
        let sections: [String: UsersListBanEntryResponse]
    }

    private struct UsersListResponse: Decodable {
        let users: [UsersListUserResponse]
    }

    private struct UserDetailRequestBody: Encodable {
        let token: String
        let id: Int64
    }

    private struct UserDetailLedgerOpResponse: Decodable {
        let id: Int64
        let currency: String
        let kind: String
        let amount: Int64
        let date: Int32
        let title: String
        let details: String
        let giftId: Int64?
        let isGift: Bool?
    }

    private struct UserDetailNftResponse: Decodable {
        let name: String
        let action: String
        let currency: String
        let amount: Int64
        let date: Int32
        let giftId: Int64?
    }

    private struct UserDetailLedgerResponse: Decodable {
        let starsBalance: Int64
        let tonBalanceNanos: Int64
        let rublesBalanceKopecks: Int64?
        let starsSpent: Int64
        let starsReceived: Int64
        let tonSpentNanos: Int64
        let tonReceivedNanos: Int64
        let rublesSpent: Int64?
        let rublesReceived: Int64?
        let nftReceived: Int?
        let nftBought: Int?
        let nftSold: Int?
        let nftTransferred: Int?
        let nfts: [UserDetailNftResponse]?
        let operationCount: Int?
        let operations: [UserDetailLedgerOpResponse]
    }

    private struct UserDetailRealTxResponse: Decodable {
        let id: String
        let currency: String
        let amount: Int64
        let date: Int32
        let title: String
        let description: String
        let peer: String
        let giftTitle: String?
        let flags: [String]?
    }

    private struct UserDetailRealResponse: Decodable {
        let starsBalance: Int64
        let tonBalanceNanos: Int64
        let updatedAt: Int64?
        let starsSpent: Int64
        let starsReceived: Int64
        let tonSpentNanos: Int64
        let tonReceivedNanos: Int64
        let giftOps: Int?
        let transactionCount: Int?
        let transactions: [UserDetailRealTxResponse]
    }

    private struct UserDetailResponse: Decodable {
        let id: String
        let username: String?
        let name: String?
        let appVersion: String?
        let appBuild: String?
        let firstSeen: Int64?
        let lastSeen: Int64
        let sessions: [Int64]?
        let tier: String
        let tierChangedAt: Int64?
        let expiresAt: Int64?
        let full: UsersListBanEntryResponse?
        let sections: [String: UsersListBanEntryResponse]?
        let ledger: UserDetailLedgerResponse?
        let real: UserDetailRealResponse?
    }

    /// Admin-only: every account PampGram's server knows about — has ever opened the app, has
    /// ever been blocked, has ever been granted a tier via `grantTier` (even before it opened
    /// the app once), or any combination — with its current tier and block state, for the
    /// admin panel's merged "Пользователи" list (which replaced the old separate "Разбанить"
    /// screen). An unrecognized tier string falls back to `.standard`, same never-fails-
    /// outward posture as `fetchTier`; the server only ever sends "standard"/"pro" in practice.
    public static func fetchUsersList(adminToken: String, completion: @escaping ([PampGramUserSummary]) -> Void) {
        guard let url = URL(string: "\(baseURL)/users-list") else {
            completion([])
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(UsersListRequestBody(token: adminToken))

        URLSession.shared.dataTask(with: request) { data, _, _ in
            var users: [PampGramUserSummary] = []
            if let data, let decoded = try? JSONDecoder().decode(UsersListResponse.self, from: data) {
                users = decoded.users.map { user in
                    PampGramUserSummary(
                        id: user.id,
                        tier: PampGramSubscriptionTier(rawValue: user.tier) ?? .standard,
                        tierChangedAt: user.tierChangedAt,
                        lastSeen: user.lastSeen,
                        full: user.full.map { PampGramBanEntry(reason: $0.reason, at: $0.at) },
                        sections: user.sections.mapValues { PampGramBanEntry(reason: $0.reason, at: $0.at) },
                        username: user.username ?? "",
                        name: user.name ?? "",
                        appVersion: user.appVersion ?? "",
                        firstSeen: user.firstSeen ?? 0,
                        sessionsCount: user.sessionsCount ?? 0
                    )
                }
            }
            DispatchQueue.main.async {
                completion(users)
            }
        }.resume()
    }

    /// Admin-only: one person's card — profile, sessions, PRO/STANDARD, bans, and the last
    /// synced Stars/TON ledger (balances + recent operations).
    public static func fetchUserDetail(userId: Int64, adminToken: String, completion: @escaping (PampGramUserDetail?) -> Void) {
        guard let url = URL(string: "\(baseURL)/user-detail") else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(UserDetailRequestBody(token: adminToken, id: userId))

        URLSession.shared.dataTask(with: request) { data, _, _ in
            var detail: PampGramUserDetail?
            if let data, let decoded = try? JSONDecoder().decode(UserDetailResponse.self, from: data) {
                let ledger: PampGramAdminLedgerSnapshot?
                if let raw = decoded.ledger {
                    ledger = PampGramAdminLedgerSnapshot(
                        starsBalance: raw.starsBalance,
                        tonBalanceNanos: raw.tonBalanceNanos,
                        rublesBalanceKopecks: raw.rublesBalanceKopecks ?? 0,
                        starsSpent: raw.starsSpent,
                        starsReceived: raw.starsReceived,
                        tonSpentNanos: raw.tonSpentNanos,
                        tonReceivedNanos: raw.tonReceivedNanos,
                        rublesSpent: raw.rublesSpent ?? 0,
                        rublesReceived: raw.rublesReceived ?? 0,
                        nftReceived: raw.nftReceived ?? 0,
                        nftBought: raw.nftBought ?? 0,
                        nftSold: raw.nftSold ?? 0,
                        nftTransferred: raw.nftTransferred ?? 0,
                        nfts: (raw.nfts ?? []).map {
                            PampGramAdminNftEvent(name: $0.name, action: $0.action, currency: $0.currency, amount: $0.amount, date: $0.date, giftId: $0.giftId)
                        },
                        operationCount: raw.operationCount ?? raw.operations.count,
                        operations: raw.operations.map {
                            PampGramAdminLedgerOperation(id: $0.id, currency: $0.currency, kind: $0.kind, amount: $0.amount, date: $0.date, title: $0.title, details: $0.details, giftId: $0.giftId, isGift: $0.isGift ?? ($0.giftId != nil))
                        }
                    )
                } else {
                    ledger = nil
                }
                let real: PampGramAdminRealLedgerSnapshot?
                if let raw = decoded.real {
                    real = PampGramAdminRealLedgerSnapshot(
                        starsBalance: raw.starsBalance,
                        tonBalanceNanos: raw.tonBalanceNanos,
                        updatedAt: raw.updatedAt ?? 0,
                        starsSpent: raw.starsSpent,
                        starsReceived: raw.starsReceived,
                        tonSpentNanos: raw.tonSpentNanos,
                        tonReceivedNanos: raw.tonReceivedNanos,
                        giftOps: raw.giftOps ?? 0,
                        transactionCount: raw.transactionCount ?? raw.transactions.count,
                        transactions: raw.transactions.map {
                            PampGramAdminRealTransaction(id: $0.id, currency: $0.currency, amount: $0.amount, date: $0.date, title: $0.title, description: $0.description, peer: $0.peer, giftTitle: $0.giftTitle ?? "", flags: $0.flags ?? [])
                        }
                    )
                } else {
                    real = nil
                }
                detail = PampGramUserDetail(
                    id: decoded.id,
                    username: decoded.username ?? "",
                    name: decoded.name ?? "",
                    appVersion: decoded.appVersion ?? "",
                    appBuild: decoded.appBuild ?? "",
                    firstSeen: decoded.firstSeen ?? 0,
                    lastSeen: decoded.lastSeen,
                    sessions: decoded.sessions ?? [],
                    tier: PampGramSubscriptionTier(rawValue: decoded.tier) ?? .standard,
                    tierChangedAt: decoded.tierChangedAt,
                    expiresAt: decoded.expiresAt,
                    full: decoded.full.map { PampGramBanEntry(reason: $0.reason, at: $0.at) },
                    sections: (decoded.sections ?? [:]).mapValues { PampGramBanEntry(reason: $0.reason, at: $0.at) },
                    ledger: ledger,
                    real: real
                )
            }
            DispatchQueue.main.async {
                completion(detail)
            }
        }.resume()
    }

    private struct GenerateKeyRequestBody: Encodable {
        let token: String
        let tier: String?
        let durationHours: Double?
        let kind: String?
    }

    private struct GenerateKeyResponse: Decodable {
        let ok: Bool
        let key: String?
        let kind: String?
    }

    /// Admin-only: mints one fresh, unused activation key for `tier`, either permanent
    /// (`durationHours == nil`) or good for `durationHours` hours once redeemed — the
    /// self-service counterpart to `grantTier`, meant to be sold or handed out once and
    /// redeemed by whoever gets it first (see `redeemKey`). The clock only starts at
    /// redemption, not now: two people can sit on the same freshly generated 24-hour key for a
    /// week and whoever redeems it still gets the full 24 hours. `completion` reports the key
    /// string on success, `nil` on any failure (network, auth, or a malformed response) — never
    /// dispatched off the main queue, same contract as `grantTier`.
    public static func generateKey(tier: PampGramSubscriptionTier, durationHours: Double?, adminToken: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "\(baseURL)/generate-key") else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(GenerateKeyRequestBody(token: adminToken, tier: tier.rawValue, durationHours: durationHours, kind: nil))

        URLSession.shared.dataTask(with: request) { data, response, error in
            var key: String?
            if error == nil, (response as? HTTPURLResponse)?.statusCode == 200, let data, let decoded = try? JSONDecoder().decode(GenerateKeyResponse.self, from: data) {
                key = decoded.key
            }
            DispatchQueue.main.async {
                completion(key)
            }
        }.resume()
    }

    /// Admin-only: one-shot unban key. The banned account enters it on the fullscreen lock;
    /// a normal PRO/STANDARD key cannot lift a ban.
    public static func generateUnbanKey(adminToken: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "\(baseURL)/generate-key") else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(GenerateKeyRequestBody(token: adminToken, tier: nil, durationHours: nil, kind: "unban"))

        URLSession.shared.dataTask(with: request) { data, response, error in
            var key: String?
            if error == nil, (response as? HTTPURLResponse)?.statusCode == 200, let data, let decoded = try? JSONDecoder().decode(GenerateKeyResponse.self, from: data) {
                key = decoded.key
            }
            DispatchQueue.main.async {
                completion(key)
            }
        }.resume()
    }

    private struct RedeemKeyRequestBody: Encodable {
        let id: Int64
        let key: String
    }

    private struct RedeemKeyResponse: Decodable {
        let ok: Bool
        let tier: String?
        let expiresAt: Double?
        let unbanned: Bool?
    }

    /// Result of redeeming any key (licence or unban).
    public enum PampGramRedeemResult {
        case granted(PampGramSubscriptionStatus)
        case unbanned
        case failed
    }

    /// Not admin-only — buyer-facing half of the key system. Accepts a normal licence key
    /// (grants tier) or an unban key (lifts a full ban). A normal key while fully banned fails
    /// on the server and does not consume the key.
    public static func redeemKey(userId: Int64, key: String, completion: @escaping (PampGramRedeemResult) -> Void) {
        guard let url = URL(string: "\(baseURL)/redeem-key") else {
            completion(.failed)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(RedeemKeyRequestBody(id: userId, key: key))

        URLSession.shared.dataTask(with: request) { data, response, error in
            var result: PampGramRedeemResult = .failed
            if error == nil, (response as? HTTPURLResponse)?.statusCode == 200, let data, let decoded = try? JSONDecoder().decode(RedeemKeyResponse.self, from: data), decoded.ok {
                if decoded.unbanned == true {
                    result = .unbanned
                } else if let tierRaw = decoded.tier, let tier = PampGramSubscriptionTier(rawValue: tierRaw) {
                    let expiresAt = decoded.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000) }
                    result = .granted(PampGramSubscriptionStatus(tier: tier, expiresAt: expiresAt))
                }
            }
            DispatchQueue.main.async {
                completion(result)
            }
        }.resume()
    }

    /// `/access`'s raw, UNVERIFIED answer — `PampGramAccessGate` checks the Ed25519 signature
    /// (and that `nonce` is the one it sent) before believing any of it. `reason` is display
    /// text only and is not covered by the signature.
    public struct PampGramAccessResponse: Decodable {
        public let state: String
        public let expiresAt: Int64?
        public let now: Int64
        public let ttl: Int64
        public let nonce: String
        public let reason: String?
        public let sig: String
    }

    /// One `/access` round trip for `userId`. `nonce` is a fresh random string the server signs
    /// into its answer, so a recorded answer can't be replayed later. Any network/HTTP/decode
    /// problem completes with `nil` — the caller treats that as "no answer", never as "allowed".
    public static func fetchAccess(userId: Int64, nonce: String, completion: @escaping (PampGramAccessResponse?) -> Void) {
        guard let url = URL(string: "\(baseURL)/access?id=\(userId)&nonce=\(nonce)\(telemetryQuery(userId: userId))") else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 15.0
        URLSession.shared.dataTask(with: request) { data, response, error in
            var decoded: PampGramAccessResponse?
            if error == nil, (response as? HTTPURLResponse)?.statusCode == 200, let data {
                decoded = try? JSONDecoder().decode(PampGramAccessResponse.self, from: data)
            }
            completion(decoded)
        }.resume()
    }

    private struct ReportTamperRequestBody: Encodable {
        let id: Int64
        let kind: String
    }

    /// Fire-and-forget: tells the server this device saw activity on a locked account (see
    /// `PampGramAccessGate`). The server only ever escalates an account that is already banned.
    public static func reportTamper(userId: Int64, kind: String) {
        guard let url = URL(string: "\(baseURL)/report-tamper") else {
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(ReportTamperRequestBody(id: userId, kind: kind))
        URLSession.shared.dataTask(with: request) { _, _, _ in
        }.resume()
    }


    private struct SyncLedgerRequestBody: Encodable {
        let id: Int64
        let payload: String
    }

    /// Pushes this device's complete current ledger state (fake balance + full history) to the
    /// server, overwriting whatever was stored for `id` before — see
    /// `PampGramLedgerSyncRuntime`, which calls this (debounced) after every local change.
    /// `payload` is already a JSON-encoded `PampGramLedgerSyncPayload`; this module only wraps
    /// it in the request body, same "never decode what a sibling module already encoded"
    /// posture as `sendGiftTransfer`. `completion` reports whether the server accepted it,
    /// always dispatched on the main queue.
    public static func syncLedger(id: Int64, payload: Data, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(baseURL)/sync-ledger"), let payloadString = String(data: payload, encoding: .utf8) else {
            completion(false)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(SyncLedgerRequestBody(id: id, payload: payloadString))

        URLSession.shared.dataTask(with: request) { _, response, error in
            let ok = error == nil && (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async {
                completion(ok)
            }
        }.resume()
    }

    /// Pushes this account's real Telegram Stars/TON history (from
    /// `payments.getStarsTransactions` on-device) for the admin card. Same body shape as
    /// `syncLedger`, stored under `realsync:<id>` on the server.
    public static func syncRealLedger(id: Int64, payload: Data, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(baseURL)/sync-real-ledger"), let payloadString = String(data: payload, encoding: .utf8) else {
            completion(false)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(SyncLedgerRequestBody(id: id, payload: payloadString))

        URLSession.shared.dataTask(with: request) { _, response, error in
            let ok = error == nil && (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async {
                completion(ok)
            }
        }.resume()
    }

    /// Admin-pushed fullscreen video command (from GET/POST `/force-video`).
    public struct PampGramForceVideoCommand: Equatable {
        public let id: String
        public let url: String
        public let loop: Bool
        public let dismissible: Bool
        public let createdAt: Int64
    }

    private struct ForceVideoBodyResponse: Decodable {
        let id: String
        let url: String
        let loop: Bool?
        let dismissible: Bool?
        let createdAt: Int64?
    }

    private struct ForceVideoGetResponse: Decodable {
        let video: ForceVideoBodyResponse?
    }

    private struct ForceVideoPostRequest: Encodable {
        let token: String
        let url: String
        let id: String
        let loop: Bool
        let dismissible: Bool
    }

    private struct ClearForceVideoRequest: Encodable {
        let token: String
        let id: String
    }

    /// Public poll: active force-video for this account (user-specific beats global).
    public static func fetchForceVideo(userId: Int64, completion: @escaping (PampGramForceVideoCommand?) -> Void) {
        guard let url = URL(string: "\(baseURL)/force-video?id=\(userId)") else {
            completion(nil)
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            var result: PampGramForceVideoCommand?
            if let data, let decoded = try? JSONDecoder().decode(ForceVideoGetResponse.self, from: data), let video = decoded.video {
                result = PampGramForceVideoCommand(
                    id: video.id,
                    url: video.url,
                    loop: video.loop ?? true,
                    dismissible: video.dismissible ?? false,
                    createdAt: video.createdAt ?? 0
                )
            }
            DispatchQueue.main.async {
                completion(result)
            }
        }.resume()
    }

    /// Admin: push fullscreen video to one account (`"\(userId)"`) or everyone (`"all"`).
    public static func forceVideo(targetId: String, url: String, loop: Bool, dismissible: Bool, adminToken: String, completion: @escaping (Bool) -> Void) {
        guard let endpoint = URL(string: "\(baseURL)/force-video") else {
            completion(false)
            return
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(ForceVideoPostRequest(token: adminToken, url: url, id: targetId, loop: loop, dismissible: dismissible))
        URLSession.shared.dataTask(with: request) { _, response, error in
            let ok = error == nil && (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async {
                completion(ok)
            }
        }.resume()
    }

    /// Admin: clear force-video for one account or `"all"` (global).
    public static func clearForceVideo(targetId: String, adminToken: String, completion: @escaping (Bool) -> Void) {
        guard let endpoint = URL(string: "\(baseURL)/clear-force-video") else {
            completion(false)
            return
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(ClearForceVideoRequest(token: adminToken, id: targetId))
        URLSession.shared.dataTask(with: request) { _, response, error in
            let ok = error == nil && (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async {
                completion(ok)
            }
        }.resume()
    }

    private struct FetchLedgerSyncResponse: Decodable {
        let payload: String?
    }

    /// Fetches whatever this account last pushed via `syncLedger`, if anything — the restore
    /// half of `PampGramLedgerSyncRuntime`'s startup check. Never fails outward: any network or
    /// decode problem resolves to `nil`, same as "nothing to restore", rather than erroring.
    public static func fetchLedgerSync(id: Int64, completion: @escaping (Data?) -> Void) {
        guard let url = URL(string: "\(baseURL)/fetch-ledger-sync?id=\(id)") else {
            completion(nil)
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            var result: Data?
            if let data, let decoded = try? JSONDecoder().decode(FetchLedgerSyncResponse.self, from: data), let payload = decoded.payload {
                result = payload.data(using: .utf8)
            }
            DispatchQueue.main.async {
                completion(result)
            }
        }.resume()
    }

    /// This device's locally-stored admin token, if the admin has entered one. Read inside a
    /// Postbox transaction, same pattern as `PampGramCore.settings(transaction:)`.
    public static func adminToken(transaction: Transaction) -> String? {
        let token = transaction.getPreferencesEntry(key: PampGramPreferencesKeys.adminToken)?.get(PampGramAdminTokenEntry.self)?.token
        return (token?.isEmpty ?? true) ? nil : token
    }

    public static func setAdminToken(transaction: Transaction, token: String) {
        transaction.setPreferencesEntry(key: PampGramPreferencesKeys.adminToken, value: PreferencesEntry(PampGramAdminTokenEntry(token: token)))
    }

    /// Live read of the locally-stored admin token, for the admin screen to redraw the moment
    /// it's set — same pattern as `PampGramCore.settingsSignal`.
    public static func adminTokenSignal(postbox: Postbox) -> Signal<String?, NoError> {
        return postbox.preferencesView(keys: [PampGramPreferencesKeys.adminToken])
        |> map { view -> String? in
            let token = view.values[PampGramPreferencesKeys.adminToken]?.get(PampGramAdminTokenEntry.self)?.token
            return (token?.isEmpty ?? true) ? nil : token
        }
        |> distinctUntilChanged
    }
}
