import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import OverlayStatusController
import PromptUI
import PampGramCore
import PhantomGiftKit

/// One package from the real "Купить звёзды" sheet's own published Stars→₽ pricing —
/// PampGram never invents these numbers, just reuses Telegram's own public tiers so the fake
/// screen reads as authentic.
private struct PampGramStarsPackage: Equatable {
    let stars: Int64
    let priceKopecks: Int64
}

private let pampGramStarsPackages: [PampGramStarsPackage] = [
    .init(stars: 100, priceKopecks: 18_199), .init(stars: 150, priceKopecks: 26_499),
    .init(stars: 250, priceKopecks: 42_900), .init(stars: 350, priceKopecks: 59_900),
    .init(stars: 500, priceKopecks: 84_900), .init(stars: 750, priceKopecks: 125_900),
    .init(stars: 1_000, priceKopecks: 167_900), .init(stars: 1_500, priceKopecks: 249_900),
    .init(stars: 2_500, priceKopecks: 419_900), .init(stars: 5_000, priceKopecks: 829_900),
    .init(stars: 10_000, priceKopecks: 1_659_900), .init(stars: 25_000, priceKopecks: 4_149_900),
    .init(stars: 50_000, priceKopecks: 8_299_900), .init(stars: 100_000, priceKopecks: 16_599_900),
    .init(stars: 150_000, priceKopecks: 24_999_900)
]
private let pampGramStarsCompact: Set<Int64> = [100, 250, 500, 1_000, 2_500, 10_000, 50_000, 150_000]

/// The fake card the local checkout "charges" — cosmetic only: whatever is selected, the money
/// comes out of `localRublesBalanceKopecks`, never a real card. SberPay is PampGram's own
/// already-linked source; "Добавить карту" appends more on top of it.
private struct PampGramPaymentMethod: Equatable {
    let id: String
    let title: String
    let detail: String
}

private let pampGramAttachedCard = PampGramPaymentMethod(id: "sberpay", title: "SberPay", detail: "Привязана · Сбербанк •••• 4415")

private final class PampGramStarsPurchaseArguments {
    let openCheckout: (PampGramStarsPackage) -> Void
    let toggleExpanded: () -> Void

    init(openCheckout: @escaping (PampGramStarsPackage) -> Void, toggleExpanded: @escaping () -> Void) {
        self.openCheckout = openCheckout
        self.toggleExpanded = toggleExpanded
    }
}

private enum PampGramStarsPurchaseEntry: ItemListNodeEntry {
    case balanceText(String)
    case packagesHeader(String)
    case package(Int, PampGramStarsPackage)
    case additional(Bool)

    var section: ItemListSectionId {
        switch self {
        case .balanceText:
            return 0
        case .packagesHeader, .package, .additional:
            return 1
        }
    }

    var stableId: Int32 {
        switch self {
        case .balanceText:
            return 0
        case .packagesHeader:
            return 1
        case let .package(index, _):
            return Int32(2 + index)
        case .additional:
            return 100
        }
    }

    static func ==(lhs: PampGramStarsPurchaseEntry, rhs: PampGramStarsPurchaseEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.balanceText(lhsText), .balanceText(rhsText)):
            return lhsText == rhsText
        case let (.packagesHeader(lhsText), .packagesHeader(rhsText)):
            return lhsText == rhsText
        case let (.package(lhsIndex, lhsPackage), .package(rhsIndex, rhsPackage)):
            return lhsIndex == rhsIndex && lhsPackage == rhsPackage
        case let (.additional(lhs), .additional(rhs)):
            return lhs == rhs
        default:
            return false
        }
    }

    static func <(lhs: PampGramStarsPurchaseEntry, rhs: PampGramStarsPurchaseEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramStarsPurchaseArguments
        switch self {
        case let .balanceText(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .packagesHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .additional(expanded):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: expanded ? "Скрыть дополнительные" : "⌄  Дополнительно", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: { arguments.toggleExpanded() })
        case let .package(_, package):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: generatePampGramSectionIcon(systemName: "star.fill", backgroundColor: UIColor(rgb: 0xf5a623)),
                title: "\(package.stars) звёзд",
                label: formatRubles(kopecks: package.priceKopecks),
                sectionId: self.section,
                style: .blocks,
                action: {
                    arguments.openCheckout(package)
                }
            )
        }
    }
}

private func pampGramStarsPurchaseEntries(balanceKopecks: Int64, expanded: Bool) -> [PampGramStarsPurchaseEntry] {
    var entries: [PampGramStarsPurchaseEntry] = []
    entries.append(.balanceText("Баланс карты: \(formatRubles(kopecks: balanceKopecks))"))
    entries.append(.packagesHeader("ВЫБЕРИТЕ КОЛИЧЕСТВО"))
    let visible = expanded ? pampGramStarsPackages : pampGramStarsPackages.filter { pampGramStarsCompact.contains($0.stars) }
    for (index, package) in visible.enumerated() { entries.append(.package(index, package)) }
    entries.append(.additional(expanded))
    return entries
}

// MARK: - Checkout screen

private final class PampGramStarsCheckoutArguments {
    let pay: () -> Void
    let choosePayment: () -> Void
    let cancel: () -> Void

    init(pay: @escaping () -> Void, choosePayment: @escaping () -> Void, cancel: @escaping () -> Void) {
        self.pay = pay
        self.choosePayment = choosePayment
        self.cancel = cancel
    }
}

private enum PampGramStarsCheckoutEntry: ItemListNodeEntry {
    case itemRow(String, String)
    case totalRow(String, String)
    case paymentHeader(String)
    case paymentRow(String, String)
    case footer(String)
    case payButton(String, Bool)
    case cancelButton(String)

    var section: ItemListSectionId {
        switch self {
        case .itemRow, .totalRow:
            return 0
        case .paymentHeader, .paymentRow:
            return 1
        case .footer, .payButton, .cancelButton:
            return 2
        }
    }

    var stableId: Int32 {
        switch self {
        case .itemRow:
            return 0
        case .totalRow:
            return 1
        case .paymentHeader:
            return 2
        case .paymentRow:
            return 3
        case .footer:
            return 4
        case .payButton:
            return 5
        case .cancelButton:
            return 6
        }
    }

    static func ==(lhs: PampGramStarsCheckoutEntry, rhs: PampGramStarsCheckoutEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.itemRow(lhsTitle, lhsLabel), .itemRow(rhsTitle, rhsLabel)):
            return lhsTitle == rhsTitle && lhsLabel == rhsLabel
        case let (.totalRow(lhsTitle, lhsLabel), .totalRow(rhsTitle, rhsLabel)):
            return lhsTitle == rhsTitle && lhsLabel == rhsLabel
        case let (.paymentHeader(lhsText), .paymentHeader(rhsText)):
            return lhsText == rhsText
        case let (.paymentRow(lhsTitle, lhsLabel), .paymentRow(rhsTitle, rhsLabel)):
            return lhsTitle == rhsTitle && lhsLabel == rhsLabel
        case let (.footer(lhsText), .footer(rhsText)):
            return lhsText == rhsText
        case let (.payButton(lhsTitle, lhsEnabled), .payButton(rhsTitle, rhsEnabled)):
            return lhsTitle == rhsTitle && lhsEnabled == rhsEnabled
        case let (.cancelButton(lhsTitle), .cancelButton(rhsTitle)):
            return lhsTitle == rhsTitle
        default:
            return false
        }
    }

    static func <(lhs: PampGramStarsCheckoutEntry, rhs: PampGramStarsCheckoutEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramStarsCheckoutArguments
        switch self {
        case let .itemRow(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "star.fill", backgroundColor: UIColor(rgb: 0xf5a623)), title: title, enabled: false, label: label, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case let .totalRow(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, enabled: false, titleFont: .bold, label: label, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case let .paymentHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .paymentRow(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "creditcard.fill", backgroundColor: UIColor(rgb: 0x34c759)), title: title, label: label, sectionId: self.section, style: .blocks, action: { arguments.choosePayment() })
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .payButton(title, enabled):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: enabled ? .generic : .disabled, alignment: .center, sectionId: self.section, style: .blocks, action: {
                arguments.pay()
            })
        case let .cancelButton(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .destructive, alignment: .center, sectionId: self.section, style: .blocks, action: {
                arguments.cancel()
            })
        }
    }
}

private func pampGramStarsCheckoutEntries(package: PampGramStarsPackage, balanceKopecks: Int64, method: PampGramPaymentMethod) -> [PampGramStarsCheckoutEntry] {
    var entries: [PampGramStarsCheckoutEntry] = []
    entries.append(.itemRow("\(package.stars) Звёзд Telegram", formatRubles(kopecks: package.priceKopecks)))
    entries.append(.totalRow("Итого", formatRubles(kopecks: package.priceKopecks)))
    entries.append(.paymentHeader("СПОСОБ ОПЛАТЫ"))
    entries.append(.paymentRow(method.title, method.detail))
    let canAfford = balanceKopecks >= package.priceKopecks
    entries.append(.footer(canAfford ? "Спишется с локальной карты — та же, что пополняется в «Подарки» → «Локальные рубли»." : "На карте недостаточно средств. Пополните карту в «Подарки» → «Локальные рубли»."))
    entries.append(.payButton("Заплатить \(formatRubles(kopecks: package.priceKopecks))", canAfford))
    entries.append(.cancelButton("Отмена"))
    return entries
}

/// Pushed when a package is picked on the list screen — a dedicated confirm-and-pay step
/// (item, total, payment method, "Оплатить" button) rather than a plain alert, so the local
/// purchase reads like an actual checkout instead of a single tap-to-buy row. On success shows
/// Telegram's own native loading→checkmark overlay (`OverlayStatusController`, the same one
/// real purchases and link-copies use elsewhere in the app) instead of anything borrowed from
/// a third-party checkout UI.
private func pampGramStarsCheckoutController(context: AccountContext, package: PampGramStarsPackage, onPaid: @escaping (Int64) -> Void) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    var popSelfImpl: (() -> Void)?
    let methodPromise = ValuePromise<PampGramPaymentMethod>(pampGramAttachedCard, ignoreRepeated: true)
    var currentMethod = pampGramAttachedCard
    var methods: [PampGramPaymentMethod] = [pampGramAttachedCard]
    var showPaymentSheetImpl: (() -> Void)?

    let addCard: () -> Void = {
        presentControllerImpl?(promptController(
            context: context,
            text: "Добавить карту",
            subtitle: "Введите номер карты. Оплата всё равно списывается с локальной карты — настоящая карта не привязывается.",
            value: "",
            placeholder: "0000 0000 0000 0000",
            characterLimit: 19,
            apply: { value in
                guard let value else {
                    showPaymentSheetImpl?()
                    return
                }
                let digits = value.filter { $0.isNumber }
                guard digits.count >= 4 else {
                    showPaymentSheetImpl?()
                    return
                }
                let last4 = String(digits.suffix(4))
                let newCard = PampGramPaymentMethod(id: "card_\(digits)", title: "Банковская карта", detail: "•••• \(last4)")
                if !methods.contains(newCard) {
                    methods.append(newCard)
                }
                currentMethod = newCard
                methodPromise.set(newCard)
                showPaymentSheetImpl?()
            }
        ))
    }

    let showPaymentSheet: () -> Void = {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let sheet = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = [ActionSheetTextItem(title: "Способ оплаты")]
        for method in methods {
            let selected = method == currentMethod
            items.append(ActionSheetButtonItem(title: selected ? "✓ \(method.title) · \(method.detail)" : "\(method.title) · \(method.detail)", color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                currentMethod = method
                methodPromise.set(method)
            }))
        }
        items.append(ActionSheetButtonItem(title: "Добавить карту", color: .accent, action: { [weak sheet] in
            sheet?.dismissAnimated()
            addCard()
        }))
        sheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: "OK", color: .accent, font: .bold, action: { [weak sheet] in sheet?.dismissAnimated() })])
        ])
        presentControllerImpl?(sheet)
    }
    showPaymentSheetImpl = showPaymentSheet

    let arguments = PampGramStarsCheckoutArguments(
        pay: {
            let _ = (PampGramCore.settingsSignal(postbox: context.account.postbox) |> take(1) |> deliverOnMainQueue).start(next: { settings in
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                guard settings.localRublesBalanceKopecks >= package.priceKopecks else {
                    presentControllerImpl?(textAlertController(
                        context: context,
                        title: "Недостаточно средств",
                        text: "На карте \(formatRubles(kopecks: settings.localRublesBalanceKopecks)), а нужно \(formatRubles(kopecks: package.priceKopecks)). Пополните карту в разделе «Подарки» → «Локальные рубли».",
                        actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]
                    ))
                    return
                }

                let loadingController = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: nil))
                presentControllerImpl?(loadingController)

                Queue.mainQueue().after(0.6, {
                    let _ = context.account.postbox.transaction { transaction -> Bool in
                        let current = PampGramCore.settings(transaction: transaction)
                        guard current.localRublesBalanceKopecks >= package.priceKopecks else { return false }
                        var rubleBalanceAfter: Int64 = 0
                        var starsBalanceAfter: Int64 = 0
                        PampGramCore.updateSettings(transaction: transaction, { settings in
                            var settings = settings
                            settings.localRublesBalanceKopecks -= package.priceKopecks
                            settings.fakeStarsBalance += package.stars
                            rubleBalanceAfter = settings.localRublesBalanceKopecks
                            starsBalanceAfter = settings.fakeStarsBalance
                            return settings
                        })
                        PampGramLocalLedgerStore.add(transaction: transaction, operation: PampGramLocalOperation(currency: .rubles, kind: .purchase, amount: -package.priceKopecks, title: "Покупка Stars", details: "\(currentMethod.title) · \(currentMethod.detail)", balanceAfter: rubleBalanceAfter))
                        PampGramLocalLedgerStore.add(transaction: transaction, operation: PampGramLocalOperation(currency: .stars, kind: .topUp, amount: package.stars, title: "Пополнение Stars", details: "Покупка звёзд Telegram успешно", balanceAfter: starsBalanceAfter))
                        return true
                    }.start(next: { success in
                        guard success else { return }
                        loadingController.dismiss()
                        // Drop the native star-topup plaque into the Telegram service chat (777000);
                        // its box art/colour differs per star count, like a real purchase.
                        let _ = PampGramPhantomGiftMessage.insertLocalStarsTopUpMessage(context: context, starCount: package.stars, fiatKopecks: package.priceKopecks).start()
                        presentControllerImpl?(OverlayStatusController(theme: presentationData.theme, type: .starSuccess("+\(package.stars)")))
                        popSelfImpl?()
                        onPaid(package.stars)
                    })
                })
            })
        },
        choosePayment: {
            showPaymentSheet()
        },
        cancel: {
            popSelfImpl?()
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        PampGramCore.settingsSignal(postbox: context.account.postbox),
        methodPromise.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings, method -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Оплата"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: pampGramStarsCheckoutEntries(package: package, balanceKopecks: settings.localRublesBalanceKopecks, method: method),
            style: .blocks,
            animateChanges: true
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    popSelfImpl = { [weak controller] in
        if let navigationController = controller?.navigationController as? NavigationController {
            let _ = navigationController.popViewController(animated: false)
        } else {
            controller?.dismiss()
        }
    }
    return controller
}

/// PampGram's own "Купить звёзды" — visually mirrors the real Apple In-App Purchase sheet
/// (same package list, same real published ₽ prices), but spends `localRublesBalanceKopecks`
/// instead of a real card, and credits `fakeStarsBalance` instead of the real Stars balance.
/// Picking a package pushes `pampGramStarsCheckoutController` for a proper confirm-and-pay step
/// before anything is charged. Reached only from the "Пополнить" action on the Stars balance
/// screen when `localRublesPurchaseEnabled` is on — every other place the app buys Stars
/// (gifting to a friend, paying for a message, joining a paid channel) still goes through the
/// real flow, since those inherently involve a real other party or a real unlock this screen
/// can't fake.
public func pampGramStarsPurchaseController(context: AccountContext, completion: @escaping (Int64) -> Void) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    var dismissImpl: (() -> Void)?
    var expandedValue = false
    let expanded = ValuePromise<Bool>(false, ignoreRepeated: true)

    let arguments = PampGramStarsPurchaseArguments(
        openCheckout: { package in
            pushControllerImpl?(pampGramStarsCheckoutController(context: context, package: package, onPaid: { stars in
                dismissImpl?()
                completion(stars)
            }))
        },
        toggleExpanded: {
            expandedValue.toggle()
            expanded.set(expandedValue)
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        PampGramCore.settingsSignal(postbox: context.account.postbox),
        expanded.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings, isExpanded -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Купить звёзды"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: pampGramStarsPurchaseEntries(balanceKopecks: settings.localRublesBalanceKopecks, expanded: isExpanded),
            style: .blocks,
            animateChanges: true
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        controller?.push(c)
    }
    dismissImpl = { [weak controller] in
        if let navigationController = controller?.navigationController as? NavigationController {
            let _ = navigationController.popViewController(animated: true)
        } else {
            controller?.dismiss()
        }
    }
    return controller
}
