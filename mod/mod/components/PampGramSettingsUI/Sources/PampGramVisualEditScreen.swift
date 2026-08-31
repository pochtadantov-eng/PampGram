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
import PampGramCore

private enum PampGramVisualEditEntry: ItemListNodeEntry {
    case aboutText(String)
    case textInput(String)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case .aboutText:
            return 0
        case .textInput:
            return 1
        }
    }

    static func ==(lhs: PampGramVisualEditEntry, rhs: PampGramVisualEditEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.aboutText(lhsText), .aboutText(rhsText)):
            return lhsText == rhsText
        case let (.textInput(lhsText), .textInput(rhsText)):
            return lhsText == rhsText
        default:
            return false
        }
    }

    static func <(lhs: PampGramVisualEditEntry, rhs: PampGramVisualEditEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! (String) -> Void
        switch self {
        case let .aboutText(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .textInput(text):
            return ItemListMultilineInputItem(presentationData: presentationData, systemStyle: .glass, text: text, placeholder: "Текст сообщения", maxLength: nil, sectionId: self.section, style: .blocks, capitalization: true, autocorrection: true, textUpdated: { text in
                arguments(text)
            })
        }
    }
}

/// Reached from a message's long-press menu ("PampGram" → "Изменить визуально") when the
/// "Изменить визуально" toggle is on. Rewrites the message's text as stored in this device's
/// own Postbox via `Transaction.updateMessage` — nothing is sent, the sender's own copy is
/// untouched.
public func pampGramVisualEditController(context: AccountContext, messageId: MessageId, currentText: String) -> ViewController {
    let textValue = Atomic<String>(value: currentText)
    let textPromise = ValuePromise<String>(currentText, ignoreRepeated: false)
    var dismissImpl: (() -> Void)?

    let applyEdit: () -> Void = {
        let newText = textValue.with { $0 }
        let _ = context.account.postbox.transaction { transaction -> Void in
            transaction.updateMessage(messageId, update: { message -> PostboxUpdateMessage in
                let updatedMessage = StoreMessage(
                    id: messageId,
                    customStableId: nil,
                    globallyUniqueId: message.globallyUniqueId,
                    groupingKey: message.groupingKey,
                    threadId: message.threadId,
                    timestamp: message.timestamp,
                    flags: StoreMessageFlags(message.flags),
                    tags: message.tags,
                    globalTags: message.globalTags,
                    localTags: message.localTags,
                    forwardInfo: message.forwardInfo.map(StoreMessageForwardInfo.init),
                    authorId: message.author?.id,
                    text: newText,
                    attributes: message.attributes.filter { !($0 is TextEntitiesMessageAttribute) },
                    media: message.media
                )
                return .update(updatedMessage)
            })
        }.start()
        dismissImpl?()
    }

    let signal = combineLatest(
        context.sharedContext.presentationData,
        textPromise.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, text -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Изменить визуально"),
            leftNavigationButton: ItemListNavigationButton(content: .text(presentationData.strings.Common_Cancel), style: .regular, enabled: true, action: {
                dismissImpl?()
            }),
            rightNavigationButton: ItemListNavigationButton(content: .text(presentationData.strings.Common_Done), style: .bold, enabled: !text.isEmpty, action: {
                applyEdit()
            }),
            backNavigationButton: nil,
            animateChanges: false
        )
        let entries: [PampGramVisualEditEntry] = [
            .aboutText("Меняет текст только на этом устройстве — собеседник и сервер ничего не получают."),
            .textInput(text)
        ]
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks,
            animateChanges: false
        )
        let updateText: (String) -> Void = { text in
            let _ = textValue.swap(text)
            textPromise.set(text)
        }
        return (controllerState, (listState, updateText))
    }

    let controller = ItemListController(context: context, state: signal)
    dismissImpl = { [weak controller] in
        if let navigationController = controller?.navigationController as? NavigationController {
            let _ = navigationController.popViewController(animated: true)
        } else {
            controller?.dismiss()
        }
    }
    return controller
}
