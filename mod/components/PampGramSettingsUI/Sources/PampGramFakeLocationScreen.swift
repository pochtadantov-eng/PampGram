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
    let editCoordinate: () -> Void
    let pickOnMap: () -> Void

    init(toggleEnabled: @escaping (Bool) -> Void, editCoordinate: @escaping () -> Void, pickOnMap: @escaping () -> Void) {
        self.toggleEnabled = toggleEnabled
        self.editCoordinate = editCoordinate
        self.pickOnMap = pickOnMap
    }
}

private enum PampGramFakeLocationSection: Int32 {
    case about
    case location
}

private enum PampGramFakeLocationEntry: ItemListNodeEntry {
    case aboutText(String)

    case enabledToggle(String, Bool)
    case coordinateRow(String, String)
    case mapRow(String)
    case footer(String)

    var section: ItemListSectionId {
        switch self {
        case .aboutText:
            return PampGramFakeLocationSection.about.rawValue
        case .enabledToggle, .coordinateRow, .mapRow, .footer:
            return PampGramFakeLocationSection.location.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .aboutText:
            return 0
        case .enabledToggle:
            return 1
        case .coordinateRow:
            return 2
        case .mapRow:
            return 3
        case .footer:
            return 4
        }
    }

    static func <(lhs: PampGramFakeLocationEntry, rhs: PampGramFakeLocationEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramFakeLocationArguments
        switch self {
        case let .aboutText(text), let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .enabledToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleEnabled(value)
            })
        case let .coordinateRow(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.editCoordinate()
            })
        case let .mapRow(title):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.pickOnMap()
            })
        }
    }
}

private func pampGramFakeLocationEntries(settings: PampGramSettings) -> [PampGramFakeLocationEntry] {
    var entries: [PampGramFakeLocationEntry] = []

    entries.append(.aboutText("Подменяет вашу геопозицию при отправке в чат — только на этом устройстве. Работает и для одноразовой точки, и для трансляции геопозиции в реальном времени."))

    entries.append(.enabledToggle("Подменять геолокацию", settings.fakeLocationEnabled))
    entries.append(.coordinateRow("Координаты", String(format: "%.4f, %.4f", settings.fakeLocationLatitude, settings.fakeLocationLongitude)))
    entries.append(.mapRow("Выбрать на карте"))
    entries.append(.footer("Одноразовая точка и «Трансляция геопозиции» (live) будут показывать выбранную точку вместо настоящей. Координаты можно ввести вручную или выбрать на карте."))

    return entries
}

/// "Фейковая геолокация" (Дополнительно): substitutes a locally-set coordinate for the real
/// GPS one at the moment a one-time location pin is sent — see the patch to
/// `LocationPickerController.swift`.
public func pampGramFakeLocationController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?

    let arguments = PampGramFakeLocationArguments(
        toggleEnabled: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.fakeLocationEnabled = value
                return settings
            }).start()
        },
        editCoordinate: {
            let _ = (PampGramCore.settingsSignal(postbox: context.account.postbox) |> take(1) |> deliverOnMainQueue).start(next: { settings in
                let currentValue = String(format: "%.6f, %.6f", settings.fakeLocationLatitude, settings.fakeLocationLongitude)
                presentControllerImpl?(promptController(
                    context: context,
                    text: "Координаты",
                    subtitle: "Широта и долгота через запятую, например: 55.751244, 37.618423",
                    value: currentValue,
                    placeholder: "55.751244, 37.618423",
                    characterLimit: 64,
                    apply: { value in
                        guard let value = value else {
                            return
                        }
                        let parts = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                        guard parts.count == 2, let latitude = Double(parts[0]), let longitude = Double(parts[1]), latitude >= -90, latitude <= 90, longitude >= -180, longitude <= 180 else {
                            return
                        }
                        let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                            var settings = settings
                            settings.fakeLocationLatitude = latitude
                            settings.fakeLocationLongitude = longitude
                            return settings
                        }).start()
                    }
                ))
            })
        },
        pickOnMap: {
            let _ = (PampGramCore.settingsSignal(postbox: context.account.postbox) |> take(1) |> deliverOnMainQueue).start(next: { settings in
                let initialLatitude = settings.fakeLocationEnabled ? settings.fakeLocationLatitude : 55.751244
                let initialLongitude = settings.fakeLocationEnabled ? settings.fakeLocationLongitude : 37.618423
                pushControllerImpl?(pampGramMapPickerController(context: context, initialLatitude: initialLatitude, initialLongitude: initialLongitude, apply: { latitude, longitude in
                    let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                        var settings = settings
                        settings.fakeLocationLatitude = latitude
                        settings.fakeLocationLongitude = longitude
                        settings.fakeLocationEnabled = true
                        return settings
                    }).start()
                }))
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
            title: .text("Фейковая геолокация"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: pampGramFakeLocationEntries(settings: settings),
            style: .blocks,
            animateChanges: true
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    return controller
}
