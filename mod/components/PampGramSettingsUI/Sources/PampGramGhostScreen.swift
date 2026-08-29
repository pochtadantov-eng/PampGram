import Foundation
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import PampGramCore

private final class PampGramGhostArguments {
    let toggleGhostReader: (Bool) -> Void
    let toggleOnlineMask: (Bool) -> Void

    init(toggleGhostReader: @escaping (Bool) -> Void, toggleOnlineMask: @escaping (Bool) -> Void) {
        self.toggleGhostReader = toggleGhostReader
        self.toggleOnlineMask = toggleOnlineMask
    }
}

private enum PampGramGhostSection: Int32 {
    case about
    case ghostReader
    case onlineMask
}

private enum PampGramGhostEntry: ItemListNodeEntry {
    case aboutText(String)

    case ghostReaderToggle(String, Bool)
    case ghostReaderFooter(String)

    case onlineMaskToggle(String, Bool)
    case onlineMaskFooter(String)

    var section: ItemListSectionId {
        switch self {
        case .aboutText:
            return PampGramGhostSection.about.rawValue
        case .ghostReaderToggle, .ghostReaderFooter:
            return PampGramGhostSection.ghostReader.rawValue
        case .onlineMaskToggle, .onlineMaskFooter:
            return PampGramGhostSection.onlineMask.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .aboutText:
            return 0
        case .ghostReaderToggle:
            return 1
        case .ghostReaderFooter:
            return 2
        case .onlineMaskToggle:
            return 3
        case .onlineMaskFooter:
            return 4
        }
    }

    static func <(lhs: PampGramGhostEntry, rhs: PampGramGhostEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramGhostArguments
        switch self {
        case let .aboutText(text), let .ghostReaderFooter(text), let .onlineMaskFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .ghostReaderToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleGhostReader(value)
            })
        case let .onlineMaskToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleOnlineMask(value)
            })
        }
    }
}

private func pampGramGhostEntries(settings: PampGramSettings) -> [PampGramGhostEntry] {
    var entries: [PampGramGhostEntry] = []

    entries.append(.aboutText("Ghost меняет только то, что остальные видят о вашей активности — списки контактов, содержимое сообщений и сам факт переписки эти функции не трогают. Включён может быть только один из двух режимов ниже: они управляют одним и тем же — статусом «в сети» — в противоположные стороны."))

    entries.append(.ghostReaderToggle("Нечиталка", settings.ghostReaderEnabled))
    entries.append(.ghostReaderFooter("Пока включено, собеседники не видят: что вы прочитали их сообщение (галочки «прочитано» не проставляются), что вы «в сети» или когда вы были последний раз, что вы печатаете, и что вы записываете голосовое/кружок или отправляете файл. Сами вы при этом продолжаете пользоваться приложением как обычно — непрочитанные у вас лично сбрасываются, история читается — просто об этом никто, кроме вас, не узнаёт. Действует на всех пользователей сразу; выбор конкретных людей для исключения появится позже."))

    entries.append(.onlineMaskToggle("Маскировка онлайна", settings.onlineMaskEnabled))
    entries.append(.onlineMaskFooter("Пока включено, все видят вас «в сети» — приложение перестаёт отправлять статус «не в сети» при сворачивании. Честно предупреждаем о технической границе: iOS не даёт приложениям работать в фоне бесконечно — статус держится, пока система реально даёт приложению время (открыто, недавно свёрнуто, входящие уведомления и т. п.), а не буквально 24/7 при полностью закрытом и не трогаемом днями приложении."))

    return entries
}

/// The "Ghost" section (formerly the unimplemented "Приватность" placeholder): presence and
/// activity concealment — the one part of PampGram that changes what OTHER people see, not
/// just what this device shows its own owner. Still entirely client-side: nothing here reads
/// or stores anyone else's data, it only withholds or overrides this account's own outgoing
/// status signals.
public func pampGramGhostSettingsController(context: AccountContext) -> ViewController {
    let arguments = PampGramGhostArguments(
        toggleGhostReader: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.ghostReaderEnabled = value
                if value {
                    settings.onlineMaskEnabled = false
                }
                return settings
            }).start()
        },
        toggleOnlineMask: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.onlineMaskEnabled = value
                if value {
                    settings.ghostReaderEnabled = false
                }
                return settings
            }).start()
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
            title: .text("Ghost"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: pampGramGhostEntries(settings: settings),
            style: .blocks,
            animateChanges: true
        )
        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
