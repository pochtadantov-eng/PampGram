import Foundation
import UIKit
import Display
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramPresentationData
import AccountContext

/**
 PampGramMessageReactions — эмодзи-реакция на любое сообщение
 =============================================================

 В отличие от первой версии этого файла (хранившей реакции отдельно в
 UserDefaults, откуда их никто и никогда не читал для отображения),
 реакция пишется прямо в `ReactionsMessageAttribute` самого сообщения
 через `transaction.updateMessage` — тот же локальный-only приём, что и
 у "Изменить текст" (PampGramVisualEditScreen.swift). Стоковый рендеринг
 Telegram уже умеет рисовать этот атрибут как обычные пилюли реакций под
 сообщением, так что ничего в отрисовке бабла патчить не нужно — эмодзи
 просто появляется, как будто кто-то отреагировал по-настоящему.
 Работает одинаково для текста, фото, голосового и стикера — атрибут не
 зависит от типа медиа.
 */

/// Добавляет/убирает `emoji` в списке реакций сообщения (сохраняя все
/// остальные существующие реакции, включая настоящие, если они есть).
public func pampGramToggleMessageReaction(context: AccountContext, messageId: MessageId, emoji: String) {
    let _ = context.account.postbox.transaction { transaction -> Void in
        transaction.updateMessage(messageId, update: { currentMessage -> PostboxUpdateMessage in
            let existingAttribute = currentMessage.attributes.compactMap { $0 as? ReactionsMessageAttribute }.first
            var reactions = existingAttribute?.reactions ?? []
            if let index = reactions.firstIndex(where: { $0.value == .builtin(emoji) }) {
                reactions.remove(at: index)
            } else {
                reactions.append(MessageReaction(value: .builtin(emoji), count: 1, chosenOrder: 0))
            }

            let newAttribute = ReactionsMessageAttribute(
                canViewList: existingAttribute?.canViewList ?? true,
                isTags: existingAttribute?.isTags ?? false,
                reactions: reactions,
                recentPeers: existingAttribute?.recentPeers ?? [],
                topPeers: existingAttribute?.topPeers ?? []
            )
            var attributes = currentMessage.attributes.filter { !($0 is ReactionsMessageAttribute) }
            attributes.append(newAttribute)

            let updatedMessage = StoreMessage(
                id: messageId,
                customStableId: currentMessage.customStableId,
                globallyUniqueId: currentMessage.globallyUniqueId,
                groupingKey: currentMessage.groupingKey,
                threadId: currentMessage.threadId,
                timestamp: currentMessage.timestamp,
                flags: StoreMessageFlags(currentMessage.flags),
                tags: currentMessage.tags,
                globalTags: currentMessage.globalTags,
                localTags: currentMessage.localTags,
                forwardInfo: currentMessage.forwardInfo.map(StoreMessageForwardInfo.init),
                authorId: currentMessage.author?.id,
                text: currentMessage.text,
                attributes: attributes,
                media: currentMessage.media
            )
            return .update(updatedMessage)
        })
    }.start()
}

/// Часто используемые эмодзи для быстрого выбора в пикере.
public func pampGramGetPopularEmojis() -> [String] {
    return [
        "👍", "❤️", "😂", "😮", "😢", "😡", "🔥", "👏", "🙏", "💯",
        "✨", "🎉", "🎈", "🎁", "🌹", "😍", "😘", "🤔", "😏", "🤣"
    ]
}

/// "PampGram" → "Поставить реакцию": ActionSheet со списком эмодзи, каждый
/// тап сразу переключает эту реакцию на сообщении и закрывает лист. Ищет
/// свой собственный top controller (тот же приём, что и остальные
/// pampGramPresent*-функции), так что вызывающему не нужно передавать
/// presenting controller явно.
public func pampGramPresentReactionPicker(context: AccountContext, messageId: MessageId) {
    guard let topController = (context.sharedContext.mainWindow?.viewController as? NavigationController)?.topViewController as? ViewController else {
        return
    }
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let sheet = ActionSheetController(presentationData: presentationData)

    var buttons: [ActionSheetItem] = [
        ActionSheetTextItem(title: "Реакция на сообщение")
    ]
    for emoji in pampGramGetPopularEmojis() {
        buttons.append(ActionSheetButtonItem(title: emoji, color: .accent, action: { [weak sheet] in
            sheet?.dismissAnimated()
            pampGramToggleMessageReaction(context: context, messageId: messageId, emoji: emoji)
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
    topController.present(sheet, in: .window(.root))
}
