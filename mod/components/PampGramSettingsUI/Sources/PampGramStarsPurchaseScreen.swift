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
    PampGramStarsPackage(stars: 50, priceKopecks: 10_299),
    PampGramStarsPackage(stars: 75, priceKopecks: 14_699),
    PampGramStarsPackage(stars: 100, priceKopecks: 18_900),
    PampGramStarsPackage(stars: 150, priceKopecks: 27_599),
    PampGramStarsPackage(stars: 250, priceKopecks: 44_900),
    PampGramStarsPackage(stars: 350, priceKopecks: 61_900),
    PampGramStarsPackage(stars: 500, priceKopecks: 87_900),
    PampGramStarsPackage(stars: 750, priceKopecks: 131_900),
    PampGramStarsPackage(stars: 1_000, priceKopecks: 174_900),
    PampGramStarsPackage(stars: 1_500, priceKopecks: 259_900),
    PampGramStarsPackage(stars: 2_500, priceKopecks: 433_900)
]

/// How many packages the first ("Купить звёзды") screen shows before "Дополнительно" is
/// needed — the real sheet also opens on a short list and hides the long tail behind a "See
/// all" row.
private let pampGramStarsShortCount = 5

private final class PampGramStarsPurchaseArguments {
    let openCheckout: (PampGramStarsPackage) -> Void
    let showMore: () -> Void

    init(openCheckout: @escaping (PampGramStarsPackage) -> Void, showMore: @escaping () -> Void) {
        self.openCheckout = openCheckout
        self.showMore = showMore
    }
}

private enum PampGramStarsPurchaseEntry: ItemListNodeEntry {
    case balanceText(String)
    case packagesHeader(String)
    case package(Int, PampGramStarsPackage)
    case more(String)

    var section: ItemListSectionId {
        switch self {
        case .balanceText:
            return 0
        case .packagesHeader, .package, .more:
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
        case .more:
            return 10_000
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
        case let (.more(lhsText), .more(rhsText)):
            return lhsText == rhsText
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
        case let .more(title):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: generatePampGramSectionIcon(systemName: "ellipsis", backgroundColor: UIColor(rgb: 0x8e8e93)),
                title: title,
                label: "",
                sectionId: self.section,
                style: .blocks,
                action: {
                    arguments.showMore()
                }
            )
        }
    }
}

private func pampGramStarsPurchaseEntries(balanceKopecks: Int64, expanded: Bool) -> [PampGramStarsPurchaseEntry] {
    var entries: [PampGramStarsPurchaseEntry] = []
    entries.append(.balanceText("Баланс карты: \(formatRubles(kopecks: balanceKopecks))"))
    entries.append(.packagesHeader("ВЫБЕРИТЕ КОЛИЧЕСТВО"))
    let visible = expanded ? pampGramStarsPackages.count : min(pampGramStarsShortCount, pampGramStarsPackages.count)
    for index in 0 ..< visible {
        entries.append(.package(index, pampGramStarsPackages[index]))
    }
    if !expanded && pampGramStarsPackages.count > pampGramStarsShortCount {
        entries.append(.more("Дополнительно"))
    }
    return entries
}

// MARK: - Checkout screen

/// The fake card the local checkout "charges" — cosmetic only: whatever is selected, the money
/// comes out of `localRublesBalanceKopecks`, never a real card.
private struct PampGramPaymentMethod: Equatable {
    let id: String
    let title: String
    let detail: String
}

/// PampGram's own already-linked payment source — a SberPay-style card shown as attached, so
/// star purchases have a believable "Способ оплаты" to charge. Extra cards can be added on top
/// of it via "Добавить карту".
private let pampGramAttachedCard = PampGramPaymentMethod(id: "sberpay", title: "SberPay", detail: "Привязана · Сбербанк •••• 4415")

private final class PampGramStarsCheckoutArguments {
    let pay: () -> Void
    let selectPaymentMethod: () -> Void
    let cancel: () -> Void

    init(pay: @escaping () -> Void, selectPaymentMethod: @escaping () -> Void, cancel: @escaping () -> Void) {
        self.pay = pay
        self.selectPaymentMethod = selectPaymentMethod
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
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "creditcard.fill", backgroundColor: UIColor(rgb: 0x34c759)), title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.selectPaymentMethod()
            })
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
    // Starts with the attached SberPay card; "Добавить карту" appends to it.
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
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: "OK", color: .accent, font: .bold, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                })
            ])
        ])
        presentControllerImpl?(sheet)
    }
    showPaymentSheetImpl = showPaymentSheet

    let arguments = PampGramStarsCheckoutArguments(
        selectPaymentMethod: {
            showPaymentSheet()
        },
        cancel: {
            popSelfImpl?()
        },
        pay: {
            let _ = (PampGramCore.rawSettingsSignal(postbox: context.account.postbox) |> take(1) |> deliverOnMainQueue).start(next: { settings in
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
                    let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                        var settings = settings
                        guard settings.localRublesBalanceKopecks >= package.priceKopecks else {
                            return settings
                        }
                        settings.localRublesBalanceKopecks -= package.priceKopecks
                        settings.fakeStarsBalance += package.stars
                        return settings
                    }).start(completed: {
                        loadingController.dismiss()
                        // Record the пополнение so it shows in the (merged) Stars transaction
                        // history, and drop the native star-topup plaque into the Telegram
                        // service chat — same as a real purchase.
                        let _ = PampGramFakeTopUpStore.record(context: context, isTon: false, amount: package.stars, fiatKopecks: package.priceKopecks).start()
                        let _ = PampGramPhantomGiftMessage.insertLocalStarsTopUpMessage(context: context, starCount: package.stars, fiatKopecks: package.priceKopecks).start()
                        presentControllerImpl?(OverlayStatusController(theme: presentationData.theme, type: .starSuccess("+\(package.stars)")))
                        popSelfImpl?()
                        onPaid(package.stars)
                    })
                })
            })
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        PampGramCore.rawSettingsSignal(postbox: context.account.postbox),
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
    let expandedPromise = ValuePromise<Bool>(false, ignoreRepeated: true)

    let arguments = PampGramStarsPurchaseArguments(
        openCheckout: { package in
            pushControllerImpl?(pampGramStarsCheckoutController(context: context, package: package, onPaid: { stars in
                dismissImpl?()
                completion(stars)
            }))
        },
        showMore: {
            expandedPromise.set(true)
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        PampGramCore.rawSettingsSignal(postbox: context.account.postbox),
        expandedPromise.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings, expanded -> (ItemListControllerState, (ItemListNodeState, Any)) in
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
            entries: pampGramStarsPurchaseEntries(balanceKopecks: settings.localRublesBalanceKopecks, expanded: expanded),
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
