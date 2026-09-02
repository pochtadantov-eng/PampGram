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
import PromptUI
import UndoUI
import PampGramCore

private final class PampGramFakeAdminArguments {
    let addChannel: () -> Void
    let openChannel: (PeerId, String) -> Void

    init(addChannel: @escaping () -> Void, openChannel: @escaping (PeerId, String) -> Void) {
        self.addChannel = addChannel
        self.openChannel = openChannel
    }
}

private enum PampGramFakeAdminSection: Int32 {
    case about
    case add
    case channels
}

private enum PampGramFakeAdminEntry: ItemListNodeEntry {
    case aboutText(String)
    case addChannel(String)
    case channelsHeader(String)
    case channel(PeerId, String)
    case channelsEmpty(String)

    var section: ItemListSectionId {
        switch self {
        case .aboutText:
            return PampGramFakeAdminSection.about.rawValue
        case .addChannel:
            return PampGramFakeAdminSection.add.rawValue
        case .channelsHeader, .channel, .channelsEmpty:
            return PampGramFakeAdminSection.channels.rawValue
        }
    }

    var stableId: Int64 {
        switch self {
        case .aboutText:
            return 0
        case .addChannel:
            return 1
        case .channelsHeader:
            return 2
        case .channelsEmpty:
            return 3
        case let .channel(peerId, _):
            return 100 + peerId.toInt64()
        }
    }

    static func ==(lhs: PampGramFakeAdminEntry, rhs: PampGramFakeAdminEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.aboutText(l), .aboutText(r)):
            return l == r
        case let (.addChannel(l), .addChannel(r)):
            return l == r
        case let (.channelsHeader(l), .channelsHeader(r)):
            return l == r
        case let (.channelsEmpty(l), .channelsEmpty(r)):
            return l == r
        case let (.channel(lp, lt), .channel(rp, rt)):
            return lp == rp && lt == rt
        default:
            return false
        }
    }

    static func <(lhs: PampGramFakeAdminEntry, rhs: PampGramFakeAdminEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramFakeAdminArguments
        switch self {
        case let .aboutText(text), let .channelsEmpty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .channelsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .addChannel(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.addChannel()
            })
        case let .channel(peerId, title):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: generatePampGramSectionIcon(systemName: "megaphone.fill", backgroundColor: UIColor(rgb: 0xff3b30)),
                title: title,
                label: "Написать",
                sectionId: self.section,
                style: .blocks,
                action: {
                    arguments.openChannel(peerId, title)
                }
            )
        }
    }
}

private func pampGramFakeAdminEntries(channelIds: [PeerId], peers: [PeerId: EnginePeer?]) -> [PampGramFakeAdminEntry] {
    var entries: [PampGramFakeAdminEntry] = []
    entries.append(.aboutText("Фейк админ полностью локальный: вы визуально пишете пост в выбранный канал, и он виден только на этом устройстве. В сам канал ничего не отправляется, права и подписчики не меняются."))
    entries.append(.addChannel("Добавить канал"))
    entries.append(.channelsHeader("КАНАЛЫ С ФЕЙК-АДМИНОМ"))
    if channelIds.isEmpty {
        entries.append(.channelsEmpty("Пока нет каналов. Добавьте канал, чтобы писать в нём визуальные посты."))
    } else {
        for peerId in channelIds {
            let title = (peers[peerId] ?? nil)?.compactDisplayTitle ?? "Неизвестный канал"
            entries.append(.channel(peerId, title))
        }
    }
    return entries
}

/// "Фейк админ" (Дополнительно): pick a channel and write a purely local "post" into it — the
/// message is inserted only into this device's copy of the chat (via `pampGramInsertTextDirect`,
/// `Namespaces.Message.Local`), so it looks like you posted to the channel while nothing is sent
/// and nobody else sees it. The set of enabled channels is stored in `PampGramFakeAdminStore`.
public func pampGramFakeAdminController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    var presentInWindowImpl: ((ViewController) -> Void)?

    let writePost: (PeerId, String) -> Void = { peerId, title in
        presentControllerImpl?(promptController(
            context: context,
            text: "Пост в «\(title)»",
            subtitle: "Текст появится как пост канала только на этом устройстве.",
            value: "",
            placeholder: "Текст поста",
            characterLimit: 4096,
            apply: { value in
                guard let value else {
                    return
                }
                pampGramInsertTextDirect(context: context, peerId: peerId, text: value, incoming: true)
            }
        ))
    }

    let arguments = PampGramFakeAdminArguments(
        addChannel: {
            let _ = (context.account.postbox.transaction { transaction -> Set<PeerId> in
                return Set(PampGramFakeAdminStore.all(transaction: transaction).filter { $0.enabled }.map { $0.peerId })
            }
            |> deliverOnMainQueue).start(next: { existing in
                let selectionController = context.sharedContext.makeContactMultiselectionController(ContactMultiselectionControllerParams(
                    context: context,
                    mode: .chatSelection(ContactMultiselectionControllerMode.ChatSelection(
                        title: "Выберите канал",
                        searchPlaceholder: "Поиск",
                        selectedChats: existing,
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
                    guard !peerIds.isEmpty else {
                        return
                    }
                    let _ = context.account.postbox.transaction { transaction in
                        for peerId in peerIds {
                            PampGramFakeAdminStore.update(transaction: transaction, peerId: peerId, { state in
                                var state = state
                                state.enabled = true
                                return state
                            })
                        }
                    }.start()
                })

                presentInWindowImpl?(selectionController)
            })
        },
        openChannel: { peerId, title in
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let sheet = ActionSheetController(presentationData: presentationData)
            sheet.setItemGroups([
                ActionSheetItemGroup(items: [
                    ActionSheetTextItem(title: title),
                    ActionSheetButtonItem(title: "Написать пост", color: .accent, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                        writePost(peerId, title)
                    }),
                    ActionSheetButtonItem(title: "Убрать из фейк-админа", color: .destructive, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                        let _ = context.account.postbox.transaction { transaction in
                            PampGramFakeAdminStore.update(transaction: transaction, peerId: peerId, { state in
                                var state = state
                                state.enabled = false
                                return state
                            })
                        }.start()
                    })
                ]),
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                    })
                ])
            ])
            presentInWindowImpl?(sheet)
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        PampGramFakeAdminStore.allSignal(postbox: context.account.postbox)
    )
    |> mapToSignal { presentationData, states -> Signal<(PresentationData, [PeerId], [PeerId: EnginePeer?]), NoError> in
        let channelIds = states.filter { $0.enabled }.map { $0.peerId }
        return context.engine.data.subscribe(
            EngineDataMap(channelIds.map(TelegramEngine.EngineData.Item.Peer.Peer.init))
        )
        |> map { peers -> (PresentationData, [PeerId], [PeerId: EnginePeer?]) in
            return (presentationData, channelIds, peers)
        }
    }
    |> deliverOnMainQueue
    |> map { presentationData, channelIds, peers -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Фейк админ"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: pampGramFakeAdminEntries(channelIds: channelIds, peers: peers),
            style: .blocks,
            animateChanges: true
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    presentInWindowImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}
