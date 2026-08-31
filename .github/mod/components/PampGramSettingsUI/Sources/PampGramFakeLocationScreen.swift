import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import AccountContext
import PampGramCore

private final class PampGramFakeLocationArguments {
    let toggleEnabled: (Bool) -> Void
    let openMap: () -> Void
    init(toggleEnabled: @escaping (Bool) -> Void, openMap: @escaping () -> Void) { self.toggleEnabled = toggleEnabled; self.openMap = openMap }
}

private enum PampGramFakeLocationEntry: ItemListNodeEntry {
    case about(String), enabled(String, Bool), map(String, String), footer(String)
    var section: ItemListSectionId { switch self { case .about: return 0; default: return 1 } }
    var stableId: Int32 { switch self { case .about: return 0; case .enabled: return 1; case .map: return 2; case .footer: return 3 } }
    static func <(lhs: Self, rhs: Self) -> Bool { lhs.stableId < rhs.stableId }
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let a = arguments as! PampGramFakeLocationArguments
        switch self {
        case let .about(text), let .footer(text): return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .enabled(title, value): return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: a.toggleEnabled)
        case let .map(title, label): return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, action: a.openMap)
        }
    }
}

public func pampGramFakeLocationController(context: AccountContext) -> ViewController {
    var openMapImpl: (() -> Void)?
    let args = PampGramFakeLocationArguments(
        toggleEnabled: { value in let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { var s=$0; s.fakeLocationEnabled=value; return s }).start() },
        openMap: { openMapImpl?() }
    )
    let signal = combineLatest(context.sharedContext.presentationData, PampGramCore.settingsSignal(postbox: context.account.postbox))
    |> deliverOnMainQueue
    |> map { pd, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let entries: [PampGramFakeLocationEntry] = [
            .about("Выбери любую точку на карте. При включённой подмене PampGram использует сохранённую точку вместо настоящего GPS для отправки геопозиции."),
            .enabled("Подменять геолокацию", settings.fakeLocationEnabled),
            .map("Выбрать на карте", String(format: "%.4f, %.4f", settings.fakeLocationLatitude, settings.fakeLocationLongitude)),
            .footer("На карте слева сверху «Назад» — без сохранения, справа «Применить» — сохранить точку и вернуться сюда. Эта же сохранённая точка предназначена для live-location обновлений.")
        ]
        return (ItemListControllerState(presentationData: ItemListPresentationData(pd), title: .text("Фейковая геолокация"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: pd.strings.Common_Back), animateChanges: false), (ItemListNodeState(presentationData: ItemListPresentationData(pd), entries: entries, style: .blocks, animateChanges: true), args))
    }
    let controller = ItemListController(context: context, state: signal)
    openMapImpl = { [weak controller] in
        let _ = (PampGramCore.settingsSignal(postbox: context.account.postbox) |> take(1) |> deliverOnMainQueue).start(next: { settings in
            let map = PampGramLocationMapViewController(latitude: settings.fakeLocationLatitude, longitude: settings.fakeLocationLongitude, apply: { coordinate in
                let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { var s=$0; s.fakeLocationLatitude=coordinate.latitude; s.fakeLocationLongitude=coordinate.longitude; return s }).start()
            })
            (controller?.navigationController as? UIViewController ?? controller)?.present(map, animated: true)
        })
    }
    return controller
}
