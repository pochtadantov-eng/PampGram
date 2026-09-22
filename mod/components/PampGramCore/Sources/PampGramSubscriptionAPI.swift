import Foundation
import Postbox
import SwiftSignalKit

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

/// One row of the admin panel's "Разбанить" list — a banned account and why.
public struct PampGramBannedUser: Codable, Equatable {
    public let id: String
    public let full: String?
    public let sections: [String: String]

    // A `public struct`'s synthesized memberwise initializer is only `internal` unless one
    // is written explicitly — without this, other modules (the admin panel's UI) can decode
    // this type from JSON but can't construct one directly themselves.
    public init(id: String, full: String?, sections: [String: String]) {
        self.id = id
        self.full = full
        self.sections = sections
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

    private struct StatusResponse: Decodable {
        let tier: String
        let expiresAt: Double?
    }

    private struct GrantRequestBody: Encodable {
        let id: Int64
        let tier: String
        let token: String
        let durationHours: Double?
    }

    /// Live-ish (one-shot per subscription) read of `userId`'s tier and, for a time-limited
    /// grant or redeemed key, when it runs out. Never fails outward: any network problem, bad
    /// response, or the baseURL placeholder still being unfilled all resolve to
    /// `.standard`/`nil` — the safe default — rather than erroring the screen that asked.
    public static func fetchStatus(userId: Int64) -> Signal<PampGramSubscriptionStatus, NoError> {
        return Signal { subscriber in
            guard let url = URL(string: "\(baseURL)/status?id=\(userId)") else {
                subscriber.putNext(PampGramSubscriptionStatus(tier: .standard, expiresAt: nil))
                subscriber.putCompletion()
                return EmptyDisposable
            }
            let task = URLSession.shared.dataTask(with: url) { data, _, _ in
                var status = PampGramSubscriptionStatus(tier: .standard, expiresAt: nil)
                if let data, let decoded = try? JSONDecoder().decode(StatusResponse.self, from: data) {
                    let tier = PampGramSubscriptionTier(rawValue: decoded.tier) ?? .standard
                    let expiresAt = decoded.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000) }
                    status = PampGramSubscriptionStatus(tier: tier, expiresAt: expiresAt)
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

    private struct BannedListRequestBody: Encodable {
        let token: String
    }

    private struct BannedListResponse: Decodable {
        let users: [PampGramBannedUser]
    }

    /// Live-ish read of `userId`'s ban state. Same never-fails-outward contract as
    /// `fetchTier`: any network or decode problem resolves to `.none` (not banned) rather than
    /// erroring the screen that asked — a banned section only ever locks because the server
    /// said so, never because a request happened to fail.
    public static func fetchBanStatus(userId: Int64) -> Signal<PampGramBanStatus, NoError> {
        return Signal { subscriber in
            guard let url = URL(string: "\(baseURL)/ban-status?id=\(userId)") else {
                subscriber.putNext(.none)
                subscriber.putCompletion()
                return EmptyDisposable
            }
            let task = URLSession.shared.dataTask(with: url) { data, _, _ in
                var status = PampGramBanStatus.none
                if let data, let decoded = try? JSONDecoder().decode(PampGramBanStatus.self, from: data) {
                    status = decoded
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

    /// Admin-only: every currently-banned account, for the admin panel's "Разбанить" list.
    public static func fetchBannedList(adminToken: String, completion: @escaping ([PampGramBannedUser]) -> Void) {
        guard let url = URL(string: "\(baseURL)/banned-list") else {
            completion([])
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(BannedListRequestBody(token: adminToken))

        URLSession.shared.dataTask(with: request) { data, _, _ in
            var users: [PampGramBannedUser] = []
            if let data, let decoded = try? JSONDecoder().decode(BannedListResponse.self, from: data) {
                users = decoded.users
            }
            DispatchQueue.main.async {
                completion(users)
            }
        }.resume()
    }

    private struct GenerateKeyRequestBody: Encodable {
        let token: String
        let tier: String
        let durationHours: Double?
    }

    private struct GenerateKeyResponse: Decodable {
        let ok: Bool
        let key: String?
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
        request.httpBody = try? JSONEncoder().encode(GenerateKeyRequestBody(token: adminToken, tier: tier.rawValue, durationHours: durationHours))

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
    }

    /// Not admin-only — this is the buyer-facing half of the key system, called from any
    /// install once its owner has a key someone generated for them. Grants that key's tier
    /// (and, if the key was minted with a duration, an expiry starting now) to `userId` (this
    /// device's own account, always) exactly like an admin's `grantTier` would, and the key is
    /// gone the moment the server accepts it — a second redemption attempt with the same
    /// string, from this device or any other, fails exactly like an unknown key would.
    /// `completion` reports the granted status on success, `nil` on any failure (network, an
    /// already-used/unknown key, or a malformed response).
    public static func redeemKey(userId: Int64, key: String, completion: @escaping (PampGramSubscriptionStatus?) -> Void) {
        guard let url = URL(string: "\(baseURL)/redeem-key") else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(RedeemKeyRequestBody(id: userId, key: key))

        URLSession.shared.dataTask(with: request) { data, response, error in
            var status: PampGramSubscriptionStatus?
            if error == nil, (response as? HTTPURLResponse)?.statusCode == 200, let data, let decoded = try? JSONDecoder().decode(RedeemKeyResponse.self, from: data), let tierRaw = decoded.tier, let tier = PampGramSubscriptionTier(rawValue: tierRaw) {
                let expiresAt = decoded.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000) }
                status = PampGramSubscriptionStatus(tier: tier, expiresAt: expiresAt)
            }
            DispatchQueue.main.async {
                completion(status)
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
