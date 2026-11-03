import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import PromptUI
import PampGramCore

private final class PampGramAdditionalArguments {
    let toggleVoiceChanger: (Bool) -> Void
    let openVoicePreset: () -> Void
    let openUploadSpeed: () -> Void
    let openDownloadSpeed: () -> Void
    let openFakeLocation: () -> Void
    let openChatLock: () -> Void
    let openCallOverrides: () -> Void
    let openFakeAdmin: () -> Void
    let toggleInfinitePins: (Bool) -> Void
    let toggleLegalPremium: (Bool) -> Void
    let toggleBypassViewOnceMedia: (Bool) -> Void
    let toggleBypassTimedMedia: (Bool) -> Void
    let toggleBypassMarkViewed: (Bool) -> Void
    let toggleStorySaving: (Bool) -> Void
    let toggleScreenshotBypass: (Bool) -> Void
    let toggleForwardProtectedToSaved: (Bool) -> Void
    let toggleAutoSaveVideoMessages: (Bool) -> Void
    let toggleFakeTyping: (Bool) -> Void
    let toggleHideOwnPhone: (Bool) -> Void
    let openFakePhoneNumber: () -> Void
    let toggleProfileIds: (Bool) -> Void
    let toggleAccountLink: (Bool) -> Void
    let openFakeBots: () -> Void
    let toggleFakeForwardedFrom: (Bool) -> Void
    let toggleFakeReactions: (Bool) -> Void
    let toggleFakePremiumBadge: (Bool) -> Void
    let toggleFakeSubscribers: (Bool) -> Void
    let toggleFakeReadReceipts: (Bool) -> Void
    let toggleChatEditor: (Bool) -> Void
    let toggleConversationGenerator: (Bool) -> Void
    let toggleFakeDeletedMessage: (Bool) -> Void
    let toggleInvisibleMessages: (Bool) -> Void
    let toggleReactionSpammer: (Bool) -> Void
    let toggleFakeVoiceFromText: (Bool) -> Void
    let toggleStickerPackCloner: (Bool) -> Void
    let toggleFakePortals: (Bool) -> Void
    let toggleFakeSystemMessages: (Bool) -> Void
    let toggleFakePaymentReceipts: (Bool) -> Void
    let toggleVoiceCloner: (Bool) -> Void
    let toggleChatTimeMachine: (Bool) -> Void
    let toggleFakeIncomingCall: (Bool) -> Void
    let toggleFakeScreenshotNotification: (Bool) -> Void
    let toggleFakeDeletedAccount: (Bool) -> Void
    let toggleFakeGroupGenerator: (Bool) -> Void

    init(toggleVoiceChanger: @escaping (Bool) -> Void, openVoicePreset: @escaping () -> Void, openUploadSpeed: @escaping () -> Void, openDownloadSpeed: @escaping () -> Void, openFakeLocation: @escaping () -> Void, openChatLock: @escaping () -> Void, openCallOverrides: @escaping () -> Void, openFakeAdmin: @escaping () -> Void, toggleInfinitePins: @escaping (Bool) -> Void, toggleLegalPremium: @escaping (Bool) -> Void, toggleBypassViewOnceMedia: @escaping (Bool) -> Void, toggleBypassTimedMedia: @escaping (Bool) -> Void, toggleBypassMarkViewed: @escaping (Bool) -> Void, toggleStorySaving: @escaping (Bool) -> Void, toggleScreenshotBypass: @escaping (Bool) -> Void, toggleForwardProtectedToSaved: @escaping (Bool) -> Void, toggleAutoSaveVideoMessages: @escaping (Bool) -> Void, toggleFakeTyping: @escaping (Bool) -> Void, toggleHideOwnPhone: @escaping (Bool) -> Void, openFakePhoneNumber: @escaping () -> Void, toggleProfileIds: @escaping (Bool) -> Void, toggleAccountLink: @escaping (Bool) -> Void, openFakeBots: @escaping () -> Void, toggleFakeForwardedFrom: @escaping (Bool) -> Void, toggleFakeReactions: @escaping (Bool) -> Void, toggleFakePremiumBadge: @escaping (Bool) -> Void, toggleFakeSubscribers: @escaping (Bool) -> Void, toggleFakeReadReceipts: @escaping (Bool) -> Void, toggleChatEditor: @escaping (Bool) -> Void, toggleConversationGenerator: @escaping (Bool) -> Void, toggleFakeDeletedMessage: @escaping (Bool) -> Void, toggleInvisibleMessages: @escaping (Bool) -> Void, toggleReactionSpammer: @escaping (Bool) -> Void, toggleFakeVoiceFromText: @escaping (Bool) -> Void, toggleStickerPackCloner: @escaping (Bool) -> Void, toggleFakePortals: @escaping (Bool) -> Void, toggleFakeSystemMessages: @escaping (Bool) -> Void, toggleFakePaymentReceipts: @escaping (Bool) -> Void, toggleVoiceCloner: @escaping (Bool) -> Void, toggleChatTimeMachine: @escaping (Bool) -> Void, toggleFakeIncomingCall: @escaping (Bool) -> Void, toggleFakeScreenshotNotification: @escaping (Bool) -> Void, toggleFakeDeletedAccount: @escaping (Bool) -> Void, toggleFakeGroupGenerator: @escaping (Bool) -> Void) {
        self.toggleVoiceChanger = toggleVoiceChanger
        self.openVoicePreset = openVoicePreset
        self.openUploadSpeed = openUploadSpeed
        self.openDownloadSpeed = openDownloadSpeed
        self.openFakeLocation = openFakeLocation
        self.openChatLock = openChatLock
        self.openCallOverrides = openCallOverrides
        self.openFakeAdmin = openFakeAdmin
        self.toggleInfinitePins = toggleInfinitePins
        self.toggleLegalPremium = toggleLegalPremium
        self.toggleBypassViewOnceMedia = toggleBypassViewOnceMedia
        self.toggleBypassTimedMedia = toggleBypassTimedMedia
        self.toggleBypassMarkViewed = toggleBypassMarkViewed
        self.toggleStorySaving = toggleStorySaving
        self.toggleScreenshotBypass = toggleScreenshotBypass
        self.toggleForwardProtectedToSaved = toggleForwardProtectedToSaved
        self.toggleAutoSaveVideoMessages = toggleAutoSaveVideoMessages
        self.toggleFakeTyping = toggleFakeTyping
        self.toggleHideOwnPhone = toggleHideOwnPhone
        self.openFakePhoneNumber = openFakePhoneNumber
        self.toggleProfileIds = toggleProfileIds
        self.toggleAccountLink = toggleAccountLink
        self.openFakeBots = openFakeBots
        self.toggleFakeForwardedFrom = toggleFakeForwardedFrom
        self.toggleFakeReactions = toggleFakeReactions
        self.toggleFakePremiumBadge = toggleFakePremiumBadge
        self.toggleFakeSubscribers = toggleFakeSubscribers
        self.toggleFakeReadReceipts = toggleFakeReadReceipts
        self.toggleChatEditor = toggleChatEditor
        self.toggleConversationGenerator = toggleConversationGenerator
        self.toggleFakeDeletedMessage = toggleFakeDeletedMessage
        self.toggleInvisibleMessages = toggleInvisibleMessages
        self.toggleReactionSpammer = toggleReactionSpammer
        self.toggleFakeVoiceFromText = toggleFakeVoiceFromText
        self.toggleStickerPackCloner = toggleStickerPackCloner
        self.toggleFakePortals = toggleFakePortals
        self.toggleFakeSystemMessages = toggleFakeSystemMessages
        self.toggleFakePaymentReceipts = toggleFakePaymentReceipts
        self.toggleVoiceCloner = toggleVoiceCloner
        self.toggleChatTimeMachine = toggleChatTimeMachine
        self.toggleFakeIncomingCall = toggleFakeIncomingCall
        self.toggleFakeScreenshotNotification = toggleFakeScreenshotNotification
        self.toggleFakeDeletedAccount = toggleFakeDeletedAccount
        self.toggleFakeGroupGenerator = toggleFakeGroupGenerator
    }
}

// MARK: - Sections

private enum PampGramAdditionalSection: Int32 {
    case about
    case voice
    case speed
    case media
    case profile
    case messages
    case generators
    case voiceCalls
    case tools
    case premium
}

// MARK: - Entries

private enum PampGramAdditionalEntry: ItemListNodeEntry {
    case aboutText(String)

    // ИЗМЕНЕНИЕ ГОЛОСА
    case voiceHeader(String)
    case voiceToggle(String, Bool)
    case voicePresetRow(String, String)
    case voiceFooter(String)

    // СКОРОСТЬ ПЕРЕДАЧИ
    case speedHeader(String)
    case uploadSpeedRow(String, String)
    case downloadSpeedRow(String, String)
    case speedFooter(String)

    // МЕДИА И ЗАЩИТА
    case mediaHeader(String)
    case viewOnceToggle(String, Bool)
    case timedToggle(String, Bool)
    case markViewedToggle(String, Bool)
    case screenshotsToggle(String, Bool)
    case chatScreenshotsToggle(String, Bool)
    case forwardProtectedToSavedToggle(String, Bool)
    case autoSaveVideoMessagesToggle(String, Bool)
    case mediaFooter(String)

    // ПРОФИЛЬ
    case profileHeader(String)
    case hideOwnPhoneToggle(String, Bool)
    case fakePhoneNumberRow(String, String)
    case profileIdsToggle(String, Bool)
    case accountLinkToggle(String, Bool)
    case fakePremiumBadgeToggle(String, Bool)
    case fakeDeletedAccountToggle(String, Bool)
    case profileFooter(String)

    // СООБЩЕНИЯ И ЧАТ
    case messagesHeader(String)
    case fakeForwardedFromToggle(String, Bool)
    case fakeReactionsToggle(String, Bool)
    case fakeReadReceiptsToggle(String, Bool)
    case chatEditorToggle(String, Bool)
    case chatTimeMachineToggle(String, Bool)
    case invisibleMessagesToggle(String, Bool)
    case fakeDeletedMessageToggle(String, Bool)
    case fakeSystemMessagesToggle(String, Bool)
    case messagesFooter(String)

    // ГЕНЕРАТОРЫ
    case generatorsHeader(String)
    case conversationGeneratorToggle(String, Bool)
    case fakeGroupGeneratorToggle(String, Bool)
    case fakePaymentReceiptsToggle(String, Bool)
    case generatorsFooter(String)

    // ГОЛОС И ЗВОНКИ
    case voiceCallsHeader(String)
    case fakeVoiceFromTextToggle(String, Bool)
    case voiceClonerToggle(String, Bool)
    case fakeIncomingCallToggle(String, Bool)
    case callOverridesRow(String)
    case voiceCallsFooter(String)

    // ИНСТРУМЕНТЫ
    case toolsHeader(String)
    case fakeLocationRow(String, String)
    case chatLockRow(String, String)
    case fakeAdminRow(String)
    case fakeSubscribersToggle(String, Bool)
    case fakeBotsRow(String, String)
    case fakePortalsToggle(String, Bool)
    case fakeTypingToggle(String, Bool)
    case reactionSpammerToggle(String, Bool)
    case stickerPackClonerToggle(String, Bool)
    case fakeScreenshotNotificationToggle(String, Bool)
    case toolsFooter(String)

    // ПРЕМИУМ
    case premiumHeader(String)
    case infinitePinsToggle(String, Bool)
    case legalPremiumToggle(String, Bool)
    case premiumFooter(String)

    var section: ItemListSectionId {
        switch self {
        case .aboutText:
            return PampGramAdditionalSection.about.rawValue
        case .voiceHeader, .voiceToggle, .voicePresetRow, .voiceFooter:
            return PampGramAdditionalSection.voice.rawValue
        case .speedHeader, .uploadSpeedRow, .downloadSpeedRow, .speedFooter:
            return PampGramAdditionalSection.speed.rawValue
        case .mediaHeader, .viewOnceToggle, .timedToggle, .markViewedToggle, .screenshotsToggle, .chatScreenshotsToggle, .forwardProtectedToSavedToggle, .autoSaveVideoMessagesToggle, .mediaFooter:
            return PampGramAdditionalSection.media.rawValue
        case .profileHeader, .hideOwnPhoneToggle, .fakePhoneNumberRow, .profileIdsToggle, .accountLinkToggle, .fakePremiumBadgeToggle, .fakeDeletedAccountToggle, .profileFooter:
            return PampGramAdditionalSection.profile.rawValue
        case .messagesHeader, .fakeForwardedFromToggle, .fakeReactionsToggle, .fakeReadReceiptsToggle, .chatEditorToggle, .chatTimeMachineToggle, .invisibleMessagesToggle, .fakeDeletedMessageToggle, .fakeSystemMessagesToggle, .messagesFooter:
            return PampGramAdditionalSection.messages.rawValue
        case .generatorsHeader, .conversationGeneratorToggle, .fakeGroupGeneratorToggle, .fakePaymentReceiptsToggle, .generatorsFooter:
            return PampGramAdditionalSection.generators.rawValue
        case .voiceCallsHeader, .fakeVoiceFromTextToggle, .voiceClonerToggle, .fakeIncomingCallToggle, .callOverridesRow, .voiceCallsFooter:
            return PampGramAdditionalSection.voiceCalls.rawValue
        case .toolsHeader, .fakeLocationRow, .chatLockRow, .fakeAdminRow, .fakeSubscribersToggle, .fakeBotsRow, .fakePortalsToggle, .fakeTypingToggle, .reactionSpammerToggle, .stickerPackClonerToggle, .fakeScreenshotNotificationToggle, .toolsFooter:
            return PampGramAdditionalSection.tools.rawValue
        case .premiumHeader, .infinitePinsToggle, .legalPremiumToggle, .premiumFooter:
            return PampGramAdditionalSection.premium.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .aboutText: return 0

        case .voiceHeader: return 1
        case .voiceToggle: return 2
        case .voicePresetRow: return 3
        case .voiceFooter: return 4

        case .speedHeader: return 10
        case .uploadSpeedRow: return 11
        case .downloadSpeedRow: return 12
        case .speedFooter: return 13

        case .mediaHeader: return 100
        case .viewOnceToggle: return 101
        case .timedToggle: return 102
        case .markViewedToggle: return 103
        case .screenshotsToggle: return 104
        case .chatScreenshotsToggle: return 105
        case .forwardProtectedToSavedToggle: return 106
        case .autoSaveVideoMessagesToggle: return 107
        case .mediaFooter: return 109

        case .profileHeader: return 200
        case .hideOwnPhoneToggle: return 201
        case .fakePhoneNumberRow: return 202
        case .profileIdsToggle: return 203
        case .accountLinkToggle: return 204
        case .fakePremiumBadgeToggle: return 205
        case .fakeDeletedAccountToggle: return 206
        case .profileFooter: return 209

        case .messagesHeader: return 300
        case .fakeForwardedFromToggle: return 301
        case .fakeReactionsToggle: return 302
        case .fakeReadReceiptsToggle: return 303
        case .chatEditorToggle: return 304
        case .chatTimeMachineToggle: return 305
        case .invisibleMessagesToggle: return 306
        case .fakeDeletedMessageToggle: return 307
        case .fakeSystemMessagesToggle: return 308
        case .messagesFooter: return 319

        case .generatorsHeader: return 400
        case .conversationGeneratorToggle: return 401
        case .fakeGroupGeneratorToggle: return 402
        case .fakePaymentReceiptsToggle: return 403
        case .generatorsFooter: return 409

        case .voiceCallsHeader: return 500
        case .fakeVoiceFromTextToggle: return 501
        case .voiceClonerToggle: return 502
        case .fakeIncomingCallToggle: return 503
        case .callOverridesRow: return 504
        case .voiceCallsFooter: return 509

        case .toolsHeader: return 600
        case .fakeLocationRow: return 601
        case .chatLockRow: return 602
        case .fakeAdminRow: return 603
        case .fakeSubscribersToggle: return 604
        case .fakeBotsRow: return 605
        case .fakePortalsToggle: return 606
        case .fakeTypingToggle: return 607
        case .reactionSpammerToggle: return 608
        case .stickerPackClonerToggle: return 609
        case .fakeScreenshotNotificationToggle: return 610
        case .toolsFooter: return 619

        case .premiumHeader: return 700
        case .infinitePinsToggle: return 701
        case .legalPremiumToggle: return 702
        case .premiumFooter: return 709
        }
    }

    static func <(lhs: PampGramAdditionalEntry, rhs: PampGramAdditionalEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramAdditionalArguments
        switch self {

        // Headers
        case let .voiceHeader(text), let .speedHeader(text), let .mediaHeader(text), let .profileHeader(text), let .messagesHeader(text), let .generatorsHeader(text), let .voiceCallsHeader(text), let .toolsHeader(text), let .premiumHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)

        // Footers
        case let .aboutText(text), let .voiceFooter(text), let .speedFooter(text), let .mediaFooter(text), let .profileFooter(text), let .messagesFooter(text), let .generatorsFooter(text), let .voiceCallsFooter(text), let .toolsFooter(text), let .premiumFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)

        // MARK: Voice
        case let .voiceToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleVoiceChanger(value)
            })
        case let .voicePresetRow(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openVoicePreset()
            })

        // MARK: Speed
        case let .uploadSpeedRow(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openUploadSpeed()
            })
        case let .downloadSpeedRow(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openDownloadSpeed()
            })

        // MARK: Media
        case let .viewOnceToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "eye.fill", backgroundColor: UIColor(rgb: 0x34c759)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleBypassViewOnceMedia(value)
            })
        case let .timedToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "timer", backgroundColor: UIColor(rgb: 0x34c759)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleBypassTimedMedia(value)
            })
        case let .markViewedToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "checkmark.circle.fill", backgroundColor: UIColor(rgb: 0x34c759)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleBypassMarkViewed(value)
            })
        case let .screenshotsToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "camera.viewfinder", backgroundColor: UIColor(rgb: 0xff9500)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleStorySaving(value)
            })
        case let .chatScreenshotsToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "eye.trianglebadge.exclamationmark", backgroundColor: UIColor(rgb: 0xff3b30)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleScreenshotBypass(value)
            })
        case let .forwardProtectedToSavedToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "bookmark.fill", backgroundColor: UIColor(rgb: 0x007aff)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleForwardProtectedToSaved(value)
            })
        case let .autoSaveVideoMessagesToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "circle.circle.fill", backgroundColor: UIColor(rgb: 0xaf52de)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleAutoSaveVideoMessages(value)
            })

        // MARK: Profile
        case let .hideOwnPhoneToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "phone.down.fill", backgroundColor: UIColor(rgb: 0x8e8e93)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleHideOwnPhone(value)
            })
        case let .fakePhoneNumberRow(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "phone.badge.plus", backgroundColor: UIColor(rgb: 0x34c759)), title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openFakePhoneNumber()
            })
        case let .profileIdsToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "number", backgroundColor: UIColor(rgb: 0x5856d6)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleProfileIds(value)
            })
        case let .accountLinkToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "link", backgroundColor: UIColor(rgb: 0x007aff)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleAccountLink(value)
            })
        case let .fakePremiumBadgeToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "star.fill", backgroundColor: UIColor(rgb: 0xf5a623)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleFakePremiumBadge(value)
            })
        case let .fakeDeletedAccountToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "person.crop.circle.badge.xmark", backgroundColor: UIColor(rgb: 0xff3b30)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleFakeDeletedAccount(value)
            })

        // MARK: Messages
        case let .fakeForwardedFromToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "arrowshape.turn.up.right.fill", backgroundColor: UIColor(rgb: 0xff6b00)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleFakeForwardedFrom(value)
            })
        case let .fakeReactionsToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "heart.circle.fill", backgroundColor: UIColor(rgb: 0xff2d55)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleFakeReactions(value)
            })
        case let .fakeReadReceiptsToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "checkmark.message.fill", backgroundColor: UIColor(rgb: 0x34c759)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleFakeReadReceipts(value)
            })
        case let .chatEditorToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "pencil.and.outline", backgroundColor: UIColor(rgb: 0x5856d6)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleChatEditor(value)
            })
        case let .chatTimeMachineToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "clock.arrow.circlepath", backgroundColor: UIColor(rgb: 0x5856d6)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleChatTimeMachine(value)
            })
        case let .invisibleMessagesToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "eye.slash.fill", backgroundColor: UIColor(rgb: 0x8e8e93)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleInvisibleMessages(value)
            })
        case let .fakeDeletedMessageToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "trash.slash.fill", backgroundColor: UIColor(rgb: 0xff3b30)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleFakeDeletedMessage(value)
            })
        case let .fakeSystemMessagesToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "exclamationmark.shield.fill", backgroundColor: UIColor(rgb: 0x8e8e93)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleFakeSystemMessages(value)
            })

        // MARK: Generators
        case let .conversationGeneratorToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "text.bubble.fill", backgroundColor: UIColor(rgb: 0x8e44ad)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleConversationGenerator(value)
            })
        case let .fakeGroupGeneratorToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "person.3.sequence.fill", backgroundColor: UIColor(rgb: 0x8e44ad)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleFakeGroupGenerator(value)
            })
        case let .fakePaymentReceiptsToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "creditcard.fill", backgroundColor: UIColor(rgb: 0x34c759)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleFakePaymentReceipts(value)
            })

        // MARK: Voice & Calls
        case let .fakeVoiceFromTextToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "waveform.circle.fill", backgroundColor: UIColor(rgb: 0x007aff)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleFakeVoiceFromText(value)
            })
        case let .voiceClonerToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "waveform.and.person.filled", backgroundColor: UIColor(rgb: 0xff2d55)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleVoiceCloner(value)
            })
        case let .fakeIncomingCallToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "phone.arrow.down.left.fill", backgroundColor: UIColor(rgb: 0x30b0c7)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleFakeIncomingCall(value)
            })
        case let .callOverridesRow(title):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "phone.fill", backgroundColor: UIColor(rgb: 0x34c759)), title: title, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openCallOverrides()
            })

        // MARK: Tools
        case let .fakeLocationRow(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "location.fill", backgroundColor: UIColor(rgb: 0x007aff)), title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openFakeLocation()
            })
        case let .chatLockRow(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "lock.fill", backgroundColor: UIColor(rgb: 0xff9500)), title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openChatLock()
            })
        case let .fakeAdminRow(title):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "megaphone.fill", backgroundColor: UIColor(rgb: 0xff3b30)), title: title, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openFakeAdmin()
            })
        case let .fakeSubscribersToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "person.3.fill", backgroundColor: UIColor(rgb: 0x30b0c7)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleFakeSubscribers(value)
            })
        case let .fakeBotsRow(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "bitcoinsign.circle.fill", backgroundColor: UIColor(rgb: 0x1b8ed2)), title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openFakeBots()
            })
        case let .fakePortalsToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "gift.fill", backgroundColor: UIColor(rgb: 0x7b61ff)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleFakePortals(value)
            })
        case let .fakeTypingToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "keyboard.fill", backgroundColor: UIColor(rgb: 0xff2d55)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleFakeTyping(value)
            })
        case let .reactionSpammerToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "bolt.heart.fill", backgroundColor: UIColor(rgb: 0xff9500)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleReactionSpammer(value)
            })
        case let .stickerPackClonerToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "doc.on.doc.fill", backgroundColor: UIColor(rgb: 0xaf52de)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleStickerPackCloner(value)
            })
        case let .fakeScreenshotNotificationToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "camera.metering.spot", backgroundColor: UIColor(rgb: 0xff9500)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleFakeScreenshotNotification(value)
            })

        // MARK: Premium
        case let .infinitePinsToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "infinity", backgroundColor: UIColor(rgb: 0x5856d6)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleInfinitePins(value)
            })
        case let .legalPremiumToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "star.circle.fill", backgroundColor: UIColor(rgb: 0xf5a623)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleLegalPremium(value)
            })
        }
    }
}

// MARK: - Entries builder

private func pampGramAdditionalEntries(settings: PampGramSettings) -> [PampGramAdditionalEntry] {
    var entries: [PampGramAdditionalEntry] = []

    entries.append(.aboutText("Другие возможности PampGram: голос, скорость, медиа, профиль, сообщения и инструменты."))

    // ── ИЗМЕНЕНИЕ ГОЛОСА ──
    entries.append(.voiceHeader("ИЗМЕНЕНИЕ ГОЛОСА"))
    entries.append(.voiceToggle("Изменять голос в сообщениях", settings.voiceChangerMessagesEnabled))
    entries.append(.voicePresetRow("Голос", settings.voicePreset.displayName))
    entries.append(.voiceFooter("Только для новых голосовых, до отправки. Звонков не касается."))

    // ── СКОРОСТЬ ПЕРЕДАЧИ ──
    entries.append(.speedHeader("СКОРОСТЬ ПЕРЕДАЧИ"))
    entries.append(.uploadSpeedRow("Ускорение загрузки", settings.uploadSpeedMode.displayName))
    entries.append(.downloadSpeedRow("Ускорение скачивания", settings.downloadSpeedMode.displayName))
    entries.append(.speedFooter("«Турбо» — максимум, который поддерживает сеть Telegram. Реальная скорость всё равно зависит от вашего интернета и сервера."))

    // ── МЕДИА И ЗАЩИТА ──
    entries.append(.mediaHeader("МЕДИА И ЗАЩИТА"))
    entries.append(.viewOnceToggle("Обход одноразовых", settings.bypassViewOnceMediaEnabled))
    entries.append(.timedToggle("Обход с таймером", settings.bypassTimedMediaEnabled))
    entries.append(.markViewedToggle("Отмечать просмотренным", settings.bypassMarkViewedEnabled))
    entries.append(.screenshotsToggle("Сохранение историй", settings.storySavingEnabled))
    entries.append(.chatScreenshotsToggle("Обход скриншотов", settings.bypassScreenshotProtectionEnabled))
    entries.append(.forwardProtectedToSavedToggle("Пересылка в Избранное", settings.forwardProtectedToSavedEnabled))
    entries.append(.autoSaveVideoMessagesToggle("Сохранять кружки", settings.autoSaveVideoMessagesEnabled))
    entries.append(.mediaFooter("• Обход одноразовых — фото/видео «один раз» становится обычным. Открывается в галерее, без размытия, без таймера. Сохранить можно из галереи или через меню PampGram → «Сохранить в галерею».\n• Обход с таймером — медиа с таймером (до 60 сек) остаётся в чате навсегда. Работает аналогично.\n• Отмечать просмотренным — при открытии обойдённого фото у отправителя оно «сгорает» как обычно, а у вас остаётся. Выключите, чтобы отправитель НЕ видел, что вы открывали.\n• Сохранение историй — «Сохранить» для защищённых историй, скриншот/запись экрана работает.\n• Обход скриншотов — скриншот и запись экрана в защищённых чатах и каналах. Секретные чаты не затрагиваются.\n• Пересылка в Избранное — в меню PampGram появляется «В Избранное» для отправки копии медиа в Saved Messages.\n• Сохранять кружки — видеокружки сохраняются в Фотоплёнку при просмотре.\n\nДля сохранения одноразового/таймерного медиа: зажмите сообщение → PampGram → «Сохранить в галерею» или «В Избранное»."))

    // ── ПРОФИЛЬ ──
    entries.append(.profileHeader("ПРОФИЛЬ"))
    entries.append(.hideOwnPhoneToggle("Скрыть номер телефона", settings.hideOwnPhoneNumber))
    entries.append(.fakePhoneNumberRow("Фейковый номер телефона", settings.fakePhoneNumber.isEmpty ? "Выключено" : settings.fakePhoneNumber))
    entries.append(.profileIdsToggle("ID Профилей", settings.profileIdsEnabled))
    entries.append(.accountLinkToggle("Ссылка аккаунта", settings.accountLinkEnabled))
    entries.append(.fakePremiumBadgeToggle("Фейк Premium / верификация", settings.fakePremiumBadgeEnabled))
    entries.append(.fakeDeletedAccountToggle("Фейк «удалил аккаунт»", settings.fakeDeletedAccountEnabled))
    entries.append(.profileFooter("Всё локально — видно только на этом устройстве и на скриншотах.\n• Скрыть номер — прячет настоящий номер из вашего профиля.\n• Фейковый номер — показывает другой номер вместо реального. Нажмите, чтобы ввести.\n• ID Профилей — числовой ID появляется в чужих профилях.\n• Ссылка аккаунта — t.me/username в чужих профилях.\n• Premium / верификация — звёздочка и галочка рядом с вашим именем.\n• «Удалил аккаунт» — ваш профиль выглядит как Deleted Account."))

    // ── СООБЩЕНИЯ И ЧАТ ──
    entries.append(.messagesHeader("СООБЩЕНИЯ И ЧАТ"))
    entries.append(.fakeForwardedFromToggle("Фейк «Переслано от»", settings.fakeForwardedFromEnabled))
    entries.append(.fakeReactionsToggle("Фейк реакции", settings.fakeReactionsEnabled))
    entries.append(.fakeReadReceiptsToggle("Фейк прочитано", settings.fakeReadReceiptsEnabled))
    entries.append(.chatEditorToggle("Редактор чата", settings.chatEditorEnabled))
    entries.append(.chatTimeMachineToggle("Машина времени", settings.chatTimeMachineEnabled))
    entries.append(.invisibleMessagesToggle("Невидимые сообщения", settings.invisibleMessagesEnabled))
    entries.append(.fakeDeletedMessageToggle("Фейк удаления", settings.fakeDeletedMessageEnabled))
    entries.append(.fakeSystemMessagesToggle("Фейк системные сообщения", settings.fakeSystemMessagesEnabled))
    entries.append(.messagesFooter("Действия через контекстное меню сообщения (долгое нажатие).\n• Фейк пересылка — «Переслано от…» → выбор контакта или канала.\n• Фейк реакции — произвольные реакции с нужными цифрами под сообщением.\n• Фейк прочитано — двойные или одинарные галочки по желанию.\n• Редактор чата — правка текста, времени и реакций любого сообщения, включая чужие.\n• Машина времени — «Изменить время» → выбор новой даты и времени отправки.\n• Невидимые — сообщения из невидимых Unicode-символов. Пуш приходит, а в чате пусто.\n• Фейк удаления — показывает что собеседник «удалил» сообщение.\n• Системные сообщения — «Аккаунт верифицирован», «Номер изменён» и т.д. от имени Telegram."))

    // ── ГЕНЕРАТОРЫ ──
    entries.append(.generatorsHeader("ГЕНЕРАТОРЫ"))
    entries.append(.conversationGeneratorToggle("Генератор переписки", settings.conversationGeneratorEnabled))
    entries.append(.fakeGroupGeneratorToggle("Генератор группы", settings.fakeGroupGeneratorEnabled))
    entries.append(.fakePaymentReceiptsToggle("Генератор чеков", settings.fakePaymentReceiptsEnabled))
    entries.append(.generatorsFooter("• Генератор переписки — создаёт диалог с нуля: выбор контакта, реплики за обоих, время и статусы.\n• Генератор группы — фейковый групповой чат с участниками, аватарками и сообщениями.\n• Генератор чеков — реалистичные чеки Stars/TON/Premium с хешем и деталями транзакции."))

    // ── ГОЛОС И ЗВОНКИ ──
    entries.append(.voiceCallsHeader("ГОЛОС И ЗВОНКИ"))
    entries.append(.fakeVoiceFromTextToggle("Голосовое из текста", settings.fakeVoiceFromTextEnabled))
    entries.append(.voiceClonerToggle("Клон голоса", settings.voiceClonerEnabled))
    entries.append(.fakeIncomingCallToggle("Фейк входящий звонок", settings.fakeIncomingCallEnabled))
    entries.append(.callOverridesRow("Настройки звонков"))
    entries.append(.voiceCallsFooter("• Голосовое из текста — вводишь текст, отправляется как голосовое. Мужской или женский голос.\n• Клон голоса — запиши 10 сек образца голоса, потом генерируй голосовые этим голосом.\n• Фейк звонок — полноэкранный входящий звонок от любого контакта с вибрацией и звуком.\n• Настройки звонков — косметическое редактирование отображения звонков."))

    // ── ИНСТРУМЕНТЫ ──
    entries.append(.toolsHeader("ИНСТРУМЕНТЫ"))
    entries.append(.fakeLocationRow("Фейковая геолокация", settings.fakeLocationEnabled ? "Включено" : "Выключено"))
    entries.append(.chatLockRow("Блокировка чатов", settings.chatLockEnabled ? "Включено" : "Выключено"))
    entries.append(.fakeAdminRow("Фейк админ"))
    entries.append(.fakeSubscribersToggle("Фейк подписчики", settings.fakeSubscribersEnabled))
    let fakeBots = pampGramParseFakeBots(settings.fakeBotsRaw)
    let builtInCount = settings.fakeCryptoBotEnabled && !fakeBots.contains(where: { $0.id == PampGramFakeCryptoBotRuntime.officialBotUserId }) ? 1 : 0
    entries.append(.fakeBotsRow("Фейковые боты", "\(fakeBots.count + builtInCount)"))
    entries.append(.fakePortalsToggle("Фейковый Portals", settings.fakePortalsEnabled))
    entries.append(.fakeTypingToggle("Фейк набор текста", settings.fakeTypingEnabled))
    entries.append(.reactionSpammerToggle("Спам реакциями", settings.reactionSpammerEnabled))
    entries.append(.stickerPackClonerToggle("Клон стикерпаков", settings.stickerPackClonerEnabled))
    entries.append(.fakeScreenshotNotificationToggle("Фейк скриншот", settings.fakeScreenshotNotificationEnabled))
    entries.append(.toolsFooter("• Геолокация — отправка поддельного местоположения. Выбор точки на карте.\n• Блокировка чатов — локальный пароль на выбранные чаты.\n• Фейк админ — визуальные посты от имени админа в любом канале.\n• Фейк подписчики — любое число участников в своём канале или группе.\n• Фейковые боты — список ботов с локальным CryptoBot-кошельком внутри.\n• Фейковый Portals — локальная копия мини-аппа @portals с балансами и витриной.\n• Фейк набор текста — в меню чата: «Печатает…» / «Записывает ГС…» без остановки.\n• Спам реакциями — ставит/снимает реакцию в цикле. Непрерывные уведомления.\n• Клон стикерпаков — копия любого пака, включая Premium emoji.\n• Фейк скриншот — отправляет «Сделан снимок экрана» в секретный чат без реального скриншота."))

    // ── ПРЕМИУМ ──
    entries.append(.premiumHeader("ПРЕМИУМ"))
    entries.append(.infinitePinsToggle("Закрепить чаты ∞", settings.infinitePinsEnabled))
    entries.append(.legalPremiumToggle("Легальный премиум", settings.legalPremiumEnabled))
    entries.append(.premiumFooter("• Закрепить чаты ∞ — снимает лимит на число закреплённых чатов и папок на этом устройстве.\n• Легальный премиум — разблокирует часть Premium-функций Telegram локально.\nМожет не синхронизироваться на другие устройства."))

    return entries
}

// MARK: - Pickers

private func pampGramPresentModePicker(context: AccountContext, presentController: (ViewController) -> Void, title: String, current: PampGramSpeedMode, apply: @escaping (PampGramSpeedMode) -> Void) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let sheet = ActionSheetController(presentationData: presentationData)
    var buttons: [ActionSheetItem] = [ActionSheetTextItem(title: title)]
    for mode in PampGramSpeedMode.allCases {
        let label = mode == current ? "✓ \(mode.displayName)" : mode.displayName
        buttons.append(ActionSheetButtonItem(title: label, color: .accent, action: { [weak sheet] in
            sheet?.dismissAnimated()
            apply(mode)
        }))
    }
    sheet.setItemGroups([
        ActionSheetItemGroup(items: buttons),
        ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                sheet?.dismissAnimated()
            })
        ])
    ])
    presentController(sheet)
}

private func pampGramPresentVoicePresetPicker(context: AccountContext, presentController: (ViewController) -> Void, current: PampGramVoicePreset, apply: @escaping (PampGramVoicePreset) -> Void) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let sheet = ActionSheetController(presentationData: presentationData)
    var buttons: [ActionSheetItem] = [ActionSheetTextItem(title: "Голос")]
    for preset in PampGramVoicePreset.allCases {
        let label = preset == current ? "✓ \(preset.displayName)" : preset.displayName
        buttons.append(ActionSheetButtonItem(title: label, color: .accent, action: { [weak sheet] in
            sheet?.dismissAnimated()
            apply(preset)
        }))
    }
    sheet.setItemGroups([
        ActionSheetItemGroup(items: buttons),
        ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                sheet?.dismissAnimated()
            })
        ])
    ])
    presentController(sheet)
}

// MARK: - Controller

public func pampGramAdditionalSettingsController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?

    let arguments = PampGramAdditionalArguments(
        toggleVoiceChanger: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.voiceChangerMessagesEnabled = value
                return settings
            }).start()
        },
        openVoicePreset: {
            let _ = (PampGramCore.settingsSignal(postbox: context.account.postbox) |> take(1) |> deliverOnMainQueue).start(next: { settings in
                pampGramPresentVoicePresetPicker(context: context, presentController: { c in presentControllerImpl?(c) }, current: settings.voicePreset, apply: { preset in
                    let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                        var settings = settings
                        settings.voicePreset = preset
                        return settings
                    }).start()
                })
            })
        },
        openUploadSpeed: {
            let _ = (PampGramCore.settingsSignal(postbox: context.account.postbox) |> take(1) |> deliverOnMainQueue).start(next: { settings in
                pampGramPresentModePicker(context: context, presentController: { c in presentControllerImpl?(c) }, title: "Ускорение загрузки", current: settings.uploadSpeedMode, apply: { mode in
                    let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                        var settings = settings
                        settings.uploadSpeedMode = mode
                        return settings
                    }).start()
                })
            })
        },
        openDownloadSpeed: {
            let _ = (PampGramCore.settingsSignal(postbox: context.account.postbox) |> take(1) |> deliverOnMainQueue).start(next: { settings in
                pampGramPresentModePicker(context: context, presentController: { c in presentControllerImpl?(c) }, title: "Ускорение скачивания", current: settings.downloadSpeedMode, apply: { mode in
                    let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                        var settings = settings
                        settings.downloadSpeedMode = mode
                        return settings
                    }).start()
                })
            })
        },
        openFakeLocation: {
            pushControllerImpl?(pampGramFakeLocationController(context: context))
        },
        openChatLock: {
            pushControllerImpl?(pampGramChatLockController(context: context))
        },
        openCallOverrides: {
            pushControllerImpl?(pampGramCallOverridesController(context: context))
        },
        openFakeAdmin: {
            pushControllerImpl?(pampGramFakeAdminController(context: context))
        },
        toggleInfinitePins: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.infinitePinsEnabled = value
                return settings
            }).start()
        },
        toggleLegalPremium: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.legalPremiumEnabled = value
                return settings
            }).start()
        },
        toggleBypassViewOnceMedia: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.bypassViewOnceMediaEnabled = value
                return settings
            }).start()
        },
        toggleBypassTimedMedia: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.bypassTimedMediaEnabled = value
                return settings
            }).start()
        },
        toggleBypassMarkViewed: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.bypassMarkViewedEnabled = value
                return settings
            }).start()
        },
        toggleStorySaving: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.storySavingEnabled = value
                return settings
            }).start()
        },
        toggleScreenshotBypass: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.bypassScreenshotProtectionEnabled = value
                return settings
            }).start()
        },
        toggleForwardProtectedToSaved: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.forwardProtectedToSavedEnabled = value
                return settings
            }).start()
        },
        toggleAutoSaveVideoMessages: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.autoSaveVideoMessagesEnabled = value
                return settings
            }).start()
        },
        toggleFakeTyping: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.fakeTypingEnabled = value
                return settings
            }).start()
        },
        toggleHideOwnPhone: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.hideOwnPhoneNumber = value
                return settings
            }).start()
        },
        openFakePhoneNumber: {
            let _ = (PampGramCore.settingsSignal(postbox: context.account.postbox) |> take(1) |> deliverOnMainQueue).start(next: { settings in
                presentControllerImpl?(promptController(
                    context: context,
                    text: "Фейковый номер телефона",
                    subtitle: "Показывается вместо настоящего — в настройках и в «Моём профиле». Пусто — выключено.",
                    value: settings.fakePhoneNumber,
                    placeholder: "+1 234 567 89 00",
                    characterLimit: 32,
                    apply: { value in
                        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                            var settings = settings
                            settings.fakePhoneNumber = trimmed
                            return settings
                        }).start()
                    }
                ))
            })
        },
        toggleProfileIds: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.profileIdsEnabled = value
                return settings
            }).start()
        },
        toggleAccountLink: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.accountLinkEnabled = value
                return settings
            }).start()
        },
        openFakeBots: {
            pushControllerImpl?(pampGramFakeBotsController(context: context))
        },
        toggleFakeForwardedFrom: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.fakeForwardedFromEnabled = value
                return settings
            }).start()
        },
        toggleFakeReactions: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.fakeReactionsEnabled = value
                return settings
            }).start()
        },
        toggleFakePremiumBadge: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.fakePremiumBadgeEnabled = value
                return settings
            }).start()
        },
        toggleFakeSubscribers: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.fakeSubscribersEnabled = value
                return settings
            }).start()
        },
        toggleFakeReadReceipts: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.fakeReadReceiptsEnabled = value
                return settings
            }).start()
        },
        toggleChatEditor: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.chatEditorEnabled = value
                return settings
            }).start()
        },
        toggleConversationGenerator: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.conversationGeneratorEnabled = value
                return settings
            }).start()
        },
        toggleFakeDeletedMessage: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.fakeDeletedMessageEnabled = value
                return settings
            }).start()
        },
        toggleInvisibleMessages: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.invisibleMessagesEnabled = value
                return settings
            }).start()
        },
        toggleReactionSpammer: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.reactionSpammerEnabled = value
                return settings
            }).start()
        },
        toggleFakeVoiceFromText: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.fakeVoiceFromTextEnabled = value
                return settings
            }).start()
        },
        toggleStickerPackCloner: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.stickerPackClonerEnabled = value
                return settings
            }).start()
        },
        toggleFakePortals: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.fakePortalsEnabled = value
                return settings
            }).start()
        },
        toggleFakeSystemMessages: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.fakeSystemMessagesEnabled = value
                return settings
            }).start()
        },
        toggleFakePaymentReceipts: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.fakePaymentReceiptsEnabled = value
                return settings
            }).start()
        },
        toggleVoiceCloner: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.voiceClonerEnabled = value
                return settings
            }).start()
        },
        toggleChatTimeMachine: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.chatTimeMachineEnabled = value
                return settings
            }).start()
        },
        toggleFakeIncomingCall: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.fakeIncomingCallEnabled = value
                return settings
            }).start()
        },
        toggleFakeScreenshotNotification: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.fakeScreenshotNotificationEnabled = value
                return settings
            }).start()
        },
        toggleFakeDeletedAccount: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.fakeDeletedAccountEnabled = value
                return settings
            }).start()
        },
        toggleFakeGroupGenerator: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.fakeGroupGeneratorEnabled = value
                return settings
            }).start()
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        PampGramCore.settingsSignal(postbox: context.account.postbox)
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Дополнительно"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: pampGramAdditionalEntries(settings: settings),
            style: .blocks,
            animateChanges: true
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        controller?.push(c)
    }
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}
