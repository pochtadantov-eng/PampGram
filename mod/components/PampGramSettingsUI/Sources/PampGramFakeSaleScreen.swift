import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import PhantomGiftKit
import UndoUI

private func pampGramFakeSalePriceText(_ price: CurrencyAmount) -> String {
    switch price.currency {
    case .stars:
        return "\(price.amount.value) ⭐"
    case .ton:
        return String(format: "%.3f TON", Double(price.amount.value) / 1_000_000_000.0)
    }
}

private final class PampGramFakeSaleArguments {
    let confirmSale: (PampGramPhantomGift) -> Void
    init(confirmSale: @escaping (PampGramPhantomGift) -> Void) { self.confirmSale = confirmSale }
}

private enum PampGramFakeSaleEntry: ItemListNodeEntry {
    case about(String)
    case header(String)
    case gift(Int32, PampGramPhantomGift)
    case empty(String)
    var section: ItemListSectionId { return self.stableId == 0 ? 0 : 1 }
    var stableId: Int32 {
        switch self {
        case .about: return 0
        case .header: return 1
        case let .gift(index, _): return 10 + index
        case .empty: return 9000
        }
    }
    static func <(lhs: Self, rhs: Self) -> Bool { lhs.stableId < rhs.stableId }
    @_optimize(none)
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let a = arguments as! PampGramFakeSaleArguments
        switch self {
        case let .about(text), let .empty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .header(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .gift(_, gift):
            let baseTitle = gift.title
            let title: String
            if let number = gift.number {
                title = "\(baseTitle) #\(number)"
            } else {
                title = baseTitle
            }
            let label = gift.marketPrice.map(pampGramFakeSalePriceText) ?? ""
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "bag.fill.badge.plus", backgroundColor: UIColor(rgb: 0x34c759)), title: title, label: label, sectionId: self.section, style: .blocks, action: { a.confirmSale(gift) })
        }
    }
}

/// "Fake покупка TG": lists this device's own phantom gifts that are currently listed on the
/// local market (`marketPrice != nil`) and lets the admin confirm that "someone bought" one —
/// crediting the fake balance and posting a local "your gift was sold" notification into the
/// Telegram service chat, exactly like a genuine completed resale would. Nothing here touches
/// any real Telegram or TON endpoint; see `PampGramPhantomGiftManager.confirmFakeMarketSale`.
public func pampGramFakeSaleController(context: AccountContext) -> ViewController {
    var present: ((ViewController) -> Void)?
    var presentTooltip: ((String) -> Void)?

    let args = PampGramFakeSaleArguments(confirmSale: { gift in
        let baseTitle = gift.title
        let displayTitle: String
        if let number = gift.number {
            displayTitle = "\(baseTitle) #\(number)"
        } else {
            displayTitle = baseTitle
        }
        let priceText = gift.marketPrice.map(pampGramFakeSalePriceText) ?? ""
        let alertController = textAlertController(
            context: context,
            title: "Подтвердить покупку?",
            text: "«\(displayTitle)» будет отмечен как купленный за \(priceText). Сумма зачислится на ваш баланс, и в «Telegram» придёт уведомление о продаже — реальная сделка Stars/TON не выполняется.",
            actions: [
                TextAlertAction(type: .genericAction, title: "Отмена", action: {}),
                TextAlertAction(type: .defaultAction, title: "Подтвердить", action: {
                    let _ = (PampGramPhantomGiftManager.confirmFakeMarketSale(context: context, giftId: gift.id)
                    |> deliverOnMainQueue).start(completed: {
                        presentTooltip?("Готово: «\(displayTitle)» отмечен как проданный за \(priceText).")
                    })
                }),
            ],
            actionLayout: .vertical
        )
        present?(alertController)
    })

    let signal = combineLatest(context.sharedContext.presentationData, PampGramPhantomGiftStore.allGiftsSignal(context: context))
    |> deliverOnMainQueue
    |> map { presentationData, gifts -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let listed = gifts.filter { $0.peerId == context.account.peerId && $0.soldDate == nil && $0.marketPrice != nil }
        var entries: [PampGramFakeSaleEntry] = [.about("Показывает ваши подарки, выставленные на локальном визуальном маркете за Stars или TON. Подтвердите покупку — и баланс, уведомление и статус подарка обновятся так, будто его действительно купили."), .header("ВЫСТАВЛЕНО НА ПРОДАЖУ")]
        if listed.isEmpty {
            entries.append(.empty("Сейчас ничего не выставлено. Выставить подарок можно в «Коллекция и маркет»."))
        } else {
            for (i, gift) in listed.enumerated() { entries.append(.gift(Int32(i), gift)) }
        }
        return (
            ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Fake покупка TG"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false),
            (ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true), args)
        )
    }
    let controller = ItemListController(context: context, state: signal)
    present = { [weak controller] c in controller?.present(c, in: .window(.root)) }
    presentTooltip = { [weak controller] text in
        guard let controller else { return }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        controller.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), in: .current)
    }
    return controller
}
