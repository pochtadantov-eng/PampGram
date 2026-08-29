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
