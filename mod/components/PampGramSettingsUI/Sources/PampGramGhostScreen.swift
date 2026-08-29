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

    entries.append(.aboutText("Меняет то, что видят о вас другие. Включён может быть только один режим ниже."))

    entries.append(.ghostReaderToggle("Нечиталка", settings.ghostReaderEnabled))
    entries.append(.ghostReaderFooter("Скрывает прочтение, «в сети», набор текста и отправку файлов. У вас всё работает как обычно."))

    entries.append(.onlineMaskToggle("Маскировка онлайна", settings.onlineMaskEnabled))
    entries.append(.onlineMaskFooter("Держит статус «в сети», пока даёт iOS. Также включает приватность «Последний визит» → «Все» — иначе статус никто не увидит."))

    return entries
}

/// The "Ghost" section (formerly the unimplemented "Приватность" placeholder): presence and
/// activity concealment — the one part of PampGram that changes what OTHER people see, not
/// just what this device shows its own owner. Still entirely client-side: nothing here reads
/// or stores anyone else's data, it only withholds or overrides this account's own outgoing
/// status signals.
public func pampGramGhostSettingsController(context: AccountContext) -> ViewController {
    var presentTooltipImpl: ((String) -> Void)?

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

            if value {
                // The mask only works end to end if the "Last Seen & Online" privacy rule
                // actually lets people see the status we're now broadcasting — with it
                // restricted (e.g. "Nobody"), Telegram's own privacy engine hides the online
                // status server-side regardless of what we send, and the mask would do
                // nothing visible. Switching it to "Everybody" is what makes the toggle's own
                // promise true, exactly like turning on the mask should.
                let _ = context.engine.privacy.updateSelectiveAccountPrivacySettings(type: .presence, settings: .enableEveryone(disableFor: [:])).start()
                presentTooltipImpl?("Настройка приватности «Последний визит и онлайн» переключена на «Все» — иначе маскировку никто не увидит.")
            }
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

    let controller = ItemListController(context: context, state: signal)
    presentTooltipImpl = { [weak controller] text in
        guard let controller else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        controller.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), in: .current)
    }
    return controller
}
