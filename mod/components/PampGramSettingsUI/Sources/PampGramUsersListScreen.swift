import Foundation
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import AccountContext
import UndoUI
import PampGramCore

private enum PampGramUsersListSection: Int32 {
    case summary
    case list
}

private enum PampGramUsersListEntry: ItemListNodeEntry {
    case summary(String)
    case listHeader(String)
    case userRow(Int32, PampGramUserSummary)
    case emptyText(String)

    var section: ItemListSectionId {
        switch self {
        case .summary:
            return PampGramUsersListSection.summary.rawValue
        case .listHeader, .userRow, .emptyText:
            return PampGramUsersListSection.list.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .summary:
            return 0
        case .listHeader:
            return 1
        case let .userRow(index, _):
            return 2 + index
        case .emptyText:
            return Int32.max
        }
    }

    static func ==(lhs: PampGramUsersListEntry, rhs: PampGramUsersListEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.summary(lhsText), .summary(rhsText)):
            return lhsText == rhsText
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

    static func <(lhs: PampGramUsersListEntry, rhs: PampGramUsersListEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch self {
        case let .summary(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .listHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .userRow(_, user):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: "ID \(user.id)",
                label: user.tier == .pro ? "PRO" : "STANDARD",
                additionalDetailLabel: pampGramFormatLastSeen(user.lastSeen),
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .none,
                action: nil
            )
        case let .emptyText(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private let pampGramLastSeenFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "dd.MM.yy HH:mm"
    return formatter
}()

private func pampGramFormatLastSeen(_ lastSeen: Int64) -> String {
    guard lastSeen > 0 else {
        return "—"
    }
    return pampGramLastSeenFormatter.string(from: Date(timeIntervalSince1970: Double(lastSeen) / 1000.0))
}

private func pampGramUsersListEntries(users: [PampGramUserSummary]) -> [PampGramUsersListEntry] {
    let proCount = users.filter { $0.tier == .pro }.count
    var entries: [PampGramUsersListEntry] = [
        .summary("Всего аккаунтов: \(users.count) · PRO: \(proCount) · STANDARD: \(users.count - proCount)")
    ]
    entries.append(.listHeader("АККАУНТЫ"))
    if users.isEmpty {
        entries.append(.emptyText("Пока никто не открывал PampGram."))
    } else {
        for (index, user) in users.enumerated() {
            entries.append(.userRow(Int32(index), user))
        }
    }
    return entries
}

/// The admin panel's "Пользователи" screen: every account the server has ever heard a
/// `/status` call from (see `server/pampgram-subs-worker/src/index.js`'s `seen:<id>` key),
/// each with its current tier and when it was last seen, newest first. Read-only — this
/// answers "how many people actually use this and what are they on", it doesn't act on any of
/// them; granting/banning stays on the admin screen's own rows and the "Разбанить" list.
public func pampGramUsersListController(context: AccountContext) -> ViewController {
    var presentTooltipImpl: ((String) -> Void)?
    let usersPromise = Promise<[PampGramUserSummary]>([])

    let reload: () -> Void = {
        let _ = (context.account.postbox.transaction { transaction -> String? in
            return PampGramSubscriptionAPI.adminToken(transaction: transaction)
        }
        |> deliverOnMainQueue).start(next: { adminToken in
            guard let adminToken else {
                presentTooltipImpl?("Сначала задай админ-токен в разделе выше.")
                return
            }
            PampGramSubscriptionAPI.fetchUsersList(adminToken: adminToken) { users in
                usersPromise.set(.single(users))
            }
        })
    }

    let signal = combineLatest(
        context.sharedContext.presentationData,
        usersPromise.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, users -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Пользователи"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: pampGramUsersListEntries(users: users),
            style: .blocks,
            animateChanges: true
        )
        return (controllerState, (listState, ()))
    }

    let controller = ItemListController(context: context, state: signal)
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

