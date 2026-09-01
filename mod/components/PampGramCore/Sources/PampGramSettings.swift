import Foundation
import Postbox
import SwiftSignalKit

/// One of the 5 fixed presets "Изменить голос" offers — each just a pitch (in cents) and
/// playback-rate pair fed to `AVAudioUnitTimePitch`. Deliberately simple, honestly-named
/// pitch/tempo changes rather than a claim of true voice conversion (a robot-style ring
/// modulator or a real vocoder is a different, much bigger feature).
public enum PampGramVoicePreset: String, CaseIterable {
    case male
    case female
    case child
    case robot
    case giant

    public var displayName: String {
        switch self {
        case .male: return "Мужской"
        case .female: return "Женский"
        case .child: return "Ребёнок"
        case .robot: return "Робот"
        case .giant: return "Великан"
        }
    }

    /// Cents to feed `AVAudioUnitTimePitch.pitch` (±2400 is the unit's own range).
    public var pitchCents: Float {
        switch self {
        case .male: return -500
        case .female: return 500
        case .child: return 750
        case .robot: return -150
        case .giant: return -950
        }
    }

    /// Playback-rate multiplier for the pitch unit. Kept at 1.0 for every preset on purpose:
    /// any value ≠ 1.0 changes the message's tempo (and so its duration), which read as the
    /// recording being sped up/slowed down. The presets change only pitch, never speed — the
    /// message plays back at exactly its original length.
    public var rate: Float {
        return 1.0
    }
}

/// Custom Codable conformance rather than the compiler's default raw-value synthesis: that
/// default routes through `Encoder.singleValueContainer()`/`Decoder.singleValueContainer()`,
/// which Telegram's own `PostboxEncoder`/`PostboxDecoder` (used for every PampGram settings
/// write, via `PreferencesEntry`) does not implement — it's a hard `preconditionFailure()`
/// there. A keyed container with one field is the encoding this coder actually supports.
extension PampGramVoicePreset: Codable {
    private enum CodingKeys: String, CodingKey {
        case value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(String.self, forKey: .value)
        self = PampGramVoicePreset(rawValue: raw) ?? .male
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.rawValue, forKey: .value)
    }
}

/// A profile for "Ускорение загрузки"/"Ускорение скачивания" — how aggressively PampGram
/// asks Telegram's own upload/download machinery to parallelize file transfers. Never
/// invents bandwidth that isn't there and never exceeds what the app's real code already
/// uses elsewhere (`increaseParallelParts`/`useLargerParts` is the exact profile Telegram's
/// own history-import already opts into) — this only decides how often that existing lever
/// gets pulled.
public enum PampGramSpeedMode: String, CaseIterable {
    case standard
    case fast
    case turbo

    public var displayName: String {
        switch self {
        case .standard: return "Стандарт"
        case .fast: return "Быстрый"
        case .turbo: return "Турбо"
        }
    }
}

/// See `PampGramVoicePreset`'s matching extension for why this can't use the compiler's
/// default raw-value Codable synthesis.
extension PampGramSpeedMode: Codable {
    private enum CodingKeys: String, CodingKey {
        case value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(String.self, forKey: .value)
        self = PampGramSpeedMode(rawValue: raw) ?? .standard
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.rawValue, forKey: .value)
    }
}

/// In-memory, per-launch record of which peers this account has *actively* messaged in the
/// current app session. Feeds the Ghost "Читать при действиях" option: once you've sent a
/// message into a chat you've already revealed your presence there, so suppressing your read
/// receipts for that one chat stops being useful — the receipt is allowed through again. Kept
/// in memory on purpose (not in Postbox): it's a session-scoped signal, resets cleanly on
/// relaunch, and never grows a persisted list. Read from the read-state push hook, written
/// from the outgoing-message enqueue hook — both in the same app process.
public final class PampGramGhostRuntime {
    public static let shared = PampGramGhostRuntime()

    private let actedPeerIds = Atomic<Set<Int64>>(value: Set())

    private init() {}

    public func markActed(peerId: Int64) {
        let _ = self.actedPeerIds.modify { current in
            var current = current
            current.insert(peerId)
            return current
        }
    }

    public func hasActed(peerId: Int64) -> Bool {
        return self.actedPeerIds.with { $0.contains(peerId) }
    }
}

/// Every PampGram feature is a *local* one: it changes what this device shows its own
/// owner, and nothing else. Nothing in this module — or in anything that reads it — sends
/// data to Telegram, alters another account's state, touches real Stars or real Gifts, or
/// bypasses a payment. Settings therefore live entirely in this account's own Postbox, in
/// a key range reserved for the mod, and are never synced to the account manager or to any
/// server-backed preferences.
public struct PampGramSettings: Codable, Equatable {
    /// Shows the clearly-labelled "Фантом" tab inside the real gift-sending screen.
    public var phantomGiftsEnabled: Bool
    /// The mod's own play-money Stars counter, spent by Phantom Gifts. Completely unrelated
    /// to `StarsContext` / the real Telegram Stars balance, which PampGram never reads,
    /// writes, or displays in its place.
    public var fakeStarsBalance: Int64
    /// The mod's own play-money TON counter, in nanotons, for symmetry with the Stars one.
    /// Display only — PampGram has no wallet and moves no crypto.
    public var fakeTonBalanceNanos: Int64
    /// Whether `fakeStarsBalance` is what's *displayed* in place of the real Stars balance
    /// (gift-sending screen, Settings row, the Stars balance screen). Independent of
    /// `phantomGiftsEnabled`: the "Подарок" tab and its spending can stay on with this off,
    /// or vice versa — this toggle only ever affects what a number on screen reads, never
    /// what gets spent.
    public var fakeStarsDisplayEnabled: Bool
    /// Same as `fakeStarsDisplayEnabled`, but for `fakeTonBalanceNanos` in place of the real
    /// TON/GRAM balance. Independent of the Stars one on purpose, so either currency can be
    /// faked on its own.
    public var fakeTonDisplayEnabled: Bool
    /// Whether a message deleted by the other side is kept, visibly marked, in this chat's
    /// history instead of vanishing. Purely local: it never tells Telegram, or the person who
    /// deleted it, that a copy was kept.
    public var antiDeleteMessagesEnabled: Bool
    /// Legacy Ghost toggles, kept only so old stored settings still decode and can be
    /// migrated. The Ghost section is now the granular `ghostMode*` set below; `init(from:)`
    /// maps a previously-on `ghostReaderEnabled` into the new fields once. Nothing reads
    /// these two directly any more.
    public var ghostReaderEnabled: Bool
    public var onlineMaskEnabled: Bool

    /// "Режим призрака" master switch (Ghost section). When off, every `ghostMode*` feature
    /// below is inert regardless of its own toggle — the section's single on/off gate, exactly
    /// like the header switch in the screen. Each feature only suppresses *this* account's own
    /// outgoing signals (read receipts, story views, typing, presence); nothing here reads or
    /// stores anyone else's data.
    public var ghostModeEnabled: Bool
    /// "Не читать сообщения": withhold the outgoing "read up to here" sync that drives the
    /// other side's read-receipt checkmarks. Local read state (badges, this device's own
    /// "read" UI) is untouched. Honored per-peer through the exception set below.
    public var ghostHideReadReceipts: Bool
    /// "Не читать истории": withhold the outgoing "story seen" sync, so viewing someone's
    /// story doesn't add this account to their viewer list. Honored per-peer.
    public var ghostHideStoryViews: Bool
    /// "Не отправлять «онлайн»": never broadcast an online presence, even while the app is
    /// open in the foreground. Presence is a single global account signal, so this (and
    /// `ghostAutoOffline`) are not per-peer — the exception set doesn't apply to them.
    public var ghostHideOnline: Bool
    /// "Не отправлять «печатает»": withhold every outgoing activity ping — typing, choosing a
    /// sticker, recording voice/video, upload progress. Honored per-peer.
    public var ghostHideTyping: Bool
    /// "Автоматический «офлайн»": drop the background-online window — go offline the moment
    /// the app leaves the foreground, instead of the usual short keep-alive. Global, like
    /// `ghostHideOnline`.
    public var ghostAutoOffline: Bool
    /// "Читать при действиях": once you've sent a message into a chat this session (tracked in
    /// `PampGramGhostRuntime`), stop hiding your read receipts *for that chat* — you've already
    /// revealed you're there. Only relaxes `ghostHideReadReceipts`, nothing else.
    public var ghostReadOnAction: Bool
    /// Exceptions — "Все каналы": Ghost's per-peer suppression skips broadcast channels.
    public var ghostExcludeAllChannels: Bool
    /// Exceptions — "Все группы": Ghost's per-peer suppression skips groups/supergroups.
    public var ghostExcludeAllGroups: Bool
    /// Exceptions — "Папки": chat-folder ids whose explicitly-included chats Ghost skips.
    public var ghostExcludedFolderIds: [Int32]
    /// Exceptions — "Добавить исключение": individual chats Ghost skips.
    public var ghostExcludedPeerIds: [PeerId]
    /// Chats excluded from "Восстановление удалённых сообщений": a message deleted by the
    /// other side in one of these chats is left alone (normal Telegram behavior), instead of
    /// being kept and shown like every other chat's deletions are. Checked by
    /// `PampGramDeletedMessageCapture.captureBeforeDelete` per message's `peerId`.
    public var antiDeleteExcludedPeerIds: [PeerId]
    /// "Изменить визуально": lets the long-press menu on a message from the other side offer
    /// "PampGram" → "Изменить визуально", rewriting that message's text as stored in this
    /// device's own Postbox. Purely local — the edit is never sent, and the sender's copy is
    /// untouched; the bubble carries a small pencil badge (`PampGramVisualEditAttribute`) so
    /// it stays distinguishable from what they actually sent.
    public var visualEditEnabled: Bool
    /// "От него": shows a 5th tab ("Подарок мне") next to the "Подарок ему" tab in the real
    /// gift-sending screen — the same real market, but a purchase from it inserts the
    /// message as if the *other* side bought and sent the gift, not this account. Nothing is
    /// deducted from any local balance: nobody "spent" anything in this direction.
    public var fromHimGiftsEnabled: Bool
    /// "Изменить голос" (Дополнительно): pitch-shifts an outgoing voice message, offline,
    /// after recording finishes and before it's attached to the message — never touches
    /// live call audio (see `voicePreset` for which of the 5 presets is applied).
    public var voiceChangerMessagesEnabled: Bool
    public var voicePreset: PampGramVoicePreset
    /// "Ускорение загрузки"/"Ускорение скачивания" (Дополнительно): how many parts Telegram's
    /// own upload/download code is allowed to run in parallel, and how large each part is —
    /// tuning existing, already-used parameters, never a claim of more bandwidth than the
    /// connection actually has.
    public var uploadSpeedMode: PampGramSpeedMode
    public var downloadSpeedMode: PampGramSpeedMode
    /// "Фейковая геолокация" (Дополнительно): when sending a one-time location pin, substitute
    /// this coordinate for the real GPS one. Only affects a plain location share — live
    /// (continuously-updating) location sharing is untouched, since faking a moving position
    /// safely would mean patching the GPS-consuming layer itself, not just one send call.
    public var fakeLocationEnabled: Bool
    public var fakeLocationLatitude: Double
    public var fakeLocationLongitude: Double
    /// "Блокировка чатов" (Дополнительно): a single local PIN gating specific chats, checked
    /// once at `navigateToChatControllerImpl` before the real chat ever opens — not Telegram's
    /// own Secret Chats or app passcode, just an extra local step before this device shows one
    /// of the chats in `lockedChatPeerIds`.
    public var chatLockEnabled: Bool
    public var chatLockPin: String
    public var lockedChatPeerIds: [PeerId]
    /// "Закрепить чаты" (Дополнительно): bypass the client-side pinned-chats limit so more than
    /// the usual 5/10 chats can be pinned. Client-side only — Telegram's server keeps its own
    /// limit, so pins beyond it may not sync to other devices, but on this device they pin.
    public var infinitePinsEnabled: Bool
    /// "Легальный премиум" (Дополнительно): flip on the client-side-only premium unlocks that
    /// Telegram never verifies server-side — a locally-shown Premium badge/status, premium
    /// stickers & reactions in the picker, and the relaxed folder/pin client limits.
    public var legalPremiumEnabled: Bool
    /// "Локальные рубли" (Подарки): a play-money ruble balance — a local "card" — spent by
    /// PampGram's own fake "Купить звёзды" screen (see `PampGramStarsPurchaseScreen.swift`)
    /// instead of the real Apple In-App Purchase flow when `localRublesPurchaseEnabled` is
    /// on. In kopecks (1/100 ruble), same reasoning as `fakeTonBalanceNanos` being in
    /// nanotons: keeps arithmetic exact without floating point.
    public var localRublesBalanceKopecks: Int64
    public var localRublesPurchaseEnabled: Bool

    public static let defaultFakeStarsBalance: Int64 = 50_000
    public static let defaultFakeTonBalanceNanos: Int64 = 0

    public static var defaultSettings: PampGramSettings {
        return PampGramSettings(
            phantomGiftsEnabled: true,
            fakeStarsBalance: defaultFakeStarsBalance,
            fakeTonBalanceNanos: defaultFakeTonBalanceNanos,
            fakeStarsDisplayEnabled: true,
            fakeTonDisplayEnabled: true,
            antiDeleteMessagesEnabled: true,
            ghostReaderEnabled: false,
            onlineMaskEnabled: false,
            ghostModeEnabled: false,
            ghostHideReadReceipts: false,
            ghostHideStoryViews: false,
            ghostHideOnline: false,
            ghostHideTyping: false,
            ghostAutoOffline: false,
            ghostReadOnAction: false,
            ghostExcludeAllChannels: false,
            ghostExcludeAllGroups: false,
            ghostExcludedFolderIds: [],
            ghostExcludedPeerIds: [],
            antiDeleteExcludedPeerIds: [],
            visualEditEnabled: false,
            fromHimGiftsEnabled: false,
            voiceChangerMessagesEnabled: false,
            voicePreset: .male,
            uploadSpeedMode: .standard,
            downloadSpeedMode: .standard,
            fakeLocationEnabled: false,
            fakeLocationLatitude: 0,
            fakeLocationLongitude: 0,
            chatLockEnabled: false,
            chatLockPin: "",
            lockedChatPeerIds: [],
            localRublesBalanceKopecks: 0,
            localRublesPurchaseEnabled: false,
            infinitePinsEnabled: false,
            legalPremiumEnabled: false
        )
    }

    public init(phantomGiftsEnabled: Bool, fakeStarsBalance: Int64, fakeTonBalanceNanos: Int64, fakeStarsDisplayEnabled: Bool, fakeTonDisplayEnabled: Bool, antiDeleteMessagesEnabled: Bool, ghostReaderEnabled: Bool, onlineMaskEnabled: Bool, ghostModeEnabled: Bool, ghostHideReadReceipts: Bool, ghostHideStoryViews: Bool, ghostHideOnline: Bool, ghostHideTyping: Bool, ghostAutoOffline: Bool, ghostReadOnAction: Bool, ghostExcludeAllChannels: Bool, ghostExcludeAllGroups: Bool, ghostExcludedFolderIds: [Int32], ghostExcludedPeerIds: [PeerId], antiDeleteExcludedPeerIds: [PeerId], visualEditEnabled: Bool, fromHimGiftsEnabled: Bool, voiceChangerMessagesEnabled: Bool, voicePreset: PampGramVoicePreset, uploadSpeedMode: PampGramSpeedMode, downloadSpeedMode: PampGramSpeedMode, fakeLocationEnabled: Bool, fakeLocationLatitude: Double, fakeLocationLongitude: Double, chatLockEnabled: Bool, chatLockPin: String, lockedChatPeerIds: [PeerId], localRublesBalanceKopecks: Int64, localRublesPurchaseEnabled: Bool, infinitePinsEnabled: Bool, legalPremiumEnabled: Bool) {
        self.phantomGiftsEnabled = phantomGiftsEnabled
        self.fakeStarsBalance = fakeStarsBalance
        self.fakeTonBalanceNanos = fakeTonBalanceNanos
        self.fakeStarsDisplayEnabled = fakeStarsDisplayEnabled
        self.fakeTonDisplayEnabled = fakeTonDisplayEnabled
        self.antiDeleteMessagesEnabled = antiDeleteMessagesEnabled
        self.ghostReaderEnabled = ghostReaderEnabled
        self.onlineMaskEnabled = onlineMaskEnabled
        self.ghostModeEnabled = ghostModeEnabled
        self.ghostHideReadReceipts = ghostHideReadReceipts
        self.ghostHideStoryViews = ghostHideStoryViews
        self.ghostHideOnline = ghostHideOnline
        self.ghostHideTyping = ghostHideTyping
        self.ghostAutoOffline = ghostAutoOffline
        self.ghostReadOnAction = ghostReadOnAction
        self.ghostExcludeAllChannels = ghostExcludeAllChannels
        self.ghostExcludeAllGroups = ghostExcludeAllGroups
        self.ghostExcludedFolderIds = ghostExcludedFolderIds
        self.ghostExcludedPeerIds = ghostExcludedPeerIds
        self.antiDeleteExcludedPeerIds = antiDeleteExcludedPeerIds
        self.visualEditEnabled = visualEditEnabled
        self.fromHimGiftsEnabled = fromHimGiftsEnabled
        self.voiceChangerMessagesEnabled = voiceChangerMessagesEnabled
        self.voicePreset = voicePreset
        self.uploadSpeedMode = uploadSpeedMode
        self.downloadSpeedMode = downloadSpeedMode
        self.fakeLocationEnabled = fakeLocationEnabled
        self.fakeLocationLatitude = fakeLocationLatitude
        self.fakeLocationLongitude = fakeLocationLongitude
        self.chatLockEnabled = chatLockEnabled
        self.chatLockPin = chatLockPin
        self.lockedChatPeerIds = lockedChatPeerIds
        self.localRublesBalanceKopecks = localRublesBalanceKopecks
        self.localRublesPurchaseEnabled = localRublesPurchaseEnabled
        self.infinitePinsEnabled = infinitePinsEnabled
        self.legalPremiumEnabled = legalPremiumEnabled
    }

    /// Decoded field by field with `decodeIfPresent` rather than by the synthesized
    /// initializer: a synthesized one throws the moment a newer PampGram adds a field, and
    /// a throw here silently resets *every* setting back to the defaults on upgrade.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = PampGramSettings.defaultSettings
        self.phantomGiftsEnabled = try container.decodeIfPresent(Bool.self, forKey: .phantomGiftsEnabled) ?? defaults.phantomGiftsEnabled
        self.fakeStarsBalance = try container.decodeIfPresent(Int64.self, forKey: .fakeStarsBalance) ?? defaults.fakeStarsBalance
        self.fakeTonBalanceNanos = try container.decodeIfPresent(Int64.self, forKey: .fakeTonBalanceNanos) ?? defaults.fakeTonBalanceNanos
        self.fakeStarsDisplayEnabled = try container.decodeIfPresent(Bool.self, forKey: .fakeStarsDisplayEnabled) ?? defaults.fakeStarsDisplayEnabled
        self.fakeTonDisplayEnabled = try container.decodeIfPresent(Bool.self, forKey: .fakeTonDisplayEnabled) ?? defaults.fakeTonDisplayEnabled
        self.antiDeleteMessagesEnabled = try container.decodeIfPresent(Bool.self, forKey: .antiDeleteMessagesEnabled) ?? defaults.antiDeleteMessagesEnabled
        self.ghostReaderEnabled = try container.decodeIfPresent(Bool.self, forKey: .ghostReaderEnabled) ?? defaults.ghostReaderEnabled
        self.onlineMaskEnabled = try container.decodeIfPresent(Bool.self, forKey: .onlineMaskEnabled) ?? defaults.onlineMaskEnabled

        // Migration: the granular Ghost fields didn't exist before. When they're all absent
        // (settings written by an older PampGram) but the old bundled "Нечиталка" was on, seed
        // the new fields from it so the feature keeps working after the update instead of
        // silently switching off. `ghostModeEnabled` being the marker key: present → new
        // settings, honor them verbatim; absent → migrate from the legacy toggle.
        if let ghostModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .ghostModeEnabled) {
            self.ghostModeEnabled = ghostModeEnabled
            self.ghostHideReadReceipts = try container.decodeIfPresent(Bool.self, forKey: .ghostHideReadReceipts) ?? defaults.ghostHideReadReceipts
            self.ghostHideStoryViews = try container.decodeIfPresent(Bool.self, forKey: .ghostHideStoryViews) ?? defaults.ghostHideStoryViews
            self.ghostHideOnline = try container.decodeIfPresent(Bool.self, forKey: .ghostHideOnline) ?? defaults.ghostHideOnline
            self.ghostHideTyping = try container.decodeIfPresent(Bool.self, forKey: .ghostHideTyping) ?? defaults.ghostHideTyping
            self.ghostAutoOffline = try container.decodeIfPresent(Bool.self, forKey: .ghostAutoOffline) ?? defaults.ghostAutoOffline
            self.ghostReadOnAction = try container.decodeIfPresent(Bool.self, forKey: .ghostReadOnAction) ?? defaults.ghostReadOnAction
        } else if self.ghostReaderEnabled {
            self.ghostModeEnabled = true
            self.ghostHideReadReceipts = true
            self.ghostHideStoryViews = true
            self.ghostHideOnline = true
            self.ghostHideTyping = true
            self.ghostAutoOffline = false
            self.ghostReadOnAction = false
        } else {
            self.ghostModeEnabled = defaults.ghostModeEnabled
            self.ghostHideReadReceipts = defaults.ghostHideReadReceipts
            self.ghostHideStoryViews = defaults.ghostHideStoryViews
            self.ghostHideOnline = defaults.ghostHideOnline
            self.ghostHideTyping = defaults.ghostHideTyping
            self.ghostAutoOffline = defaults.ghostAutoOffline
            self.ghostReadOnAction = defaults.ghostReadOnAction
        }
        self.ghostExcludeAllChannels = try container.decodeIfPresent(Bool.self, forKey: .ghostExcludeAllChannels) ?? defaults.ghostExcludeAllChannels
        self.ghostExcludeAllGroups = try container.decodeIfPresent(Bool.self, forKey: .ghostExcludeAllGroups) ?? defaults.ghostExcludeAllGroups
        self.ghostExcludedFolderIds = try container.decodeIfPresent([Int32].self, forKey: .ghostExcludedFolderIds) ?? defaults.ghostExcludedFolderIds
        self.ghostExcludedPeerIds = try container.decodeIfPresent([PeerId].self, forKey: .ghostExcludedPeerIds) ?? defaults.ghostExcludedPeerIds
        self.antiDeleteExcludedPeerIds = try container.decodeIfPresent([PeerId].self, forKey: .antiDeleteExcludedPeerIds) ?? defaults.antiDeleteExcludedPeerIds
        self.visualEditEnabled = try container.decodeIfPresent(Bool.self, forKey: .visualEditEnabled) ?? defaults.visualEditEnabled
        self.fromHimGiftsEnabled = try container.decodeIfPresent(Bool.self, forKey: .fromHimGiftsEnabled) ?? defaults.fromHimGiftsEnabled
        self.voiceChangerMessagesEnabled = try container.decodeIfPresent(Bool.self, forKey: .voiceChangerMessagesEnabled) ?? defaults.voiceChangerMessagesEnabled
        self.voicePreset = try container.decodeIfPresent(PampGramVoicePreset.self, forKey: .voicePreset) ?? defaults.voicePreset
        self.uploadSpeedMode = try container.decodeIfPresent(PampGramSpeedMode.self, forKey: .uploadSpeedMode) ?? defaults.uploadSpeedMode
        self.downloadSpeedMode = try container.decodeIfPresent(PampGramSpeedMode.self, forKey: .downloadSpeedMode) ?? defaults.downloadSpeedMode
        self.fakeLocationEnabled = try container.decodeIfPresent(Bool.self, forKey: .fakeLocationEnabled) ?? defaults.fakeLocationEnabled
        self.fakeLocationLatitude = try container.decodeIfPresent(Double.self, forKey: .fakeLocationLatitude) ?? defaults.fakeLocationLatitude
        self.fakeLocationLongitude = try container.decodeIfPresent(Double.self, forKey: .fakeLocationLongitude) ?? defaults.fakeLocationLongitude
        self.chatLockEnabled = try container.decodeIfPresent(Bool.self, forKey: .chatLockEnabled) ?? defaults.chatLockEnabled
        self.chatLockPin = try container.decodeIfPresent(String.self, forKey: .chatLockPin) ?? defaults.chatLockPin
        self.lockedChatPeerIds = try container.decodeIfPresent([PeerId].self, forKey: .lockedChatPeerIds) ?? defaults.lockedChatPeerIds
        self.localRublesBalanceKopecks = try container.decodeIfPresent(Int64.self, forKey: .localRublesBalanceKopecks) ?? defaults.localRublesBalanceKopecks
        self.localRublesPurchaseEnabled = try container.decodeIfPresent(Bool.self, forKey: .localRublesPurchaseEnabled) ?? defaults.localRublesPurchaseEnabled
        self.infinitePinsEnabled = try container.decodeIfPresent(Bool.self, forKey: .infinitePinsEnabled) ?? defaults.infinitePinsEnabled
        self.legalPremiumEnabled = try container.decodeIfPresent(Bool.self, forKey: .legalPremiumEnabled) ?? defaults.legalPremiumEnabled
    }

    /// Whether a peer is exempt from Ghost's per-peer suppression, given its type and the
    /// folder ids it belongs to. Pure and primitive-typed on purpose: it's called from hooks
    /// inside TelegramCore, which resolve `isChannel`/`isGroup`/`folderIds` from the peer and
    /// the chat filters themselves — this module can't reference those TelegramCore types.
    /// Presence (online/auto-offline) is global and never routed through here.
    public func ghostExcludesPeer(peerId: PeerId?, isChannel: Bool, isGroup: Bool, folderIds: [Int32]) -> Bool {
        if let peerId, self.ghostExcludedPeerIds.contains(peerId) {
            return true
        }
        if isChannel && self.ghostExcludeAllChannels {
            return true
        }
        if isGroup && self.ghostExcludeAllGroups {
            return true
        }
        if !self.ghostExcludedFolderIds.isEmpty && !folderIds.isEmpty {
            for folderId in folderIds where self.ghostExcludedFolderIds.contains(folderId) {
                return true
            }
        }
        return false
    }
}

/// Reserved, PampGram-private preference keys. Deliberately NOT added to the shared
/// `ApplicationSpecificPreferencesKeys` enum in TelegramUIPreferences: keeping them inside
/// the mod's own module means no chance of colliding with a real key upstream adds later,
/// and no shared file to merge-conflict on when rebasing onto a new Telegram release.
public enum PampGramPreferencesKeys {
    public static func key(_ value: Int32) -> ValueBoxKey {
        let key = ValueBoxKey(length: 4)
        key.setInt32(0, value: value)
        return key
    }

    public static let settings = key(900_000)
    public static let phantomGifts = key(900_100)
    public static let deletedMessages = key(900_200)
    public static let adminToken = key(900_300)
    public static let localOperations = key(900_400)
    public static let profileVisuals = key(900_500)
    public static let appearance = key(900_600)
    public static let behavior = key(900_700)
    public static let fakeAdmin = key(900_800)
}

public enum PampGramCore {
    public static func settings(transaction: Transaction) -> PampGramSettings {
        return transaction.getPreferencesEntry(key: PampGramPreferencesKeys.settings)?.get(PampGramSettings.self) ?? PampGramSettings.defaultSettings
    }

    public static func updateSettings(transaction: Transaction, _ f: (PampGramSettings) -> PampGramSettings) {
        let updated = f(self.settings(transaction: transaction))
        transaction.setPreferencesEntry(key: PampGramPreferencesKeys.settings, value: PreferencesEntry(updated))
    }

    /// Live settings, for screens that need to redraw when a value changes.
    public static func settingsSignal(postbox: Postbox) -> Signal<PampGramSettings, NoError> {
        return postbox.preferencesView(keys: [PampGramPreferencesKeys.settings])
        |> map { view -> PampGramSettings in
            return view.values[PampGramPreferencesKeys.settings]?.get(PampGramSettings.self) ?? PampGramSettings.defaultSettings
        }
        |> distinctUntilChanged
    }

    public static func updateSettingsInteractively(postbox: Postbox, _ f: @escaping (PampGramSettings) -> PampGramSettings) -> Signal<Never, NoError> {
        return postbox.transaction { transaction -> Void in
            self.updateSettings(transaction: transaction, f)
        }
        |> ignoreValues
    }
}
