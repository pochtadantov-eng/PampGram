import Foundation
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import AccountContext
import PampGramCore

private final class PampGramAdditionalArguments {
    let toggleAdBlock: (Bool) -> Void
    let toggleProfileIds: (Bool) -> Void
    let toggleHideOwnPhone: (Bool) -> Void
    init(toggleAdBlock: @escaping (Bool) -> Void, toggleProfileIds: @escaping (Bool) -> Void, toggleHideOwnPhone: @escaping (Bool) -> Void) {
        self.toggleAdBlock = toggleAdBlock
        self.toggleProfileIds = toggleProfileIds
        self.toggleHideOwnPhone = toggleHideOwnPhone
    }
}

private enum PampGramAdditionalEntry: ItemListNodeEntry {
    case about(String)
    case contentHeader(String)
    case adBlock(String, Bool)
    case profileHeader(String)
    case showProfileIds(String, Bool)
    case hideOwnPhone(String, Bool)
    case footer(String)

    var section: ItemListSectionId {
        switch self {
        case .about: return 0
        case .contentHeader, .adBlock: return 1
        case .profileHeader, .showProfileIds, .hideOwnPhone, .footer: return 2
        }
    }

    var stableId: Int32 {
        switch self {
        case .about: return 0
        case .contentHeader: return 1
        case .adBlock: return 2
        case .profileHeader: return 3
        case .showProfileIds: return 4
        case .hideOwnPhone: return 5
        case .footer: return 6
        }
    }

    static func < (lhs: PampGramAdditionalEntry, rhs: PampGramAdditionalEntry) -> Bool { lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramAdditionalArguments
        switch self {
        case let .about(text), let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .contentHeader(text), let .profileHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .adBlock(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: arguments.toggleAdBlock)
        case let .showProfileIds(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: arguments.toggleProfileIds)
        case let .hideOwnPhone(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: arguments.toggleHideOwnPhone)
        }
    }
}

public func pampGramAdditionalSettingsController(context: AccountContext) -> ViewController {
    let arguments = PampGramAdditionalArguments(
        toggleAdBlock: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.adBlockEnabled = value
                return settings
            }).start()
        },
        toggleProfileIds: { value in
            let _ = context.account.postbox.transaction { transaction in
                PampGramBehaviorStore.update(transaction: transaction, { state in
                    var state = state; state.showProfileIds = value; return state
                })
            }.start()
        },
        toggleHideOwnPhone: { value in
            let _ = context.account.postbox.transaction { transaction in
                PampGramBehaviorStore.update(transaction: transaction, { state in
                    var state = state; state.hideOwnPhone = value; return state
                })
            }.start()
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        PampGramCore.settingsSignal(postbox: context.account.postbox),
        PampGramBehaviorStore.signal(postbox: context.account.postbox)
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings, behavior -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let entries: [PampGramAdditionalEntry] = [
            .about("Системные и профильные функции, которым не нужен отдельный большой раздел."),
            .contentHeader("КОНТЕНТ"),
            .adBlock("Блокировать рекламу", settings.adBlockEnabled),
            .profileHeader("ПРОФИЛЬ"),
            .showProfileIds("Показывать настоящий ID", behavior.showProfileIds),
            .hideOwnPhone("Скрывать мой номер в профиле", behavior.hideOwnPhone),
            .footer("ID берётся из настоящего Telegram PeerId. Скрытие номера меняет только отображение собственного профиля в PampGram и не меняет серверные настройки приватности.")
        ]
        return (
            ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Дополнительно"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false),
            (ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true), arguments)
        )
    }
    return ItemListController(context: context, state: signal)
}
