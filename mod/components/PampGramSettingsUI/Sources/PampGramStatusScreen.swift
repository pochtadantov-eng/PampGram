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
import PromptUI
import UndoUI
import PampGramCore

private final class PampGramStatusArguments {
    let openIconPicker: () -> Void
    let openGifts: () -> Void
    let openMessages: () -> Void
    let openGhost: () -> Void
    let redeemKey: () -> Void

    init(openIconPicker: @escaping () -> Void, openGifts: @escaping () -> Void, openMessages: @escaping () -> Void, openGhost: @escaping () -> Void, redeemKey: @escaping () -> Void) {
        self.openIconPicker = openIconPicker
        self.openGifts = openGifts
        self.openMessages = openMessages
        self.openGhost = openGhost
        self.redeemKey = redeemKey
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

/// A short "до 21.10, 14:32"-style label for a subscription's expiry, for the status badge.
private func pampGramFormatExpiry(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return "до \(formatter.string(from: date))"
}

private enum PampGramStatusEntry: ItemListNodeEntry {
    case badge(PampGramSubscriptionStatus)

    case activationHeader(String)
    case redeemKeyAction(String)
    case activationFooter(String)

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
        case .activationHeader, .redeemKeyAction, .activationFooter:
            return 1
        case .iconHeader, .iconSummary, .iconFooter:
            return 2
        case .giftsHeader, .giftsRow:
            return 3
        case .messagesHeader, .messagesRow:
            return 4
        case .ghostHeader, .ghostRow:
            return 5
        }
    }

    var stableId: Int32 {
        switch self {
        case .badge:
            return 0
        case .activationHeader:
            return 1
        case .redeemKeyAction:
            return 2
        case .activationFooter:
            return 3
        case .iconHeader:
            return 4
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
        case let .badge(status):
            let isPro = status.tier == .pro
            let detailLabel = status.expiresAt.map(pampGramFormatExpiry) ?? "Выбери свой стиль приложения и подписку"
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: pampGramSettingsIcon(size: 44.0),
                title: "Статус",
                titleFont: .bold,
                titleBadge: isPro ? "PRO" : "STANDARD",
                label: "",
                additionalDetailLabel: detailLabel,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .none,
                action: nil
            )
        case let .activationHeader(text), let .iconHeader(text), let .giftsHeader(text), let .messagesHeader(text), let .ghostHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .iconFooter(text), let .activationFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .redeemKeyAction(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.redeemKey()
            })
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

private func pampGramStatusEntries(status: PampGramSubscriptionStatus, icons: [PresentationAppIcon], currentIconName: String?, settings: PampGramSettings, profileVisuals: PampGramProfileVisualState) -> [PampGramStatusEntry] {
    var entries: [PampGramStatusEntry] = []

    entries.append(.badge(status))

    entries.append(.activationHeader("АКТИВАЦИЯ"))
    entries.append(.redeemKeyAction("Активировать ключ"))
    entries.append(.activationFooter("Ключ, который тебе выдали или продали, включает подписку на этом аккаунте — на всех его устройствах сразу. Каждый ключ одноразовый: после активации тариф здесь обновится, если открыть «Статус» заново."))

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
    entries.append(.giftsRow(4, "Визуальный +888", profileVisuals.anonymousNumberEnabled))
    entries.append(.giftsRow(5, "Визуальный рейтинг", profileVisuals.ratingEnabled))

    entries.append(.messagesHeader("ЧАТЫ"))
    entries.append(.messagesRow(0, "Удалённые сообщения", settings.antiDeleteMessagesEnabled))
    entries.append(.messagesRow(1, "Изменить визуально", settings.visualEditEnabled))

    entries.append(.ghostHeader("GHOST"))
    entries.append(.ghostRow(0, "Режим призрака", settings.ghostModeEnabled))
    entries.append(.ghostRow(1, "Не читать сообщения", settings.ghostModeEnabled && settings.ghostHideReadReceipts))
    entries.append(.ghostRow(2, "Не читать истории", settings.ghostModeEnabled && settings.ghostHideStoryViews))
    entries.append(.ghostRow(3, "Не отправлять «онлайн»", settings.ghostModeEnabled && settings.ghostHideOnline))
    entries.append(.ghostRow(4, "Не отправлять «печатает»", settings.ghostModeEnabled && settings.ghostHideTyping))
    entries.append(.ghostRow(5, "Автоматический «офлайн»", settings.ghostModeEnabled && settings.ghostAutoOffline))
    entries.append(.ghostRow(6, "Читать при действиях", settings.ghostModeEnabled && settings.ghostReadOnAction))

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
    var presentControllerImpl: ((ViewController) -> Void)?
    var presentTooltipImpl: ((String) -> Void)?
    var currentIconNameValue = context.sharedContext.applicationBindings.getAlternateIconName()
    let currentIconName = ValuePromise<String?>(currentIconNameValue)

    var appIcons = context.sharedContext.applicationBindings.getAvailableAlternateIcons()
    appIcons = appIcons.filter { !$0.isPremium }

    let arguments = PampGramStatusArguments(
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
        },
        redeemKey: {
            presentControllerImpl?(promptController(
                context: context,
                text: "Активировать ключ",
                subtitle: "Ключ, который тебе дали или продали — например, XXXX-XXXX-XXXX-XXXX",
                value: "",
                placeholder: "ключ",
                characterLimit: 64,
                apply: { value in
                    guard let key = value?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
                        return
                    }
                    let accountId = context.account.peerId.id._internalGetInt64Value()
                    PampGramSubscriptionAPI.redeemKey(userId: accountId, key: key) { status in
                        guard let status else {
                            presentTooltipImpl?("Ключ не подошёл — проверь, что он введён верно и ещё не использован.")
                            return
                        }
                        let durationText = status.expiresAt.map { " (\(pampGramFormatExpiry($0)))" } ?? ""
                        presentTooltipImpl?("Активировано: тариф \(status.tier == .pro ? "PRO" : "STANDARD")\(durationText). Открой «Статус» заново, чтобы увидеть обновлённый значок.")
                    }
                }
            ))
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        PampGramCore.settingsSignal(postbox: context.account.postbox),
        PampGramProfileVisualStore.signal(postbox: context.account.postbox),
        PampGramSubscriptionAPI.fetchStatus(userId: context.account.peerId.id._internalGetInt64Value()),
        currentIconName.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings, profileVisuals, subscriptionStatus, currentIconName -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Статус"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: pampGramStatusEntries(status: subscriptionStatus, icons: appIcons, currentIconName: currentIconName, settings: settings, profileVisuals: profileVisuals),
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
    presentTooltipImpl = { [weak controller] text in
        guard let controller else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        controller.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), in: .current)
    }
    return controller
}
