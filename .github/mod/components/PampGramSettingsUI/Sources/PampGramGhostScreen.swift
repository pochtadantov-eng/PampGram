import Foundation
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import UndoUI
import PampGramCore

private final class PampGramGhostArguments {
    let toggleGhostReader: (Bool) -> Void
    let toggleOnlineMask: (Bool) -> Void
    let toggleScreenshotProtectionBypass: (Bool) -> Void
    let toggleHideChatOnScreenshots: (Bool) -> Void
    let openChatLock: () -> Void

    init(toggleGhostReader: @escaping (Bool) -> Void, toggleOnlineMask: @escaping (Bool) -> Void, toggleScreenshotProtectionBypass: @escaping (Bool) -> Void, toggleHideChatOnScreenshots: @escaping (Bool) -> Void, openChatLock: @escaping () -> Void) {
        self.toggleGhostReader = toggleGhostReader
        self.toggleOnlineMask = toggleOnlineMask
        self.toggleScreenshotProtectionBypass = toggleScreenshotProtectionBypass
        self.toggleHideChatOnScreenshots = toggleHideChatOnScreenshots
        self.openChatLock = openChatLock
    }
}

private enum PampGramGhostSection: Int32 {
    case about
    case ghostReader
    case onlineMask
    case screenshots
    case security
}

private enum PampGramGhostEntry: ItemListNodeEntry {
    case aboutText(String)

    case ghostReaderToggle(String, Bool)
    case ghostReaderFooter(String)

    case onlineMaskToggle(String, Bool)
    case onlineMaskFooter(String)

    case screenshotsHeader(String)
    case screenshotProtectionBypass(String, Bool)
    case hideChatOnScreenshots(String, Bool)
    case screenshotsFooter(String)

    case securityHeader(String)
    case chatLock(String, String)
    case securityFooter(String)

    var section: ItemListSectionId {
        switch self {
        case .aboutText:
            return PampGramGhostSection.about.rawValue
        case .ghostReaderToggle, .ghostReaderFooter:
            return PampGramGhostSection.ghostReader.rawValue
        case .onlineMaskToggle, .onlineMaskFooter:
            return PampGramGhostSection.onlineMask.rawValue
        case .screenshotsHeader, .screenshotProtectionBypass, .hideChatOnScreenshots, .screenshotsFooter:
            return PampGramGhostSection.screenshots.rawValue
        case .securityHeader, .chatLock, .securityFooter:
            return PampGramGhostSection.security.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .aboutText: return 0
        case .ghostReaderToggle: return 1
        case .ghostReaderFooter: return 2
        case .onlineMaskToggle: return 3
        case .onlineMaskFooter: return 4
        case .screenshotsHeader: return 5
        case .screenshotProtectionBypass: return 6
        case .hideChatOnScreenshots: return 7
        case .screenshotsFooter: return 8
        case .securityHeader: return 9
        case .chatLock: return 10
        case .securityFooter: return 11
        }
    }

    static func <(lhs: PampGramGhostEntry, rhs: PampGramGhostEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramGhostArguments
        switch self {
        case let .aboutText(text), let .ghostReaderFooter(text), let .onlineMaskFooter(text), let .screenshotsFooter(text), let .securityFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .screenshotsHeader(text), let .securityHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .ghostReaderToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleGhostReader(value)
            })
        case let .onlineMaskToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleOnlineMask(value)
            })
        case let .screenshotProtectionBypass(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: arguments.toggleScreenshotProtectionBypass)
        case let .hideChatOnScreenshots(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: arguments.toggleHideChatOnScreenshots)
        case let .chatLock(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, action: arguments.openChatLock)
        }
    }
}

private func pampGramGhostEntries(settings: PampGramSettings) -> [PampGramGhostEntry] {
    var entries: [PampGramGhostEntry] = []

    entries.append(.aboutText("Меняет то, что видят о вас другие. Включён может быть только один режим ниже."))

    entries.append(.ghostReaderToggle("Нечиталка", settings.ghostReaderEnabled))
    entries.append(.ghostReaderFooter("Скрывает прочтение, «в сети», набор текста и отправку файлов. У вас всё работает как обычно."))

    entries.append(.onlineMaskToggle("Маскировка онлайна", settings.onlineMaskEnabled))
    entries.append(.onlineMaskFooter("Держит статус «в сети», пока даёт iOS. Также включает приватность «Последний визит» → «Все» — иначе статус никто не увидит."))

    entries.append(.screenshotsHeader("СКРИНШОТЫ И ЗАХВАТ ЭКРАНА"))
    entries.append(.screenshotProtectionBypass("Обход защиты от скриншотов", settings.screenshotProtectionBypassEnabled))
    entries.append(.hideChatOnScreenshots("Скрывать чат на скриншотах", settings.hideChatOnScreenshotsEnabled))
    entries.append(.screenshotsFooter("Настройки захвата экрана для обычных облачных чатов."))

    entries.append(.securityHeader("ЛОКАЛЬНАЯ ЗАЩИТА"))
    entries.append(.chatLock("Блокировка чатов", settings.chatLockEnabled ? "Включено" : "Выключено"))
    entries.append(.securityFooter("PIN-защита выбранных чатов хранится и проверяется локально на этом устройстве."))

    return entries
}

/// The "Ghost" section (formerly the unimplemented "Приватность" placeholder): presence and
/// activity concealment — the one part of PampGram that changes what OTHER people see, not
/// just what this device shows its own owner. Still entirely client-side: nothing here reads
/// or stores anyone else's data, it only withholds or overrides this account's own outgoing
/// status signals.
public func pampGramGhostSettingsController(context: AccountContext) -> ViewController {
    var presentTooltipImpl: ((String) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?

    let arguments = PampGramGhostArguments(
        toggleGhostReader: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.ghostReaderEnabled = value
                if value {
                    settings.onlineMaskEnabled = false
                }
                return settings
            }).start()
        },
        toggleOnlineMask: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.onlineMaskEnabled = value
                if value {
                    settings.ghostReaderEnabled = false
                }
                return settings
            }).start()

            if value {
                // The mask only works end to end if the "Last Seen & Online" privacy rule
                // actually lets people see the status we're now broadcasting — with it
                // restricted (e.g. "Nobody"), Telegram's own privacy engine hides the online
                // status server-side regardless of what we send, and the mask would do
                // nothing visible. Switching it to "Everybody" is what makes the toggle's own
                // promise true, exactly like turning on the mask should.
                let _ = context.engine.privacy.updateSelectiveAccountPrivacySettings(type: .presence, settings: .enableEveryone(disableFor: [:])).start()
                presentTooltipImpl?("Настройка приватности «Последний визит и онлайн» переключена на «Все» — иначе маскировку никто не увидит.")
            }
        },
        toggleScreenshotProtectionBypass: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.screenshotProtectionBypassEnabled = value
                return settings
            }).start()
        },
        toggleHideChatOnScreenshots: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.hideChatOnScreenshotsEnabled = value
                return settings
            }).start()
        },
        openChatLock: {
            pushControllerImpl?(pampGramChatLockController(context: context))
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
            title: .text("Ghost"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: pampGramGhostEntries(settings: settings),
            style: .blocks,
            animateChanges: true
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in controller?.push(c) }
    presentTooltipImpl = { [weak controller] text in
        guard let controller else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        controller.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), in: .current)
    }
    return controller
}
