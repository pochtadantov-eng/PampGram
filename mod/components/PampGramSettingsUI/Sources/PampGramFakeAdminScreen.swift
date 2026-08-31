import Foundation
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext
import PromptUI
import PampGramCore

private final class PampGramFakeAdminArguments {
    let toggle: (Bool) -> Void
    let editTitle: () -> Void
    let editDescription: () -> Void
    let editLink: () -> Void
    let toggleReactions: (Bool) -> Void
    let addPost: () -> Void
    init(toggle: @escaping (Bool) -> Void, editTitle: @escaping () -> Void, editDescription: @escaping () -> Void, editLink: @escaping () -> Void, toggleReactions: @escaping (Bool) -> Void, addPost: @escaping () -> Void) { self.toggle=toggle; self.editTitle=editTitle; self.editDescription=editDescription; self.editLink=editLink; self.toggleReactions=toggleReactions; self.addPost=addPost }
}

private enum PampGramFakeAdminEntry: ItemListNodeEntry {
    case about(String), enabled(String, Bool), header(String), title(String, String), description(String, String), link(String, String), reactions(String, Bool), addPost(String), footer(String)
    var section: ItemListSectionId { switch self { case .about: return 0; case .enabled: return 1; case .header, .title, .description, .link, .reactions, .addPost, .footer: return 2 } }
    var stableId: Int32 { switch self { case .about: return 0; case .enabled: return 1; case .header: return 2; case .title: return 3; case .description: return 4; case .link: return 5; case .reactions: return 6; case .addPost: return 7; case .footer: return 8 } }
    static func <(lhs: Self, rhs: Self) -> Bool { lhs.stableId < rhs.stableId }
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let a = arguments as! PampGramFakeAdminArguments
        switch self {
        case let .about(t), let .footer(t): return ItemListTextItem(presentationData: presentationData, text: .plain(t), sectionId: self.section)
        case let .enabled(t,v): return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: t, value: v, sectionId: self.section, style: .blocks, updated: a.toggle)
        case let .header(t): return ItemListSectionHeaderItem(presentationData: presentationData, text: t, sectionId: self.section)
        case let .title(t,l): return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: t, label: l, sectionId: self.section, style: .blocks, action: a.editTitle)
        case let .description(t,l): return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: t, label: l, sectionId: self.section, style: .blocks, action: a.editDescription)
        case let .link(t,l): return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: t, label: l, sectionId: self.section, style: .blocks, action: a.editLink)
        case let .reactions(t,v): return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: t, value: v, sectionId: self.section, style: .blocks, updated: a.toggleReactions)
        case let .addPost(t): return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: t, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: a.addPost)
        }
    }
}

public func pampGramFakeAdminController(context: AccountContext, peerId: EnginePeer.Id) -> ViewController {
    var present: ((ViewController) -> Void)?
    func update(_ f: @escaping (PampGramFakeAdminChannelState) -> PampGramFakeAdminChannelState) { let _ = context.account.postbox.transaction { transaction in PampGramFakeAdminStore.update(transaction: transaction, peerId: peerId, f) }.start() }
    func prompt(title: String, value: String, apply: @escaping (inout PampGramFakeAdminChannelState, String) -> Void) { present?(promptController(context: context, text: title, subtitle: "Визуально только в PampGram.", value: value, characterLimit: 256, apply: { v in guard let v else { return }; update { state in var state=state; apply(&state,v); return state } })) }
    let args = PampGramFakeAdminArguments(
        toggle: { v in update { var s=$0; s.enabled=v; return s } },
        editTitle: { let _=(PampGramFakeAdminStore.signal(postbox: context.account.postbox, peerId: peerId)|>take(1)|>deliverOnMainQueue).start(next:{ s in prompt(title:"Название канала", value:s.titleOverride ?? "") { $0.titleOverride=$1.isEmpty ? nil : $1 } }) },
        editDescription: { let _=(PampGramFakeAdminStore.signal(postbox: context.account.postbox, peerId: peerId)|>take(1)|>deliverOnMainQueue).start(next:{ s in prompt(title:"Описание канала", value:s.descriptionOverride ?? "") { $0.descriptionOverride=$1.isEmpty ? nil : $1 } }) },
        editLink: { let _=(PampGramFakeAdminStore.signal(postbox: context.account.postbox, peerId: peerId)|>take(1)|>deliverOnMainQueue).start(next:{ s in prompt(title:"Ссылка", value:s.inviteLinkOverride ?? "") { $0.inviteLinkOverride=$1.isEmpty ? nil : $1 } }) },
        toggleReactions: { v in update { var s=$0; s.reactionsEnabled=v; return s } },
        addPost: { present?(promptController(context: context, text: "Локальный пост", subtitle: "Появится визуально в этом канале и не отправится на сервер Telegram.", value: "", placeholder: "Текст поста", characterLimit: 4096, apply: { v in guard let v else{return}; pampGramInsertFakeAdminPost(context: context, peerId: peerId, text: v) })) }
    )
    let signal = combineLatest(context.sharedContext.presentationData, PampGramFakeAdminStore.signal(postbox: context.account.postbox, peerId: peerId))
    |> deliverOnMainQueue
    |> map { pd, s -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let entries: [PampGramFakeAdminEntry] = [.about("Фейк Администратор создаёт локальный админский слой для выбранного канала. Реальные права и серверные настройки не меняются."), .enabled("Фейк Администратор", s.enabled), .header("ВИЗУАЛЬНЫЕ НАСТРОЙКИ КАНАЛА"), .title("Название", s.titleOverride ?? "Как в Telegram"), .description("Описание", s.descriptionOverride?.isEmpty == false ? "Изменено" : "Как в Telegram"), .link("Ссылка", s.inviteLinkOverride ?? "Как в Telegram"), .reactions("Реакции", s.reactionsEnabled ?? true), .addPost("Написать локальный пост"), .footer("Локально созданные сообщения отмечаются словом «Локально» только при их зажатии. Настоящие сообщения канала не меняются.")]
        return (ItemListControllerState(presentationData: ItemListPresentationData(pd), title: .text("Фейк Администратор"), leftNavigationButton:nil, rightNavigationButton:nil, backNavigationButton:ItemListBackButton(title:pd.strings.Common_Back), animateChanges:false), (ItemListNodeState(presentationData: ItemListPresentationData(pd), entries:entries, style:.blocks, animateChanges:true), args))
    }
    let controller=ItemListController(context:context,state:signal); present={ [weak controller] c in controller?.present(c,in:.window(.root)) }; return controller
}
