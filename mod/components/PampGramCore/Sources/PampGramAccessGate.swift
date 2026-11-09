import Foundation
import UIKit
import Postbox
import SwiftSignalKit
import CryptoKit

/// Why the app is locked.
public enum PampGramAccessLockKind: Equatable {
    /// No verified answer from the server yet (first launch, or the server hasn't replied).
    case checking
    /// No key was ever activated (`expired == false`) or the subscription ran out.
    case needsKey(expired: Bool)
    /// Full ban from the admin.
    case banned(reason: String)
    /// The last good answer is older than the server allowed and the server can't be reached.
    case unreachable
    /// The device clock was moved back to stretch an offline answer.
    case clockTampered
    /// Daily "owner confirms you paid your percentage" gate (server state "daily_hold").
    case ownerConfirm(message: String)
}

public enum PampGramAccessState: Equatable {
    case allowed
    case locked(PampGramAccessLockKind)
}

/// The strictest state across every signed-in account, plus the account that causes it.
public struct PampGramAccessSnapshot: Equatable {
    public let state: PampGramAccessState
    public let userId: Int64?
}

/// One verified server answer, kept so the app can still decide while offline. Everything the
/// signature covers is stored, so the record is re-verified every time it is read: editing the
/// stored file (or restoring an old backup of it) gets the edit rejected, not believed.
private struct PampGramAccessRecord: Codable, Equatable {
    var userId: Int64
    var state: String
    var expiresAt: Int64?
    var serverNow: Int64
    var ttl: Int64
    var nonce: String
    var sig: String
    var reason: String?
    /// Device clock (ms) when this answer arrived.
    var receivedAt: Int64
}

/// The licence gate. PampGram is usable only while the server says the account is "active";
/// every other answer (no key, expired, banned) — and the absence of a trustworthy answer —
/// locks the whole app behind a full-screen overlay (`PampGramAccessLockOverlay`, in
/// PampGramSettingsUI) and switches every PampGram feature off.
///
/// What this defends against, and what it can't:
///  - A fake or edited server answer: answers are Ed25519-signed by the server. The app holds
///    only the PUBLIC key, so there is no secret in the binary to extract and sign with.
///  - A recorded "active" answer played back later: every request carries a fresh nonce that the
///    signature covers.
///  - Blocking the server to keep an old "active": an answer is only good for the `ttl` the
///    server signed (48 h at most, less near the subscription's end). Past that the app locks.
///  - Rolling the clock back during that window: the receive time and the highest time ever
///    seen are remembered; a clock behind either locks the app until the server is reachable.
///  - Editing local settings while locked (balances, the ban flag, the owner flag): detected,
///    undone at once, reported to the server (which escalates a banned account).
///  - Staying on an old build: bump `/set-min-version` to this build's number after shipping.
/// It can NOT stop someone who patches the app binary itself (nothing client-side can).
public final class PampGramAccessGate {
    public static let shared = PampGramAccessGate()
    public static let didChangeNotification = Notification.Name("PampGramAccessGateDidChange")

    /// Raw 32-byte Ed25519 public key, base64. Pair of the Worker's ACCESS_SIGNING_KEY secret
    /// (see server/pampgram-subs-worker/scripts/gen-access-key.mjs). Replacing it locks every
    /// build that still carries the old one.
    private static let accessPublicKeyBase64 = "msm40g3Albw0l7wNBrMaBlLKfQsWC1uJEhZEZ2E04H4="

    private static let recordsKey = "PampGram_AccessRecords_v1"
    private static let lastSeenKey = "PampGram_AccessLastSeen_v1"
    private static let clockSlackMs: Int64 = 120_000
    private static let pollIntervalMs: Int64 = 300_000
    private static let enforcementGraceSeconds: Double = 5.0
    private static let tamperReportIntervalSeconds: Double = 120.0

    private let lock = NSLock()
    private var records: [Int64: PampGramAccessRecord]
    private var lastSeenMs: Int64
    private var startedUsers: Set<Int64> = []
    private var postboxes: [Int64: Postbox] = [:]
    private var watchers: [Int64: Disposable] = [:]
    private var inFlight: Set<Int64> = []
    private var lastFetchAt: [Int64: Int64] = [:]
    private var appliedDesired: [Int64: Int] = [:]
    private var enforcedAt: [Int64: Double] = [:]
    private var lastTamperReportAt: [Int64: Double] = [:]
    private var lastPublished: PampGramAccessSnapshot?
    private var tickScheduled = false
    private var observersInstalled = false

    private init() {
        self.records = PampGramAccessGate.loadRecords()
        self.lastSeenMs = Int64(UserDefaults.standard.double(forKey: PampGramAccessGate.lastSeenKey))
    }

    // MARK: - Public

    /// The current strictest state. Safe to call from any thread, as often as needed.
    public var snapshot: PampGramAccessSnapshot {
        self.lock.lock()
        let result = self.snapshotLocked(nowMs: PampGramAccessGate.nowMs())
        self.lock.unlock()
        return result
    }

    /// Registers an account (once) and starts checking it. Called from `PampGramBanEnforcer.start`,
    /// which `AccountContextImpl.init` already calls for every real account.
    public func start(userId: Int64, postbox: Postbox) {
        self.lock.lock()
        if self.startedUsers.contains(userId) {
            self.lock.unlock()
            return
        }
        self.startedUsers.insert(userId)
        self.postboxes[userId] = postbox
        let needsObservers = !self.observersInstalled
        self.observersInstalled = true
        let needsTick = !self.tickScheduled
        self.tickScheduled = true
        self.lock.unlock()

        if needsObservers {
            NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { _ in
                PampGramAccessGate.shared.refreshNow()
            }
        }
        if needsTick {
            PampGramAccessGate.shared.scheduleTick()
        }

        self.startWatching(userId: userId, postbox: postbox)
        self.reevaluate()
        self.refresh(userId: userId)
    }

    /// Asks the server again right now, for every registered account (after a key was entered,
    /// when the app comes to the foreground, on the lock screen's "retry").
    public func refreshNow() {
        self.lock.lock()
        let users = Array(self.startedUsers)
        self.lock.unlock()
        for userId in users {
            self.refresh(userId: userId)
        }
    }

    /// The lock overlay found itself hidden/removed by something other than this code.
    public func reportOverlayTampering() {
        let userId = self.snapshot.userId
        if let userId = userId {
            self.reportTamperThrottled(userId: userId, kind: "overlay_tampered")
        }
    }

    // MARK: - Evaluation

    private static func nowMs() -> Int64 {
        return Int64(Date().timeIntervalSince1970 * 1000.0)
    }

    private static func priority(_ state: PampGramAccessState) -> Int {
        switch state {
        case .allowed:
            return 0
        case .locked(let kind):
            switch kind {
            case .checking:
                return 1
            case .unreachable:
                return 2
            case .clockTampered:
                return 3
            case .needsKey:
                return 4
            case .ownerConfirm:
                return 5
            case .banned:
                return 6
            }
        }
    }

    private static func verify(_ record: PampGramAccessRecord) -> Bool {
        return PampGramAccessGate.verifySignature(userId: record.userId, state: record.state, expiresAt: record.expiresAt, now: record.serverNow, ttl: record.ttl, nonce: record.nonce, sig: record.sig)
    }

    /// The exact string the server signs — see `accessMessage` in server/.../src/access.js.
    private static func verifySignature(userId: Int64, state: String, expiresAt: Int64?, now: Int64, ttl: Int64, nonce: String, sig: String) -> Bool {
        guard let keyData = Data(base64Encoded: PampGramAccessGate.accessPublicKeyBase64), let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData), let signature = Data(base64Encoded: sig) else {
            return false
        }
        let expiresText = expiresAt.map { String($0) } ?? "null"
        let message = "access1|\(userId)|\(state)|\(expiresText)|\(now)|\(ttl)|\(nonce)"
        return key.isValidSignature(signature, for: Data(message.utf8))
    }

    private static func evaluate(record: PampGramAccessRecord, nowMs: Int64, lastSeenMs: Int64) -> PampGramAccessState {
        guard PampGramAccessGate.verify(record) else {
            return .locked(.checking)
        }
        switch record.state {
        case "banned":
            return .locked(.banned(reason: record.reason ?? ""))
        case "none":
            return .locked(.needsKey(expired: false))
        case "expired":
            return .locked(.needsKey(expired: true))
        case "daily_hold":
            return .locked(.ownerConfirm(message: record.reason ?? ""))
        case "active":
            if nowMs < record.receivedAt - PampGramAccessGate.clockSlackMs || nowMs < lastSeenMs - PampGramAccessGate.clockSlackMs {
                return .locked(.clockTampered)
            }
            if nowMs - record.receivedAt > record.ttl {
                return .locked(.unreachable)
            }
            if let expiresAt = record.expiresAt {
                // Server time, extrapolated with elapsed device time: the subscription's end is
                // judged against the server's clock, not the (movable) device calendar.
                let estimatedServerNow = record.serverNow + (nowMs - record.receivedAt)
                if estimatedServerNow >= expiresAt {
                    return .locked(.needsKey(expired: true))
                }
            }
            return .allowed
        default:
            return .locked(.checking)
        }
    }

    private func stateLocked(userId: Int64, nowMs: Int64) -> PampGramAccessState {
        if userId == PampGramSubscriptionAPI.adminAccountId {
            return .allowed
        }
        if let record = self.records[userId] {
            return PampGramAccessGate.evaluate(record: record, nowMs: nowMs, lastSeenMs: self.lastSeenMs)
        }
        return .locked(.checking)
    }

    private func snapshotLocked(nowMs: Int64) -> PampGramAccessSnapshot {
        var knownIds = Set(self.records.keys)
        knownIds.formUnion(self.startedUsers)
        var best = PampGramAccessSnapshot(state: .allowed, userId: nil)
        var bestPriority = 0
        for userId in knownIds.sorted() {
            let state = self.stateLocked(userId: userId, nowMs: nowMs)
            let priority = PampGramAccessGate.priority(state)
            if priority > bestPriority {
                best = PampGramAccessSnapshot(state: state, userId: userId)
                bestPriority = priority
            }
        }
        return best
    }

    // MARK: - Network

    private static func makeNonce() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        var result = ""
        for _ in 0 ..< 24 {
            result.append(alphabet[Int.random(in: 0 ..< alphabet.count)])
        }
        return result
    }

    private func refresh(userId: Int64) {
        if userId == PampGramSubscriptionAPI.adminAccountId {
            return
        }
        self.lock.lock()
        if self.inFlight.contains(userId) {
            self.lock.unlock()
            return
        }
        self.inFlight.insert(userId)
        self.lastFetchAt[userId] = PampGramAccessGate.nowMs()
        self.lock.unlock()

        let nonce = PampGramAccessGate.makeNonce()
        PampGramSubscriptionAPI.fetchAccess(userId: userId, nonce: nonce, completion: { response in
            PampGramAccessGate.shared.handle(userId: userId, nonce: nonce, response: response)
        })
    }

    private func handle(userId: Int64, nonce: String, response: PampGramSubscriptionAPI.PampGramAccessResponse?) {
        let nowMs = PampGramAccessGate.nowMs()
        self.lock.lock()
        self.inFlight.remove(userId)
        if let response = response, response.nonce == nonce, PampGramAccessGate.verifySignature(userId: userId, state: response.state, expiresAt: response.expiresAt, now: response.now, ttl: response.ttl, nonce: response.nonce, sig: response.sig) {
            let record = PampGramAccessRecord(userId: userId, state: response.state, expiresAt: response.expiresAt, serverNow: response.now, ttl: response.ttl, nonce: response.nonce, sig: response.sig, reason: response.reason, receivedAt: nowMs)
            self.records[userId] = record
            // A fresh, verified answer is proof of the real time: it resets the clock guard.
            self.lastSeenMs = nowMs
            self.persistLocked()
        }
        // An unverifiable or missing answer changes nothing: whatever the stored record says
        // (or "checking" when there is none) stays in force — never "allowed" by default.
        self.lock.unlock()
        self.reevaluate()
    }

    // MARK: - Enforcement

    /// 0 = leave alone, 1 = unlock, 2 = lock, 3 = lock and zero the balances (banned).
    private static func desiredAction(_ state: PampGramAccessState) -> Int {
        switch state {
        case .allowed:
            return 1
        case .locked(let kind):
            switch kind {
            case .checking, .unreachable:
                return 0
            case .needsKey, .clockTampered, .ownerConfirm:
                return 2
            case .banned:
                return 3
            }
        }
    }

    /// Recomputes every account's state, applies it to the settings, and tells the overlay.
    private func reevaluate() {
        let nowMs = PampGramAccessGate.nowMs()
        self.lock.lock()
        if nowMs > self.lastSeenMs {
            self.lastSeenMs = nowMs
            UserDefaults.standard.set(Double(nowMs), forKey: PampGramAccessGate.lastSeenKey)
        }
        let users = Array(self.startedUsers)
        var actions: [(Int64, Int)] = []
        for userId in users {
            let action = PampGramAccessGate.desiredAction(self.stateLocked(userId: userId, nowMs: nowMs))
            if self.appliedDesired[userId] != action {
                actions.append((userId, action))
            }
        }
        let current = self.snapshotLocked(nowMs: nowMs)
        let changed = self.lastPublished != current
        self.lastPublished = current
        self.lock.unlock()

        for (userId, action) in actions {
            self.applyEnforcement(userId: userId, action: action)
        }
        if changed {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: PampGramAccessGate.didChangeNotification, object: nil)
            }
        }
    }

    private func applyEnforcement(userId: Int64, action: Int) {
        self.lock.lock()
        let postbox = self.postboxes[userId]
        self.appliedDesired[userId] = action
        self.lock.unlock()
        guard let postbox = postbox else {
            return
        }
        let isAdmin = userId == PampGramSubscriptionAPI.adminAccountId
        let transactionSignal = postbox.transaction { transaction -> Void in
            let raw = PampGramCore.rawSettings(transaction: transaction)
            if PampGramAccessGate.needsEnforcement(raw: raw, action: action, isAdmin: isAdmin) {
                PampGramCore.updateSettings(transaction: transaction, { settings in
                    return PampGramAccessGate.enforced(settings, action: action, isAdmin: isAdmin)
                })
            }
        }
        let _ = (transactionSignal |> deliverOn(Queue.concurrentDefaultQueue())).start(next: { _ in
            PampGramAccessGate.shared.noteEnforced(userId: userId, locked: action >= 2)
        })
    }

    /// Kept out of the transaction closure on purpose: the Swift 6.4 optimizer crashed
    /// ("cannot get borrow introducers", SimplifyCFG) on this logic when it was written inline
    /// as a guard/early-return over the large settings struct.
    @inline(never)
    private static func needsEnforcement(raw: PampGramSettings, action: Int, isAdmin: Bool) -> Bool {
        if raw.isOwnerAccount && !isAdmin {
            return true
        }
        if action == 1 {
            return raw.bannedLocally
        }
        if action >= 2 && !raw.bannedLocally {
            return true
        }
        if action == 3 {
            return raw.fakeStarsBalance != 0 || raw.fakeTonBalanceNanos != 0 || raw.localRublesBalanceKopecks != 0
        }
        return false
    }

    @inline(never)
    private static func enforced(_ settings: PampGramSettings, action: Int, isAdmin: Bool) -> PampGramSettings {
        var result = settings
        // The owner flag is only ever legitimate on the admin's own account; a copy of it on
        // any other account means the stored settings were edited.
        if result.isOwnerAccount && !isAdmin {
            result.isOwnerAccount = false
        }
        if action == 1 {
            result.bannedLocally = false
        } else if action >= 2 {
            result.bannedLocally = true
        }
        if action == 3 {
            result.fakeStarsBalance = 0
            result.fakeTonBalanceNanos = 0
            result.localRublesBalanceKopecks = 0
        }
        return result
    }

    private func noteEnforced(userId: Int64, locked: Bool) {
        self.lock.lock()
        if locked {
            self.enforcedAt[userId] = Date().timeIntervalSince1970
        } else {
            self.enforcedAt[userId] = nil
        }
        self.lock.unlock()
    }

    // MARK: - Tamper watch

    private func startWatching(userId: Int64, postbox: Postbox) {
        if userId == PampGramSubscriptionAPI.adminAccountId {
            return
        }
        let disposable = (PampGramCore.rawSettingsSignal(postbox: postbox)
        |> deliverOn(Queue.concurrentDefaultQueue())).start(next: { raw in
            PampGramAccessGate.shared.inspect(userId: userId, raw: raw)
        })
        self.lock.lock()
        self.watchers[userId] = disposable
        self.lock.unlock()
    }

    private static func violationKind(state: PampGramAccessState, raw: PampGramSettings, userId: Int64) -> String? {
        if raw.isOwnerAccount && userId != PampGramSubscriptionAPI.adminAccountId {
            return "owner_flag_forged"
        }
        guard case .locked(let kind) = state else {
            return nil
        }
        switch kind {
        case .checking, .unreachable:
            return nil
        case .banned:
            if !raw.bannedLocally {
                return "settings_unlocked"
            }
            if raw.fakeStarsBalance != 0 || raw.fakeTonBalanceNanos != 0 || raw.localRublesBalanceKopecks != 0 {
                return "balance_edit"
            }
            return nil
        case .needsKey, .clockTampered, .ownerConfirm:
            if !raw.bannedLocally {
                return "settings_unlocked"
            }
            return nil
        }
    }

    /// Runs on every change of the stored settings. While the app is locked the settings screens
    /// are unreachable, so a change that undoes the lock (or touches a banned account's balance)
    /// didn't come from the UI: put it back and tell the server.
    private func inspect(userId: Int64, raw: PampGramSettings) {
        let nowMs = PampGramAccessGate.nowMs()
        self.lock.lock()
        let state = self.stateLocked(userId: userId, nowMs: nowMs)
        let enforcedTime = self.enforcedAt[userId]
        self.lock.unlock()

        guard let kind = PampGramAccessGate.violationKind(state: state, raw: raw, userId: userId) else {
            return
        }
        // Undo it right away (idempotent: once fixed, this function finds nothing next time).
        self.applyEnforcement(userId: userId, action: PampGramAccessGate.desiredAction(state))

        var graceElapsed = false
        if let enforcedTime = enforcedTime {
            graceElapsed = Date().timeIntervalSince1970 - enforcedTime > PampGramAccessGate.enforcementGraceSeconds
        }
        // Our own write needs a moment to reach the signal; only a change that shows up well
        // after the lock was applied counts. A forged owner flag has no such excuse.
        if kind == "owner_flag_forged" || graceElapsed {
            self.reportTamperThrottled(userId: userId, kind: kind)
        }
    }

    private func reportTamperThrottled(userId: Int64, kind: String) {
        let nowT = Date().timeIntervalSince1970
        self.lock.lock()
        let last = self.lastTamperReportAt[userId] ?? 0
        let shouldReport = nowT - last > PampGramAccessGate.tamperReportIntervalSeconds
        if shouldReport {
            self.lastTamperReportAt[userId] = nowT
        }
        self.lock.unlock()
        if shouldReport {
            PampGramSubscriptionAPI.reportTamper(userId: userId, kind: kind)
            // The server may just have escalated the ban; look again soon.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3.0) {
                PampGramAccessGate.shared.refreshNow()
            }
        }
    }

    // MARK: - Ticking and storage

    private func scheduleTick() {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 20.0) {
            PampGramAccessGate.shared.tick()
            PampGramAccessGate.shared.scheduleTick()
        }
    }

    private func tick() {
        let nowMs = PampGramAccessGate.nowMs()
        self.lock.lock()
        let due = self.startedUsers.filter { nowMs - (self.lastFetchAt[$0] ?? 0) >= PampGramAccessGate.pollIntervalMs }
        self.lock.unlock()
        for userId in due {
            self.refresh(userId: userId)
        }
        self.reevaluate()
    }

    private static func loadRecords() -> [Int64: PampGramAccessRecord] {
        guard let data = UserDefaults.standard.data(forKey: PampGramAccessGate.recordsKey), let list = try? JSONDecoder().decode([PampGramAccessRecord].self, from: data) else {
            return [:]
        }
        var result: [Int64: PampGramAccessRecord] = [:]
        for record in list {
            result[record.userId] = record
        }
        return result
    }

    private func persistLocked() {
        let list = Array(self.records.values)
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: PampGramAccessGate.recordsKey)
        }
        UserDefaults.standard.set(Double(self.lastSeenMs), forKey: PampGramAccessGate.lastSeenKey)
    }
}
