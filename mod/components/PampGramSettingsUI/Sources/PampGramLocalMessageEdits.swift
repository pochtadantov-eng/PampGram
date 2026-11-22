import Foundation
import Display
import Postbox
import SwiftSignalKit
import TelegramCore
import AccountContext
import UndoUI
import PampGramCore

private enum PampGramLocalEditOutcome {
    case done
    case notFound
    case expired
}

private func pampGramShowEditResult(context: AccountContext, text: String) {
    Queue.mainQueue().async {
        guard let controller = (context.sharedContext.mainWindow?.viewController as? NavigationController)?.topViewController as? ViewController else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        controller.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), in: .current)
    }
}

private func pampGramUpdateLocalMessage(context: AccountContext, messageId: MessageId, label: String, silent: Bool = false, _ transform: @escaping (Message, inout [MessageAttribute], inout StoreMessageForwardInfo?) -> Void) {
    let _ = (context.account.postbox.transaction { transaction -> PampGramLocalEditOutcome in
        guard let message = transaction.getMessage(messageId) else {
            return .notFound
        }
        if message.media.contains(where: { $0 is TelegramMediaExpiredContent }) {
            return .expired
        }
        transaction.updateMessage(messageId, update: { message -> PostboxUpdateMessage in
            var attributes = message.attributes
            var forwardInfo = message.forwardInfo.map(StoreMessageForwardInfo.init)
            transform(message, &attributes, &forwardInfo)
            return .update(StoreMessage(
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
                forwardInfo: forwardInfo,
                authorId: message.author?.id,
                text: message.text,
                attributes: attributes,
                media: message.media
            ))
        })
        return .done
    }
    |> deliverOnMainQueue).start(next: { outcome in
        switch outcome {
        case .done:
            PampGramDiagnostics.shared.log("Правка сообщения", "\(label): сообщение \(messageId.id) обновлено")
            if !silent {
                pampGramShowEditResult(context: context, text: "\(label): готово")
            }
        case .notFound:
            PampGramDiagnostics.shared.log("Правка сообщения", "\(label): сообщение \(messageId.id) не найдено")
            pampGramShowEditResult(context: context, text: "\(label): сообщение не найдено")
        case .expired:
            PampGramDiagnostics.shared.log("Правка сообщения", "\(label): сообщение \(messageId.id) истекшее, содержимого нет")
            pampGramShowEditResult(context: context, text: "Это истекшее сообщение: содержимого нет, изменение не отобразится. Попробуйте на обычном сообщении.")
        }
    })
}

/// "Фейк пересылка": the message is rewritten in this device's Postbox as forwarded from a hidden
/// sender with the given name, which the stock bubble already draws as "Переслано от …".
public func pampGramApplyFakeForward(context: AccountContext, messageId: MessageId, name: String) {
    pampGramUpdateLocalMessage(context: context, messageId: messageId, label: "Фейк пересылка") { message, _, forwardInfo in
        forwardInfo = StoreMessageForwardInfo(authorId: nil, sourceId: nil, sourceMessageId: nil, date: message.timestamp, authorSignature: name, psaType: nil, flags: [])
    }
}

/// "Фейк реакции": sets the count of one reaction under the message, locally.
public func pampGramApplyFakeReaction(context: AccountContext, messageId: MessageId, emoji: String, count: Int32) {
    pampGramUpdateLocalMessage(context: context, messageId: messageId, label: "Фейк реакция") { _, attributes, _ in
        let value = MessageReaction.Reaction.builtin(emoji)
        var reactions: [MessageReaction] = []
        if let existing = attributes.first(where: { $0 is ReactionsMessageAttribute }) as? ReactionsMessageAttribute {
            reactions = existing.reactions.filter { $0.value != value }
        }
        reactions.append(MessageReaction(value: value, count: max(1, count), chosenOrder: nil))
        attributes.removeAll(where: { $0 is ReactionsMessageAttribute })
        attributes.append(ReactionsMessageAttribute(canViewList: false, isTags: false, reactions: reactions, recentPeers: [], topPeers: []))
    }
}

/// "Фейк удаления": marks the message the way anti-delete marks a really deleted one — dimmed,
/// with the small trash badge.
public func pampGramApplyFakeDeleted(context: AccountContext, messageId: MessageId) {
    pampGramUpdateLocalMessage(context: context, messageId: messageId, label: "Фейк удаление") { _, attributes, _ in
        if !attributes.contains(where: { $0 is PampGramDeletedByRemoteAttribute }) {
            attributes.append(PampGramDeletedByRemoteAttribute(deletedAt: Int32(Date().timeIntervalSince1970)))
        }
    }
}

/// Re-stores the message unchanged so the chat re-renders it (used after an in-memory display
/// override such as "Изменить время", which changes nothing in Postbox on its own).
public func pampGramRefreshMessage(context: AccountContext, messageId: MessageId) {
    pampGramUpdateLocalMessage(context: context, messageId: messageId, label: "Обновление", silent: true) { _, _, _ in }
}
