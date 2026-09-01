import Foundation
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext
import PromptUI
import PhantomGiftKit

private func pampGramGiftPriceText(_ price: CurrencyAmount?) -> String {
    guard let price else { return "Не на продаже" }
    switch price.currency {
    case .stars:
        return "\(price.amount.value) ⭐"
    case .ton:
        return String(format: "%.3f TON", Double(price.amount.value) / 1_000_000_000.0)
    }
}

private final class PampGramGiftMarketArguments {
    let openGift: (PampGramPhantomGift) -> Void
    init(openGift: @escaping (PampGramPhantomGift) -> Void) { self.openGift = openGift }
}

private enum PampGramGiftMarketEntry: ItemListNodeEntry {
    case about(String)
    case header(String)
    case gift(Int32, PampGramPhantomGift)
    case empty(String)
    case footer(String)
    var section: ItemListSectionId { return self.stableId == 0 ? 0 : 1 }
    var stableId: Int32 {
        switch self {
        case .about: return 0
        case .header: return 1
        case let .gift(index, _): return 10 + index
        case .empty: return 9000
        case .footer: return 9001
        }
    }
    static func <(lhs: Self, rhs: Self) -> Bool { lhs.stableId < rhs.stableId }
    @_optimize(none)
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let a = arguments as! PampGramGiftMarketArguments
        switch self {
        case let .about(text), let .empty(text), let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .header(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .gift(_, gift):
            var badges: [String] = []
            if gift.pinnedToTop { badges.append("закреплён") }
            if gift.worn { badges.append("носится") }
            if !gift.savedToProfile { badges.append("скрыт") }
            if gift.marketPrice != nil { badges.append("маркет") }
            let detail = badges.isEmpty ? pampGramGiftPriceText(gift.marketPrice) : "\(badges.joined(separator: " · ")) · \(pampGramGiftPriceText(gift.marketPrice))"
            let baseTitle = gift.title
            let title: String
            if let number = gift.number {
                title = "\(baseTitle) #\(number)"
            } else {
                title = baseTitle
            }
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: detail, sectionId: self.section, style: .blocks, action: { a.openGift(gift) })
        }
    }
}

public func pampGramGiftMarketController(context: AccountContext) -> ViewController {
    var present: ((ViewController) -> Void)?

    func setMarketPrice(gift: PampGramPhantomGift, currency: CurrencyAmount.Currency) {
        present?(promptController(context: context, text: currency == .stars ? "Цена в Stars" : "Цена в TON", subtitle: "Локальная цена на визуальном маркете PampGram.", value: "", placeholder: currency == .stars ? "500" : "50", characterLimit: 24, apply: { value in
            guard let value else { return }
            let normalized = value.replacingOccurrences(of: ",", with: ".")
            guard let number = Double(normalized), number > 0 else { return }
            let amount: Int64 = currency == .stars ? Int64(number.rounded()) : Int64((number * 1_000_000_000.0).rounded())
            let price = CurrencyAmount(amount: StarsAmount(value: amount, nanos: 0), currency: currency)
            let _ = PampGramPhantomGiftManager.setMarketListing(context: context, giftId: gift.id, price: price).start()
        }))
    }

    func transfer(gift: PampGramPhantomGift) {
        present?(promptController(context: context, text: "Передать визуально", subtitle: "Введите настоящий числовой ID профиля-получателя. Передача существует только в локальной коллекции PampGram.", value: "", placeholder: "123456789", characterLimit: 20, apply: { value in
            guard let value, let raw = Int64(value), raw > 0 else { return }
            let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(raw))
            let _ = PampGramPhantomGiftManager.transfer(context: context, giftId: gift.id, to: peerId).start()
        }))
    }

    let args = PampGramGiftMarketArguments(openGift: { gift in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let sheet = ActionSheetController(presentationData: presentationData)
        let baseTitle = gift.title
        let displayTitle: String
        if let number = gift.number {
            displayTitle = "\(baseTitle) #\(number)"
        } else {
            displayTitle = baseTitle
        }
        var items: [ActionSheetItem] = [ActionSheetTextItem(title: displayTitle)]
        if gift.peerId == context.account.peerId {
            items.append(ActionSheetButtonItem(title: gift.pinnedToTop ? "Открепить в профиле" : "Закрепить в профиле", color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                let _ = PampGramPhantomGiftManager.setPinnedToTop(context: context, matching: gift.asProfileGift, pinnedToTop: !gift.pinnedToTop).start()
            }))
            items.append(ActionSheetButtonItem(title: gift.savedToProfile ? "Скрыть из профиля" : "Показать в профиле", color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                let _ = PampGramPhantomGiftManager.setSavedToProfile(context: context, matching: gift.asProfileGift, savedToProfile: !gift.savedToProfile).start()
            }))
            items.append(ActionSheetButtonItem(title: gift.worn ? "Перестать носить" : "Носить", color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                let _ = PampGramPhantomGiftManager.setWorn(context: context, giftId: gift.id, worn: !gift.worn).start()
            }))
        }
        items.append(ActionSheetButtonItem(title: "Выставить за Stars", color: .accent, action: { [weak sheet] in sheet?.dismissAnimated(); setMarketPrice(gift: gift, currency: .stars) }))
        items.append(ActionSheetButtonItem(title: "Выставить за TON", color: .accent, action: { [weak sheet] in sheet?.dismissAnimated(); setMarketPrice(gift: gift, currency: .ton) }))
        if gift.marketPrice != nil {
            items.append(ActionSheetButtonItem(title: "Снять с маркета", color: .destructive, action: { [weak sheet] in
                sheet?.dismissAnimated()
                let _ = PampGramPhantomGiftManager.setMarketListing(context: context, giftId: gift.id, price: nil).start()
            }))
        }
        items.append(ActionSheetButtonItem(title: "Передать визуально", color: .accent, action: { [weak sheet] in sheet?.dismissAnimated(); transfer(gift: gift) }))
        sheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in sheet?.dismissAnimated() })])
        ])
        present?(sheet)
    })

    let signal = combineLatest(context.sharedContext.presentationData, PampGramPhantomGiftStore.allGiftsSignal(context: context))
    |> deliverOnMainQueue
    |> map { presentationData, gifts -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let active = gifts.filter { $0.soldDate == nil }
        var entries: [PampGramGiftMarketEntry] = [.about("Управление визуальной коллекцией: профиль, закрепление, ношение, передача и локальный маркет. Никаких реальных операций Telegram/TON здесь нет."), .header("КОЛЛЕКЦИЯ")]
        if active.isEmpty { entries.append(.empty("Визуальных подарков пока нет.")) }
        else { for (i, gift) in active.enumerated() { entries.append(.gift(Int32(i), gift)) } }
        entries.append(.footer("Подарок, купленный себе через визуальный маркет, автоматически появляется в этой коллекции и может быть добавлен в профиль."))
        return (
            ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Коллекция и маркет"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false),
            (ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true), args)
        )
    }
    let controller = ItemListController(context: context, state: signal)
    present = { [weak controller] c in controller?.present(c, in: .window(.root)) }
    return controller
}
