import Foundation
import UIKit
import AccountContext
import TelegramCore

/**
 INTEGRATION GUIDE для PampGramVisualChatMenu
 ============================================

 Этот файл показывает, как интегрировать меню визуального чата
 в интерфейс Telegram iOS.

 МЕСТО ИНТЕГРАЦИИ: Кнопка скрепки (attachment/paperclip button) в чате
 ============================================

 Обычно это находится в:
 - ChatController.swift
 - ChatInputPanelNode.swift
 - Или похожем файле управления input panel

 СПОСОБ 1: Долгий клик по кнопке скрепки
 =========================================

 БЫЛО:
 ```swift
 let attachmentButton = UIButton()
 attachmentButton.addTarget(self, action: #selector(attachmentButtonPressed), for: .touchUpInside)
 ```

 СТАЛО:
 ```swift
 let attachmentButton = UIButton()
 attachmentButton.addTarget(self, action: #selector(attachmentButtonPressed), for: .touchUpInside)

 // Добавляем долгий клик для меню визуального чата
 let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(attachmentButtonLongPressed(_:)))
 attachmentButton.addGestureRecognizer(longPressGesture)
 ```

 МЕТОД для обработки долгого клика:
 ```swift
 @objc func attachmentButtonLongPressed(_ gesture: UILongPressGestureRecognizer) {
     guard gesture.state == .began else { return }
     pampGramPresentVisualChatMenu(context: self.context, peerId: self.chatLocation.peerId)
 }
 ```

 СПОСОБ 2: Меню (ActionSheet) при клике на скрепку
 ====================================================

 Если хочешь показать меню с выбором между обычным вложением и визуальным чатом:

 БЫЛО:
 ```swift
 @objc func attachmentButtonPressed() {
     presentAttachmentMenu()
 }
 ```

 СТАЛО:
 ```swift
 @objc func attachmentButtonPressed() {
     let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
     let actionSheet = ActionSheetController(presentationData: presentationData)

     var items: [ActionSheetItem] = [
         ActionSheetTextItem(title: "Вложение"),
         ActionSheetButtonItem(title: "📎 Обычное вложение", color: .accent, action: { [weak self] in
             self?.presentAttachmentMenu()
         }),
         ActionSheetButtonItem(title: "💬 Визуальный чат", color: .accent, action: { [weak self] in
             guard let self = self else { return }
             pampGramPresentVisualChatMenu(context: self.context, peerId: self.chatLocation.peerId)
         })
     ]

     items.append(ActionSheetItemGroup(items: [
         ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
             actionSheet?.dismissAnimated()
         })
     ]))

     actionSheet.setItemGroups(items)
     self.present(actionSheet, in: .window(.root))
 }
 ```

 СПОСОБ 3: Отдельная кнопка для визуального чата
 =================================================

 Добавить рядом со скрепкой еще одну кнопку:

 БЫЛО:
 ```swift
 // Только скрепка
 self.attachmentButton = UIButton()
 ```

 СТАЛО:
 ```swift
 // Скрепка
 self.attachmentButton = UIButton()
 self.attachmentButton.addTarget(self, action: #selector(attachmentButtonPressed), for: .touchUpInside)

 // Новая кнопка для визуального чата
 self.visualChatButton = UIButton()
 self.visualChatButton.setImage(UIImage(systemName: "bubble.left.and.bubble.right"), for: .normal)
 self.visualChatButton.addTarget(self, action: #selector(visualChatButtonPressed), for: .touchUpInside)

 // Добавляем обе в stackView
 self.inputAccessoryStackView.addArrangedSubview(self.attachmentButton)
 self.inputAccessoryStackView.addArrangedSubview(self.visualChatButton)
 ```

 МЕТОД для визуального чата:
 ```swift
 @objc func visualChatButtonPressed() {
     pampGramPresentVisualChatMenu(context: self.context, peerId: self.chatLocation.peerId)
 }
 ```

 ЧТО НУЖНО В PATCH ФАЙЛЕ
 =======================

 Если используешь автоматический патч, добавь туда:

 diff --git a/Telegram/TelegramUI/Views/Chat/ChatInputPanel.swift
 index original..modified 100644
 --- a/Telegram/TelegramUI/Views/Chat/ChatInputPanel.swift
 +++ b/Telegram/TelegramUI/Views/Chat/ChatInputPanel.swift
 @@ -150,6 +150,11 @@ class ChatInputPanel {
      func setupAttachmentButton() {
          let attachmentButton = UIButton()
          attachmentButton.addTarget(self, action: #selector(attachmentButtonPressed), for: .touchUpInside)
 +
 +        // Добавляем долгий клик для визуального чата
 +        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(attachmentButtonLongPressed(_:)))
 +        attachmentButton.addGestureRecognizer(longPressGesture)
      }

  @@ -160,6 +165,12 @@ class ChatInputPanel {
       }
 +
 +    @objc func attachmentButtonLongPressed(_ gesture: UILongPressGestureRecognizer) {
 +        guard gesture.state == .began else { return }
 +        pampGramPresentVisualChatMenu(context: self.context, peerId: self.chatLocation.peerId)
 +    }

 ТЕСТИРОВАНИЕ
 ============

 1. Откройте чат
 2. Нажмите и удерживайте кнопку скрепки (или используйте выбранный вариант интеграции)
 3. Должно открыться меню создания визуального чата
 4. Нажимайте кнопки для добавления сообщений
 5. Нажмите "✅ Отправить"
 6. Сообщения должны появиться в чате по ролям

 ПРИМЕЧАНИЯ
 ==========

 - Все сообщения сохраняются локально, на сервер не отправляются
 - Визуальный чат будет виден только на этом устройстве
 - Собеседник не получит эти сообщения
 - Каждый элемент отправляется отдельным сообщением с правильной ролью (входящее/исходящее)
 */

// Вспомогательные утилиты для удобства интеграции

/// Расширение для быстрого доступа к меню визуального чата
public extension AccountContext {
    func presentVisualChatMenu(from controller: UIViewController, peerId: EnginePeer.Id) {
        pampGramPresentVisualChatMenu(context: self, peerId: peerId)
    }
}

/// Расширение для работы с chat location
public extension ChatLocation {
    var peerIdForVisualChat: EnginePeer.Id? {
        switch self {
        case .peer(let peerId):
            return peerId
        default:
            return nil
        }
    }
}
