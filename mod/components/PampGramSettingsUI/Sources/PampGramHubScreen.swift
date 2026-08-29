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
    case status(Int, Int)
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
                label: pampGramVersionString,
                additionalDetailLabel: "Расширяй. Скрывай. Контролируй.",
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .none,
                action: {
                    arguments.openAbout()
                }
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
                title: "Удалённые сообщения",
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
                icon: generatePampGramSectionIcon(systemName: "eye.slash.fill", backgroundColor: UIColor(rgb: 0x34c759)),
                title: "Ghost",
                titleFont: .bold,
                label: "",
                additionalDetailLabel: "Скрытые функции и защита",
                sectionId: self.section,
                style: .blocks,
                action: {
                    arguments.openGhost()
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
        case let .status(activeCount, totalCount):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: generatePampGramSectionIcon(systemName: "checkmark.shield.fill", backgroundColor: UIColor(rgb: 0x8e44ec)),
                title: "Статус",
                titleFont: .bold,
                label: "",
                additionalDetailLabel: "\(activeCount) из \(totalCount) функций активны",
                additionalDetailLabelColor: activeCount == totalCount ? .constructive : .generic,
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
                action: {
                    arguments.openSupport()
                }
            )
        }
    }
}

private final class PampGramHubArguments {
    let openGifts: () -> Void
    let openMessages: () -> Void
    let openGhost: () -> Void
    let openPlaceholder: (String) -> Void
    let openStatus: () -> Void
    let openAbout: () -> Void
    let openSupport: () -> Void

    init(openGifts: @escaping () -> Void, openMessages: @escaping () -> Void, openGhost: @escaping () -> Void, openPlaceholder: @escaping (String) -> Void, openStatus: @escaping () -> Void, openAbout: @escaping () -> Void, openSupport: @escaping () -> Void) {
        self.openGifts = openGifts
        self.openMessages = openMessages
        self.openGhost = openGhost
        self.openPlaceholder = openPlaceholder
        self.openStatus = openStatus
        self.openAbout = openAbout
        self.openSupport = openSupport
    }
}

/// PampGram's own Telegram channel and the person to reach for support/donations — kept in
/// one place since the "PampGram Team" row's action sheet is the only thing that uses them.
private let pampGramChannelUrl = "https://t.me/PampGrams"
private let pampGramSupportUsername = "kopimastera"

private func pampGramDonateUrl(currencyLabel: String) -> String {
    let text = "Привет, я решил поддержать твой проект, поэтому хочу тебе дать \(currencyLabel), жду твоего ответа."
    let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
    return "https://t.me/\(pampGramSupportUsername)?text=\(encoded)"
}

private func pampGramHubEntries(settings: PampGramSettings) -> [PampGramHubEntry] {
    let toggles = [
        settings.phantomGiftsEnabled,
        settings.fakeStarsDisplayEnabled,
        settings.fakeTonDisplayEnabled,
        settings.fromHimGiftsEnabled,
        settings.antiDeleteMessagesEnabled,
        settings.visualEditEnabled,
        settings.ghostReaderEnabled,
        settings.onlineMaskEnabled
    ]
    let activeCount = toggles.filter { $0 }.count
    return [
        .hero,
        .gifts,
        .messages,
        .privacy,
        .appearance,
        .advanced,
        .status(activeCount, toggles.count),
        .team
    ]
}

/// The PampGram root screen: a hub of sections rather than one long list, so unrelated
/// features (gifts/balances, message history, and whatever future PampGram screens need) each
/// get their own page instead of piling into a single scroll.
public func pampGramSettingsController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    var presentControllerImpl: ((ViewController) -> Void)?
    var navigationControllerImpl: (() -> NavigationController?)?

    let arguments = PampGramHubArguments(
        openGifts: {
            pushControllerImpl?(pampGramGiftsSettingsController(context: context))
        },
        openMessages: {
            pushControllerImpl?(pampGramMessagesSettingsController(context: context))
        },
        openGhost: {
            pushControllerImpl?(pampGramGhostSettingsController(context: context))
        },
        openPlaceholder: { title in
            pushControllerImpl?(pampGramPlaceholderController(context: context, title: title))
        },
        openStatus: {
            pushControllerImpl?(pampGramStatusController(context: context))
        },
        openAbout: {
            pushControllerImpl?(pampGramAboutController(context: context))
        },
        openSupport: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }

            let openChannel: () -> Void = {
                guard let navigationController = navigationControllerImpl?() else {
                    return
                }
                context.sharedContext.openExternalUrl(context: context, urlContext: .generic, url: pampGramChannelUrl, forceExternal: false, presentationData: presentationData, navigationController: navigationController, dismissInput: {})
            }

            let openDonateChat: (String) -> Void = { currencyLabel in
                guard let navigationController = navigationControllerImpl?() else {
                    return
                }
                context.sharedContext.openExternalUrl(context: context, urlContext: .generic, url: pampGramDonateUrl(currencyLabel: currencyLabel), forceExternal: false, presentationData: presentationData, navigationController: navigationController, dismissInput: {})
            }

            let showDonateOptions: () -> Void = {
                let donateSheet = ActionSheetController(presentationData: presentationData)
                donateSheet.setItemGroups([
                    ActionSheetItemGroup(items: [
                        ActionSheetTextItem(title: "Чем хочешь поддержать?"),
                        ActionSheetButtonItem(title: "⭐ Telegram Stars", color: .accent, action: { [weak donateSheet] in
                            donateSheet?.dismissAnimated()
                            openDonateChat("звёзды")
                        }),
                        ActionSheetButtonItem(title: "₽ Рубли", color: .accent, action: { [weak donateSheet] in
                            donateSheet?.dismissAnimated()
                            openDonateChat("рубли")
                        })
                    ]),
                    ActionSheetItemGroup(items: [
                        ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak donateSheet] in
                            donateSheet?.dismissAnimated()
                        })
                    ])
                ])
                presentControllerImpl?(donateSheet)
            }

            let mainSheet = ActionSheetController(presentationData: presentationData)
            mainSheet.setItemGroups([
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: "Наш канал", color: .accent, action: { [weak mainSheet] in
                        mainSheet?.dismissAnimated()
                        openChannel()
                    }),
                    ActionSheetButtonItem(title: "Поддержать проект 💜", color: .accent, action: { [weak mainSheet] in
                        mainSheet?.dismissAnimated()
                        showDonateOptions()
                    })
                ]),
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak mainSheet] in
                        mainSheet?.dismissAnimated()
                    })
                ])
            ])
            presentControllerImpl?(mainSheet)
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
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    navigationControllerImpl = { [weak controller] in
        return controller?.navigationController as? NavigationController
    }
    return controller
}
