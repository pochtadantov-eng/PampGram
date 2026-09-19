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

private final class PampGramFakePhoneNumberArguments {
    let toggleEnabled: (Bool) -> Void
    let editNumber: () -> Void

    init(toggleEnabled: @escaping (Bool) -> Void, editNumber: @escaping () -> Void) {
        self.toggleEnabled = toggleEnabled
        self.editNumber = editNumber
    }
}

private enum PampGramFakePhoneNumberSection: Int32 {
    case about
    case settings
}

private enum PampGramFakePhoneNumberEntry: ItemListNodeEntry {
    case aboutText(String)

    case enabledToggle(String, Bool)
    case numberRow(String, String)
    case footer(String)

    var section: ItemListSectionId {
        switch self {
        case .aboutText:
            return PampGramFakePhoneNumberSection.about.rawValue
        case .enabledToggle, .numberRow, .footer:
            return PampGramFakePhoneNumberSection.settings.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .aboutText:
            return 0
        case .enabledToggle:
            return 1
        case .numberRow:
            return 2
        case .footer:
            return 3
        }
    }

    static func <(lhs: PampGramFakePhoneNumberEntry, rhs: PampGramFakePhoneNumberEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramFakePhoneNumberArguments
        switch self {
        case let .aboutText(text), let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .enabledToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleEnabled(value)
            })
        case let .numberRow(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.editNumber()
            })
        }
    }
}

private func pampGramFakePhoneNumberEntries(settings: PampGramSettings) -> [PampGramFakePhoneNumberEntry] {
    var entries: [PampGramFakePhoneNumberEntry] = []

    entries.append(.aboutText("Подменяет ваш номер телефона в настройках — только на этом устройстве. Другие пользователи по-прежнему видят номер согласно настройкам приватности Telegram."))

    entries.append(.enabledToggle("Показывать фейковый номер", settings.fakePhoneNumberEnabled))
    let currentNumber = settings.fakePhoneNumberValue.isEmpty ? "Не задан" : settings.fakePhoneNumberValue
    entries.append(.numberRow("Номер", currentNumber))
    entries.append(.footer("Введите номер в международном формате, например +7 999 123 45 67. Он будет показан вместо настоящего в экране «Настройки». Если включена и «Скрыть номер телефона», фейковый номер приоритетнее."))

    return entries
}

public func pampGramFakePhoneNumberController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?

    let arguments = PampGramFakePhoneNumberArguments(
        toggleEnabled: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.fakePhoneNumberEnabled = value
                return settings
            }).start()
        },
        editNumber: {
            let _ = (PampGramCore.settingsSignal(postbox: context.account.postbox) |> take(1) |> deliverOnMainQueue).start(next: { settings in
                presentControllerImpl?(promptController(
                    context: context,
                    text: "Фейковый номер",
                    subtitle: "Введите номер в международном формате",
                    value: settings.fakePhoneNumberValue,
                    placeholder: "+7 999 123 45 67",
                    characterLimit: 32,
                    apply: { value in
                        guard let value = value else {
                            return
                        }
                        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                            var settings = settings
                            settings.fakePhoneNumberValue = trimmed
                            if !trimmed.isEmpty {
                                settings.fakePhoneNumberEnabled = true
                            }
                            return settings
                        }).start()
                    }
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
            title: .text("Фейковый номер"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: pampGramFakePhoneNumberEntries(settings: settings),
            style: .blocks,
            animateChanges: true
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}
