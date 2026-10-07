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
import PampGramCore
import PhantomGiftKit
import PromptUI
import UndoUI

private final class PampGramModerationArguments {
    let toggleEnabled: (Bool) -> Void
    let editKey: () -> Void
    let testKey: () -> Void
    let toggleBlock: (Bool) -> Void
    let toggleStrangersOnly: (Bool) -> Void
    let clearLog: () -> Void

    init(toggleEnabled: @escaping (Bool) -> Void, editKey: @escaping () -> Void, testKey: @escaping () -> Void, toggleBlock: @escaping (Bool) -> Void, toggleStrangersOnly: @escaping (Bool) -> Void, clearLog: @escaping () -> Void) {
        self.toggleEnabled = toggleEnabled
        self.editKey = editKey
        self.testKey = testKey
        self.toggleBlock = toggleBlock
        self.toggleStrangersOnly = toggleStrangersOnly
        self.clearLog = clearLog
    }
}

private enum PampGramModerationSection: Int32 {
    case about
    case main
    case options
    case log
}

private enum PampGramModerationEntry: ItemListNodeEntry {
    case about(String)
    case enabled(Bool)
    case key(String)
    case testKey
    case blockSender(Bool)
    case strangersOnly(Bool)
    case optionsFooter(String)
    case logHeader(String)
    case logEmpty(String)
    case logItem(Int32, String)
    case clearLog

    var section: ItemListSectionId {
        switch self {
        case .about:
            return PampGramModerationSection.about.rawValue
        case .enabled, .key, .testKey:
            return PampGramModerationSection.main.rawValue
        case .blockSender, .strangersOnly, .optionsFooter:
            return PampGramModerationSection.options.rawValue
        case .logHeader, .logEmpty, .logItem, .clearLog:
            return PampGramModerationSection.log.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .about: return 0
        case .enabled: return 1
        case .key: return 2
        case .testKey: return 3
        case .blockSender: return 4
        case .strangersOnly: return 5
        case .optionsFooter: return 6
        case .logHeader: return 7
        case .logEmpty: return 8
        case let .logItem(index, _): return 10 + index
        case .clearLog: return 1000
        }
    }

    static func <(lhs: PampGramModerationEntry, rhs: PampGramModerationEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramModerationArguments
        switch self {
        case let .about(text), let .optionsFooter(text), let .logEmpty(text), let .logItem(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .enabled(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "shield.lefthalf.filled", backgroundColor: UIColor(rgb: 0x34c759)), title: "Автомодерация", value: value, enableInteractiveChanges: false, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleEnabled(value)
            })
        case let .key(label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "key.fill", backgroundColor: UIColor(rgb: 0xff9500)), title: "API-ключ Anthropic", label: label, sectionId: self.section, style: .blocks, action: {
                arguments.editKey()
            })
        case .testKey:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Проверить ключ", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.testKey()
            })
        case let .blockSender(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "hand.raised.fill", backgroundColor: UIColor(rgb: 0xff3b30)), title: "Блокировать отправителя", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleBlock(value)
            })
        case let .strangersOnly(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "person.crop.circle.badge.questionmark", backgroundColor: UIColor(rgb: 0x5856d6)), title: "Не проверять контакты", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleStrangersOnly(value)
            })
        case let .logHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case .clearLog:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Очистить журнал", kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.clearLog()
            })
        }
    }
}

private let pampGramModerationDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "dd.MM HH:mm"
    return formatter
}()

private func pampGramModerationEntries(settings: PampGramSettings, log: [PampGramModerationLogEntry]) -> [PampGramModerationEntry] {
    var entries: [PampGramModerationEntry] = []
    entries.append(.about("Следит за новыми входящими картинками и стикерами во всех чатах и группах. Если ИИ видит порно, 18+ или расчленёнку, сообщение удаляется с этого телефона, а отправитель блокируется.\n\nВажно: для проверки копия картинки (уменьшенная, без текста и имён) уходит в сервис Anthropic по вашему ключу. Платите вы по тарифу Anthropic. Если ИИ не уверен, он ничего не трогает. Проверяются только новые сообщения; видео и анимированные стикеры проверяются по превью-кадру."))
    entries.append(.enabled(settings.moderationEnabled))
    let keyLabel: String
    if settings.moderationApiKey.isEmpty {
        keyLabel = "Не задан"
    } else {
        keyLabel = "••••" + String(settings.moderationApiKey.suffix(4))
    }
    entries.append(.key(keyLabel))
    if !settings.moderationApiKey.isEmpty {
        entries.append(.testKey)
    }
    entries.append(.blockSender(settings.moderationBlockSender))
    entries.append(.strangersOnly(settings.moderationStrangersOnly))
    entries.append(.optionsFooter("Если блокировка выключена, сообщение только удаляется. Заблокированного можно вернуть в Настройки → Конфиденциальность → Заблокированные."))
    entries.append(.logHeader("ЖУРНАЛ СРАБАТЫВАНИЙ"))
    if log.isEmpty {
        entries.append(.logEmpty("Пока ничего не удалялось."))
    } else {
        for (index, item) in log.prefix(30).enumerated() {
            let date = pampGramModerationDateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(item.date)))
            let reason = item.verdict == "GORE" ? "жестокость" : "18+"
            let action = item.blocked ? "удалено, заблокирован" : "удалено"
            let name = item.title.isEmpty ? "—" : item.title
            entries.append(.logItem(Int32(index), "\(date) · \(name) · \(reason) · \(action)"))
        }
        entries.append(.clearLog)
    }
    return entries
}

public func pampGramModerationController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    var presentTooltipImpl: ((String) -> Void)?

    func updateSettings(_ f: @escaping (inout PampGramSettings) -> Void) {
        let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
            var settings = settings
            f(&settings)
            return settings
        }).start()
    }

    let arguments = PampGramModerationArguments(
        toggleEnabled: { value in
            if !value {
                updateSettings { $0.moderationEnabled = false }
                return
            }
            let _ = (context.account.postbox.transaction { transaction -> String in
                return PampGramCore.rawSettings(transaction: transaction).moderationApiKey
            }
            |> deliverOnMainQueue).start(next: { key in
                if key.isEmpty {
                    presentTooltipImpl?("Сначала задайте API-ключ Anthropic.")
                    return
                }
                presentControllerImpl?(textAlertController(
                    context: context,
                    title: "Включить автомодерацию?",
                    text: "Новые картинки и стикеры из ваших чатов будут уменьшаться и отправляться на проверку в Anthropic по вашему ключу. Найденные порно и жестокость будут удаляться, а отправители блокироваться. Продолжить?",
                    actions: [
                        TextAlertAction(type: .genericAction, title: "Отмена", action: {}),
                        TextAlertAction(type: .defaultAction, title: "Включить", action: {
                            updateSettings { $0.moderationEnabled = true }
                        })
                    ]
                ))
            })
        },
        editKey: {
            presentControllerImpl?(promptController(
                context: context,
                text: "API-ключ Anthropic",
                subtitle: "Вставьте ключ вида sk-ant-… Он хранится только на этом телефоне. Пустое поле удалит ключ.",
                value: "",
                placeholder: "sk-ant-...",
                characterLimit: 400,
                autocapitalizationType: .none,
                autocorrectionType: .no,
                apply: { value in
                    guard let value else {
                        return
                    }
                    let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    updateSettings { settings in
                        settings.moderationApiKey = key
                        if key.isEmpty {
                            // Without a key there is nothing to run, so the switch goes off too.
                            settings.moderationEnabled = false
                        }
                    }
                }
            ))
        },
        testKey: {
            let _ = (context.account.postbox.transaction { transaction -> String in
                return PampGramCore.rawSettings(transaction: transaction).moderationApiKey
            }
            |> deliverOnMainQueue).start(next: { key in
                presentTooltipImpl?("Проверяем ключ…")
                PampGramModerationRuntime.testKey(apiKey: key, completion: { error in
                    presentTooltipImpl?(error ?? "Ключ работает ✅")
                })
            })
        },
        toggleBlock: { value in
            updateSettings { $0.moderationBlockSender = value }
        },
        toggleStrangersOnly: { value in
            updateSettings { $0.moderationStrangersOnly = value }
        },
        clearLog: {
            let _ = context.account.postbox.transaction { transaction -> Void in
                PampGramModerationLogStore.clear(transaction: transaction)
            }.start()
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        PampGramCore.rawSettingsSignal(postbox: context.account.postbox),
        PampGramModerationLogStore.signal(postbox: context.account.postbox)
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings, log -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Автомодерация"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: pampGramModerationEntries(settings: settings, log: log),
            style: .blocks,
            animateChanges: false
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    presentTooltipImpl = { [weak controller] text in
        guard let controller else { return }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        controller.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), in: .current)
    }
    return controller
}
