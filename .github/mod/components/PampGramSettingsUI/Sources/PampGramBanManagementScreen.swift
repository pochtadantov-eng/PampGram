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
import UndoUI
import PampGramCore

private final class PampGramBanManagementArguments {
    let searchUser: () -> Void
    let openUser: (PampGramBannedUser) -> Void

    init(searchUser: @escaping () -> Void, openUser: @escaping (PampGramBannedUser) -> Void) {
        self.searchUser = searchUser
        self.openUser = openUser
    }
}

private enum PampGramBanManagementSection: Int32 {
    case search
    case list
}

private enum PampGramBanManagementEntry: ItemListNodeEntry {
    case searchAction(String)
    case listHeader(String)
    case userRow(Int32, PampGramBannedUser)
    case emptyText(String)

    var section: ItemListSectionId {
        switch self {
        case .searchAction:
            return PampGramBanManagementSection.search.rawValue
        case .listHeader, .userRow, .emptyText:
            return PampGramBanManagementSection.list.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .searchAction:
            return 0
        case .listHeader:
            return 1
        case let .userRow(index, _):
            return 2 + index
        case .emptyText:
            return Int32.max
        }
    }

    static func ==(lhs: PampGramBanManagementEntry, rhs: PampGramBanManagementEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.searchAction(lhsTitle), .searchAction(rhsTitle)):
            return lhsTitle == rhsTitle
        case let (.listHeader(lhsText), .listHeader(rhsText)):
            return lhsText == rhsText
        case let (.userRow(lhsIndex, lhsUser), .userRow(rhsIndex, rhsUser)):
            return lhsIndex == rhsIndex && lhsUser == rhsUser
        case let (.emptyText(lhsText), .emptyText(rhsText)):
            return lhsText == rhsText
        default:
            return false
        }
    }

    static func <(lhs: PampGramBanManagementEntry, rhs: PampGramBanManagementEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramBanManagementArguments
        switch self {
        case let .searchAction(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.searchUser()
            })
        case let .listHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .userRow(_, user):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "ID \(user.id)", label: pampGramBanSummary(user), sectionId: self.section, style: .blocks, action: {
                arguments.openUser(user)
            })
        case let .emptyText(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

/// A one-line read-out of everything a user is currently banned from, for the list row and the
/// detail sheet's header alike — e.g. "Полностью: Мошенничество" or "Подарки: спам; Ghost: ...".
private func pampGramBanSummary(_ user: PampGramBannedUser) -> String {
    var parts: [String] = []
    if let full = user.full {
        parts.append("Полностью: \(full)")
    }
    for section in PampGramBanSection.allCases {
        if let reason = user.sections[section.rawValue] {
            parts.append("\(section.displayName): \(reason)")
        }
    }
    return parts.isEmpty ? "Не забанен" : parts.joined(separator: "; ")
}

private func pampGramBanManagementEntries(users: [PampGramBannedUser]) -> [PampGramBanManagementEntry] {
    var entries: [PampGramBanManagementEntry] = [
        .searchAction("Найти пользователя")
    ]
    entries.append(.listHeader("ЗАБАНЕННЫЕ"))
    if users.isEmpty {
        entries.append(.emptyText("Сейчас никто не забанен."))
    } else {
        for (index, user) in users.enumerated() {
            entries.append(.userRow(Int32(index), user))
        }
    }
    return entries
}

/// The admin panel's "Разбанить" screen: every currently-banned account (from `/banned-list`),
/// plus a search action for looking up any account by username or ID — including ones that
/// aren't banned, so the admin can confirm that too. Both paths end at the same detail sheet,
/// which lists exactly the unban actions that apply to that account and nothing else.
public func pampGramBannedUsersController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    var presentTooltipImpl: ((String) -> Void)?
    let usersPromise = Promise<[PampGramBannedUser]>([])

    let requireAdminToken: (@escaping (String) -> Void) -> Void = { onToken in
        let _ = (context.account.postbox.transaction { transaction -> String? in
            return PampGramSubscriptionAPI.adminToken(transaction: transaction)
        }
        |> deliverOnMainQueue).start(next: { adminToken in
            guard let adminToken else {
                presentTooltipImpl?("Сначала задай админ-токен в разделе выше.")
                return
            }
            onToken(adminToken)
        })
    }

    let reload: () -> Void = {
        requireAdminToken { adminToken in
            PampGramSubscriptionAPI.fetchBannedList(adminToken: adminToken) { users in
                usersPromise.set(.single(users))
            }
        }
    }

    let showUserDetail: (PampGramBannedUser) -> Void = { user in
        requireAdminToken { adminToken in
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            guard let userId = Int64(user.id) else {
                return
            }

            let detailSheet = ActionSheetController(presentationData: presentationData)
            var buttons: [ActionSheetItem] = [ActionSheetTextItem(title: "ID \(user.id)\n\(pampGramBanSummary(user))")]

            if user.full != nil {
                buttons.append(ActionSheetButtonItem(title: "Снять полный бан", color: .accent, action: { [weak detailSheet] in
                    detailSheet?.dismissAnimated()
                    PampGramSubscriptionAPI.unbanUser(userId: userId, scope: .full, adminToken: adminToken) { ok in
                        presentTooltipImpl?(ok ? "Полный бан снят." : "Не получилось.")
                        reload()
                    }
                }))
            }
            for section in PampGramBanSection.allCases {
                if user.sections[section.rawValue] != nil {
                    buttons.append(ActionSheetButtonItem(title: "Снять бан раздела «\(section.displayName)»", color: .accent, action: { [weak detailSheet] in
                        detailSheet?.dismissAnimated()
                        PampGramSubscriptionAPI.unbanUser(userId: userId, scope: .section(section), adminToken: adminToken) { ok in
                            presentTooltipImpl?(ok ? "Бан раздела снят." : "Не получилось.")
                            reload()
                        }
                    }))
                }
            }
            if user.full != nil || !user.sections.isEmpty {
                buttons.append(ActionSheetButtonItem(title: "Разбанить полностью", color: .destructive, action: { [weak detailSheet] in
                    detailSheet?.dismissAnimated()
                    PampGramSubscriptionAPI.unbanUser(userId: userId, scope: .all, adminToken: adminToken) { ok in
                        presentTooltipImpl?(ok ? "Пользователь полностью разбанен." : "Не получилось.")
                        reload()
                    }
                }))
            }

            detailSheet.setItemGroups([
                ActionSheetItemGroup(items: buttons),
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak detailSheet] in
                        detailSheet?.dismissAnimated()
                    })
                ])
            ])
            presentControllerImpl?(detailSheet)
        }
    }

    let arguments = PampGramBanManagementArguments(
        searchUser: {
            presentControllerImpl?(promptController(
                context: context,
                text: "Найти пользователя",
                subtitle: "Юзернейм (без @) или числовой ID аккаунта",
                value: "",
                placeholder: "username или id",
                characterLimit: 64,
                apply: { value in
                    guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                        return
                    }
                    if value.hasPrefix("@") {
                        value.removeFirst()
                    }
                    if let userId = Int64(value) {
                        requireAdminToken { adminToken in
                            let _ = (PampGramSubscriptionAPI.fetchBanStatus(userId: userId)
                            |> deliverOnMainQueue).start(next: { status in
                                showUserDetail(PampGramBannedUser(id: "\(userId)", full: status.full, sections: status.sections))
                            })
                        }
                    } else {
                        let _ = (context.engine.peers.resolvePeerByName(name: value, referrer: nil)
                        |> deliverOnMainQueue).start(next: { result in
                            guard case let .result(peer) = result else {
                                return
                            }
                            guard let peer else {
                                presentTooltipImpl?("Пользователь «\(value)» не найден.")
                                return
                            }
                            let userId = peer.id.id._internalGetInt64Value()
                            let _ = (PampGramSubscriptionAPI.fetchBanStatus(userId: userId)
                            |> deliverOnMainQueue).start(next: { status in
                                showUserDetail(PampGramBannedUser(id: "\(userId)", full: status.full, sections: status.sections))
                            })
                        })
                    }
                }
            ))
        },
        openUser: { user in
            showUserDetail(user)
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        usersPromise.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, users -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Разбанить"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: pampGramBanManagementEntries(users: users),
            style: .blocks,
            animateChanges: true
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    presentTooltipImpl = { [weak controller] text in
        guard let controller else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        controller.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), in: .current)
    }

    reload()

    return controller
}
