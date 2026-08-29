import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import PampGramCore

private enum PampGramHubSection: Int32 {
    case hero
    case sections
    case status
    case team
}

private enum PampGramHubEntry: ItemListNodeEntry {
    case hero
    case gifts
    case messages
    case privacy
    case appearance
    case advanced
    case status(Bool)
    case team

    var section: ItemListSectionId {
        switch self {
        case .hero:
            return PampGramHubSection.hero.rawValue
        case .gifts, .messages, .privacy, .appearance, .advanced:
            return PampGramHubSection.sections.rawValue
        case .status:
            return PampGramHubSection.status.rawValue
        case .team:
            return PampGramHubSection.team.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .hero:
            return 0
        case .gifts:
            return 1
        case .messages:
            return 2
        case .privacy:
            return 3
        case .appearance:
            return 4
        case .advanced:
            return 5
        case .status:
            return 6
        case .team:
            return 7
        }
    }

    static func <(lhs: PampGramHubEntry, rhs: PampGramHubEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramHubArguments
        switch self {
        case .hero:
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: pampGramSettingsIcon(),
                title: "PampGram",
                titleFont: .bold,
                titleBadge: "MOD",
                label: "v1.0.0 (Stable)",
                additionalDetailLabel: "Расширяй. Скрывай. Контролируй.",
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .none,
                action: nil
            )
        case .gifts:
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: generatePampGramSectionIcon(systemName: "gift.fill", backgroundColor: UIColor(rgb: 0x8e44ec)),
                title: "Подарки",
                titleFont: .bold,
                label: "",
                additionalDetailLabel: "Управление подарками и визуалами",
                sectionId: self.section,
                style: .blocks,
                action: {
                    arguments.openGifts()
                }
            )
        case .messages:
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: generatePampGramSectionIcon(systemName: "message.fill", backgroundColor: UIColor(rgb: 0x3b82f6)),
                title: "Сообщения",
                titleFont: .bold,
                label: "",
                additionalDetailLabel: "Визуальный редактор и история",
                sectionId: self.section,
                style: .blocks,
                action: {
                    arguments.openMessages()
                }
            )
        case .privacy:
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: generatePampGramSectionIcon(systemName: "lock.fill", backgroundColor: UIColor(rgb: 0x34c759)),
                title: "Приватность",
                titleFont: .bold,
                label: "",
                additionalDetailLabel: "Скрытые функции и защита",
                sectionId: self.section,
                style: .blocks,
                action: {
                    arguments.openPlaceholder("Приватность")
                }
            )
        case .appearance:
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: generatePampGramSectionIcon(systemName: "paintbrush.fill", backgroundColor: UIColor(rgb: 0xff9500)),
                title: "Внешний вид",
                titleFont: .bold,
                label: "",
                additionalDetailLabel: "Темы, иконки, интерфейс",
                sectionId: self.section,
                style: .blocks,
                action: {
                    arguments.openPlaceholder("Внешний вид")
                }
            )
        case .advanced:
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: generatePampGramSectionIcon(systemName: "gearshape.fill", backgroundColor: UIColor(rgb: 0x8e8e93)),
                title: "Дополнительно",
                titleFont: .bold,
                label: "",
                additionalDetailLabel: "Другие возможности PampGram",
                sectionId: self.section,
                style: .blocks,
                action: {
                    arguments.openPlaceholder("Дополнительно")
                }
            )
        case let .status(allActive):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: generatePampGramSectionIcon(systemName: "checkmark.shield.fill", backgroundColor: UIColor(rgb: 0x8e44ec)),
                title: "Статус",
                titleFont: .bold,
                label: "",
                additionalDetailLabel: allActive ? "Все функции активны" : "Часть функций отключена",
                additionalDetailLabelColor: allActive ? .constructive : .generic,
                sectionId: self.section,
                style: .blocks,
                action: {
                    arguments.openStatus()
                }
            )
        case .team:
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: pampGramSettingsIcon(),
                title: "PampGram Team",
                label: "",
                additionalDetailLabel: "Сделано с 💜 для тебя",
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .none,
                action: nil
            )
        }
    }
}

private final class PampGramHubArguments {
    let openGifts: () -> Void
    let openMessages: () -> Void
    let openPlaceholder: (String) -> Void
    let openStatus: () -> Void

    init(openGifts: @escaping () -> Void, openMessages: @escaping () -> Void, openPlaceholder: @escaping (String) -> Void, openStatus: @escaping () -> Void) {
        self.openGifts = openGifts
        self.openMessages = openMessages
        self.openPlaceholder = openPlaceholder
        self.openStatus = openStatus
    }
}

private func pampGramHubEntries(settings: PampGramSettings) -> [PampGramHubEntry] {
    let allActive = settings.phantomGiftsEnabled && settings.fakeStarsDisplayEnabled && settings.fakeTonDisplayEnabled && settings.antiDeleteMessagesEnabled
    return [
        .hero,
        .gifts,
        .messages,
        .privacy,
        .appearance,
        .advanced,
        .status(allActive),
        .team
    ]
}

/// The PampGram root screen: a hub of sections rather than one long list, so unrelated
/// features (gifts/balances, message history, and whatever future PampGram screens need) each
/// get their own page instead of piling into a single scroll.
public func pampGramSettingsController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?

    let arguments = PampGramHubArguments(
        openGifts: {
            pushControllerImpl?(pampGramGiftsSettingsController(context: context))
        },
        openMessages: {
            pushControllerImpl?(pampGramMessagesSettingsController(context: context))
        },
        openPlaceholder: { title in
            pushControllerImpl?(pampGramPlaceholderController(context: context, title: title))
        },
        openStatus: {
            pushControllerImpl?(pampGramStatusController(context: context))
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
            title: .text("PampGram"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: pampGramHubEntries(settings: settings),
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
