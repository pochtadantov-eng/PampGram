import Foundation
import Postbox
import SwiftSignalKit

/// Entry point `AccountContextImpl.init` calls for every real account. Used to poll
/// `/ban-status` by itself and flip `PampGramSettings.bannedLocally`; that job (and the whole
/// "is this account allowed to use the app at all" question — no key, expired, banned) now
/// belongs to `PampGramAccessGate`, which reads the signed `/access` answer, locks the app
/// behind a full-screen overlay, switches every feature off through `bannedLocally`, zeroes a
/// banned account's visual balances, and watches for tampering. This type stays only so the
/// existing call site (and its signature) keep working unchanged.
///
/// Section bans (gifts / messages / ghost) are unaffected: they are still checked per section
/// by `pampGramGateSection` when that section is opened.
public final class PampGramBanEnforcer {
    public static let shared = PampGramBanEnforcer()

    private init() {
    }

    /// `userId` is the plain Telegram account id (`peerId.id._internalGetInt64Value()`);
    /// `accountKey` is kept for source compatibility with the call site and is not needed.
    public func start(accountKey: Int64, userId: Int64, postbox: Postbox) {
        PampGramAccessGate.shared.start(userId: userId, postbox: postbox)
    }
}
