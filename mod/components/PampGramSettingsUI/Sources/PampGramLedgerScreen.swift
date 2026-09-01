import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramPresentationData
import ItemListUI
import AccountContext
import PromptUI
import PampGramCore

private enum PampGramLedgerFilter: String {
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

private func pampGramLedgerAmountText(currency: PampGramLocalCurrency, amount: Int64) -> String {
    switch currency {
    case .stars:
        return "\(amount >= 0 ? "+" : "")\(amount) ⭐"
    case .ton:
        let value = Double(amount) / 1_000_000_000.0
        return String(format: "%@%.4f TON", amount >= 0 ? "+" : "", value)
    case .rubles:
        let value = Double(amount) / 100.0
        return String(format: "%@%.2f ₽", amount >= 0 ? "+" : "", value)
    }
}

private func pampGramLedgerBalanceText(currency: PampGramLocalCurrency, value: Int64) -> String {
    switch currency {
    case .stars: return "\(value) ⭐"
    case .ton: return String(format: "%.4f TON", Double(value) / 1_000_000_000.0)
    case .rubles: return String(format: "%.2f ₽", Double(value) / 100.0)
    }
}

private func pampGramLedgerParseAmount(currency: PampGramLocalCurrency, text: String) -> Int64? {
    let normalized = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
    guard let value = Double(normalized), value >= 0.0 else { return nil }
    switch currency {
    case .stars: return Int64(value.rounded())
    case .ton: return Int64((value * 1_000_000_000.0).rounded())
    case .rubles: return Int64((value * 100.0).rounded())
    }
}

private final class PampGramLedgerArguments {
    let chooseFilter: () -> Void
    let addOperation: () -> Void
    let clear: () -> Void

    init(chooseFilter: @escaping () -> Void, addOperation: @escaping () -> Void, clear: @escaping () -> Void) {
        self.chooseFilter = chooseFilter
        self.addOperation = addOperation
        self.clear = clear
    }
}

private enum PampGramLedgerEntry: ItemListNodeEntry {
    case balance(String)
    case stats(String)
    case filter(String)
    case add
    case operation(Int64, String, String, String)
    case empty
    case clear
    case footer(String)

    var section: ItemListSectionId {
        switch self {
        case .balance, .stats: return 0
        case .filter, .add: return 1
        case .operation, .empty: return 2
        case .clear, .footer: return 3
        }
    }

    var stableId: Int64 {
        switch self {
        case .balance: return 0
        case .stats: return 1
        case .filter: return 2
        case .add: return 3
        case let .operation(id, _, _, _): return 10_000 + id
        case .empty: return 9_000
        case .clear: return 9_001
        case .footer: return 9_002
        }
    }

    static func ==(lhs: PampGramLedgerEntry, rhs: PampGramLedgerEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.balance(a), .balance(b)): return a == b
        case let (.stats(a), .stats(b)): return a == b
        case let (.filter(a), .filter(b)): return a == b
        case (.add, .add), (.empty, .empty), (.clear, .clear): return true
        case let (.operation(a1, a2, a3, a4), .operation(b1, b2, b3, b4)): return a1 == b1 && a2 == b2 && a3 == b3 && a4 == b4
        case let (.footer(a), .footer(b)): return a == b
        default: return false
        }
    }

    static func <(lhs: PampGramLedgerEntry, rhs: PampGramLedgerEntry) -> Bool { lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramLedgerArguments
        switch self {
        case let .balance(text):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Текущий баланс", titleFont: .bold, label: text, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case let .stats(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .filter(text):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Фильтр", label: text, sectionId: self.section, style: .blocks, action: arguments.chooseFilter)
        case .add:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Добавить операцию", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: arguments.addOperation)
        case let .operation(_, title, amount, detail):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: amount, additionalDetailLabel: detail, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case .empty:
            return ItemListTextItem(presentationData: presentationData, text: .plain("По выбранному фильтру операций пока нет."), sectionId: self.section)
        case .clear:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Очистить историю", kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: arguments.clear)
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func pampGramLedgerController(context: AccountContext, currency: PampGramLocalCurrency) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    var filterValue: PampGramLedgerFilter = .all
    let filter = ValuePromise<PampGramLedgerFilter>(.all, ignoreRepeated: true)

    func add(kind: PampGramLocalOperationKind) {
        let isOutgoing = kind == .purchase || kind == .debit || kind == .transfer
        presentControllerImpl?(promptController(
            context: context,
            text: kind.displayName,
            subtitle: "Введите сумму для локальной истории \(currency.displayName). Баланс пересчитается сразу.",
            value: "",
            placeholder: currency == .stars ? "100" : "10.0",
            characterLimit: 24,
            apply: { value in
                guard let value, let parsed = pampGramLedgerParseAmount(currency: currency, text: value) else { return }
                let signed = isOutgoing ? -parsed : parsed
                let _ = context.account.postbox.transaction { transaction -> Void in
                    PampGramLocalLedgerStore.addAndApply(transaction: transaction, currency: currency, kind: kind, amount: signed, title: kind.displayName, details: "Добавлено вручную")
                }.start()
            }
        ))
    }

    let arguments = PampGramLedgerArguments(
        chooseFilter: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let sheet = ActionSheetController(presentationData: presentationData)
            sheet.setItemGroups([
                ActionSheetItemGroup(items: PampGramLedgerFilter.allCasesCompat.map { value in
                    ActionSheetButtonItem(title: (value == filterValue ? "✓ " : "") + value.title, color: .accent, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                        filterValue = value
                        filter.set(value)
                    })
                }),
                ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in sheet?.dismissAnimated() })])
            ])
            presentControllerImpl?(sheet)
        },
        addOperation: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let sheet = ActionSheetController(presentationData: presentationData)
            sheet.setItemGroups([
                ActionSheetItemGroup(items: [
                    ActionSheetTextItem(title: "Тип операции"),
                    ActionSheetButtonItem(title: "Пополнение", color: .accent, action: { [weak sheet] in sheet?.dismissAnimated(); add(kind: .topUp) }),
                    ActionSheetButtonItem(title: "Зачисление", color: .accent, action: { [weak sheet] in sheet?.dismissAnimated(); add(kind: .credit) }),
                    ActionSheetButtonItem(title: "Списание", color: .accent, action: { [weak sheet] in sheet?.dismissAnimated(); add(kind: .debit) }),
                    ActionSheetButtonItem(title: "Покупка", color: .accent, action: { [weak sheet] in sheet?.dismissAnimated(); add(kind: .purchase) }),
                    ActionSheetButtonItem(title: "Продажа", color: .accent, action: { [weak sheet] in sheet?.dismissAnimated(); add(kind: .sale) }),
                    ActionSheetButtonItem(title: "Передача", color: .accent, action: { [weak sheet] in sheet?.dismissAnimated(); add(kind: .transfer) })
                ]),
                ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in sheet?.dismissAnimated() })])
            ])
            presentControllerImpl?(sheet)
        },
        clear: {
            let _ = context.account.postbox.transaction { transaction -> Void in
                let all = PampGramLocalLedgerStore.all(transaction: transaction)
                for operation in all where operation.currency == currency {
                    PampGramLocalLedgerStore.remove(transaction: transaction, id: operation.id)
                }
            }.start()
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        PampGramCore.settingsSignal(postbox: context.account.postbox),
        PampGramLocalLedgerStore.signal(postbox: context.account.postbox),
        filter.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings, allOperations, selectedFilter -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let operations = allOperations.filter { operation in
            guard operation.currency == currency else { return false }
            switch selectedFilter {
            case .all: return true
            case .incoming: return operation.amount >= 0
            case .outgoing: return operation.amount < 0
            }
        }
        let stats = PampGramLocalLedgerStore.statistics(allOperations, currency: currency)
        let balance: Int64
        switch currency {
        case .stars: balance = settings.fakeStarsBalance
        case .ton: balance = settings.fakeTonBalanceNanos
        case .rubles: balance = settings.localRublesBalanceKopecks
        }
        var entries: [PampGramLedgerEntry] = [
            .balance(pampGramLedgerBalanceText(currency: currency, value: balance)),
            .stats("Операций: \(stats.operationCount) · Пополнений: \(stats.topUps) · Покупок: \(stats.purchases) · Продаж: \(stats.sales)\nЗачислено: \(pampGramLedgerAmountText(currency: currency, amount: stats.incoming)) · Списано: \(pampGramLedgerAmountText(currency: currency, amount: -stats.outgoing)) · Итог: \(pampGramLedgerAmountText(currency: currency, amount: stats.net))"),
            .filter(selectedFilter.title),
            .add
        ]
        if operations.isEmpty {
            entries.append(.empty)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            for operation in operations {
                let date = formatter.string(from: Date(timeIntervalSince1970: Double(operation.date)))
                let detail = operation.details.isEmpty ? date : "\(operation.details) · \(date)"
                entries.append(.operation(operation.id, operation.title, pampGramLedgerAmountText(currency: currency, amount: operation.amount), detail))
            }
        }
        entries.append(.clear)
        entries.append(.footer("История и статистика полностью локальные и всегда строятся из одного журнала операций, поэтому пополнения, покупки Stars и покупки/продажи подарков автоматически попадают сюда."))
        return (
            ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("\(currency.displayName) · история"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false),
            (ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true), arguments)
        )
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in controller?.present(c, in: .window(.root)) }
    return controller
}

private extension PampGramLedgerFilter {
    static var allCasesCompat: [PampGramLedgerFilter] { [.all, .incoming, .outgoing] }
}
