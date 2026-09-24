import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import UndoUI
import PampGramCore

private enum PampGramSubscriptionEntry: ItemListNodeEntry {
    case hero
    case planHeader(String)
    case planRow(String)
    case proPlanRow(String)
    case planFooter(String)
    case activateAction(String)
    case upgradeAction(String)

    var section: ItemListSectionId {
        switch self {
        case .hero:
            return 0
        case .planHeader, .planRow, .proPlanRow, .planFooter, .activateAction, .upgradeAction:
            return 1
        }
    }

    var stableId: Int32 {
        switch self {
        case .hero:
            return 0
        case .planHeader:
            return 1
        case .planRow, .proPlanRow:
            return 2
        case .planFooter:
            return 3
        case .upgradeAction:
            return 4
        case .activateAction:
            return 5
        }
    }

    static func <(lhs: PampGramSubscriptionEntry, rhs: PampGramSubscriptionEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramSubscriptionArguments
        switch self {
        case .hero:
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: pampGramSettingsIcon(size: 44.0),
                title: "PampGram",
                titleFont: .bold,
                titleBadge: "MOD",
                label: pampGramVersionString,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .none,
                action: nil
            )
        case let .planHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .planRow(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .proPlanRow(expiryText):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: generatePampGramSectionIcon(systemName: "crown.fill", backgroundColor: UIColor(rgb: 0xffcc00)),
                title: "Ваш план",
                titleFont: .bold,
                titleBadge: "PRO",
                label: "",
                additionalDetailLabel: expiryText,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .none,
                action: nil
            )
        case let .planFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .activateAction(title):
            // ItemListActionItem has no icon support.
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .neutral, alignment: .center, sectionId: self.section, style: .blocks, action: {
                arguments.activatePremium()
            })
        case let .upgradeAction(title):
            // ItemListActionItem has no icon support.
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .center, sectionId: self.section, style: .blocks, action: {
                arguments.openPremiumFeatures()
            })
        }
    }
}

private final class PampGramSubscriptionArguments {
    let activatePremium: () -> Void
    let openPremiumFeatures: () -> Void

    init(activatePremium: @escaping () -> Void, openPremiumFeatures: @escaping () -> Void) {
        self.activatePremium = activatePremium
        self.openPremiumFeatures = openPremiumFeatures
    }
}

/// Reached from the hub's own "Ваш план" row (PampGramHubScreen.swift) and from
/// `pampGramGateTier` when a Standard account taps a PRO-only section — both land here rather
/// than jumping straight to the paywall, so there's one canonical "your plan" screen regardless
/// of how you got here. "Возможности Premium" opens the full paywall
/// (`PampGramPremiumScreen.swift`, which lists Standard's included sections alongside the
/// PRO-exclusive ones); "Обновить план" redeems a one-time code via the same shared
/// `pampGramPresentRedeemKeyFlow` every other redeem entry point in the mod uses (a key minted
/// as "pro" — see the admin panel's "Сгенерировать ключ" — grants tier on redemption, no
/// separate mechanism needed here).
public func pampGramSubscriptionController(context: AccountContext) -> ViewController {
    let selfAccountId = context.account.peerId.id._internalGetInt64Value()
    let statusPromise = Promise<PampGramSubscriptionStatus>()
    var presentControllerImpl: ((ViewController) -> Void)?
    var presentTooltipImpl: ((String) -> Void)?

    func refreshStatus() {
        statusPromise.set(PampGramSubscriptionAPI.fetchStatus(userId: selfAccountId))
    }
    refreshStatus()

    let arguments = PampGramSubscriptionArguments(
        activatePremium: {
            pampGramPresentRedeemKeyFlow(context: context, presentController: { controller in
                presentControllerImpl?(controller)
            }, presentTooltip: { text in
                presentTooltipImpl?(text)
            }, onActivated: { _ in
                refreshStatus()
            })
        },
        openPremiumFeatures: {
            pampGramPresentPremiumScreen(context: context)
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        statusPromise.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, status -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Подписка"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )

        var entries: [PampGramSubscriptionEntry] = [.hero]
        switch status.tier {
        case .standard:
            entries.append(.planHeader("ВАШ ПЛАН"))
            entries.append(.planRow("Standard"))
            entries.append(.planFooter("В Standard входят разделы «Чаты», «Ghost» и «Дополнительно». Premium открывает всё остальное — «Подарки» и «Внешний вид» — без ограничений."))
            entries.append(.upgradeAction("Возможности Premium"))
            entries.append(.activateAction("Обновить план"))
        case .pro:
            entries.append(.planHeader("ВАШ ПЛАН"))
            let expiryText = status.expiresAt.map(pampGramFormatSubscriptionExpiry) ?? "Без ограничения по сроку"
            entries.append(.proPlanRow(expiryText))
            entries.append(.planFooter("Все разделы открыты — «Чаты», «Ghost», «Дополнительно», «Подарки» и «Внешний вид»."))
            entries.append(.upgradeAction("Возможности Premium"))
        }

        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks,
            animateChanges: true
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
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
