import Foundation
import Postbox
import SwiftSignalKit

/// A purely local "NFT username" shown on the owner's own profile.
public struct PampGramVisualUsername: Codable, Equatable {
    public var name: String
    public var priceTon: Double
    public var boughtAt: Int32
    /// The same price in US cents at the TON rate of the moment it was added (shown by
    /// Telegram's collectible-username sheet next to the TON price). 0 = unknown.
    public var priceUsdCents: Int64

    public init(name: String, priceTon: Double, boughtAt: Int32, priceUsdCents: Int64 = 0) {
        self.name = name
        self.priceTon = priceTon
        self.boughtAt = boughtAt
        self.priceUsdCents = priceUsdCents
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.priceTon = try container.decodeIfPresent(Double.self, forKey: .priceTon) ?? 0.0
        self.boughtAt = try container.decodeIfPresent(Int32.self, forKey: .boughtAt) ?? 0
        self.priceUsdCents = try container.decodeIfPresent(Int64.self, forKey: .priceUsdCents) ?? 0
    }
}

/// Local visuals added next to the rating and +888 in the gifts settings: the verification
/// badge ("Major" / "Hold"), the GRAM card, and visual usernames. Stored as JSON inside
/// `PampGramProfileVisualState.extras`.
public struct PampGramVisualExtras: Codable, Equatable {
    /// 0 = none, 1 = Major, 2 = Hold.
    public var badge: Int
    /// Custom-emoji file id of the verification icon to show next to your own name (the same
    /// thing Telegram shows for third-party verification). 0 = none.
    public var badgeFileId: Int64
    /// Where the icon was copied from ("@username"), for display only.
    public var badgeSource: String
    public var cardEnabled: Bool
    public var cardBalance: Int64
    /// Address the visual wallet shows when Telegram's own wallet was never created. "" = a
    /// neutral placeholder address.
    public var cardAddress: String
    /// Index into the card background presets.
    public var cardBackground: Int
    /// Emoji "sticker" drawn on the card ("" = none).
    public var cardSticker: String
    /// Where the sticker sits on the card, 0...1 of its width/height.
    public var cardStickerX: Double
    public var cardStickerY: Double
    public var usernames: [PampGramVisualUsername]

    public static let badgeNames: [String] = ["Нет", "Major", "Hold"]

    public static var `default`: PampGramVisualExtras {
        return PampGramVisualExtras(badge: 0, badgeFileId: 0, badgeSource: "", cardEnabled: false, cardBalance: 0, cardAddress: "", cardBackground: 0, cardSticker: "", cardStickerX: 0.82, cardStickerY: 0.28, usernames: [])
    }

    public init(badge: Int, badgeFileId: Int64, badgeSource: String, cardEnabled: Bool, cardBalance: Int64, cardAddress: String, cardBackground: Int, cardSticker: String, cardStickerX: Double, cardStickerY: Double, usernames: [PampGramVisualUsername]) {
        self.badge = badge
        self.badgeFileId = badgeFileId
        self.badgeSource = badgeSource
        self.cardEnabled = cardEnabled
        self.cardBalance = cardBalance
        self.cardAddress = cardAddress
        self.cardBackground = cardBackground
        self.cardSticker = cardSticker
        self.cardStickerX = cardStickerX
        self.cardStickerY = cardStickerY
        self.usernames = usernames
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = PampGramVisualExtras.default
        self.badge = try container.decodeIfPresent(Int.self, forKey: .badge) ?? defaults.badge
        self.badgeFileId = try container.decodeIfPresent(Int64.self, forKey: .badgeFileId) ?? defaults.badgeFileId
        self.badgeSource = try container.decodeIfPresent(String.self, forKey: .badgeSource) ?? defaults.badgeSource
        self.cardEnabled = try container.decodeIfPresent(Bool.self, forKey: .cardEnabled) ?? defaults.cardEnabled
        self.cardBalance = try container.decodeIfPresent(Int64.self, forKey: .cardBalance) ?? defaults.cardBalance
        self.cardAddress = try container.decodeIfPresent(String.self, forKey: .cardAddress) ?? defaults.cardAddress
        self.cardBackground = try container.decodeIfPresent(Int.self, forKey: .cardBackground) ?? defaults.cardBackground
        self.cardSticker = try container.decodeIfPresent(String.self, forKey: .cardSticker) ?? defaults.cardSticker
        self.cardStickerX = try container.decodeIfPresent(Double.self, forKey: .cardStickerX) ?? defaults.cardStickerX
        self.cardStickerY = try container.decodeIfPresent(Double.self, forKey: .cardStickerY) ?? defaults.cardStickerY
        self.usernames = try container.decodeIfPresent([PampGramVisualUsername].self, forKey: .usernames) ?? defaults.usernames
    }
}

public extension PampGramProfileVisualState {
    var visualExtras: PampGramVisualExtras {
        get {
            guard let data = self.extras.data(using: .utf8), let decoded = try? JSONDecoder().decode(PampGramVisualExtras.self, from: data) else {
                return PampGramVisualExtras.default
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue), let text = String(data: data, encoding: .utf8) {
                self.extras = text
            }
        }
    }
}

/// Synchronous mirror of the visual extras for code that can't wait on a signal: the real wallet
/// state (fake GRAM balance on the wallet card and the profile "Balance" chip) and the profile
/// header (verification icon next to your own name).
public final class PampGramVisualExtrasRuntime {
    public static let shared = PampGramVisualExtrasRuntime()

    /// Neutral placeholder shown as the wallet address when no address was entered.
    public static let placeholderWalletAddress = "UQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJKZ"

    private let lock = NSLock()
    /// Per account: with several accounts signed in, one account's settings must never leak
    /// into another's wallet or profile.
    private var byAccount: [Int64: PampGramVisualExtras] = [:]
    private var startedAccounts: Set<Int64> = []
    private var disposables: [Int64: Disposable] = [:]

    private init() {
    }

    public func start(accountKey: Int64, postbox: Postbox) {
        self.lock.lock()
        if self.startedAccounts.contains(accountKey) {
            self.lock.unlock()
            return
        }
        self.startedAccounts.insert(accountKey)
        self.lock.unlock()

        let disposable = (PampGramProfileVisualStore.signal(postbox: postbox)
        |> deliverOn(Queue.concurrentDefaultQueue())).start(next: { state in
            let extras = state.visualExtras
            PampGramVisualExtrasRuntime.shared.set(extras, accountKey: accountKey)
        })
        self.lock.lock()
        self.disposables[accountKey] = disposable
        self.lock.unlock()
    }

    private func set(_ extras: PampGramVisualExtras, accountKey: Int64) {
        self.lock.lock()
        self.byAccount[accountKey] = extras
        self.lock.unlock()
    }

    private func extras(accountKey: Int64) -> PampGramVisualExtras {
        self.lock.lock()
        let result = self.byAccount[accountKey] ?? PampGramVisualExtras.default
        self.lock.unlock()
        return result
    }

    /// The fake balance in nanograms when "Карточка GRAM" is on, otherwise nil (real balance).
    public func fakeBalanceNanos(accountKey: Int64) -> Int64? {
        let extras = self.extras(accountKey: accountKey)
        if !extras.cardEnabled {
            return nil
        }
        let result = extras.cardBalance.multipliedReportingOverflow(by: 1_000_000_000)
        return result.overflow ? Int64.max : result.partialValue
    }

    /// Address for the visual wallet when Telegram's real wallet was never created; nil when
    /// "Карточка GRAM" is off (the real wallet state is shown untouched).
    public func fakeWalletAddress(accountKey: Int64) -> String? {
        let extras = self.extras(accountKey: accountKey)
        if !extras.cardEnabled {
            return nil
        }
        let trimmed = extras.cardAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? PampGramVisualExtrasRuntime.placeholderWalletAddress : trimmed
    }

    public func verificationFileId(accountKey: Int64) -> Int64? {
        let fileId = self.extras(accountKey: accountKey).badgeFileId
        return fileId != 0 ? fileId : nil
    }
}
