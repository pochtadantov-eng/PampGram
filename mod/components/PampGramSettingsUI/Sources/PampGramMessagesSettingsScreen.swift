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
import UndoUI
import PampGramCore

private final class PampGramMessagesArguments {
    let toggleAntiDelete: (Bool) -> Void
    let openExclusions: () -> Void
    let toggleVisualEdit: (Bool) -> Void
    let openVisualEditItems: () -> Void
    let openHistory: () -> Void
    let clearHistory: () -> Void
    let toggleSaveOnceMedia: (Bool) -> Void
    let toggleForwardOnceVoice: (Bool) -> Void

    init(toggleAntiDelete: @escaping (Bool) -> Void, openExclusions: @escaping () -> Void, toggleVisualEdit: @escaping (Bool) -> Void, openVisualEditItems: @escaping () -> Void, openHistory: @escaping () -> Void, clearHistory: @escaping () -> Void, toggleSaveOnceMedia: @escaping (Bool) -> Void, toggleForwardOnceVoice: @escaping (Bool) -> Void) {
        self.toggleAntiDelete = toggleAntiDelete
        self.openExclusions = openExclusions
        self.toggleVisualEdit = toggleVisualEdit
        self.openVisualEditItems = openVisualEditItems
        self.openHistory = openHistory
        self.clearHistory = clearHistory
        self.toggleSaveOnceMedia = toggleSaveOnceMedia
        self.toggleForwardOnceVoice = toggleForwardOnceVoice
    }
}

private enum PampGramMessagesSection: Int32 {
    case about
    case antiDelete
    case visualEdit
    case onceMedia
    case history
}

private enum PampGramMessagesEntry: ItemListNodeEntry {
    case aboutText(String)

    case antiDeleteToggle(String, Bool)
    case exclusionsRow(String, String)
    case antiDeleteFooter(String)

    case visualEditToggle(String, Bool)
    case visualEditItemsRow(String)
    case visualEditFooter(String)

    case onceMediaHeader(String)
    case saveOnceMediaToggle(String, Bool)
    case forwardOnceVoiceToggle(String, Bool)
    case onceMediaFooter(String)

    case historyHeader(String)
    case historyList(String, String)
    case clearHistory(String, Bool)
    case historyFooter(String)

    var section: ItemListSectionId {
        switch self {
        case .aboutText:
            return PampGramMessagesSection.about.rawValue
        case .antiDeleteToggle, .exclusionsRow, .antiDeleteFooter:
            return PampGramMessagesSection.antiDelete.rawValue
        case .visualEditToggle, .visualEditItemsRow, .visualEditFooter:
            return PampGramMessagesSection.visualEdit.rawValue
        case .onceMediaHeader, .saveOnceMediaToggle, .forwardOnceVoiceToggle, .onceMediaFooter:
            return PampGramMessagesSection.onceMedia.rawValue
        case .historyHeader, .historyList, .clearHistory, .historyFooter:
            return PampGramMessagesSection.history.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .aboutText:
            return 0
        case .antiDeleteToggle:
            return 1
        case .exclusionsRow:
            return 2
        case .antiDeleteFooter:
            return 3
        case .visualEditToggle:
            return 4
        case .visualEditItemsRow:
            return 5
        case .visualEditFooter:
            return 6
        case .onceMediaHeader:
            return 7
        case .saveOnceMediaToggle:
            return 8
        case .forwardOnceVoiceToggle:
            return 9
        case .onceMediaFooter:
            return 10
        case .historyHeader:
            return 11
        case .historyList:
            return 12
        case .clearHistory:
            return 13
        case .historyFooter:
            return 14
        }
    }

    static func <(lhs: PampGramMessagesEntry, rhs: PampGramMessagesEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramMessagesArguments
        switch self {
        case let .aboutText(text), let .antiDeleteFooter(text), let .visualEditFooter(text), let .onceMediaFooter(text), let .historyFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .onceMediaHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .saveOnceMediaToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleSaveOnceMedia(value)
            })
        case let .forwardOnceVoiceToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleForwardOnceVoice(value)
            })
        case let .historyHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .antiDeleteToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "trash.slash.fill", backgroundColor: UIColor(rgb: 0xff3b30)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleAntiDelete(value)
            })
        case let .exclusionsRow(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "person.crop.circle.badge.minus", backgroundColor: UIColor(rgb: 0x8e8e93)), title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openExclusions()
            })
        case let .visualEditToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "pencil.circle.fill", backgroundColor: UIColor(rgb: 0x3b82f6)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleVisualEdit(value)
            })
        case let .visualEditItemsRow(title):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openVisualEditItems()
            })
        case let .historyList(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "clock.arrow.circlepath", backgroundColor: UIColor(rgb: 0x8e44ec)), title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openHistory()
            })
        case let .clearHistory(title, enabled):
            // ItemListActionItem has no icon support.
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: enabled ? .destructive : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.clearHistory()
            })
        }
    }
}

private func pampGramMessagesEntries(settings: PampGramSettings, historyCount: Int) -> [PampGramMessagesEntry] {
    var entries: [PampGramMessagesEntry] = []

    entries.append(.aboutText("Работает только на этом устройстве, никому не сообщается."))

    entries.append(.antiDeleteToggle("Удалённые сообщения", settings.antiDeleteMessagesEnabled))
    entries.append(.exclusionsRow("Исключения", "\(settings.antiDeleteExcludedPeerIds.count)"))
    entries.append(.antiDeleteFooter("Удалённое сообщение — своё или собеседника — остаётся в чате затемнённым, с иконкой корзины. Снять пометки можно кнопкой «Восстановить чат» в конкретном чате. В исключённых чатах — как обычно."))

    entries.append(.visualEditToggle("Изменить визуально", settings.visualEditEnabled))
    entries.append(.visualEditItemsRow("Настроить пункты"))
    entries.append(.visualEditFooter("Добавляет в меню сообщения (зажать → PampGram) пункты для фейковых фото/голосовых/файлов/звонков и изменения текста — всё видно только вам. «Настроить пункты» решает, какие именно показывать."))

    entries.append(.onceMediaHeader("ОДНОРАЗОВЫЕ МЕДИА"))
    entries.append(.saveOnceMediaToggle("Сохранять в галерею", settings.saveOnceMediaEnabled))
    entries.append(.forwardOnceVoiceToggle("Пересылать одноразовые ГС", settings.forwardOnceVoiceEnabled))
    entries.append(.onceMediaFooter("Перенесено в Дополнительно → Медиа и защита. Включите «Обход одноразовых» / «Обход с таймером», затем: зажмите сообщение → PampGram → «Сохранить в галерею» или «В Избранное»."))

    entries.append(.historyHeader("ИСТОРИЯ"))
    entries.append(.historyList("Восстановленные сообщения", "\(historyCount)"))
    entries.append(.clearHistory("Очистить всю историю", historyCount > 0))
    entries.append(.historyFooter("Уберёт восстановленные сообщения из чатов. Отменить нельзя."))

    return entries
}

/// The "Чаты" section (hub row title — the screen itself still deals with anti-delete
/// messages specifically): the anti-delete feature's master toggle, its per-chat exclusion
/// list, and a link into its capture history.
public func pampGramMessagesSettingsController(context: AccountContext) -> ViewController {
    var presentTooltipImpl: ((String) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?

    let arguments = PampGramMessagesArguments(
        toggleAntiDelete: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.antiDeleteMessagesEnabled = value
                return settings
            }).start()
        },
        openExclusions: {
            pushControllerImpl?(pampGramMessagesExclusionsController(context: context))
        },
        toggleVisualEdit: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.visualEditEnabled = value
                return settings
            }).start()
        },
        openVisualEditItems: {
            pushControllerImpl?(pampGramVisualEditItemsController(context: context))
        },
        openHistory: {
            pushControllerImpl?(pampGramMessagesHistoryController(context: context))
        },
        clearHistory: {
            let _ = (context.account.postbox.transaction { transaction -> Void in
                let removed = PampGramDeletedMessageStore.removeAll(transaction: transaction)
                transaction.deleteMessages(removed.map { $0.localMessageId }, forEachMedia: { _ in })
            }
            |> deliverOnMainQueue).start(completed: {
                presentTooltipImpl?("История очищена.")
            })
        },
        toggleSaveOnceMedia: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.saveOnceMediaEnabled = value
                return settings
            }).start()
        },
        toggleForwardOnceVoice: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.forwardOnceVoiceEnabled = value
                return settings
            }).start()
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        PampGramCore.settingsSignal(postbox: context.account.postbox),
        PampGramDeletedMessageStore.allSignal(postbox: context.account.postbox)
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings, history -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Чаты"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: pampGramMessagesEntries(settings: settings, historyCount: history.count),
            style: .blocks,
            animateChanges: true
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        controller?.push(c)
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
