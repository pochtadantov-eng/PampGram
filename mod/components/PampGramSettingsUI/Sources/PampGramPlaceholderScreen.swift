import Foundation
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

private enum PampGramPlaceholderEntry: ItemListNodeEntry {
    case text(String)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        return 0
    }

    static func <(lhs: PampGramPlaceholderEntry, rhs: PampGramPlaceholderEntry) -> Bool {
        return false
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch self {
        case let .text(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

/// A stand-in for a PampGram section with no shipped functionality yet — keeps the hub's
/// navigation whole instead of leaving a row that leads nowhere.
public func pampGramPlaceholderController(context: AccountContext, title: String) -> ViewController {
    let signal = context.sharedContext.presentationData
    |> deliverOnMainQueue
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(title),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: [PampGramPlaceholderEntry.text("Этот раздел пока пуст — функции появятся здесь в следующих обновлениях PampGram.")],
            style: .blocks,
            animateChanges: true
        )
        return (controllerState, (listState, ()))
    }

    return ItemListController(context: context, state: signal)
}
