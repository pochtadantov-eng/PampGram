import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import PampGramCore

/// One package from the real "Купить звёзды" sheet's own published Stars→₽ pricing —
/// PampGram never invents these numbers, just reuses Telegram's own public tiers so the fake
/// screen reads as authentic.
private struct PampGramStarsPackage {
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

private final class PampGramStarsPurchaseArguments {
    let buy: (PampGramStarsPackage) -> Void

    init(buy: @escaping (PampGramStarsPackage) -> Void) {
        self.buy = buy
    }
}

private enum PampGramStarsPurchaseEntry: ItemListNodeEntry {
    case balanceText(String)
    case packagesHeader(String)
    case package(Int, PampGramStarsPackage)

    var section: ItemListSectionId {
        switch self {
        case .balanceText:
            return 0
        case .packagesHeader, .package:
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
                    arguments.buy(package)
                }
            )
        }
    }
}

private func pampGramStarsPurchaseEntries(balanceKopecks: Int64) -> [PampGramStarsPurchaseEntry] {
    var entries: [PampGramStarsPurchaseEntry] = []
    entries.append(.balanceText("Баланс карты: \(formatRubles(kopecks: balanceKopecks))"))
    entries.append(.packagesHeader("ВЫБЕРИТЕ КОЛИЧЕСТВО"))
    for (index, package) in pampGramStarsPackages.enumerated() {
        entries.append(.package(index, package))
    }
    return entries
}

/// PampGram's own "Купить звёзды" — visually mirrors the real Apple In-App Purchase sheet
/// (same package list, same real published ₽ prices), but spends `localRublesBalanceKopecks`
/// instead of a real card, and credits `fakeStarsBalance` instead of the real Stars balance.
/// Reached only from the "Пополнить" action on the Stars balance screen when
/// `localRublesPurchaseEnabled` is on — every other place the app buys Stars (gifting to a
/// friend, paying for a message, joining a paid channel) still goes through the real flow,
/// since those inherently involve a real other party or a real unlock this screen can't fake.
public func pampGramStarsPurchaseController(context: AccountContext, completion: @escaping (Int64) -> Void) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    var dismissImpl: (() -> Void)?

    let arguments = PampGramStarsPurchaseArguments(
        buy: { package in
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
                presentControllerImpl?(textAlertController(
                    context: context,
                    title: "Купить \(package.stars) звёзд?",
                    text: "С карты спишется \(formatRubles(kopecks: package.priceKopecks)).",
                    actions: [
                        TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                        TextAlertAction(type: .defaultAction, title: "Купить", action: {
                            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                                var settings = settings
                                guard settings.localRublesBalanceKopecks >= package.priceKopecks else {
                                    return settings
                                }
                                settings.localRublesBalanceKopecks -= package.priceKopecks
                                settings.fakeStarsBalance += package.stars
                                return settings
                            }).start(completed: {
                                dismissImpl?()
                                completion(package.stars)
                            })
                        })
                    ],
                    actionLayout: .horizontal
                ))
            })
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        PampGramCore.settingsSignal(postbox: context.account.postbox)
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
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
            entries: pampGramStarsPurchaseEntries(balanceKopecks: settings.localRublesBalanceKopecks),
            style: .blocks,
            animateChanges: true
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
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
