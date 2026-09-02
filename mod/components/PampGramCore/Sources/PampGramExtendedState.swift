import Foundation
import Postbox
import SwiftSignalKit

/// Raw-string enums are stored inside `PreferencesEntry`. They must use a keyed
/// `Codable` representation: Telegram's Postbox encoder deliberately has no
/// `singleValueContainer`, which is what Swift otherwise synthesizes for a raw enum.
public enum PampGramLocalCurrency: String, CaseIterable {
    case stars
    case ton
    case rubles

    public var displayName: String {
        switch self {
        case .stars: return "Stars"
        case .ton: return "TON"
        case .rubles: return "Рубли"
        }
    }
}

extension PampGramLocalCurrency: Codable {
    private enum CodingKeys: String, CodingKey {
        case value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawValue = try container.decode(String.self, forKey: .value)
        self = PampGramLocalCurrency(rawValue: rawValue) ?? .stars
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.rawValue, forKey: .value)
    }
}

public enum PampGramLocalOperationKind: String, CaseIterable {
    case topUp
    case purchase
    case sale
    case transfer
    case debit
    case credit

    public var displayName: String {
        switch self {
        case .topUp: return "Пополнение"
        case .purchase: return "Покупка"
        case .sale: return "Продажа"
        case .transfer: return "Передача"
        case .debit: return "Списание"
        case .credit: return "Зачисление"
        }
    }
}

extension PampGramLocalOperationKind: Codable {
    private enum CodingKeys: String, CodingKey {
        case value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawValue = try container.decode(String.self, forKey: .value)
        self = PampGramLocalOperationKind(rawValue: rawValue) ?? .topUp
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.rawValue, forKey: .value)
    }
}

/// One row in PampGram's entirely local ledger. `amount` uses the smallest exact unit of
/// the selected currency: Stars = whole stars, TON = nanotons, RUB = kopecks.
public struct PampGramLocalOperation: Codable, Equatable, Identifiable {
    public let id: Int64
    public let currency: PampGramLocalCurrency
    public let kind: PampGramLocalOperationKind
    public let amount: Int64
    public let date: Int32
    public let title: String
    public let details: String
    public let peerId: PeerId?
    public let giftId: Int64?
    public let balanceAfter: Int64?

    public init(id: Int64 = Int64.random(in: 1 ... (Int64.max / 4)), currency: PampGramLocalCurrency, kind: PampGramLocalOperationKind, amount: Int64, date: Int32 = Int32(Date().timeIntervalSince1970), title: String, details: String = "", peerId: PeerId? = nil, giftId: Int64? = nil, balanceAfter: Int64? = nil) {
        self.id = id
        self.currency = currency
        self.kind = kind
        self.amount = amount
        self.date = date
        self.title = title
        self.details = details
        self.peerId = peerId
        self.giftId = giftId
        self.balanceAfter = balanceAfter
    }
}

private struct PampGramLocalOperationList: Codable {
    var items: [PampGramLocalOperation]
}

public struct PampGramLedgerStatistics: Equatable {
    public var incoming: Int64 = 0
    public var outgoing: Int64 = 0
    public var purchases: Int = 0
    public var sales: Int = 0
    public var topUps: Int = 0
    public var transfers: Int = 0
    public var operationCount: Int = 0

    public var net: Int64 { self.incoming - self.outgoing }
}

public enum PampGramLocalLedgerStore {
    public static func all(transaction: Transaction) -> [PampGramLocalOperation] {
        return transaction.getPreferencesEntry(key: PampGramPreferencesKeys.localOperations)?.get(PampGramLocalOperationList.self)?.items ?? []
    }

    public static func add(transaction: Transaction, operation: PampGramLocalOperation) {
        transaction.updatePreferencesEntry(key: PampGramPreferencesKeys.localOperations, { entry in
            var list = entry?.get(PampGramLocalOperationList.self) ?? PampGramLocalOperationList(items: [])
            list.items.append(operation)
            if list.items.count > 5000 {
                list.items.removeFirst(list.items.count - 5000)
            }
            return PreferencesEntry(list)
        })
    }

    public static func remove(transaction: Transaction, id: Int64) {
        transaction.updatePreferencesEntry(key: PampGramPreferencesKeys.localOperations, { entry in
            var list = entry?.get(PampGramLocalOperationList.self) ?? PampGramLocalOperationList(items: [])
            list.items.removeAll(where: { $0.id == id })
            return PreferencesEntry(list)
        })
    }

    public static func clear(transaction: Transaction) {
        transaction.setPreferencesEntry(key: PampGramPreferencesKeys.localOperations, value: PreferencesEntry(PampGramLocalOperationList(items: [])))
    }

    public static func signal(postbox: Postbox) -> Signal<[PampGramLocalOperation], NoError> {
        return postbox.preferencesView(keys: [PampGramPreferencesKeys.localOperations])
        |> map { view in
            let items = view.values[PampGramPreferencesKeys.localOperations]?.get(PampGramLocalOperationList.self)?.items ?? []
            return items.sorted(by: { $0.date > $1.date })
        }
    }

    /// Adds an operation and applies its amount to the matching local balance in one Postbox
    /// transaction. Positive amounts credit, negative amounts debit. The operation receives
    /// the exact balance-after value so the history remains useful even after later edits.
    public static func addAndApply(transaction: Transaction, currency: PampGramLocalCurrency, kind: PampGramLocalOperationKind, amount: Int64, title: String, details: String = "", peerId: PeerId? = nil, giftId: Int64? = nil) {
        var balanceAfter: Int64 = 0
        PampGramCore.updateSettings(transaction: transaction, { settings in
            var settings = settings
            switch currency {
            case .stars:
                settings.fakeStarsBalance += amount
                balanceAfter = settings.fakeStarsBalance
            case .ton:
                settings.fakeTonBalanceNanos += amount
                balanceAfter = settings.fakeTonBalanceNanos
            case .rubles:
                settings.localRublesBalanceKopecks += amount
                balanceAfter = settings.localRublesBalanceKopecks
            }
            return settings
        })
        self.add(transaction: transaction, operation: PampGramLocalOperation(currency: currency, kind: kind, amount: amount, title: title, details: details, peerId: peerId, giftId: giftId, balanceAfter: balanceAfter))
    }

    public static func currentBalance(transaction: Transaction, currency: PampGramLocalCurrency) -> Int64 {
        let settings = PampGramCore.settings(transaction: transaction)
        switch currency {
        case .stars: return settings.fakeStarsBalance
        case .ton: return settings.fakeTonBalanceNanos
        case .rubles: return settings.localRublesBalanceKopecks
        }
    }

    public static func statistics(_ operations: [PampGramLocalOperation], currency: PampGramLocalCurrency) -> PampGramLedgerStatistics {
        var result = PampGramLedgerStatistics()
        for operation in operations where operation.currency == currency {
            result.operationCount += 1
            if operation.amount >= 0 {
                result.incoming += operation.amount
            } else {
                result.outgoing += -operation.amount
            }
            switch operation.kind {
            case .purchase: result.purchases += 1
            case .sale: result.sales += 1
            case .topUp: result.topUps += 1
            case .transfer: result.transfers += 1
            case .debit, .credit: break
            }
        }
        return result
    }
}

public struct PampGramProfileVisualState: Codable, Equatable {
    public var ratingEnabled: Bool
    public var ratingValue: Int64
    public var ratingPoints: Int64
    public var anonymousNumberEnabled: Bool
    public var anonymousNumber: String
    public var anonymousNumberPurchasedAt: Int32
    public var anonymousNumberPriceTonNanos: Int64

    public static var `default`: PampGramProfileVisualState {
        return PampGramProfileVisualState(
            ratingEnabled: false,
            ratingValue: 0,
            ratingPoints: 0,
            anonymousNumberEnabled: false,
            anonymousNumber: "+888 0000 0000",
            anonymousNumberPurchasedAt: Int32(Date().timeIntervalSince1970),
            anonymousNumberPriceTonNanos: 0
        )
    }

    public init(ratingEnabled: Bool, ratingValue: Int64, ratingPoints: Int64, anonymousNumberEnabled: Bool, anonymousNumber: String, anonymousNumberPurchasedAt: Int32, anonymousNumberPriceTonNanos: Int64) {
        self.ratingEnabled = ratingEnabled
        self.ratingValue = ratingValue
        self.ratingPoints = ratingPoints
        self.anonymousNumberEnabled = anonymousNumberEnabled
        self.anonymousNumber = anonymousNumber
        self.anonymousNumberPurchasedAt = anonymousNumberPurchasedAt
        self.anonymousNumberPriceTonNanos = anonymousNumberPriceTonNanos
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = PampGramProfileVisualState.default
        self.ratingEnabled = try container.decodeIfPresent(Bool.self, forKey: .ratingEnabled) ?? defaults.ratingEnabled
        self.ratingValue = try container.decodeIfPresent(Int64.self, forKey: .ratingValue) ?? defaults.ratingValue
        self.ratingPoints = try container.decodeIfPresent(Int64.self, forKey: .ratingPoints) ?? defaults.ratingPoints
        self.anonymousNumberEnabled = try container.decodeIfPresent(Bool.self, forKey: .anonymousNumberEnabled) ?? defaults.anonymousNumberEnabled
        self.anonymousNumber = try container.decodeIfPresent(String.self, forKey: .anonymousNumber) ?? defaults.anonymousNumber
        self.anonymousNumberPurchasedAt = try container.decodeIfPresent(Int32.self, forKey: .anonymousNumberPurchasedAt) ?? defaults.anonymousNumberPurchasedAt
        self.anonymousNumberPriceTonNanos = try container.decodeIfPresent(Int64.self, forKey: .anonymousNumberPriceTonNanos) ?? defaults.anonymousNumberPriceTonNanos
    }
}

public enum PampGramProfileVisualStore {
    public static func state(transaction: Transaction) -> PampGramProfileVisualState {
        return transaction.getPreferencesEntry(key: PampGramPreferencesKeys.profileVisuals)?.get(PampGramProfileVisualState.self) ?? .default
    }

    public static func update(transaction: Transaction, _ f: (PampGramProfileVisualState) -> PampGramProfileVisualState) {
        transaction.setPreferencesEntry(key: PampGramPreferencesKeys.profileVisuals, value: PreferencesEntry(f(self.state(transaction: transaction))))
    }

    public static func signal(postbox: Postbox) -> Signal<PampGramProfileVisualState, NoError> {
        return postbox.preferencesView(keys: [PampGramPreferencesKeys.profileVisuals])
        |> map { view in
            view.values[PampGramPreferencesKeys.profileVisuals]?.get(PampGramProfileVisualState.self) ?? .default
        }
        |> distinctUntilChanged
    }
}

public enum PampGramAppearancePreset: String, CaseIterable {
    case standard
    case glass
    case compact

    public var displayName: String {
        switch self {
        case .standard: return "Стандартный"
        case .glass: return "Glass"
        case .compact: return "Compact"
        }
    }
}

extension PampGramAppearancePreset: Codable {
    private enum CodingKeys: String, CodingKey {
        case value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawValue = try container.decode(String.self, forKey: .value)
        self = PampGramAppearancePreset(rawValue: rawValue) ?? .standard
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.rawValue, forKey: .value)
    }
}

public struct PampGramAppearanceState: Codable, Equatable {
    public var preset: PampGramAppearancePreset
    public var bubbleRadius: Int32
    public var bubbleOpacityPercent: Int32
    public var chatDensity: Int32
    public var blurStrength: Int32
    public var animationsMode: Int32
    public var reduceAnimations: Bool
    public var oledBlack: Bool
    public var compactHub: Bool
    public var monochromeIcons: Bool
    public var showChatPreview: Bool
    public var showChatDate: Bool
    public var avatarSize: Int32
    public var profileHeaderBlur: Int32
    public var incomingColorHex: String
    public var outgoingColorHex: String
    public var inputRadius: Int32
    public var cardScalePercent: Int32
    public var iconScalePercent: Int32
    public var textScalePercent: Int32
    public var boldHeaders: Bool
    public var glassCards: Bool
    public var minimalMode: Bool
    public var avatarShape: Int32
    public var profileGradientHex: String

    public static var `default`: PampGramAppearanceState {
        return PampGramAppearanceState(preset: .standard, bubbleRadius: 16, bubbleOpacityPercent: 100, chatDensity: 1, blurStrength: 40, animationsMode: 1, reduceAnimations: false, oledBlack: false, compactHub: false, monochromeIcons: false, showChatPreview: true, showChatDate: true, avatarSize: 48, profileHeaderBlur: 30, incomingColorHex: "#FFFFFF", outgoingColorHex: "#DCF8C6", inputRadius: 22, cardScalePercent: 100, iconScalePercent: 100, textScalePercent: 100, boldHeaders: true, glassCards: false, minimalMode: false, avatarShape: 0, profileGradientHex: "#2AABEE,#8774E1")
    }

    public init(preset: PampGramAppearancePreset, bubbleRadius: Int32, bubbleOpacityPercent: Int32, chatDensity: Int32, blurStrength: Int32, animationsMode: Int32, reduceAnimations: Bool, oledBlack: Bool, compactHub: Bool, monochromeIcons: Bool, showChatPreview: Bool, showChatDate: Bool, avatarSize: Int32, profileHeaderBlur: Int32, incomingColorHex: String, outgoingColorHex: String, inputRadius: Int32, cardScalePercent: Int32, iconScalePercent: Int32, textScalePercent: Int32, boldHeaders: Bool, glassCards: Bool, minimalMode: Bool, avatarShape: Int32, profileGradientHex: String) {
        self.preset = preset
        self.bubbleRadius = bubbleRadius
        self.bubbleOpacityPercent = bubbleOpacityPercent
        self.chatDensity = chatDensity
        self.blurStrength = blurStrength
        self.animationsMode = animationsMode
        self.reduceAnimations = reduceAnimations
        self.oledBlack = oledBlack
        self.compactHub = compactHub
        self.monochromeIcons = monochromeIcons
        self.showChatPreview = showChatPreview
        self.showChatDate = showChatDate
        self.avatarSize = avatarSize
        self.profileHeaderBlur = profileHeaderBlur
        self.incomingColorHex = incomingColorHex
        self.outgoingColorHex = outgoingColorHex
        self.inputRadius = inputRadius
        self.cardScalePercent = cardScalePercent
        self.iconScalePercent = iconScalePercent
        self.textScalePercent = textScalePercent
        self.boldHeaders = boldHeaders
        self.glassCards = glassCards
        self.minimalMode = minimalMode
        self.avatarShape = avatarShape
        self.profileGradientHex = profileGradientHex
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PampGramAppearanceState.default
        self.preset = try c.decodeIfPresent(PampGramAppearancePreset.self, forKey: .preset) ?? d.preset
        self.bubbleRadius = try c.decodeIfPresent(Int32.self, forKey: .bubbleRadius) ?? d.bubbleRadius
        self.bubbleOpacityPercent = try c.decodeIfPresent(Int32.self, forKey: .bubbleOpacityPercent) ?? d.bubbleOpacityPercent
        self.chatDensity = try c.decodeIfPresent(Int32.self, forKey: .chatDensity) ?? d.chatDensity
        self.blurStrength = try c.decodeIfPresent(Int32.self, forKey: .blurStrength) ?? d.blurStrength
        self.animationsMode = try c.decodeIfPresent(Int32.self, forKey: .animationsMode) ?? d.animationsMode
        self.reduceAnimations = try c.decodeIfPresent(Bool.self, forKey: .reduceAnimations) ?? d.reduceAnimations
        self.oledBlack = try c.decodeIfPresent(Bool.self, forKey: .oledBlack) ?? d.oledBlack
        self.compactHub = try c.decodeIfPresent(Bool.self, forKey: .compactHub) ?? d.compactHub
        self.monochromeIcons = try c.decodeIfPresent(Bool.self, forKey: .monochromeIcons) ?? d.monochromeIcons
        self.showChatPreview = try c.decodeIfPresent(Bool.self, forKey: .showChatPreview) ?? d.showChatPreview
        self.showChatDate = try c.decodeIfPresent(Bool.self, forKey: .showChatDate) ?? d.showChatDate
        self.avatarSize = try c.decodeIfPresent(Int32.self, forKey: .avatarSize) ?? d.avatarSize
        self.profileHeaderBlur = try c.decodeIfPresent(Int32.self, forKey: .profileHeaderBlur) ?? d.profileHeaderBlur
        self.incomingColorHex = try c.decodeIfPresent(String.self, forKey: .incomingColorHex) ?? d.incomingColorHex
        self.outgoingColorHex = try c.decodeIfPresent(String.self, forKey: .outgoingColorHex) ?? d.outgoingColorHex
        self.inputRadius = try c.decodeIfPresent(Int32.self, forKey: .inputRadius) ?? d.inputRadius
        self.cardScalePercent = try c.decodeIfPresent(Int32.self, forKey: .cardScalePercent) ?? d.cardScalePercent
        self.iconScalePercent = try c.decodeIfPresent(Int32.self, forKey: .iconScalePercent) ?? d.iconScalePercent
        self.textScalePercent = try c.decodeIfPresent(Int32.self, forKey: .textScalePercent) ?? d.textScalePercent
        self.boldHeaders = try c.decodeIfPresent(Bool.self, forKey: .boldHeaders) ?? d.boldHeaders
        self.glassCards = try c.decodeIfPresent(Bool.self, forKey: .glassCards) ?? d.glassCards
        self.minimalMode = try c.decodeIfPresent(Bool.self, forKey: .minimalMode) ?? d.minimalMode
        self.avatarShape = try c.decodeIfPresent(Int32.self, forKey: .avatarShape) ?? d.avatarShape
        self.profileGradientHex = try c.decodeIfPresent(String.self, forKey: .profileGradientHex) ?? d.profileGradientHex
    }
}

public enum PampGramAppearanceStore {
    public static func state(transaction: Transaction) -> PampGramAppearanceState {
        return transaction.getPreferencesEntry(key: PampGramPreferencesKeys.appearance)?.get(PampGramAppearanceState.self) ?? .default
    }
    public static func update(transaction: Transaction, _ f: (PampGramAppearanceState) -> PampGramAppearanceState) {
        transaction.setPreferencesEntry(key: PampGramPreferencesKeys.appearance, value: PreferencesEntry(f(self.state(transaction: transaction))))
    }
    public static func signal(postbox: Postbox) -> Signal<PampGramAppearanceState, NoError> {
        return postbox.preferencesView(keys: [PampGramPreferencesKeys.appearance])
        |> map { $0.values[PampGramPreferencesKeys.appearance]?.get(PampGramAppearanceState.self) ?? .default }
        |> distinctUntilChanged
    }
}

public struct PampGramBehaviorState: Codable, Equatable {
    public var showProfileIds: Bool
    public var hideOwnPhone: Bool
    public var translationEnabled: Bool
    public var translationTargetLanguage: String

    public static var `default`: PampGramBehaviorState {
        return PampGramBehaviorState(showProfileIds: true, hideOwnPhone: false, translationEnabled: true, translationTargetLanguage: "ru")
    }

    public init(showProfileIds: Bool, hideOwnPhone: Bool, translationEnabled: Bool, translationTargetLanguage: String) {
        self.showProfileIds = showProfileIds
        self.hideOwnPhone = hideOwnPhone
        self.translationEnabled = translationEnabled
        self.translationTargetLanguage = translationTargetLanguage
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PampGramBehaviorState.default
        self.showProfileIds = try c.decodeIfPresent(Bool.self, forKey: .showProfileIds) ?? d.showProfileIds
        self.hideOwnPhone = try c.decodeIfPresent(Bool.self, forKey: .hideOwnPhone) ?? d.hideOwnPhone
        self.translationEnabled = try c.decodeIfPresent(Bool.self, forKey: .translationEnabled) ?? d.translationEnabled
        self.translationTargetLanguage = try c.decodeIfPresent(String.self, forKey: .translationTargetLanguage) ?? d.translationTargetLanguage
    }
}

public enum PampGramBehaviorStore {
    public static func state(transaction: Transaction) -> PampGramBehaviorState {
        return transaction.getPreferencesEntry(key: PampGramPreferencesKeys.behavior)?.get(PampGramBehaviorState.self) ?? .default
    }
    public static func update(transaction: Transaction, _ f: (PampGramBehaviorState) -> PampGramBehaviorState) {
        transaction.setPreferencesEntry(key: PampGramPreferencesKeys.behavior, value: PreferencesEntry(f(self.state(transaction: transaction))))
    }
    public static func signal(postbox: Postbox) -> Signal<PampGramBehaviorState, NoError> {
        return postbox.preferencesView(keys: [PampGramPreferencesKeys.behavior])
        |> map { $0.values[PampGramPreferencesKeys.behavior]?.get(PampGramBehaviorState.self) ?? .default }
        |> distinctUntilChanged
    }
}

public struct PampGramFakeAdminChannelState: Codable, Equatable {
    public var peerId: PeerId
    public var enabled: Bool
    public var titleOverride: String?
    public var descriptionOverride: String?
    public var reactionsEnabled: Bool?
    public var inviteLinkOverride: String?

    public init(peerId: PeerId, enabled: Bool, titleOverride: String? = nil, descriptionOverride: String? = nil, reactionsEnabled: Bool? = nil, inviteLinkOverride: String? = nil) {
        self.peerId = peerId
        self.enabled = enabled
        self.titleOverride = titleOverride
        self.descriptionOverride = descriptionOverride
        self.reactionsEnabled = reactionsEnabled
        self.inviteLinkOverride = inviteLinkOverride
    }
}

private struct PampGramFakeAdminList: Codable {
    var channels: [PampGramFakeAdminChannelState]
}

public enum PampGramFakeAdminStore {
    public static func all(transaction: Transaction) -> [PampGramFakeAdminChannelState] {
        return transaction.getPreferencesEntry(key: PampGramPreferencesKeys.fakeAdmin)?.get(PampGramFakeAdminList.self)?.channels ?? []
    }
    public static func state(transaction: Transaction, peerId: PeerId) -> PampGramFakeAdminChannelState? {
        return self.all(transaction: transaction).first(where: { $0.peerId == peerId })
    }
    public static func isEnabled(transaction: Transaction, peerId: PeerId) -> Bool {
        return self.state(transaction: transaction, peerId: peerId)?.enabled == true
    }
    public static func update(transaction: Transaction, peerId: PeerId, _ f: (PampGramFakeAdminChannelState) -> PampGramFakeAdminChannelState) {
        transaction.updatePreferencesEntry(key: PampGramPreferencesKeys.fakeAdmin, { entry in
            var list = entry?.get(PampGramFakeAdminList.self) ?? PampGramFakeAdminList(channels: [])
            let base = list.channels.first(where: { $0.peerId == peerId }) ?? PampGramFakeAdminChannelState(peerId: peerId, enabled: false)
            let value = f(base)
            list.channels.removeAll(where: { $0.peerId == peerId })
            list.channels.append(value)
            return PreferencesEntry(list)
        })
    }
    public static func signal(postbox: Postbox, peerId: PeerId) -> Signal<PampGramFakeAdminChannelState, NoError> {
        return postbox.preferencesView(keys: [PampGramPreferencesKeys.fakeAdmin])
        |> map { view in
            let list = view.values[PampGramPreferencesKeys.fakeAdmin]?.get(PampGramFakeAdminList.self)?.channels ?? []
            return list.first(where: { $0.peerId == peerId }) ?? PampGramFakeAdminChannelState(peerId: peerId, enabled: false)
        }
        |> distinctUntilChanged
    }

    /// Live list of every channel with a fake-admin record (enabled or not), for the
    /// "Фейк админ" management screen.
    public static func allSignal(postbox: Postbox) -> Signal<[PampGramFakeAdminChannelState], NoError> {
        return postbox.preferencesView(keys: [PampGramPreferencesKeys.fakeAdmin])
        |> map { view in
            return view.values[PampGramPreferencesKeys.fakeAdmin]?.get(PampGramFakeAdminList.self)?.channels ?? []
        }
        |> distinctUntilChanged
    }
}
