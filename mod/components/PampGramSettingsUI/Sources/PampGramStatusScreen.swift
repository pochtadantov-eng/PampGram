import Foundation
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import PampGramCore

private enum PampGramStatusEntry: ItemListNodeEntry {
    case header(String)
    case row(Int32, String, Bool)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case .header:
            return 0
        case let .row(index, _, _):
            return index + 1
        }
    }

    static func <(lhs: PampGramStatusEntry, rhs: PampGramStatusEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch self {
        case let .header(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .row(_, title, isOn):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: "",
                additionalDetailLabel: isOn ? "Включено" : "Выключено",
                additionalDetailLabelColor: isOn ? .constructive : .destructive,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .none,
                action: nil
            )
        }
    }
}

/// A live read-out of every PampGram toggle at once — reached from the hub's "Статус" row, so
/// there's a single place to check what's on without opening every section.
public func pampGramStatusController(context: AccountContext) -> ViewController {
    let signal = combineLatest(
        context.sharedContext.presentationData,
        PampGramCore.settingsSignal(postbox: context.account.postbox)
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Статус"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        var entries: [PampGramStatusEntry] = []
        entries.append(.header("ФУНКЦИИ"))
        entries.append(.row(0, "Вкладка «Подарок»", settings.phantomGiftsEnabled))
        entries.append(.row(1, "Локальные звёзды", settings.fakeStarsDisplayEnabled))
        entries.append(.row(2, "Локальные TON/GRAM", settings.fakeTonDisplayEnabled))
        entries.append(.row(3, "Восстановление удалённых сообщений", settings.antiDeleteMessagesEnabled))
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks,
            animateChanges: true
        )
        return (controllerState, (listState, ()))
    }

    return ItemListController(context: context, state: signal)
}
