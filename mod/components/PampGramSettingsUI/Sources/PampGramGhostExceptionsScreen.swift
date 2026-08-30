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

private final class PampGramGhostExceptionsArguments {
    let addChat: () -> Void
    let removePeer: (PeerId) -> Void

    init(addChat: @escaping () -> Void, removePeer: @escaping (PeerId) -> Void) {
        self.addChat = addChat
        self.removePeer = removePeer
    }
}

private enum PampGramGhostExceptionsSection: Int32 {
    case about
    case add
    case excluded
}

private enum PampGramGhostExceptionsEntry: ItemListNodeEntry {
    case aboutText(String)
    case addChat(String)
    case excludedHeader(String)
    case excludedPeer(PeerId, String)
    case excludedEmpty(String)

    var section: ItemListSectionId {
        switch self {
        case .aboutText:
            return PampGramGhostExceptionsSection.about.rawValue
        case .addChat:
            return PampGramGhostExceptionsSection.add.rawValue
        case .excludedHeader, .excludedPeer, .excludedEmpty:
            return PampGramGhostExceptionsSection.excluded.rawValue
        }
    }

    var stableId: Int64 {
        switch self {
        case .aboutText:
            return 0
        case .addChat:
            return 1
        case .excludedHeader:
            return 2
        case .excludedEmpty:
            return 3
        case let .excludedPeer(peerId, _):
            return 100 + peerId.toInt64()
        }
    }

    static func ==(lhs: PampGramGhostExceptionsEntry, rhs: PampGramGhostExceptionsEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.aboutText(lhsText), .aboutText(rhsText)):
            return lhsText == rhsText
        case let (.addChat(lhsText), .addChat(rhsText)):
            return lhsText == rhsText
        case let (.excludedHeader(lhsText), .excludedHeader(rhsText)):
            return lhsText == rhsText
        case let (.excludedEmpty(lhsText), .excludedEmpty(rhsText)):
            return lhsText == rhsText
        case let (.excludedPeer(lhsPeerId, lhsTitle), .excludedPeer(rhsPeerId, rhsTitle)):
            return lhsPeerId == rhsPeerId && lhsTitle == rhsTitle
        default:
            return false
        }
    }

    static func <(lhs: PampGramGhostExceptionsEntry, rhs: PampGramGhostExceptionsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramGhostExceptionsArguments
        switch self {
        case let .aboutText(text), let .excludedEmpty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .excludedHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .addChat(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.addChat()
            })
        case let .excludedPeer(peerId, title):
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

private func pampGramGhostExceptionsEntries(excludedPeerIds: [PeerId], peers: [PeerId: EnginePeer?]) -> [PampGramGhostExceptionsEntry] {
    var entries: [PampGramGhostExceptionsEntry] = []

    entries.append(.aboutText("Режим призрака не действует в этих чатах — прочтения, истории и «печатает» отправляются как обычно."))
    entries.append(.addChat("Добавить чат"))

    entries.append(.excludedHeader("ИСКЛЮЧЁННЫЕ ЧАТЫ"))
    if excludedPeerIds.isEmpty {
        entries.append(.excludedEmpty("Пока нет исключённых чатов."))
    } else {
        for peerId in excludedPeerIds {
            let title = (peers[peerId] ?? nil)?.compactDisplayTitle ?? "Неизвестный чат"
            entries.append(.excludedPeer(peerId, title))
        }
    }

    return entries
}

/// Reached from "Режим призрака" → "Добавить исключение" — individual chats where Ghost's
/// per-peer suppression is skipped, stored in `PampGramSettings.ghostExcludedPeerIds` and
/// honored by `pampGramGhostShouldSuppress` in TelegramCore.
public func pampGramGhostExceptionsController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    var presentTooltipImpl: ((String) -> Void)?

    let arguments = PampGramGhostExceptionsArguments(
        addChat: {
            let _ = (context.account.postbox.transaction { transaction -> Set<PeerId> in
                return Set(PampGramCore.settings(transaction: transaction).ghostExcludedPeerIds)
            }
            |> deliverOnMainQueue).start(next: { excluded in
                let selectionController = context.sharedContext.makeContactMultiselectionController(ContactMultiselectionControllerParams(
                    context: context,
                    mode: .chatSelection(ContactMultiselectionControllerMode.ChatSelection(
                        title: "Исключить чаты",
                        searchPlaceholder: "Поиск",
                        selectedChats: excluded,
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
                            var current = settings.ghostExcludedPeerIds
                            for peerId in peerIds where !current.contains(peerId) {
                                current.append(peerId)
                            }
                            settings.ghostExcludedPeerIds = current
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
                settings.ghostExcludedPeerIds.removeAll(where: { $0 == peerId })
                return settings
            }).start()
            presentTooltipImpl?("Убрано из исключений.")
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        PampGramCore.settingsSignal(postbox: context.account.postbox)
    )
    |> mapToSignal { presentationData, settings -> Signal<(PresentationData, PampGramSettings, [PeerId: EnginePeer?]), NoError> in
        return context.engine.data.subscribe(
            EngineDataMap(settings.ghostExcludedPeerIds.map(TelegramEngine.EngineData.Item.Peer.Peer.init))
        )
        |> map { peers -> (PresentationData, PampGramSettings, [PeerId: EnginePeer?]) in
            return (presentationData, settings, peers)
        }
    }
    |> deliverOnMainQueue
    |> map { presentationData, settings, peers -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Исключения"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: pampGramGhostExceptionsEntries(excludedPeerIds: settings.ghostExcludedPeerIds, peers: peers),
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
