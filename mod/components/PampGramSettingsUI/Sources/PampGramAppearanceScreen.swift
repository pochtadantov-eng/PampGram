import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import AccountContext

private final class PampGramAppearanceArguments {
    let chooseBadge: () -> Void

    init(chooseBadge: @escaping () -> Void) {
        self.chooseBadge = chooseBadge
    }
}

private enum PampGramAppearanceEntry: ItemListNodeEntry {
    case badgeHeader(String)
    case badgeRow(String, String)
    case badgeFooter(String)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case .badgeHeader: return 0
        case .badgeRow: return 1
        case .badgeFooter: return 2
        }
    }

    static func <(lhs: Self, rhs: Self) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let a = arguments as! PampGramAppearanceArguments
        switch self {
        case let .badgeHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .badgeRow(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "bolt.badge.clock.fill", backgroundColor: UIColor(rgb: 0xff9500)), title: title, label: label, sectionId: self.section, style: .blocks, action: a.chooseBadge)
        case let .badgeFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

/// "Внешний вид": one feature — the "Бейджик" overlay near the top of the screen (a small
/// colored pill with "TELEGRAM" or "SWIFTGRAM"), drawn on every screen by
/// `pampGramInstallStatusBadgeOverlay` in `PampGramStatusBadge.swift`, wired in once at launch
/// from AppDelegate.swift. Changing the choice here just flips `PampGramStatusBadgeStore.style`
/// — the overlay, already on screen, picks it up immediately via
/// `pampGramStatusBadgeStyleDidChangeNotification`.
public func pampGramAppearanceController(context: AccountContext) -> ViewController {
    var present: ((ViewController) -> Void)?
    let stylePromise = ValuePromise<PampGramStatusBadgeStyle>(PampGramStatusBadgeStore.style, ignoreRepeated: true)

    let arguments = PampGramAppearanceArguments(
        chooseBadge: {
            let pd = context.sharedContext.currentPresentationData.with { $0 }
            let sheet = ActionSheetController(presentationData: pd)
            let current = PampGramStatusBadgeStore.style
            let buttons = PampGramStatusBadgeStyle.allCases.map { style in
                ActionSheetButtonItem(title: style == current ? "✓ \(style.displayName)" : style.displayName, color: .accent, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    PampGramStatusBadgeStore.style = style
                    stylePromise.set(style)
                })
            }
            sheet.setItemGroups([
                ActionSheetItemGroup(items: buttons),
                ActionSheetItemGroup(items: [ActionSheetButtonItem(title: pd.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in sheet?.dismissAnimated() })])
            ])
            present?(sheet)
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, stylePromise.get())
    |> deliverOnMainQueue
    |> map { pd, style -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let entries: [PampGramAppearanceEntry] = [
            .badgeHeader("БЕЙДЖИК"),
            .badgeRow("Бейджик", style.displayName),
            .badgeFooter("Маленький значок наверху экрана, поверх всех разделов — показывает выбранное название. «Выключено» убирает его совсем.")
        ]
        return (
            ItemListControllerState(presentationData: ItemListPresentationData(pd), title: .text("Внешний вид"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: pd.strings.Common_Back), animateChanges: false),
            (ItemListNodeState(presentationData: ItemListPresentationData(pd), entries: entries, style: .blocks, animateChanges: true), arguments)
        )
    }

    let controller = ItemListController(context: context, state: signal)
    present = { [weak controller] c in controller?.present(c, in: .window(.root)) }
    return controller
}
