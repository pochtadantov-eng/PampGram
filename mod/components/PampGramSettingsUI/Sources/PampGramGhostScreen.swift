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
    let toggleMaster: (Bool) -> Void
    let toggleScreenshotBypass: (Bool) -> Void
    let toggleHideChatOnScreenshot: (Bool) -> Void
    let toggleHideReadReceipts: (Bool) -> Void
    let toggleHideStoryViews: (Bool) -> Void
    let toggleHideOnline: (Bool) -> Void
    let toggleHideTyping: (Bool) -> Void
    let toggleAutoOffline: (Bool) -> Void
    let toggleReadOnAction: (Bool) -> Void
    let toggleExcludeAllChannels: (Bool) -> Void
    let toggleExcludeAllGroups: (Bool) -> Void
    let openFolders: () -> Void
    let openExceptions: () -> Void

    init(toggleMaster: @escaping (Bool) -> Void, toggleScreenshotBypass: @escaping (Bool) -> Void, toggleHideChatOnScreenshot: @escaping (Bool) -> Void, toggleHideReadReceipts: @escaping (Bool) -> Void, toggleHideStoryViews: @escaping (Bool) -> Void, toggleHideOnline: @escaping (Bool) -> Void, toggleHideTyping: @escaping (Bool) -> Void, toggleAutoOffline: @escaping (Bool) -> Void, toggleReadOnAction: @escaping (Bool) -> Void, toggleExcludeAllChannels: @escaping (Bool) -> Void, toggleExcludeAllGroups: @escaping (Bool) -> Void, openFolders: @escaping () -> Void, openExceptions: @escaping () -> Void) {
        self.toggleMaster = toggleMaster
        self.toggleScreenshotBypass = toggleScreenshotBypass
        self.toggleHideChatOnScreenshot = toggleHideChatOnScreenshot
        self.toggleHideReadReceipts = toggleHideReadReceipts
        self.toggleHideStoryViews = toggleHideStoryViews
        self.toggleHideOnline = toggleHideOnline
        self.toggleHideTyping = toggleHideTyping
        self.toggleAutoOffline = toggleAutoOffline
        self.toggleReadOnAction = toggleReadOnAction
        self.toggleExcludeAllChannels = toggleExcludeAllChannels
        self.toggleExcludeAllGroups = toggleExcludeAllGroups
        self.openFolders = openFolders
        self.openExceptions = openExceptions
    }
}

private enum PampGramGhostSection: Int32 {
    case master
    case features
    case exceptions
}

private enum PampGramGhostEntry: ItemListNodeEntry {
    case masterToggle(String, Bool)
    case masterFooter(String)

    case featuresHeader(String)
    case screenshotBypass(String, Bool)
    case hideChatOnScreenshot(String, Bool)
    case hideReadReceipts(String, Bool, Bool)
    case hideStoryViews(String, Bool, Bool)
    case hideOnline(String, Bool, Bool)
    case hideTyping(String, Bool, Bool)
    case autoOffline(String, Bool, Bool)
    case readOnAction(String, Bool, Bool)
    case featuresFooter(String)

    case exceptionsHeader(String)
    case excludeAllChannels(String, Bool, Bool)
    case excludeAllGroups(String, Bool, Bool)
    case foldersRow(String, String, Bool)
    case exceptionsRow(String, String, Bool)
    case exceptionsFooter(String)

    var section: ItemListSectionId {
        switch self {
        case .masterToggle, .masterFooter:
            return PampGramGhostSection.master.rawValue
        case .featuresHeader, .screenshotBypass, .hideChatOnScreenshot, .hideReadReceipts, .hideStoryViews, .hideOnline, .hideTyping, .autoOffline, .readOnAction, .featuresFooter:
            return PampGramGhostSection.features.rawValue
        case .exceptionsHeader, .excludeAllChannels, .excludeAllGroups, .foldersRow, .exceptionsRow, .exceptionsFooter:
            return PampGramGhostSection.exceptions.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .masterToggle:
            return 0
        case .masterFooter:
            return 1
        case .featuresHeader:
            return 2
        case .screenshotBypass:
            return 3
        case .hideChatOnScreenshot:
            return 4
        case .hideReadReceipts:
            return 5
        case .hideStoryViews:
            return 6
        case .hideOnline:
            return 7
        case .hideTyping:
            return 8
        case .autoOffline:
            return 9
        case .readOnAction:
            return 10
        case .featuresFooter:
            return 11
        case .exceptionsHeader:
            return 12
        case .excludeAllChannels:
            return 13
        case .excludeAllGroups:
            return 14
        case .foldersRow:
            return 15
        case .exceptionsRow:
            return 16
        case .exceptionsFooter:
            return 17
        }
    }

    static func <(lhs: PampGramGhostEntry, rhs: PampGramGhostEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramGhostArguments
        switch self {
        case let .masterFooter(text), let .featuresFooter(text), let .exceptionsFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .featuresHeader(text), let .exceptionsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .masterToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleMaster(value)
            })
        case let .screenshotBypass(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleScreenshotBypass(value)
            })
        case let .hideChatOnScreenshot(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleHideChatOnScreenshot(value)
            })
        case let .hideReadReceipts(title, value, enabled):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, enabled: enabled, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleHideReadReceipts(value)
            })
        case let .hideStoryViews(title, value, enabled):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, enabled: enabled, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleHideStoryViews(value)
            })
        case let .hideOnline(title, value, enabled):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, enabled: enabled, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleHideOnline(value)
            })
        case let .hideTyping(title, value, enabled):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, enabled: enabled, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleHideTyping(value)
            })
        case let .autoOffline(title, value, enabled):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, enabled: enabled, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleAutoOffline(value)
            })
        case let .readOnAction(title, value, enabled):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, enabled: enabled, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleReadOnAction(value)
            })
        case let .excludeAllChannels(title, value, enabled):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, enabled: enabled, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleExcludeAllChannels(value)
            })
        case let .excludeAllGroups(title, value, enabled):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, enabled: enabled, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleExcludeAllGroups(value)
            })
        case let .foldersRow(title, label, enabled):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, enabled: enabled, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openFolders()
            })
        case let .exceptionsRow(title, label, enabled):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, enabled: enabled, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openExceptions()
            })
        }
    }
}

private func pampGramGhostEntries(settings: PampGramSettings, folderCount: Int, exceptionCount: Int) -> [PampGramGhostEntry] {
    var entries: [PampGramGhostEntry] = []

    let on = settings.ghostModeEnabled

    entries.append(.masterToggle("Режим призрака", settings.ghostModeEnabled))
    entries.append(.masterFooter("Когда включён, выбранные функции приватности будут активны. Всё меняет только то, что видят о вас другие — ничего чужого не читается и не сохраняется."))

    entries.append(.featuresHeader("ФУНКЦИИ"))
    entries.append(.screenshotBypass("Обход защиты от скриншотов", settings.screenshotBypassEnabled))
    entries.append(.hideChatOnScreenshot("Скрывать чат на скриншотах", settings.hideChatOnScreenshot))
    entries.append(.hideReadReceipts("Не читать сообщения", settings.ghostHideReadReceipts, on))
    entries.append(.hideStoryViews("Не читать истории", settings.ghostHideStoryViews, on))
    entries.append(.hideOnline("Не отправлять «онлайн»", settings.ghostHideOnline, on))
    entries.append(.hideTyping("Не отправлять «печатает»", settings.ghostHideTyping, on))
    entries.append(.autoOffline("Автоматический «офлайн»", settings.ghostAutoOffline, on))
    entries.append(.readOnAction("Читать при действиях", settings.ghostReadOnAction, on))
    entries.append(.featuresFooter("Прочтения, истории и «печатает» скрываются пофайлово по каждому чату (учитывая исключения ниже). «Онлайн» и «офлайн» — общий статус аккаунта, к ним исключения не применяются. «Читать при действиях»: как только вы написали в чат, прочтения в нём снова отправляются — вы уже обозначили присутствие."))

    entries.append(.exceptionsHeader("ИСКЛЮЧЕНИЯ"))
    entries.append(.excludeAllChannels("Все каналы", settings.ghostExcludeAllChannels, on))
    entries.append(.excludeAllGroups("Все группы", settings.ghostExcludeAllGroups, on))
    entries.append(.foldersRow("Папки", folderCount == 0 ? "Не выбрано" : "\(folderCount)", on))
    entries.append(.exceptionsRow("Добавить исключение", exceptionCount == 0 ? "" : "\(exceptionCount)", on))
    entries.append(.exceptionsFooter("Режим призрака не действует в выбранных чатах, типах чатов или папках. Для папок учитываются чаты, добавленные в папку вручную."))

    return entries
}

/// The "Ghost" section ("Режим призрака"): a master switch plus granular controls over what
/// this account broadcasts about itself — read receipts, story views, online status, typing —
/// and a set of exceptions (all channels, all groups, chat folders, individual chats) where
/// none of it applies. Every option only ever withholds or overrides THIS account's own
/// outgoing signals; nothing here reads or stores anyone else's data. All client-side.
public func pampGramGhostSettingsController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?

    let updateSettings: (@escaping (PampGramSettings) -> PampGramSettings) -> Void = { f in
        let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, f).start()
    }

    let arguments = PampGramGhostArguments(
        toggleMaster: { value in
            updateSettings { settings in
                var settings = settings
                settings.ghostModeEnabled = value
                return settings
            }
        },
        toggleScreenshotBypass: { value in
            updateSettings { settings in
                var settings = settings
                settings.screenshotBypassEnabled = value
                return settings
            }
        },
        toggleHideChatOnScreenshot: { value in
            updateSettings { settings in
                var settings = settings
                settings.hideChatOnScreenshot = value
                return settings
            }
        },
        toggleHideReadReceipts: { value in
            updateSettings { settings in
                var settings = settings
                settings.ghostHideReadReceipts = value
                return settings
            }
        },
        toggleHideStoryViews: { value in
            updateSettings { settings in
                var settings = settings
                settings.ghostHideStoryViews = value
                return settings
            }
        },
        toggleHideOnline: { value in
            updateSettings { settings in
                var settings = settings
                settings.ghostHideOnline = value
                return settings
            }
        },
        toggleHideTyping: { value in
            updateSettings { settings in
                var settings = settings
                settings.ghostHideTyping = value
                return settings
            }
        },
        toggleAutoOffline: { value in
            updateSettings { settings in
                var settings = settings
                settings.ghostAutoOffline = value
                return settings
            }
        },
        toggleReadOnAction: { value in
            updateSettings { settings in
                var settings = settings
                settings.ghostReadOnAction = value
                return settings
            }
        },
        toggleExcludeAllChannels: { value in
            updateSettings { settings in
                var settings = settings
                settings.ghostExcludeAllChannels = value
                return settings
            }
        },
        toggleExcludeAllGroups: { value in
            updateSettings { settings in
                var settings = settings
                settings.ghostExcludeAllGroups = value
                return settings
            }
        },
        openFolders: {
            pushControllerImpl?(pampGramGhostFoldersController(context: context))
        },
        openExceptions: {
            pushControllerImpl?(pampGramGhostExceptionsController(context: context))
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
            title: .text("Режим призрака"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: pampGramGhostEntries(settings: settings, folderCount: settings.ghostExcludedFolderIds.count, exceptionCount: settings.ghostExcludedPeerIds.count),
            style: .blocks,
            animateChanges: true
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        controller?.push(c)
    }
    return controller
}
