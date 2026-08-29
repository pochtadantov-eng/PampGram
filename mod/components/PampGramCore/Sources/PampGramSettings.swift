import Foundation
import Postbox
import SwiftSignalKit

/// One of the 5 fixed presets "Изменить голос" offers — each just a pitch (in cents) and
/// playback-rate pair fed to `AVAudioUnitTimePitch`. Deliberately simple, honestly-named
/// pitch/tempo changes rather than a claim of true voice conversion (a robot-style ring
/// modulator or a real vocoder is a different, much bigger feature).
public enum PampGramVoicePreset: String, Codable, CaseIterable {
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

    /// Playback-rate multiplier for the same unit — a small tempo shift alongside the pitch
    /// one reads as a more distinct "voice" than pitch alone.
    public var rate: Float {
        switch self {
        case .male: return 0.97
        case .female: return 1.04
        case .child: return 1.12
        case .robot: return 0.92
        case .giant: return 0.85
        }
    }
}

/// A profile for "Ускорение загрузки"/"Ускорение скачивания" — how aggressively PampGram
/// asks Telegram's own upload/download machinery to parallelize file transfers. Never
/// invents bandwidth that isn't there and never exceeds what the app's real code already
/// uses elsewhere (`increaseParallelParts`/`useLargerParts` is the exact profile Telegram's
/// own history-import already opts into) — this only decides how often that existing lever
/// gets pulled.
public enum PampGramSpeedMode: String, Codable, CaseIterable {
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
    /// "Нечиталка" (Ghost section): suppresses every outgoing activity signal this account
    /// would otherwise send to the people it talks to — read receipts, online/last-seen,
    /// typing, and recording/uploading indicators — while the local UI keeps working exactly
    /// as normal (messages still show as read locally, badges still clear). Mutually
    /// exclusive with `onlineMaskEnabled`: enabling one turns the other off, since "never
    /// online" and "always online" can't both be true.
    public var ghostReaderEnabled: Bool
    /// "Маскировка онлайна" (Ghost section): the opposite of `ghostReaderEnabled`'s presence
    /// half — keeps broadcasting "online" as persistently as the OS lets the app run, instead
    /// of going offline when backgrounded. Mutually exclusive with `ghostReaderEnabled`.
    public var onlineMaskEnabled: Bool
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
            antiDeleteExcludedPeerIds: [],
            visualEditEnabled: false,
            fromHimGiftsEnabled: false,
            voiceChangerMessagesEnabled: false,
            voicePreset: .male,
            uploadSpeedMode: .standard,
            downloadSpeedMode: .standard
        )
    }

    public init(phantomGiftsEnabled: Bool, fakeStarsBalance: Int64, fakeTonBalanceNanos: Int64, fakeStarsDisplayEnabled: Bool, fakeTonDisplayEnabled: Bool, antiDeleteMessagesEnabled: Bool, ghostReaderEnabled: Bool, onlineMaskEnabled: Bool, antiDeleteExcludedPeerIds: [PeerId], visualEditEnabled: Bool, fromHimGiftsEnabled: Bool, voiceChangerMessagesEnabled: Bool, voicePreset: PampGramVoicePreset, uploadSpeedMode: PampGramSpeedMode, downloadSpeedMode: PampGramSpeedMode) {
        self.phantomGiftsEnabled = phantomGiftsEnabled
        self.fakeStarsBalance = fakeStarsBalance
        self.fakeTonBalanceNanos = fakeTonBalanceNanos
        self.fakeStarsDisplayEnabled = fakeStarsDisplayEnabled
        self.fakeTonDisplayEnabled = fakeTonDisplayEnabled
        self.antiDeleteMessagesEnabled = antiDeleteMessagesEnabled
        self.ghostReaderEnabled = ghostReaderEnabled
        self.onlineMaskEnabled = onlineMaskEnabled
        self.antiDeleteExcludedPeerIds = antiDeleteExcludedPeerIds
        self.visualEditEnabled = visualEditEnabled
        self.fromHimGiftsEnabled = fromHimGiftsEnabled
        self.voiceChangerMessagesEnabled = voiceChangerMessagesEnabled
        self.voicePreset = voicePreset
        self.uploadSpeedMode = uploadSpeedMode
        self.downloadSpeedMode = downloadSpeedMode
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
        self.antiDeleteExcludedPeerIds = try container.decodeIfPresent([PeerId].self, forKey: .antiDeleteExcludedPeerIds) ?? defaults.antiDeleteExcludedPeerIds
        self.visualEditEnabled = try container.decodeIfPresent(Bool.self, forKey: .visualEditEnabled) ?? defaults.visualEditEnabled
        self.fromHimGiftsEnabled = try container.decodeIfPresent(Bool.self, forKey: .fromHimGiftsEnabled) ?? defaults.fromHimGiftsEnabled
        self.voiceChangerMessagesEnabled = try container.decodeIfPresent(Bool.self, forKey: .voiceChangerMessagesEnabled) ?? defaults.voiceChangerMessagesEnabled
        self.voicePreset = try container.decodeIfPresent(PampGramVoicePreset.self, forKey: .voicePreset) ?? defaults.voicePreset
        self.uploadSpeedMode = try container.decodeIfPresent(PampGramSpeedMode.self, forKey: .uploadSpeedMode) ?? defaults.uploadSpeedMode
        self.downloadSpeedMode = try container.decodeIfPresent(PampGramSpeedMode.self, forKey: .downloadSpeedMode) ?? defaults.downloadSpeedMode
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
