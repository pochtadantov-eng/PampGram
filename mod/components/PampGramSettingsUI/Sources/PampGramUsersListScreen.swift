import Foundation
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import ItemListUI
import ItemListPeerItem
import PresentationDataUtils
import AccountContext
import PromptUI
import UndoUI
import PampGramCore

private final class PampGramUsersListArguments {
    let context: AccountContext
    let searchUser: () -> Void
    let openUser: (PampGramUserSummary, EnginePeer?) -> Void

    init(context: AccountContext, searchUser: @escaping () -> Void, openUser: @escaping (PampGramUserSummary, EnginePeer?) -> Void) {
        self.context = context
        self.searchUser = searchUser
        self.openUser = openUser
    }
}

private enum PampGramUsersListSection: Int32 {
    case search
    case summary
    case list
}

private enum PampGramUsersListEntry: ItemListNodeEntry {
    case searchAction(String)
    case summary(String)
    case listHeader(String)
    case resolvedUserRow(Int32, PampGramUserSummary, EnginePeer)
    case unresolvedUserRow(Int32, PampGramUserSummary)
    case emptyText(String)

    var section: ItemListSectionId {
        switch self {
        case .searchAction:
            return PampGramUsersListSection.search.rawValue
        case .summary:
            return PampGramUsersListSection.summary.rawValue
        case .listHeader, .resolvedUserRow, .unresolvedUserRow, .emptyText:
            return PampGramUsersListSection.list.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .searchAction:
            return 0
        case .summary:
            return 1
        case .listHeader:
            return 2
        case let .resolvedUserRow(index, _, _):
            return 3 + index
        case let .unresolvedUserRow(index, _):
            return 3 + index
        case .emptyText:
            return Int32.max
        }
    }

    static func ==(lhs: PampGramUsersListEntry, rhs: PampGramUsersListEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.searchAction(lhsText), .searchAction(rhsText)):
            return lhsText == rhsText
        case let (.summary(lhsText), .summary(rhsText)):
            return lhsText == rhsText
        case let (.listHeader(lhsText), .listHeader(rhsText)):
            return lhsText == rhsText
        case let (.resolvedUserRow(lhsIndex, lhsUser, lhsPeer), .resolvedUserRow(rhsIndex, rhsUser, rhsPeer)):
            return lhsIndex == rhsIndex && lhsUser == rhsUser && lhsPeer == rhsPeer
        case let (.unresolvedUserRow(lhsIndex, lhsUser), .unresolvedUserRow(rhsIndex, rhsUser)):
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
        let arguments = arguments as! PampGramUsersListArguments
        switch self {
        case let .searchAction(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.searchUser()
            })
        case let .summary(text), let .emptyText(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .listHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .resolvedUserRow(_, user, peer):
            return ItemListPeerItem(
                presentationData: presentationData,
                systemStyle: .glass,
                dateTimeFormat: presentationData.dateTimeFormat,
                nameDisplayOrder: presentationData.nameDisplayOrder,
                context: arguments.context,
                peer: peer,
                presence: nil,
                text: .text(pampGramRowSubtitle(user), user.activeBans.isEmpty ? .secondary : .accent),
                label: .badge(user.tier == .pro ? "PRO" : "STANDARD"),
                editing: ItemListPeerItemEditing(editable: false, editing: false, revealed: false),
                enabled: true,
                selectable: true,
                sectionId: self.section,
                action: {
                    arguments.openUser(user, peer)
                },
                setPeerIdWithRevealedOptions: { _, _ in
                },
                removePeer: { _ in
                },
                style: .blocks
            )
        case let .unresolvedUserRow(_, user):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: "ID \(user.id)",
                label: user.tier == .pro ? "PRO" : "STANDARD",
                additionalDetailLabel: pampGramRowSubtitle(user),
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .none,
                action: {
                    arguments.openUser(user, nil)
                }
            )
        }
    }
}

private let pampGramUsersListDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "dd.MM.yy HH:mm"
    return formatter
}()

private func pampGramFormatLastSeen(_ lastSeen: Int64) -> String {
    guard lastSeen > 0 else {
        return "—"
    }
    return pampGramUsersListDateFormatter.string(from: Date(timeIntervalSince1970: Double(lastSeen) / 1000.0))
}

/// Deliberately never claims "никогда" for a missing date — a `nil` here can mean "this really
/// never happened" (the bulk list's own honest answer) just as easily as "wasn't fetched" (a
/// search result, which only pulls live tier/ban state, not history) — indistinguishable once
/// it's `nil`, so both read as "unknown" rather than one of them silently lying.
private func pampGramFormatOptionalDate(_ ms: Int64?) -> String {
    guard let ms, ms > 0 else {
        return "дата неизвестна"
    }
    return pampGramUsersListDateFormatter.string(from: Date(timeIntervalSince1970: Double(ms) / 1000.0))
}

private func pampGramBanSummaryShort(_ user: PampGramUserSummary) -> String {
    let bans = user.activeBans
    if bans.isEmpty {
        return "Не забанен"
    }
    if user.full != nil {
        return "Забанен полностью"
    }
    let sectionNames = bans.compactMap { $0.section?.displayName }
    return "Забанен: \(sectionNames.joined(separator: ", "))"
}

/// Ban summary plus last-seen, for the row subtitle — both status lines the row has room for
/// without a third slot.
private func pampGramRowSubtitle(_ user: PampGramUserSummary) -> String {
    return "\(pampGramBanSummaryShort(user)) · был(а) \(pampGramFormatLastSeen(user.lastSeen))"
}

private func pampGramUsersListEntries(users: [PampGramUserSummary], peers: [String: EnginePeer]) -> [PampGramUsersListEntry] {
    let proCount = users.filter { $0.tier == .pro }.count
    let bannedCount = users.filter { !$0.activeBans.isEmpty }.count
    var entries: [PampGramUsersListEntry] = [
        .searchAction("Найти пользователя")
    ]
    entries.append(.summary("Всего аккаунтов: \(users.count) · PRO: \(proCount) · STANDARD: \(users.count - proCount) · Забанено: \(bannedCount)"))
    entries.append(.listHeader("АККАУНТЫ"))
    if users.isEmpty {
        entries.append(.emptyText("Пока никто не открывал PampGram и никто не забанен."))
    } else {
        for (index, user) in users.enumerated() {
            if let peer = peers[user.id] {
                entries.append(.resolvedUserRow(Int32(index), user, peer))
            } else {
                entries.append(.unresolvedUserRow(Int32(index), user))
            }
        }
    }
    return entries
}

/// The admin panel's merged "Пользователи" screen — every account PampGram's server knows
/// about (opened the app, been banned, or both — see `PampGramUserSummary`), with avatar and
/// username where Telegram's own client already has that peer cached locally (a bare account
/// id with no prior contact/shared chat/message has no way to resolve to a profile at all —
/// that's a real limit of Telegram's own API, not something this screen can work around, so
/// those rows fall back to showing just the ID). Tapping a row opens one menu with everything
/// that used to be spread across two separate places: the real profile (when resolvable), ban
/// detail + unban actions (replacing the old standalone "Разбанить" screen), and subscription
/// detail + a quick tier change.
public func pampGramUsersListController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    var presentTooltipImpl: ((String) -> Void)?
    let usersPromise = Promise<[PampGramUserSummary]>([])
    let peersPromise = Promise<[String: EnginePeer]>([:])

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
            PampGramSubscriptionAPI.fetchUsersList(adminToken: adminToken) { users in
                usersPromise.set(.single(users))

                let peerIds = users.compactMap { user -> EnginePeer.Id? in
                    guard let raw = Int64(user.id) else {
                        return nil
                    }
                    return PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(raw))
                }
                let resolved = context.engine.data.get(EngineDataMap(peerIds.map(TelegramEngine.EngineData.Item.Peer.Peer.init(id:))))
                |> map { result -> [String: EnginePeer] in
                    var peers: [String: EnginePeer] = [:]
                    for peerId in peerIds {
                        if let maybePeer = result[peerId], let peer = maybePeer {
                            peers["\(peerId.id._internalGetInt64Value())"] = peer
                        }
                    }
                    return peers
                }
                peersPromise.set(resolved)
            }
        }
    }

    let openProfile: (EnginePeer) -> Void = { peer in
        guard let navigationController = context.sharedContext.mainWindow?.viewController as? NavigationController else {
            return
        }
        if let controller = context.sharedContext.makePeerInfoController(context: context, updatedPresentationData: nil, peer: peer, mode: .generic, avatarInitiallyExpanded: false, fromChat: false, requestsContext: nil) {
            navigationController.pushViewController(controller)
        }
    }

    let showBanDetail: (PampGramUserSummary) -> Void = { user in
        requireAdminToken { adminToken in
            guard let userId = Int64(user.id) else {
                return
            }
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let sheet = ActionSheetController(presentationData: presentationData)
            var buttons: [ActionSheetItem] = []

            if let full = user.full {
                buttons.append(ActionSheetTextItem(title: "Забанен полностью\nПричина: \(full.reason)\n\(pampGramFormatOptionalDate(full.at))"))
                buttons.append(ActionSheetButtonItem(title: "Снять полный бан", color: .accent, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    PampGramSubscriptionAPI.unbanUser(userId: userId, scope: .full, adminToken: adminToken) { ok in
                        presentTooltipImpl?(ok ? "Полный бан снят." : "Не получилось.")
                        reload()
                    }
                }))
            }
            for section in PampGramBanSection.allCases {
                if let entry = user.sections[section.rawValue] {
                    buttons.append(ActionSheetTextItem(title: "Забанен: \(section.displayName)\nПричина: \(entry.reason)\n\(pampGramFormatOptionalDate(entry.at))"))
                    buttons.append(ActionSheetButtonItem(title: "Снять бан «\(section.displayName)»", color: .accent, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                        PampGramSubscriptionAPI.unbanUser(userId: userId, scope: .section(section), adminToken: adminToken) { ok in
                            presentTooltipImpl?(ok ? "Бан раздела снят." : "Не получилось.")
                            reload()
                        }
                    }))
                }
            }

            if buttons.isEmpty {
                buttons.append(ActionSheetTextItem(title: "Не забанен"))
            } else {
                buttons.append(ActionSheetButtonItem(title: "Разбанить полностью", color: .destructive, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    PampGramSubscriptionAPI.unbanUser(userId: userId, scope: .all, adminToken: adminToken) { ok in
                        presentTooltipImpl?(ok ? "Пользователь полностью разбанен." : "Не получилось.")
                        reload()
                    }
                }))
            }

            sheet.setItemGroups([
                ActionSheetItemGroup(items: buttons),
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                    })
                ])
            ])
            presentControllerImpl?(sheet)
        }
    }

    let showTierDetail: (PampGramUserSummary) -> Void = { user in
        requireAdminToken { adminToken in
            guard let userId = Int64(user.id) else {
                return
            }
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let sheet = ActionSheetController(presentationData: presentationData)
            let targetTier: PampGramSubscriptionTier = user.tier == .pro ? .standard : .pro
            let tierDetailTitle = "Тариф: \(user.tier == .pro ? "PRO" : "STANDARD")\nИзменён: \(pampGramFormatOptionalDate(user.tierChangedAt))"
            sheet.setItemGroups([
                ActionSheetItemGroup(items: [
                    ActionSheetTextItem(title: tierDetailTitle),
                    ActionSheetButtonItem(title: user.tier == .pro ? "Понизить до STANDARD" : "Повысить до PRO", color: .accent, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                        PampGramSubscriptionAPI.grantTier(userId: userId, tier: targetTier, durationHours: nil, adminToken: adminToken) { ok in
                            presentTooltipImpl?(ok ? "Тариф изменён." : "Не получилось.")
                            reload()
                        }
                    })
                ]),
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                    })
                ])
            ])
            presentControllerImpl?(sheet)
        }
    }

    let openUser: (PampGramUserSummary, EnginePeer?) -> Void = { user, peer in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let sheet = ActionSheetController(presentationData: presentationData)
        let titleText: String
        if let peer {
            titleText = peer.addressName.map { "@\($0)" } ?? peer.compactDisplayTitle
        } else {
            titleText = "ID \(user.id)"
        }
        var buttons: [ActionSheetItem] = [ActionSheetTextItem(title: titleText)]
        if let peer {
            buttons.append(ActionSheetButtonItem(title: "Открыть профиль", color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                openProfile(peer)
            }))
        }
        buttons.append(ActionSheetButtonItem(title: "Информация о бане", color: .accent, action: { [weak sheet] in
            sheet?.dismissAnimated()
            showBanDetail(user)
        }))
        buttons.append(ActionSheetButtonItem(title: "Информация о подписке", color: .accent, action: { [weak sheet] in
            sheet?.dismissAnimated()
            showTierDetail(user)
        }))
        sheet.setItemGroups([
            ActionSheetItemGroup(items: buttons),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                })
            ])
        ])
        presentControllerImpl?(sheet)
    }

    let lookupAndOpen: (Int64, EnginePeer?) -> Void = { userId, knownPeer in
        let _ = (combineLatest(
            PampGramSubscriptionAPI.fetchTier(userId: userId),
            PampGramSubscriptionAPI.fetchBanStatus(userId: userId)
        )
        |> deliverOnMainQueue).start(next: { tier, banStatus in
            let summary = PampGramUserSummary(
                id: "\(userId)",
                tier: tier,
                tierChangedAt: nil,
                lastSeen: 0,
                full: banStatus.full.map { PampGramBanEntry(reason: $0, at: nil) },
                sections: banStatus.sections.mapValues { PampGramBanEntry(reason: $0, at: nil) }
            )
            if let knownPeer {
                openUser(summary, knownPeer)
            } else {
                let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(userId))
                let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
                |> deliverOnMainQueue).start(next: { resolvedPeer in
                    openUser(summary, resolvedPeer)
                })
            }
        })
    }

    let arguments = PampGramUsersListArguments(
        context: context,
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
                        lookupAndOpen(userId, nil)
                    } else {
                        let _ = (context.engine.peers.resolvePeerByName(name: value, referrer: nil)
                        |> deliverOnMainQueue).start(next: { result in
                            guard case let .result(peer) = result, let peer else {
                                presentTooltipImpl?("Пользователь «\(value)» не найден.")
                                return
                            }
                            lookupAndOpen(peer.id.id._internalGetInt64Value(), peer)
                        })
                    }
                }
            ))
        },
        openUser: openUser
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        usersPromise.get(),
        peersPromise.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, users, peers -> (ItemListControllerState, (ItemListNodeState, Any)) in
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
            entries: pampGramUsersListEntries(users: users, peers: peers),
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
