import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import PampGramCore
import PhantomGiftKit

private enum PampGramVisualBotHistoryFilter: String {
    case all
    case incoming
    case outgoing

    var title: String {
        switch self {
        case .all: return "Все операции"
        case .incoming: return "Зачисления"
        case .outgoing: return "Списания"
        }
    }
}

/// Signed amount for a history row, prefixed with `+` or `−` and suffixed with the currency
/// code. Matches `pampGramFormatVisualAmount` from the main screen in units but makes the sign
/// explicit — history rows don't carry other visual signalling, so the number itself has to.
private func pampGramVisualHistoryAmountText(currency: String, minorUnits: Int64) -> String {
    let info = pampGramKnownCurrencyInfo(code: currency)
    let displayDecimals = min(info.decimals, 8)
    let divisor = pow(10.0, Double(info.decimals))
    let value = Double(minorUnits) / divisor
    let sign = minorUnits >= 0 ? "+" : "−"
    return String(format: "%@%.\(displayDecimals)f %@", sign, abs(value), currency)
}

/// Compact dup of the main screen's currency table, visible here under its own name so the
/// history screen doesn't reach into the main screen's `fileprivate` declarations.
private struct PampGramKnownCurrencyInfo {
    let code: String
    let decimals: Int
}

private func pampGramKnownCurrencyInfo(code: String) -> PampGramKnownCurrencyInfo {
    switch code {
    case "USDT": return PampGramKnownCurrencyInfo(code: code, decimals: 6)
    case "TON": return PampGramKnownCurrencyInfo(code: code, decimals: 9)
    case "BTC": return PampGramKnownCurrencyInfo(code: code, decimals: 8)
    case "ETH": return PampGramKnownCurrencyInfo(code: code, decimals: 18)
    case "BNB": return PampGramKnownCurrencyInfo(code: code, decimals: 18)
    case "LTC": return PampGramKnownCurrencyInfo(code: code, decimals: 8)
    case "SOL": return PampGramKnownCurrencyInfo(code: code, decimals: 9)
    case "TRX": return PampGramKnownCurrencyInfo(code: code, decimals: 6)
    case "DOGE": return PampGramKnownCurrencyInfo(code: code, decimals: 8)
    case "NOT": return PampGramKnownCurrencyInfo(code: code, decimals: 9)
    default: return PampGramKnownCurrencyInfo(code: code, decimals: 2)
    }
}

private func pampGramVisualHistoryTitle(_ operation: PampGramVisualBotOperation, counterpartName: String?) -> String {
    switch operation.kind {
    case .deposit: return "Пополнение"
    case .withdraw: return "Вывод"
    case .sendOut: return "Отправлено"
    case .receiveIn: return "Получено"
    case .transferOut: return counterpartName.map { "Перевод на \($0)" } ?? "Перевод"
    case .transferIn: return counterpartName.map { "Перевод от \($0)" } ?? "Перевод"
    case .checkCreated: return "Чек выпущен"
    case .checkRedeemed: return counterpartName.map { "Чек от \($0)" } ?? "Чек погашен"
    case .manual: return (operation.note?.isEmpty == false ? operation.note! : "Корректировка")
    }
}

private final class PampGramVisualBotsHistoryArguments {
    let chooseFilter: () -> Void
    let chooseBot: () -> Void
    let clear: () -> Void

    init(chooseFilter: @escaping () -> Void, chooseBot: @escaping () -> Void, clear: @escaping () -> Void) {
        self.chooseFilter = chooseFilter
        self.chooseBot = chooseBot
        self.clear = clear
    }
}

private enum PampGramVisualBotsHistoryEntry: ItemListNodeEntry {
    case stats(String)
    case filter(String)
    case botFilter(String)
    case operation(Int64, String, String, String)
    case empty
    case clear
    case footer(String)

    var section: ItemListSectionId {
        switch self {
        case .stats: return 0
        case .filter, .botFilter: return 1
        case .operation, .empty: return 2
        case .clear, .footer: return 3
        }
    }

    var stableId: Int64 {
        switch self {
        case .stats: return 0
        case .filter: return 1
        case .botFilter: return 2
        case let .operation(id, _, _, _): return 10_000 + id
        case .empty: return 9_000
        case .clear: return 9_001
        case .footer: return 9_002
        }
    }

    static func ==(lhs: PampGramVisualBotsHistoryEntry, rhs: PampGramVisualBotsHistoryEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.stats(a), .stats(b)): return a == b
        case let (.filter(a), .filter(b)): return a == b
        case let (.botFilter(a), .botFilter(b)): return a == b
        case let (.operation(a1, a2, a3, a4), .operation(b1, b2, b3, b4)): return a1 == b1 && a2 == b2 && a3 == b3 && a4 == b4
        case (.empty, .empty), (.clear, .clear): return true
        case let (.footer(a), .footer(b)): return a == b
        default: return false
        }
    }

    static func <(lhs: PampGramVisualBotsHistoryEntry, rhs: PampGramVisualBotsHistoryEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramVisualBotsHistoryArguments
        switch self {
        case let .stats(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .filter(text):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Фильтр", label: text, sectionId: self.section, style: .blocks, action: arguments.chooseFilter)
        case let .botFilter(text):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Бот", label: text, sectionId: self.section, style: .blocks, action: arguments.chooseBot)
        case let .operation(_, title, amount, detail):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: amount, additionalDetailLabel: detail, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case .empty:
            return ItemListTextItem(presentationData: presentationData, text: .plain("По выбранным фильтрам операций нет."), sectionId: self.section)
        case .clear:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Очистить историю", kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: arguments.clear)
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

/// Full operation log for every visual bot on this device, with filters by sign and by bot.
/// Rows are read-only — editing happens on the main Visual Bots screen so the "apply is the
/// only write path" invariant stays easy to see; "Очистить историю" wipes only this log and
/// does not refund any balance (the balances already reflect the latest apply pair-by-pair).
public func pampGramVisualBotsHistoryController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    let filter = ValuePromise<PampGramVisualBotHistoryFilter>(.all, ignoreRepeated: true)
    var filterValue: PampGramVisualBotHistoryFilter = .all
    let botFilter = ValuePromise<String?>(nil, ignoreRepeated: true)
    var botFilterValue: String? = nil

    let arguments = PampGramVisualBotsHistoryArguments(
        chooseFilter: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let sheet = ActionSheetController(presentationData: presentationData)
            sheet.setItemGroups([
                ActionSheetItemGroup(items: [PampGramVisualBotHistoryFilter.all, .incoming, .outgoing].map { value in
                    ActionSheetButtonItem(title: (value == filterValue ? "✓ " : "") + value.title, color: .accent, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                        filterValue = value
                        filter.set(value)
                    })
                }),
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                    })
                ])
            ])
            presentControllerImpl?(sheet)
        },
        chooseBot: {
            let _ = (context.account.postbox.transaction { transaction -> [PampGramVisualBot] in
                return PampGramVisualBotStore.allBots(transaction: transaction)
            }
            |> deliverOnMainQueue).start(next: { bots in
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                let sheet = ActionSheetController(presentationData: presentationData)
                var items: [ActionSheetItem] = []
                items.append(ActionSheetButtonItem(title: (botFilterValue == nil ? "✓ " : "") + "Все боты", color: .accent, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    botFilterValue = nil
                    botFilter.set(nil)
                }))
                for bot in bots {
                    items.append(ActionSheetButtonItem(title: (botFilterValue == bot.id ? "✓ " : "") + bot.displayName, color: .accent, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                        botFilterValue = bot.id
                        botFilter.set(bot.id)
                    }))
                }
                sheet.setItemGroups([
                    ActionSheetItemGroup(items: items),
                    ActionSheetItemGroup(items: [
                        ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                            sheet?.dismissAnimated()
                        })
                    ])
                ])
                presentControllerImpl?(sheet)
            })
        },
        clear: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let sheet = ActionSheetController(presentationData: presentationData)
            sheet.setItemGroups([
                ActionSheetItemGroup(items: [
                    ActionSheetTextItem(title: "Очистить историю визуальных ботов? Балансы останутся."),
                    ActionSheetButtonItem(title: "Очистить", color: .destructive, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                        let _ = context.account.postbox.transaction { transaction -> Void in
                            transaction.setPreferencesEntry(key: PampGramPreferencesKeys.visualBotOperations, value: nil)
                        }.start()
                    })
                ]),
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                    })
                ])
            ])
            presentControllerImpl?(sheet)
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        PampGramVisualBotStore.botsSignal(context: context),
        PampGramVisualBotStore.operationsSignal(context: context),
        filter.get(),
        botFilter.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, bots, allOperations, selectedFilter, selectedBotId -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let botNamesById = Dictionary(uniqueKeysWithValues: bots.map { ($0.id, $0.displayName) })

        let filteredOperations = allOperations.filter { op in
            if let botId = selectedBotId, op.botId != botId {
                return false
            }
            switch selectedFilter {
            case .all: return true
            case .incoming: return op.minorUnits > 0
            case .outgoing: return op.minorUnits < 0
            }
        }

        var entries: [PampGramVisualBotsHistoryEntry] = []
        let incoming = allOperations.filter { $0.minorUnits > 0 }.count
        let outgoing = allOperations.filter { $0.minorUnits < 0 }.count
        entries.append(.stats("Всего: \(allOperations.count) · Зачислений: \(incoming) · Списаний: \(outgoing)"))
        entries.append(.filter(selectedFilter.title))
        let botLabel = selectedBotId.flatMap { botNamesById[$0] } ?? "Все боты"
        entries.append(.botFilter(botLabel))

        if filteredOperations.isEmpty {
            entries.append(.empty)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            for op in filteredOperations {
                let counterpartName = op.counterpartBotId.flatMap { botNamesById[$0] }
                let title = pampGramVisualHistoryTitle(op, counterpartName: counterpartName)
                let amount = pampGramVisualHistoryAmountText(currency: op.currency, minorUnits: op.minorUnits)
                let botName = botNamesById[op.botId] ?? op.botId
                let date = formatter.string(from: Date(timeIntervalSince1970: Double(op.date)))
                var detail = "\(botName) · \(date)"
                if let code = op.checkCode {
                    detail += " · \(code)"
                }
                entries.append(.operation(op.id, title, amount, detail))
            }
        }
        if !allOperations.isEmpty {
            entries.append(.clear)
        }
        entries.append(.footer("История показывает каждое изменение баланса. Переводы между ботами и чеки появляются двумя записями — списание и зачисление."))

        return (
            ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("История визуальных ботов"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false),
            (ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true), arguments)
        )
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}
