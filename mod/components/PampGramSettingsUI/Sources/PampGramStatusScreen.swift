import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import AppBundle
import PampGramCore

private final class PampGramStatusArguments {
    let selectIcon: (PresentationAppIcon) -> Void
    let openGifts: () -> Void
    let openMessages: () -> Void
    let openGhost: () -> Void

    init(selectIcon: @escaping (PresentationAppIcon) -> Void, openGifts: @escaping () -> Void, openMessages: @escaping () -> Void, openGhost: @escaping () -> Void) {
        self.selectIcon = selectIcon
        self.openGifts = openGifts
        self.openMessages = openMessages
        self.openGhost = openGhost
    }
}

/// Turns a raw alternate-icon codename (e.g. "BlueClassicIcon", "New2") into something
/// readable without inventing style descriptions we can't verify — just the real name with
/// word breaks inserted before each capital.
private func pampGramIconDisplayName(_ icon: PresentationAppIcon) -> String {
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

    case iconHeader(String)
    case icon(Int32, PresentationAppIcon, Bool)
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
        case .iconHeader, .icon, .iconFooter:
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
        case .iconHeader:
            return 1
        case let .icon(index, _, _):
            return 100 + index
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
        case let .iconHeader(text), let .giftsHeader(text), let .messagesHeader(text), let .ghostHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .iconFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .icon(_, icon, isSelected):
            let previewImage = UIImage(named: icon.imageName, in: getAppBundle(), compatibleWith: nil)
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: previewImage,
                title: pampGramIconDisplayName(icon),
                label: "",
                additionalDetailLabel: isSelected ? "Выбрано" : nil,
                additionalDetailLabelColor: .constructive,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .none,
                action: {
                    arguments.selectIcon(icon)
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

    entries.append(.iconHeader("ИКОНКА ПРИЛОЖЕНИЯ"))
    for (index, icon) in icons.enumerated() {
        let isSelected = icon.name == (currentIconName ?? icons.first(where: { $0.isDefault })?.name)
        entries.append(.icon(Int32(index), icon, isSelected))
    }
    entries.append(.iconFooter("Иконка меняется сразу на домашнем экране. Часть иконок и PRO пока недоступны."))

    entries.append(.giftsHeader("ПОДАРКИ"))
    entries.append(.giftsRow(0, "Вкладка «Подарок»", settings.phantomGiftsEnabled))
    entries.append(.giftsRow(1, "Локальные звёзды", settings.fakeStarsDisplayEnabled))
    entries.append(.giftsRow(2, "Локальные TON/GRAM", settings.fakeTonDisplayEnabled))

    entries.append(.messagesHeader("СООБЩЕНИЯ"))
    entries.append(.messagesRow(0, "Восстановление удалённых сообщений", settings.antiDeleteMessagesEnabled))

    entries.append(.ghostHeader("GHOST"))
    entries.append(.ghostRow(0, "Нечиталка", settings.ghostReaderEnabled))
    entries.append(.ghostRow(1, "Маскировка онлайна", settings.onlineMaskEnabled))

    return entries
}

/// "Статус": PampGram's own hub row for both the account's real Telegram Premium tier
/// (shown as PRO/STANDARD — no PampGram subscription exists yet, so this just reflects real
/// Premium rather than inventing a tier of our own) and the app-icon picker (wired to
/// Telegram's own real `applicationBindings.requestSetAlternateIconName`, so picking one
/// genuinely changes the home-screen icon), plus a grouped, tap-to-open read-out of every
/// PampGram toggle.
public func pampGramStatusController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    let currentIconName = ValuePromise<String?>(context.sharedContext.applicationBindings.getAlternateIconName())

    let arguments = PampGramStatusArguments(
        selectIcon: { icon in
            currentIconName.set(icon.name)
            context.sharedContext.applicationBindings.requestSetAlternateIconName(icon.isDefault ? nil : icon.name, { _ in
            })
        },
        openGifts: {
            pushControllerImpl?(pampGramGiftsSettingsController(context: context))
        },
        openMessages: {
            pushControllerImpl?(pampGramMessagesSettingsController(context: context))
        },
        openGhost: {
            pushControllerImpl?(pampGramGhostSettingsController(context: context))
        }
    )

    var appIcons = context.sharedContext.applicationBindings.getAvailableAlternateIcons()
    appIcons = appIcons.filter { !$0.isPremium }

    let signal = combineLatest(
        context.sharedContext.presentationData,
        PampGramCore.settingsSignal(postbox: context.account.postbox),
        context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: context.account.peerId)),
        currentIconName.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings, peer, currentIconName -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Статус"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let isPro = peer?.isPremium ?? false
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
