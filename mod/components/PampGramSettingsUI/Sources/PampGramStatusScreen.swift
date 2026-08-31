import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import AppBundle
import PampGramCore

private final class PampGramStatusArguments {
    let refreshSubscription: () -> Void
    let openIconPicker: () -> Void
    let openGifts: () -> Void
    let openMessages: () -> Void
    let openGhost: () -> Void

    init(refreshSubscription: @escaping () -> Void, openIconPicker: @escaping () -> Void, openGifts: @escaping () -> Void, openMessages: @escaping () -> Void, openGhost: @escaping () -> Void) {
        self.refreshSubscription = refreshSubscription
        self.openIconPicker = openIconPicker
        self.openGifts = openGifts
        self.openMessages = openMessages
        self.openGhost = openGhost
    }
}

/// Turns a raw alternate-icon codename (e.g. "BlueClassicIcon", "New2") into something
/// readable without inventing style descriptions we can't verify — just the real name with
/// word breaks inserted before each capital. Not private: PampGramIconPickerScreen.swift's
/// grid cells and confirm dialog use it too.
func pampGramIconDisplayName(_ icon: PresentationAppIcon) -> String {
    if icon.isDefault {
        return "Стандартная"
    }
    var name = icon.name
    if name.hasSuffix("Icon") {
        name.removeLast(4)
    }
    var result = ""
    for (index, character) in name.enumerated() {
        if index > 0 && character.isUppercase {
            result += " "
        }
        result.append(character)
    }
    return result.isEmpty ? icon.name : result
}

private enum PampGramStatusEntry: ItemListNodeEntry {
    case badge(Bool)
    case refreshSubscription

    case iconHeader(String)
    case iconSummary(PresentationAppIcon)
    case iconFooter(String)

    case giftsHeader(String)
    case giftsRow(Int32, String, Bool)

    case messagesHeader(String)
    case messagesRow(Int32, String, Bool)

    case ghostHeader(String)
    case ghostRow(Int32, String, Bool)

    var section: ItemListSectionId {
        switch self {
        case .badge:
            return 0
        case .refreshSubscription:
            return 0
        case .iconHeader, .iconSummary, .iconFooter:
            return 1
        case .giftsHeader, .giftsRow:
            return 2
        case .messagesHeader, .messagesRow:
            return 3
        case .ghostHeader, .ghostRow:
            return 4
        }
    }

    var stableId: Int32 {
        switch self {
        case .badge:
            return 0
        case .refreshSubscription:
            return 1
        case .iconHeader:
            return 10
        case .iconSummary:
            return 100
        case .iconFooter:
            return 199
        case .giftsHeader:
            return 200
        case let .giftsRow(index, _, _):
            return 201 + index
        case .messagesHeader:
            return 220
        case let .messagesRow(index, _, _):
            return 221 + index
        case .ghostHeader:
            return 240
        case let .ghostRow(index, _, _):
            return 241 + index
        }
    }

    static func <(lhs: PampGramStatusEntry, rhs: PampGramStatusEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramStatusArguments
        switch self {
        case let .badge(isPro):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: pampGramSettingsIcon(size: 44.0),
                title: "Статус",
                titleFont: .bold,
                titleBadge: isPro ? "PRO" : "STANDARD",
                label: "",
                additionalDetailLabel: "Выбери свой стиль приложения и подписку",
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .none,
                action: nil
            )
        case .refreshSubscription:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Обновить подписку", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.refreshSubscription()
            })
        case let .iconHeader(text), let .giftsHeader(text), let .messagesHeader(text), let .ghostHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .iconFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .iconSummary(icon):
            let previewImage = UIImage(named: icon.imageName, in: getAppBundle(), compatibleWith: nil).flatMap { generatePampGramIconPreview($0) }
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: previewImage,
                title: "Иконка приложения",
                label: pampGramIconDisplayName(icon),
                sectionId: self.section,
                style: .blocks,
                action: {
                    arguments.openIconPicker()
                }
            )
        case let .giftsRow(_, title, isOn):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: generatePampGramSectionIcon(systemName: "gift.fill", backgroundColor: UIColor(rgb: 0x8e44ec)),
                title: title,
                label: "",
                additionalDetailLabel: isOn ? "Включено" : "Выключено",
                additionalDetailLabelColor: isOn ? .constructive : .destructive,
                sectionId: self.section,
                style: .blocks,
                action: {
                    arguments.openGifts()
                }
            )
        case let .messagesRow(_, title, isOn):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: generatePampGramSectionIcon(systemName: "message.fill", backgroundColor: UIColor(rgb: 0x3b82f6)),
                title: title,
                label: "",
                additionalDetailLabel: isOn ? "Включено" : "Выключено",
                additionalDetailLabelColor: isOn ? .constructive : .destructive,
                sectionId: self.section,
                style: .blocks,
                action: {
                    arguments.openMessages()
                }
            )
        case let .ghostRow(_, title, isOn):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: generatePampGramSectionIcon(systemName: "eye.slash.fill", backgroundColor: UIColor(rgb: 0x34c759)),
                title: title,
                label: "",
                additionalDetailLabel: isOn ? "Включено" : "Выключено",
                additionalDetailLabelColor: isOn ? .constructive : .destructive,
                sectionId: self.section,
                style: .blocks,
                action: {
                    arguments.openGhost()
                }
            )
        }
    }
}

private func pampGramStatusEntries(isPro: Bool, icons: [PresentationAppIcon], currentIconName: String?, settings: PampGramSettings) -> [PampGramStatusEntry] {
    var entries: [PampGramStatusEntry] = []

    entries.append(.badge(isPro))
    entries.append(.refreshSubscription)

    entries.append(.iconHeader("ИКОНКА ПРИЛОЖЕНИЯ"))
    if let selectedIcon = icons.first(where: { $0.name == currentIconName }) ?? icons.first(where: { $0.isDefault }) ?? icons.first {
        entries.append(.iconSummary(selectedIcon))
    }
    entries.append(.iconFooter("Иконка меняется сразу на домашнем экране."))

    entries.append(.giftsHeader("ПОДАРКИ"))
    entries.append(.giftsRow(0, "Вкладка «Подарок ему»", settings.phantomGiftsEnabled))
    entries.append(.giftsRow(1, "Локальные звёзды", settings.fakeStarsDisplayEnabled))
    entries.append(.giftsRow(2, "Локальные TON/GRAM", settings.fakeTonDisplayEnabled))
    entries.append(.giftsRow(3, "От него", settings.fromHimGiftsEnabled))

    entries.append(.messagesHeader("ЧАТЫ"))
    entries.append(.messagesRow(0, "Удалённые сообщения", settings.antiDeleteMessagesEnabled))
    entries.append(.messagesRow(1, "Изменить визуально", settings.visualEditEnabled))

    entries.append(.ghostHeader("GHOST"))
    entries.append(.ghostRow(0, "Нечиталка", settings.ghostReaderEnabled))
    entries.append(.ghostRow(1, "Маскировка онлайна", settings.onlineMaskEnabled))

    return entries
}

/// "Статус": PampGram's own hub row for both this account's PampGram subscription tier
/// (PRO/STANDARD — granted by the admin panel, see `PampGramSubscriptionAPI.swift`; this is
/// the one screen in the mod that reads from PampGram's own server instead of only local
/// state) and the app-icon picker (wired to Telegram's own real
/// `applicationBindings.requestSetAlternateIconName`, so picking one genuinely changes the
/// home-screen icon), plus a grouped, tap-to-open read-out of every PampGram toggle.
public func pampGramStatusController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    var currentIconNameValue = context.sharedContext.applicationBindings.getAlternateIconName()
    let currentIconName = ValuePromise<String?>(currentIconNameValue)

    var appIcons = context.sharedContext.applicationBindings.getAvailableAlternateIcons()
    appIcons = appIcons.filter { !$0.isPremium }

    let tierPromise = ValuePromise<PampGramSubscriptionTier>(.standard, ignoreRepeated: true)
    let refreshTier: () -> Void = {
        let _ = (PampGramSubscriptionAPI.fetchTier(userId: context.account.peerId.id._internalGetInt64Value()) |> deliverOnMainQueue).start(next: { tier in
            tierPromise.set(tier)
        })
    }
    refreshTier()

    let arguments = PampGramStatusArguments(
        refreshSubscription: { refreshTier() },
        openIconPicker: {
            pampGramPresentIconPicker(context: context, icons: appIcons, currentIconName: currentIconNameValue, onSelect: { icon in
                currentIconNameValue = icon.name
                currentIconName.set(icon.name)
            })
        },
        openGifts: {
            pampGramGateSection(context: context, section: .gifts) {
                pushControllerImpl?(pampGramGiftsSettingsController(context: context))
            }
        },
        openMessages: {
            pampGramGateSection(context: context, section: .messages) {
                pushControllerImpl?(pampGramMessagesSettingsController(context: context))
            }
        },
        openGhost: {
            pampGramGateSection(context: context, section: .ghost) {
                pushControllerImpl?(pampGramGhostSettingsController(context: context))
            }
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        PampGramCore.settingsSignal(postbox: context.account.postbox),
        tierPromise.get(),
        currentIconName.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings, subscriptionTier, currentIconName -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Статус"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let isPro = subscriptionTier == .pro
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: pampGramStatusEntries(isPro: isPro, icons: appIcons, currentIconName: currentIconName, settings: settings),
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
