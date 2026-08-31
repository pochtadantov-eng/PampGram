import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import UndoUI
import PampGramCore

private final class PampGramChatLockPeersArguments {
    let addChat: () -> Void
    let removePeer: (PeerId) -> Void

    init(addChat: @escaping () -> Void, removePeer: @escaping (PeerId) -> Void) {
        self.addChat = addChat
        self.removePeer = removePeer
    }
}

private enum PampGramChatLockPeersSection: Int32 {
    case about
    case add
    case peers
}

private enum PampGramChatLockPeersEntry: ItemListNodeEntry {
    case aboutText(String)
    case addChat(String)
    case peersHeader(String)
    case peer(PeerId, String)
    case peersEmpty(String)

    var section: ItemListSectionId {
        switch self {
        case .aboutText:
            return PampGramChatLockPeersSection.about.rawValue
        case .addChat:
            return PampGramChatLockPeersSection.add.rawValue
        case .peersHeader, .peer, .peersEmpty:
            return PampGramChatLockPeersSection.peers.rawValue
        }
    }

    var stableId: Int64 {
        switch self {
        case .aboutText:
            return 0
        case .addChat:
            return 1
        case .peersHeader:
            return 2
        case .peersEmpty:
            return 3
        case let .peer(peerId, _):
            return 100 + peerId.toInt64()
        }
    }

    static func ==(lhs: PampGramChatLockPeersEntry, rhs: PampGramChatLockPeersEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.aboutText(lhsText), .aboutText(rhsText)):
            return lhsText == rhsText
        case let (.addChat(lhsText), .addChat(rhsText)):
            return lhsText == rhsText
        case let (.peersHeader(lhsText), .peersHeader(rhsText)):
            return lhsText == rhsText
        case let (.peersEmpty(lhsText), .peersEmpty(rhsText)):
            return lhsText == rhsText
        case let (.peer(lhsPeerId, lhsTitle), .peer(rhsPeerId, rhsTitle)):
            return lhsPeerId == rhsPeerId && lhsTitle == rhsTitle
        default:
            return false
        }
    }

    static func <(lhs: PampGramChatLockPeersEntry, rhs: PampGramChatLockPeersEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramChatLockPeersArguments
        switch self {
        case let .aboutText(text), let .peersEmpty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .peersHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .addChat(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.addChat()
            })
        case let .peer(peerId, title):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: "",
                additionalDetailLabel: "Убрать",
                additionalDetailLabelColor: .destructive,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .none,
                action: {
                    arguments.removePeer(peerId)
                }
            )
        }
    }
}

private func pampGramChatLockPeersEntries(lockedPeerIds: [PeerId], peers: [PeerId: EnginePeer?]) -> [PampGramChatLockPeersEntry] {
    var entries: [PampGramChatLockPeersEntry] = []

    entries.append(.aboutText("Открытие этих чатов будет требовать PIN-код, заданный на предыдущем экране."))
    entries.append(.addChat("Добавить чат"))

    entries.append(.peersHeader("ЗАЩИЩЁННЫЕ ЧАТЫ"))
    if lockedPeerIds.isEmpty {
        entries.append(.peersEmpty("Пока нет защищённых чатов."))
    } else {
        for peerId in lockedPeerIds {
            let title = (peers[peerId] ?? nil)?.compactDisplayTitle ?? "Неизвестный чат"
            entries.append(.peer(peerId, title))
        }
    }

    return entries
}

/// Reached from "Блокировка чатов" → "Защищённые чаты" — picks which specific chats require
/// the PampGram PIN before opening, checked in `navigateToChatControllerImpl`.
public func pampGramChatLockPeersController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    var presentTooltipImpl: ((String) -> Void)?

    let arguments = PampGramChatLockPeersArguments(
        addChat: {
            let _ = (context.account.postbox.transaction { transaction -> Set<PeerId> in
                return Set(PampGramCore.settings(transaction: transaction).lockedChatPeerIds)
            }
            |> deliverOnMainQueue).start(next: { locked in
                let selectionController = context.sharedContext.makeContactMultiselectionController(ContactMultiselectionControllerParams(
                    context: context,
                    mode: .chatSelection(ContactMultiselectionControllerMode.ChatSelection(
                        title: "Защитить чаты",
                        searchPlaceholder: "Поиск",
                        selectedChats: locked,
                        additionalCategories: nil,
                        chatListFilters: nil
                    )),
                    filters: [.excludeSelf]
                ))
                selectionController.navigationPresentation = .modal

                let _ = (selectionController.result
                |> take(1)
                |> deliverOnMainQueue).start(next: { [weak selectionController] result in
                    var peerIds: [PeerId] = []
                    if case let .result(peerIdsValue, _) = result {
                        peerIds = peerIdsValue.compactMap { item -> PeerId? in
                            switch item {
                            case let .peer(id):
                                return id
                            case .deviceContact:
                                return nil
                            }
                        }
                    }
                    selectionController?.dismiss()
                    if !peerIds.isEmpty {
                        let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                            var settings = settings
                            var current = settings.lockedChatPeerIds
                            for peerId in peerIds where !current.contains(peerId) {
                                current.append(peerId)
                            }
                            settings.lockedChatPeerIds = current
                            return settings
                        }).start()
                    }
                })

                presentControllerImpl?(selectionController)
            })
        },
        removePeer: { peerId in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.lockedChatPeerIds.removeAll(where: { $0 == peerId })
                return settings
            }).start()
            presentTooltipImpl?("Чат больше не защищён.")
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        PampGramCore.settingsSignal(postbox: context.account.postbox)
    )
    |> mapToSignal { presentationData, settings -> Signal<(PresentationData, PampGramSettings, [PeerId: EnginePeer?]), NoError> in
        return context.engine.data.subscribe(
            EngineDataMap(settings.lockedChatPeerIds.map(TelegramEngine.EngineData.Item.Peer.Peer.init))
        )
        |> map { peers -> (PresentationData, PampGramSettings, [PeerId: EnginePeer?]) in
            return (presentationData, settings, peers)
        }
    }
    |> deliverOnMainQueue
    |> map { presentationData, settings, peers -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Защищённые чаты"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: pampGramChatLockPeersEntries(lockedPeerIds: settings.lockedChatPeerIds, peers: peers),
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
    return controller
}
