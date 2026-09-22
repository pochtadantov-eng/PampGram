import Foundation
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
    case planFooter(String)
    case activateAction(String)
    case upgradeAction(String)

    var section: ItemListSectionId {
        switch self {
        case .hero:
            return 0
        case .planHeader, .planRow, .planFooter, .activateAction, .upgradeAction:
            return 1
        }
    }

    var stableId: Int32 {
        switch self {
        case .hero:
            return 0
        case .planHeader:
            return 1
        case .planRow:
            return 2
        case .planFooter:
            return 3
        case .activateAction:
            return 4
        case .upgradeAction:
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
        case let .planFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .activateAction(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .neutral, alignment: .center, sectionId: self.section, style: .blocks, action: {
                arguments.activatePremium()
            })
        case let .upgradeAction(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .center, sectionId: self.section, style: .blocks, action: {
                arguments.upgradePlan()
            })
        }
    }
}

private final class PampGramSubscriptionArguments {
    let activatePremium: () -> Void
    let upgradePlan: () -> Void

    init(activatePremium: @escaping () -> Void, upgradePlan: @escaping () -> Void) {
        self.activatePremium = activatePremium
        self.upgradePlan = upgradePlan
    }
}

/// The mod's own username to reach for a plan upgrade — same contact the update-required
/// screen already messages, see `PampGramUpdateRequiredScreen.swift`'s own doc for why this
/// goes through the same resolve-then-navigate path Telegram's own `tg://` message links use
/// rather than an external URL.
private func pampGramOpenUpgradeRequestChat(context: AccountContext) {
    guard let navigationController = context.sharedContext.mainWindow?.viewController as? NavigationController else {
        return
    }
    let _ = (context.engine.peers.resolvePeerByName(name: "Claps228", referrer: nil)
    |> mapToSignal { result -> Signal<EnginePeer?, NoError> in
        guard case let .result(peer) = result else {
            return .complete()
        }
        return .single(peer)
    }
    |> deliverOnMainQueue).startStandalone(next: { peer in
        guard let peer else {
            return
        }
        context.sharedContext.navigateToChatController(NavigateToChatControllerParams(
            navigationController: navigationController,
            context: context,
            chatLocation: .peer(peer),
            updateTextInputState: ChatTextInputState(inputText: NSAttributedString(string: "Здравствуйте! Хочу обновить план, пожалуйста напишите мне, как будете не заняты.")),
            activateInput: .text,
            keepStack: .always
        ))
    })
}

/// The hub's hero row opens this on tap — what used to be a static "what is this mod" blurb is
/// now this account's own subscription info, live-fetched (`fetchTier`) each time the screen
/// opens: Standard's three included sections (Чаты, Ghost, Дополнительно — see
/// `pampGramGateTier` in PampGramBannedScreen.swift for the other two, which Standard doesn't
/// reach at all) versus Premium's everything-unlocked. "Активировать премиум" redeems a
/// one-time key the same way `PampGramStatusScreen.swift`'s "Активировать ключ" always has (a
/// key minted as "pro" — see the admin panel's "Сгенерировать ключ" — grants tier on
/// redemption, no separate mechanism needed here); "Обновить план" messages the mod's own
/// account to ask for one.
public func pampGramSubscriptionController(context: AccountContext) -> ViewController {
    let selfAccountId = context.account.peerId.id._internalGetInt64Value()
    let tierPromise = Promise<PampGramSubscriptionTier>()
    var presentControllerImpl: ((ViewController) -> Void)?
    var presentTooltipImpl: ((String) -> Void)?

    func refreshTier() {
        tierPromise.set(PampGramSubscriptionAPI.fetchTier(userId: selfAccountId))
    }
    refreshTier()

    let arguments = PampGramSubscriptionArguments(
        activatePremium: {
            pampGramPresentRedeemKeyFlow(context: context, presentController: { controller in
                presentControllerImpl?(controller)
            }, presentTooltip: { text in
                presentTooltipImpl?(text)
            }, onActivated: { _ in
                refreshTier()
            })
        },
        upgradePlan: {
            pampGramOpenUpgradeRequestChat(context: context)
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        tierPromise.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, tier -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Подписка"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )

        var entries: [PampGramSubscriptionEntry] = [.hero]
        switch tier {
        case .standard:
            entries.append(.planHeader("ВАШ ПЛАН"))
            entries.append(.planRow("Standard"))
            entries.append(.planFooter("В Standard входят разделы «Чаты», «Ghost» и «Дополнительно». Premium открывает всё остальное — «Подарки» и «Внешний вид» — без ограничений."))
            entries.append(.activateAction("Активировать премиум"))
            entries.append(.upgradeAction("Обновить план"))
        case .pro:
            entries.append(.planHeader("ВАШ ПЛАН"))
            entries.append(.planRow("Premium ⭐"))
            entries.append(.planFooter("Все разделы открыты — «Чаты», «Ghost», «Дополнительно», «Подарки» и «Внешний вид»."))
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
