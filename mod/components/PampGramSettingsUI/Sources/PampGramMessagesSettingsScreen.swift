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
import PromptUI
import PampGramCore

private final class PampGramMessagesArguments {
    let toggleAntiDelete: (Bool) -> Void
    let openExclusions: () -> Void
    let toggleVisualEdit: (Bool) -> Void
    let toggleCopyProtectionBypass: (Bool) -> Void
    let toggleShowForwardOrigin: (Bool) -> Void
    let toggleDisableAutoDelete: (Bool) -> Void
    let toggleTranslation: (Bool) -> Void
    let editTranslationLanguage: () -> Void
    let openHistory: () -> Void
    let clearHistory: () -> Void

    init(toggleAntiDelete: @escaping (Bool) -> Void, openExclusions: @escaping () -> Void, toggleVisualEdit: @escaping (Bool) -> Void, toggleCopyProtectionBypass: @escaping (Bool) -> Void, toggleShowForwardOrigin: @escaping (Bool) -> Void, toggleDisableAutoDelete: @escaping (Bool) -> Void, toggleTranslation: @escaping (Bool) -> Void, editTranslationLanguage: @escaping () -> Void, openHistory: @escaping () -> Void, clearHistory: @escaping () -> Void) {
        self.toggleAntiDelete = toggleAntiDelete
        self.openExclusions = openExclusions
        self.toggleVisualEdit = toggleVisualEdit
        self.toggleCopyProtectionBypass = toggleCopyProtectionBypass
        self.toggleShowForwardOrigin = toggleShowForwardOrigin
        self.toggleDisableAutoDelete = toggleDisableAutoDelete
        self.toggleTranslation = toggleTranslation
        self.editTranslationLanguage = editTranslationLanguage
        self.openHistory = openHistory
        self.clearHistory = clearHistory
    }
}

private enum PampGramMessagesSection: Int32 {
    case about
    case chatTools
    case antiDelete
    case visualEdit
    case translation
    case history
}

private enum PampGramMessagesEntry: ItemListNodeEntry {
    case aboutText(String)

    case chatToolsHeader(String)
    case copyProtectionBypass(String, Bool)
    case showForwardOrigin(String, Bool)
    case disableAutoDelete(String, Bool)
    case chatToolsFooter(String)

    case antiDeleteToggle(String, Bool)
    case exclusionsRow(String, String)
    case antiDeleteFooter(String)

    case visualEditToggle(String, Bool)
    case visualEditFooter(String)

    case translationHeader(String)
    case translationToggle(String, Bool)
    case translationLanguage(String, String)
    case translationFooter(String)

    case historyHeader(String)
    case historyList(String, String)
    case clearHistory(String, Bool)
    case historyFooter(String)

    var section: ItemListSectionId {
        switch self {
        case .aboutText:
            return PampGramMessagesSection.about.rawValue
        case .chatToolsHeader, .copyProtectionBypass, .showForwardOrigin, .disableAutoDelete, .chatToolsFooter:
            return PampGramMessagesSection.chatTools.rawValue
        case .antiDeleteToggle, .exclusionsRow, .antiDeleteFooter:
            return PampGramMessagesSection.antiDelete.rawValue
        case .visualEditToggle, .visualEditFooter:
            return PampGramMessagesSection.visualEdit.rawValue
        case .translationHeader, .translationToggle, .translationLanguage, .translationFooter:
            return PampGramMessagesSection.translation.rawValue
        case .historyHeader, .historyList, .clearHistory, .historyFooter:
            return PampGramMessagesSection.history.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .aboutText: return 0
        case .chatToolsHeader: return 1
        case .copyProtectionBypass: return 2
        case .showForwardOrigin: return 3
        case .disableAutoDelete: return 4
        case .chatToolsFooter: return 5
        case .antiDeleteToggle: return 6
        case .exclusionsRow: return 7
        case .antiDeleteFooter: return 8
        case .visualEditToggle: return 9
        case .visualEditFooter: return 10
        case .translationHeader: return 11
        case .translationToggle: return 12
        case .translationLanguage: return 13
        case .translationFooter: return 14
        case .historyHeader: return 15
        case .historyList: return 16
        case .clearHistory: return 17
        case .historyFooter: return 18
        }
    }

    static func <(lhs: PampGramMessagesEntry, rhs: PampGramMessagesEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramMessagesArguments
        switch self {
        case let .aboutText(text), let .chatToolsFooter(text), let .antiDeleteFooter(text), let .visualEditFooter(text), let .translationFooter(text), let .historyFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .chatToolsHeader(text), let .translationHeader(text), let .historyHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .copyProtectionBypass(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: arguments.toggleCopyProtectionBypass)
        case let .showForwardOrigin(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: arguments.toggleShowForwardOrigin)
        case let .disableAutoDelete(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: arguments.toggleDisableAutoDelete)
        case let .antiDeleteToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleAntiDelete(value)
            })
        case let .exclusionsRow(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openExclusions()
            })
        case let .visualEditToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleVisualEdit(value)
            })
        case let .translationToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: arguments.toggleTranslation)
        case let .translationLanguage(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label.uppercased(), sectionId: self.section, style: .blocks, action: arguments.editTranslationLanguage)
        case let .historyList(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openHistory()
            })
        case let .clearHistory(title, enabled):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: enabled ? .destructive : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.clearHistory()
            })
        }
    }
}

private func pampGramMessagesEntries(settings: PampGramSettings, behavior: PampGramBehaviorState, historyCount: Int) -> [PampGramMessagesEntry] {
    var entries: [PampGramMessagesEntry] = []

    entries.append(.aboutText("Работает только на этом устройстве, никому не сообщается."))

    entries.append(.chatToolsHeader("ФУНКЦИИ ЧАТОВ"))
    entries.append(.copyProtectionBypass("Обход защиты от копирования", settings.copyProtectionBypassEnabled))
    entries.append(.showForwardOrigin("Добавлять от кого переслано", settings.showForwardOriginEnabled))
    entries.append(.disableAutoDelete("Отключить автоудаление исчезающих сообщений", settings.disableAutoDeleteEnabled))
    entries.append(.chatToolsFooter("Дополнительные настройки обычных облачных чатов."))

    entries.append(.antiDeleteToggle("Удалённые сообщения", settings.antiDeleteMessagesEnabled))
    entries.append(.exclusionsRow("Исключения", "\(settings.antiDeleteExcludedPeerIds.count)"))
    entries.append(.antiDeleteFooter("Удалённое собеседником сообщение остаётся в чате затемнённым, с иконкой корзины. В исключённых чатах — как обычно."))

    entries.append(.visualEditToggle("Изменить визуально", settings.visualEditEnabled))
    entries.append(.visualEditFooter("Локальные сообщения и визуальные изменения отмечаются только в контекстном меню. Для изменённых сообщений хранится локальная история правок."))

    entries.append(.translationHeader("ПЕРЕВОД"))
    entries.append(.translationToggle("Бесплатный перевод текста", behavior.translationEnabled))
    entries.append(.translationLanguage("Язык перевода", behavior.translationTargetLanguage))
    entries.append(.translationFooter("Исходный язык определяется автоматически; целевой язык задаётся кодом языка, например ru, en, de, es."))

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
        toggleCopyProtectionBypass: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.copyProtectionBypassEnabled = value
                return settings
            }).start()
        },
        toggleShowForwardOrigin: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.showForwardOriginEnabled = value
                return settings
            }).start()
        },
        toggleDisableAutoDelete: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.disableAutoDeleteEnabled = value
                return settings
            }).start()
        },
        toggleTranslation: { value in
            let _ = context.account.postbox.transaction { transaction in
                PampGramBehaviorStore.update(transaction: transaction, { state in var state = state; state.translationEnabled = value; return state })
            }.start()
        },
        editTranslationLanguage: {
            let _ = (PampGramBehaviorStore.signal(postbox: context.account.postbox) |> take(1) |> deliverOnMainQueue).start(next: { state in
                let controller = promptController(context: context, text: "Язык перевода", subtitle: "Код целевого языка: ru, en, de, es, fr и т. д.", value: state.translationTargetLanguage, characterLimit: 12, apply: { value in
                    guard let value = value?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return }
                    let _ = context.account.postbox.transaction { transaction in
                        PampGramBehaviorStore.update(transaction: transaction, { state in var state = state; state.translationTargetLanguage = value; return state })
                    }.start()
                })
                if let root = context.sharedContext.mainWindow?.viewController as? ViewController { root.present(controller, in: .window(.root)) }
            })
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
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        PampGramCore.settingsSignal(postbox: context.account.postbox),
        PampGramBehaviorStore.signal(postbox: context.account.postbox),
        PampGramDeletedMessageStore.allSignal(postbox: context.account.postbox)
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings, behavior, history -> (ItemListControllerState, (ItemListNodeState, Any)) in
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
            entries: pampGramMessagesEntries(settings: settings, behavior: behavior, historyCount: history.count),
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
