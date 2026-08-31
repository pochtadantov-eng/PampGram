import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import AccountContext
import PromptUI
import PampGramCore

private final class PampGramProfileVisualsArguments {
    let toggleRating: (Bool) -> Void
    let editRating: () -> Void
    let editPoints: () -> Void
    let toggleNumber: (Bool) -> Void
    let editNumber: () -> Void
    let editPurchasedAt: () -> Void
    let editPrice: () -> Void

    init(toggleRating: @escaping (Bool) -> Void, editRating: @escaping () -> Void, editPoints: @escaping () -> Void, toggleNumber: @escaping (Bool) -> Void, editNumber: @escaping () -> Void, editPurchasedAt: @escaping () -> Void, editPrice: @escaping () -> Void) {
        self.toggleRating = toggleRating
        self.editRating = editRating
        self.editPoints = editPoints
        self.toggleNumber = toggleNumber
        self.editNumber = editNumber
        self.editPurchasedAt = editPurchasedAt
        self.editPrice = editPrice
    }
}

private enum PampGramProfileVisualsEntry: ItemListNodeEntry {
    case about(String)
    case ratingHeader(String)
    case ratingToggle(Bool)
    case ratingValue(String)
    case points(String)
    case ratingFooter(String)
    case numberHeader(String)
    case numberToggle(Bool)
    case number(String)
    case purchasedAt(String)
    case price(String)
    case numberFooter(String)

    var section: ItemListSectionId {
        switch self {
        case .about: return 0
        case .ratingHeader, .ratingToggle, .ratingValue, .points, .ratingFooter: return 1
        case .numberHeader, .numberToggle, .number, .purchasedAt, .price, .numberFooter: return 2
        }
    }
    var stableId: Int32 {
        switch self {
        case .about: return 0
        case .ratingHeader: return 10
        case .ratingToggle: return 11
        case .ratingValue: return 12
        case .points: return 13
        case .ratingFooter: return 14
        case .numberHeader: return 20
        case .numberToggle: return 21
        case .number: return 22
        case .purchasedAt: return 23
        case .price: return 24
        case .numberFooter: return 25
        }
    }
    static func <(lhs: Self, rhs: Self) -> Bool { lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let a = arguments as! PampGramProfileVisualsArguments
        switch self {
        case let .about(text), let .ratingFooter(text), let .numberFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .ratingHeader(text), let .numberHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .ratingToggle(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Визуальный рейтинг в профиле", value: value, sectionId: self.section, style: .blocks, updated: a.toggleRating)
        case let .ratingValue(value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Рейтинг", label: value, sectionId: self.section, style: .blocks, action: a.editRating)
        case let .points(value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Баллы", label: value, sectionId: self.section, style: .blocks, action: a.editPoints)
        case let .numberToggle(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Анонимный номер в профиле", value: value, sectionId: self.section, style: .blocks, updated: a.toggleNumber)
        case let .number(value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Номер", label: value, sectionId: self.section, style: .blocks, action: a.editNumber)
        case let .purchasedAt(value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Дата покупки", label: value, sectionId: self.section, style: .blocks, action: a.editPurchasedAt)
        case let .price(value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Цена покупки", label: value, sectionId: self.section, style: .blocks, action: a.editPrice)
        }
    }
}

private func pampGramProfileDateString(_ timestamp: Int32) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter.string(from: Date(timeIntervalSince1970: Double(timestamp)))
}

public func pampGramProfileVisualsController(context: AccountContext) -> ViewController {
    var present: ((ViewController) -> Void)?

    func update(_ f: @escaping (PampGramProfileVisualState) -> PampGramProfileVisualState) {
        let _ = context.account.postbox.transaction { transaction -> Void in
            PampGramProfileVisualStore.update(transaction: transaction, f)
        }.start()
    }

    func editInt(title: String, value: Int64, apply: @escaping (Int64) -> Void) {
        present?(promptController(context: context, text: title, subtitle: "Локальное значение PampGram.", value: "\(value)", characterLimit: 20, apply: { text in
            guard let text, let result = Int64(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
            apply(result)
        }))
    }

    var latest = PampGramProfileVisualState.default
    let arguments = PampGramProfileVisualsArguments(
        toggleRating: { value in update { var s = $0; s.ratingEnabled = value; return s } },
        editRating: { editInt(title: "Рейтинг", value: latest.ratingValue) { value in update { var s = $0; s.ratingValue = value; return s } } },
        editPoints: { editInt(title: "Баллы рейтинга", value: latest.ratingPoints) { value in update { var s = $0; s.ratingPoints = value; return s } } },
        toggleNumber: { value in update { var s = $0; s.anonymousNumberEnabled = value; return s } },
        editNumber: {
            present?(promptController(context: context, text: "Анонимный номер", subtitle: "Например +888 0123 4567", value: latest.anonymousNumber, characterLimit: 32, apply: { text in
                guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                update { var s = $0; s.anonymousNumber = text; return s }
            }))
        },
        editPurchasedAt: {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let current = formatter.string(from: Date(timeIntervalSince1970: Double(latest.anonymousNumberPurchasedAt)))
            present?(promptController(context: context, text: "Дата покупки", subtitle: "Формат ГГГГ-ММ-ДД", value: current, characterLimit: 10, apply: { text in
                guard let text, let date = formatter.date(from: text) else { return }
                update { var s = $0; s.anonymousNumberPurchasedAt = Int32(date.timeIntervalSince1970); return s }
            }))
        },
        editPrice: {
            let current = String(format: "%.4f", Double(latest.anonymousNumberPriceTonNanos) / 1_000_000_000.0)
            present?(promptController(context: context, text: "Цена покупки", subtitle: "Сумма в TON", value: current, characterLimit: 24, apply: { text in
                guard let text, let value = Double(text.replacingOccurrences(of: ",", with: ".")), value >= 0 else { return }
                update { var s = $0; s.anonymousNumberPriceTonNanos = Int64((value * 1_000_000_000.0).rounded()); return s }
            }))
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, PampGramProfileVisualStore.signal(postbox: context.account.postbox))
    |> deliverOnMainQueue
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        latest = state
        let entries: [PampGramProfileVisualsEntry] = [
            .about("Настройки ниже меняют только визуальные данные профиля на этом устройстве."),
            .ratingHeader("РЕЙТИНГ"),
            .ratingToggle(state.ratingEnabled),
            .ratingValue("\(state.ratingValue)"),
            .points("\(state.ratingPoints)"),
            .ratingFooter("Рейтинг и баллы отображаются в профиле как локальная карточка PampGram."),
            .numberHeader("АНОНИМНЫЙ НОМЕР"),
            .numberToggle(state.anonymousNumberEnabled),
            .number(state.anonymousNumber),
            .purchasedAt(pampGramProfileDateString(state.anonymousNumberPurchasedAt)),
            .price(String(format: "%.4f TON", Double(state.anonymousNumberPriceTonNanos) / 1_000_000_000.0)),
            .numberFooter("Долгое нажатие/открытие номера в профиле использует эти локальные сведения о покупке.")
        ]
        return (
            ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Профиль · визуалы"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false),
            (ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true), arguments)
        )
    }
    let controller = ItemListController(context: context, state: signal)
    present = { [weak controller] c in controller?.present(c, in: .window(.root)) }
    return controller
}
