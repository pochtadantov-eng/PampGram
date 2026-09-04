import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import PromptUI
import PampGramCore

private final class PampGramFakeLocationArguments {
    let toggleEnabled: (Bool) -> Void
    let toggleMovement: (Bool) -> Void
    let selectMode: () -> Void
    let editCoordinate: () -> Void
    let pickOnMap: () -> Void
    let addRoutePoint: () -> Void
    let clearRoute: () -> Void

    init(toggleEnabled: @escaping (Bool) -> Void, toggleMovement: @escaping (Bool) -> Void, selectMode: @escaping () -> Void, editCoordinate: @escaping () -> Void, pickOnMap: @escaping () -> Void, addRoutePoint: @escaping () -> Void, clearRoute: @escaping () -> Void) {
        self.toggleEnabled = toggleEnabled
        self.toggleMovement = toggleMovement
        self.selectMode = selectMode
        self.editCoordinate = editCoordinate
        self.pickOnMap = pickOnMap
        self.addRoutePoint = addRoutePoint
        self.clearRoute = clearRoute
    }
}

private enum PampGramFakeLocationSection: Int32 { case about, location }

private enum PampGramFakeLocationEntry: ItemListNodeEntry {
    case aboutText(String)
    case enabledToggle(String, Bool)
    case movementToggle(String, Bool)
    case modeRow(String, String)
    case coordinateRow(String, String)
    case mapRow(String)
    case routeRow(String, String)
    case clearRoute(String)
    case footer(String)

    var section: ItemListSectionId {
        switch self { case .aboutText: return PampGramFakeLocationSection.about.rawValue; default: return PampGramFakeLocationSection.location.rawValue }
    }
    var stableId: Int32 {
        switch self {
        case .aboutText: return 0; case .enabledToggle: return 1; case .movementToggle: return 2
        case .modeRow: return 3; case .coordinateRow: return 4; case .mapRow: return 5
        case .routeRow: return 6; case .clearRoute: return 7; case .footer: return 8
        }
    }
    static func <(lhs: PampGramFakeLocationEntry, rhs: PampGramFakeLocationEntry) -> Bool { lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramFakeLocationArguments
        switch self {
        case let .aboutText(text), let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .enabledToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: arguments.toggleEnabled)
        case let .movementToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: arguments.toggleMovement)
        case let .modeRow(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, action: arguments.selectMode)
        case let .coordinateRow(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, action: arguments.editCoordinate)
        case let .mapRow(title):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: "", sectionId: self.section, style: .blocks, action: arguments.pickOnMap)
        case let .routeRow(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, action: arguments.addRoutePoint)
        case let .clearRoute(title):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: "", sectionId: self.section, style: .blocks, action: arguments.clearRoute)
        }
    }
}

private func routePointCount(_ route: String) -> Int {
    return route.split(separator: ";").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
}

private func lastRoutePoint(_ route: String) -> (Double, Double)? {
    guard let raw = route.split(separator: ";").last else { return nil }
    let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]) else { return nil }
    return (lat, lon)
}

private func entries(settings: PampGramSettings) -> [PampGramFakeLocationEntry] {
    var result: [PampGramFakeLocationEntry] = []
    result.append(.aboutText("Подменяет координаты одноразовой и live-геопозиции. Для live можно выбрать маршрут и характер движения."))
    result.append(.enabledToggle("Подменять геолокацию", settings.fakeLocationEnabled))
    result.append(.movementToggle("Двигаться по маршруту", settings.fakeLocationWalkingEnabled))
    result.append(.modeRow("Режим движения", settings.fakeLocationMovementMode.displayName))
    result.append(.coordinateRow("Стартовые координаты", String(format: "%.4f, %.4f", settings.fakeLocationLatitude, settings.fakeLocationLongitude)))
    result.append(.mapRow("Выбрать старт на карте"))
    let count = routePointCount(settings.fakeLocationRoute)
    result.append(.routeRow("Добавить точку маршрута", count == 0 ? "автомаршрут" : "добавлено: \(count)"))
    if count > 0 { result.append(.clearRoute("Очистить маршрут")) }
    result.append(.footer("Пешком ≈ 5 км/ч, велосипед ≈ 19 км/ч, автомобиль ≈ 50 км/ч. Симуляция использует плавный разгон, небольшие изменения скорости и лёгкий GPS-дрейф. Точки маршрута выбираются по очереди на карте; после последней точки движение плавно продолжается по замкнутому маршруту."))
    return result
}

private func presentModePicker(context: AccountContext, present: (ViewController) -> Void, current: PampGramFakeMovementMode, apply: @escaping (PampGramFakeMovementMode) -> Void) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let sheet = ActionSheetController(presentationData: presentationData)
    var items: [ActionSheetItem] = [ActionSheetTextItem(title: "Режим движения")]
    for mode in PampGramFakeMovementMode.allCases {
        items.append(ActionSheetButtonItem(title: mode == current ? "✓ \(mode.displayName)" : mode.displayName, color: .accent, action: { [weak sheet] in
            sheet?.dismissAnimated(); apply(mode)
        }))
    }
    sheet.setItemGroups([
        ActionSheetItemGroup(items: items),
        ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in sheet?.dismissAnimated() })])
    ])
    present(sheet)
}

public func pampGramFakeLocationController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?

    let arguments = PampGramFakeLocationArguments(
        toggleEnabled: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { var s = $0; s.fakeLocationEnabled = value; return s }).start()
        },
        toggleMovement: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { var s = $0; s.fakeLocationWalkingEnabled = value; if value { s.fakeLocationEnabled = true }; return s }).start()
        },
        selectMode: {
            let _ = (PampGramCore.settingsSignal(postbox: context.account.postbox) |> take(1) |> deliverOnMainQueue).start(next: { settings in
                presentModePicker(context: context, present: { presentControllerImpl?($0) }, current: settings.fakeLocationMovementMode, apply: { mode in
                    let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { var s = $0; s.fakeLocationMovementMode = mode; s.fakeLocationWalkingEnabled = true; s.fakeLocationEnabled = true; return s }).start()
                })
            })
        },
        editCoordinate: {
            let _ = (PampGramCore.settingsSignal(postbox: context.account.postbox) |> take(1) |> deliverOnMainQueue).start(next: { settings in
                presentControllerImpl?(promptController(context: context, text: "Координаты", subtitle: "Широта и долгота через запятую", value: String(format: "%.6f, %.6f", settings.fakeLocationLatitude, settings.fakeLocationLongitude), placeholder: "55.751244, 37.618423", characterLimit: 64, apply: { value in
                    guard let value = value else { return }
                    let p = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    guard p.count == 2, let lat = Double(p[0]), let lon = Double(p[1]), (-90.0...90.0).contains(lat), (-180.0...180.0).contains(lon) else { return }
                    let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { var s = $0; s.fakeLocationLatitude = lat; s.fakeLocationLongitude = lon; s.fakeLocationEnabled = true; return s }).start()
                }))
            })
        },
        pickOnMap: {
            let _ = (PampGramCore.settingsSignal(postbox: context.account.postbox) |> take(1) |> deliverOnMainQueue).start(next: { settings in
                let lat = settings.fakeLocationEnabled ? settings.fakeLocationLatitude : 55.751244
                let lon = settings.fakeLocationEnabled ? settings.fakeLocationLongitude : 37.618423
                pushControllerImpl?(pampGramMapPickerController(context: context, initialLatitude: lat, initialLongitude: lon, apply: { lat, lon in
                    let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { var s = $0; s.fakeLocationLatitude = lat; s.fakeLocationLongitude = lon; s.fakeLocationEnabled = true; return s }).start()
                }))
            })
        },
        addRoutePoint: {
            let _ = (PampGramCore.settingsSignal(postbox: context.account.postbox) |> take(1) |> deliverOnMainQueue).start(next: { settings in
                let last = lastRoutePoint(settings.fakeLocationRoute)
                pushControllerImpl?(pampGramMapPickerController(context: context, initialLatitude: last?.0 ?? settings.fakeLocationLatitude, initialLongitude: last?.1 ?? settings.fakeLocationLongitude, apply: { lat, lon in
                    let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                        var s = settings
                        let point = String(format: "%.7f,%.7f", lat, lon)
                        s.fakeLocationRoute = s.fakeLocationRoute.isEmpty ? point : s.fakeLocationRoute + ";" + point
                        s.fakeLocationWalkingEnabled = true; s.fakeLocationEnabled = true
                        return s
                    }).start()
                }))
            })
        },
        clearRoute: {
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { var s = $0; s.fakeLocationRoute = ""; return s }).start()
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, PampGramCore.settingsSignal(postbox: context.account.postbox))
    |> deliverOnMainQueue
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let state = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Фейковая геолокация"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false)
        return (state, (ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries(settings: settings), style: .blocks, animateChanges: true), arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in controller?.present(c, in: .window(.root)) }
    pushControllerImpl = { [weak controller] c in (controller?.navigationController as? NavigationController)?.pushViewController(c) }
    return controller
}
