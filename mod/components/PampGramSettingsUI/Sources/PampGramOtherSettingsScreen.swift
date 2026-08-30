import Foundation
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext
import PampGramCore

private final class PampGramOtherArguments {
    let toggleCopyProtectionBypass: (Bool) -> Void
    let toggleShowForwardOrigin: (Bool) -> Void
    let toggleDisableAutoDelete: (Bool) -> Void
    let toggleScreenshotProtectionBypass: (Bool) -> Void
    let toggleHideChatOnScreenshots: (Bool) -> Void
    let toggleAdBlock: (Bool) -> Void

    init(
        toggleCopyProtectionBypass: @escaping (Bool) -> Void,
        toggleShowForwardOrigin: @escaping (Bool) -> Void,
        toggleDisableAutoDelete: @escaping (Bool) -> Void,
        toggleScreenshotProtectionBypass: @escaping (Bool) -> Void,
        toggleHideChatOnScreenshots: @escaping (Bool) -> Void,
        toggleAdBlock: @escaping (Bool) -> Void
    ) {
        self.toggleCopyProtectionBypass = toggleCopyProtectionBypass
        self.toggleShowForwardOrigin = toggleShowForwardOrigin
        self.toggleDisableAutoDelete = toggleDisableAutoDelete
        self.toggleScreenshotProtectionBypass = toggleScreenshotProtectionBypass
        self.toggleHideChatOnScreenshots = toggleHideChatOnScreenshots
        self.toggleAdBlock = toggleAdBlock
    }
}

private enum PampGramOtherSection: Int32 {
    case about
    case features
}

private enum PampGramOtherEntry: ItemListNodeEntry {
    case aboutText(String)
    case featuresHeader(String)
    case copyProtectionBypass(String, Bool)
    case showForwardOrigin(String, Bool)
    case disableAutoDelete(String, Bool)
    case screenshotProtectionBypass(String, Bool)
    case hideChatOnScreenshots(String, Bool)
    case adBlock(String, Bool)
    case featuresFooter(String)

    var section: ItemListSectionId {
        switch self {
        case .aboutText:
            return PampGramOtherSection.about.rawValue
        case .featuresHeader, .copyProtectionBypass, .showForwardOrigin, .disableAutoDelete,
             .screenshotProtectionBypass, .hideChatOnScreenshots, .adBlock, .featuresFooter:
            return PampGramOtherSection.features.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .aboutText:
            return 0
        case .featuresHeader:
            return 1
        case .copyProtectionBypass:
            return 2
        case .showForwardOrigin:
            return 3
        case .disableAutoDelete:
            return 4
        case .screenshotProtectionBypass:
            return 5
        case .hideChatOnScreenshots:
            return 6
        case .adBlock:
            return 7
        case .featuresFooter:
            return 8
        }
    }

    static func <(lhs: PampGramOtherEntry, rhs: PampGramOtherEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramOtherArguments
        switch self {
        case let .aboutText(text), let .featuresFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .featuresHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .copyProtectionBypass(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: arguments.toggleCopyProtectionBypass)
        case let .showForwardOrigin(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: arguments.toggleShowForwardOrigin)
        case let .disableAutoDelete(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: arguments.toggleDisableAutoDelete)
        case let .screenshotProtectionBypass(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: arguments.toggleScreenshotProtectionBypass)
        case let .hideChatOnScreenshots(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: arguments.toggleHideChatOnScreenshots)
        case let .adBlock(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: arguments.toggleAdBlock)
        }
    }
}

private func pampGramOtherEntries(settings: PampGramSettings) -> [PampGramOtherEntry] {
    return [
        .aboutText("Личные полезные функции. Изменения действуют только на этом устройстве."),
        .featuresHeader("ФУНКЦИИ"),
        .copyProtectionBypass("Обход защиты от копирования", settings.copyProtectionBypassEnabled),
        .showForwardOrigin("Добавлять от кого переслано", settings.showForwardOriginEnabled),
        .disableAutoDelete("Отключить автоудаление исчезающих сообщений", settings.disableAutoDeleteEnabled),
        .screenshotProtectionBypass("Обход защиты от скриншотов", settings.screenshotProtectionBypassEnabled),
        .hideChatOnScreenshots("Скрывать чат на скриншотах", settings.hideChatOnScreenshotsEnabled),
        .adBlock("Блокировать рекламу", settings.adBlockEnabled),
        .featuresFooter("Переключатели меняют только поведение клиента. Серверные ограничения Telegram и содержимое секретных чатов не расшифровываются и не изменяются.")
    ]
}

/// The first six local-only switches from the "Прочее" section.
public func pampGramOtherSettingsController(context: AccountContext) -> ViewController {
    let update: (@escaping (inout PampGramSettings) -> Void) -> Void = { change in
        let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
            var settings = settings
            change(&settings)
            return settings
        }).start()
    }

    let arguments = PampGramOtherArguments(
        toggleCopyProtectionBypass: { value in
            update { $0.copyProtectionBypassEnabled = value }
        },
        toggleShowForwardOrigin: { value in
            update { $0.showForwardOriginEnabled = value }
        },
        toggleDisableAutoDelete: { value in
            update { $0.disableAutoDeleteEnabled = value }
        },
        toggleScreenshotProtectionBypass: { value in
            update { $0.screenshotProtectionBypassEnabled = value }
        },
        toggleHideChatOnScreenshots: { value in
            update { $0.hideChatOnScreenshotsEnabled = value }
        },
        toggleAdBlock: { value in
            update { $0.adBlockEnabled = value }
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
            title: .text("Прочее"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: pampGramOtherEntries(settings: settings),
            style: .blocks,
            animateChanges: true
        )
        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
