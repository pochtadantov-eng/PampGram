import Foundation
import Postbox
import SwiftSignalKit

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

    public static let defaultFakeStarsBalance: Int64 = 50_000
    public static let defaultFakeTonBalanceNanos: Int64 = 0

    public static var defaultSettings: PampGramSettings {
        return PampGramSettings(
            phantomGiftsEnabled: true,
            fakeStarsBalance: defaultFakeStarsBalance,
            fakeTonBalanceNanos: defaultFakeTonBalanceNanos
        )
    }

    public init(phantomGiftsEnabled: Bool, fakeStarsBalance: Int64, fakeTonBalanceNanos: Int64) {
        self.phantomGiftsEnabled = phantomGiftsEnabled
        self.fakeStarsBalance = fakeStarsBalance
        self.fakeTonBalanceNanos = fakeTonBalanceNanos
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
