import Foundation
import Postbox
import SwiftSignalKit

/// The one PampGram feature with an actual server behind it. Every other file in this module
/// changes only what this device shows its own owner — but a subscription an admin grants has
/// to show up on the *other* person's device too, and there is no way to make that true
/// without a server both copies of the app can ask. See `server/pampgram-subs-worker/` at the
/// repo root for that server's source and deployment instructions.
public enum PampGramSubscriptionTier: String, Codable {
    case standard
    case pro
}

/// What redeeming an activation key came back as — see `PampGramSubscriptionAPI.redeemKey`.
public enum PampGramKeyRedeemResult {
    case success(PampGramSubscriptionTier)
    case alreadyUsed
    case invalidKey
    case networkError
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
    private static let baseURL = "https://pampgram-subs.pampgram-pochtadantov.workers.dev"

    private struct StatusResponse: Decodable {
        let tier: String
    }

    private struct GrantRequestBody: Encodable {
        let id: Int64
        let tier: String
        let token: String
    }

    /// Live-ish (one-shot per subscription) read of `userId`'s tier. Never fails outward:
    /// any network problem, bad response, or the baseURL placeholder still being unfilled all
    /// resolve to `.standard` — the safe default — rather than erroring the screen that asked.
    public static func fetchTier(userId: Int64) -> Signal<PampGramSubscriptionTier, NoError> {
        return Signal { subscriber in
            guard let url = URL(string: "\(baseURL)/status?id=\(userId)") else {
                subscriber.putNext(.standard)
                subscriber.putCompletion()
                return EmptyDisposable
            }
            let task = URLSession.shared.dataTask(with: url) { data, _, _ in
                var tier: PampGramSubscriptionTier = .standard
                if let data, let decoded = try? JSONDecoder().decode(StatusResponse.self, from: data) {
                    tier = PampGramSubscriptionTier(rawValue: decoded.tier) ?? .standard
                }
                subscriber.putNext(tier)
                subscriber.putCompletion()
            }
            task.resume()
            return ActionDisposable {
                task.cancel()
            }
        }
    }

    private struct LicenseStatusResponse: Decodable {
        let licensed: Bool
    }

    /// Whether `userId` has redeemed an activation key, as the server sees it. Never fails
    /// outward, same contract as `fetchTier`/`fetchBanStatus`: any network or decode problem
    /// resolves to `false` — the caller (the hub screen) only ever *shows* the activation
    /// screen off the back of an explicit server answer, never because a request happened to
    /// fail; the locally-cached `PampGramSettings.licenseActivated` flag, once set to true, is
    /// never cleared by this call coming back false.
    public static func fetchLicenseStatus(userId: Int64) -> Signal<Bool, NoError> {
        return Signal { subscriber in
            guard let url = URL(string: "\(baseURL)/license-status?id=\(userId)") else {
                subscriber.putNext(false)
                subscriber.putCompletion()
                return EmptyDisposable
            }
            let task = URLSession.shared.dataTask(with: url) { data, _, _ in
                var licensed = false
                if let data, let decoded = try? JSONDecoder().decode(LicenseStatusResponse.self, from: data) {
                    licensed = decoded.licensed
                }
                subscriber.putNext(licensed)
                subscriber.putCompletion()
            }
            task.resume()
            return ActionDisposable {
                task.cancel()
            }
        }
    }

    private struct RedeemKeyRequestBody: Encodable {
        let key: String
        let id: Int64
    }

    private struct RedeemKeyResponse: Decodable {
        let ok: Bool?
        let tier: String?
        let error: String?
    }

    /// Redeems a one-time activation key for `userId` — the buyer's own action, no admin token
    /// involved. First account to redeem a given key keeps it; every other account trying the
    /// same key afterwards gets `.alreadyUsed`. On `.success`, the caller is expected to set
    /// `PampGramSettings.licenseActivated = true` (see `PampGramActivationScreen.swift`) — this
    /// call only talks to the server, it never touches local storage itself.
    public static func redeemKey(key: String, userId: Int64, completion: @escaping (PampGramKeyRedeemResult) -> Void) {
        guard let url = URL(string: "\(baseURL)/keys/redeem") else {
            completion(.networkError)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(RedeemKeyRequestBody(key: key, id: userId))

        URLSession.shared.dataTask(with: request) { data, response, error in
            let result: PampGramKeyRedeemResult
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            let decoded = data.flatMap { try? JSONDecoder().decode(RedeemKeyResponse.self, from: $0) }
            if error != nil || (statusCode == nil && decoded == nil) {
                result = .networkError
            } else if decoded?.ok == true {
                result = .success(decoded?.tier.flatMap(PampGramSubscriptionTier.init(rawValue:)) ?? .standard)
            } else if statusCode == 409 {
                result = .alreadyUsed
            } else {
                result = .invalidKey
            }
            DispatchQueue.main.async {
                completion(result)
            }
        }.resume()
    }

    private struct GenerateKeyRequestBody: Encodable {
        let token: String
        let tier: String
    }

    private struct GenerateKeyResponse: Decodable {
        let key: String?
    }

    /// Admin-only: mints one new, unused activation key for the given tier. Returns `nil` on
    /// any failure (bad token, network problem, server error) rather than a partial key.
    public static func generateKey(tier: PampGramSubscriptionTier, adminToken: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "\(baseURL)/keys/generate") else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(GenerateKeyRequestBody(token: adminToken, tier: tier.rawValue))

        URLSession.shared.dataTask(with: request) { data, _, _ in
            let key = data.flatMap { try? JSONDecoder().decode(GenerateKeyResponse.self, from: $0) }?.key
            DispatchQueue.main.async {
                completion(key)
            }
        }.resume()
    }

    /// Admin-only: sets `userId`'s tier on the server. Called only from the admin screen,
    /// which is itself only ever shown to `adminAccountId`. `adminToken` is read from this
    /// device's local storage (see `adminToken(transaction:)`/`setAdminToken`) — never a
    /// source-code constant. `completion` reports whether the server actually accepted it,
    /// always dispatched on the main queue.
    public static func grantTier(userId: Int64, tier: PampGramSubscriptionTier, adminToken: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(baseURL)/grant") else {
            completion(false)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(GrantRequestBody(id: userId, tier: tier.rawValue, token: adminToken))

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
