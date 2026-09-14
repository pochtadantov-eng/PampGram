import Foundation
import AccountContext
import TelegramCore

/**
 INTEGRATION GUIDE для PampGramChannelVisualPhoto
 ================================================

 Интеграция визуальных фото для каналов с ограничениями на загрузку медиа.

 ЗАДАЧА:
 Позволить пользователям отправлять фото в каналы, где запрещена загрузка медиа,
 без нарушения правил. Фото будет видно только на локальном устройстве.

 МЕСТО ИНТЕГРАЦИИ
 ================

 1. Кнопка в меню сообщения канала (long-press menu)
    Файл: ChatInterfaceStateContextMenus.swift (или похожий)

 2. Отдельная кнопка в input panel для каналов с ограничениями
    Файл: ChatInputPanel.swift или ChatInputPanelNode.swift

 СПОСОБ 1: Добавить пункт в меню сообщения
 ==========================================

 БЫЛО (в ChatInterfaceStateContextMenus.swift):
 ```swift
 if canSendMedia {
     items.append(
         ContextMenuActionItem(title: "Отправить фото", action: { ... })
     )
 }
 ```

 СТАЛО:
 ```swift
 if canSendMedia {
     items.append(
         ContextMenuActionItem(title: "Отправить фото", action: { ... })
     )
 } else {
     // Если нельзя отправить медиа, предложить визуальное фото
     items.append(
         ContextMenuActionItem(title: "📸 Визуальное фото", action: {
             pampGramPresentChannelVisualPhotoMenu(
                 context: self.context,
                 channelId: self.chatLocation.peerId
             )
         })
     )
 }
 ```

 СПОСОБ 2: Отдельная кнопка в input panel (для каналов)
 ========================================================

 БЫЛО (в ChatInputPanel.swift):
 ```swift
 class ChatInputPanel {
     let attachmentButton = UIButton()

     func setupButtons() {
         attachmentButton.addTarget(self, action: #selector(attachmentTapped), for: .touchUpInside)
     }
 }
 ```

 СТАЛО (добавить новую кнопку для визуальных фото):
 ```swift
 class ChatInputPanel {
     let attachmentButton = UIButton()
     let visualPhotoButton = UIButton()  // Новая кнопка

     func setupButtons() {
         attachmentButton.addTarget(self, action: #selector(attachmentTapped), for: .touchUpInside)
         visualPhotoButton.addTarget(self, action: #selector(visualPhotoTapped), for: .touchUpInside)

         // Показывать visualPhotoButton только в каналах с ограничениями
         if self.shouldHideMediaUpload {
             self.visualPhotoButton.isHidden = false
         } else {
             self.visualPhotoButton.isHidden = true
         }
     }

     @objc func visualPhotoTapped() {
         pampGramPresentChannelVisualPhotoMenu(
             context: self.context,
             channelId: self.chatLocation.peerId
         )
     }
 }
 ```

 СПОСОБ 3: Меню опций (ActionSheet)
 ==================================

 Если нельзя загружать медиа, показать меню:

 ```swift
 if !canUploadMedia {
     let sheet = ActionSheetController(presentationData: presentationData)
     sheet.setItemGroups([
         ActionSheetItemGroup(items: [
             ActionSheetTextItem(title: "Медиа недоступно в этом канале"),
             ActionSheetButtonItem(title: "📸 Добавить визуальное фото", color: .accent, action: {
                 pampGramPresentChannelVisualPhotoMenu(
                     context: self.context,
                     channelId: peerId
                 )
             })
         ]),
         ActionSheetItemGroup(items: [
             ActionSheetButtonItem(title: "Отмена", color: .accent, font: .bold, action: { ... })
         ])
     ])
     controller.present(sheet, in: .window(.root))
 }
 ```

 ДЛЯ PATCH ФАЙЛА
 ===============

 diff --git a/Telegram/TelegramUI/Views/Chat/ChatInputPanel.swift
 index original..modified 100644
 --- a/Telegram/TelegramUI/Views/Chat/ChatInputPanel.swift
 +++ b/Telegram/TelegramUI/Views/Chat/ChatInputPanel.swift
 @@ -200,6 +200,11 @@ class ChatInputPanel {
      @objc func attachmentButtonPressed() {
          let canUploadMedia = self.canUploadMediaToCurrentChat()

 +        if !canUploadMedia {
 +            pampGramPresentChannelVisualPhotoMenu(
 +                context: self.context, channelId: self.chatLocation.peerId)
 +            return
 +        }
 +
          presentAttachmentMenu()
      }

 ИСПОЛЬЗОВАНИЕ API
 ==================

 Показать меню:
 ```swift
 pampGramPresentChannelVisualPhotoMenu(context: context, channelId: channelId)
 ```

 Получить все фото для канала:
 ```swift
 let photos = pampGramGetChannelVisualPhotos(channelId: channelId)
 ```

 Сохранить фото вручную:
 ```swift
 pampGramSaveChannelVisualPhoto(
     channelId: channelId,
     imagePath: "/path/to/image.jpg",
     caption: "Описание",
     dimensions: CGSize(width: 1920, height: 1080)
 )
 ```

 Удалить фото:
 ```swift
 pampGramRemoveChannelVisualPhoto(channelId: channelId, photoId: photoUUID)
 ```

 ТЕСТИРОВАНИЕ
 ============

 1. Откройте канал с запрещенной загрузкой медиа
 2. Нажмите кнопку скрепки (или меню фото)
 3. Должно открыться меню визуальных фото
 4. Выберите фото из галереи
 5. Добавьте подпись (опционально)
 6. Фото должно появиться в хранилище канала
 7. Откройте "Просмотреть сохраненные" для просмотра

 ОСОБЕННОСТИ
 ===========

 - ✅ Фото сохраняется только локально на устройстве
 - ✅ На сервер ничего не отправляется
 - ✅ Не нарушает правила канала
 - ✅ Видно только тому, кто добавил
 - ✅ Можно добавлять подписи к фото
 - ✅ Автоматическое сжатие фото (JPEG 90%)
 - ✅ Сохранение разрешения изображения
 - ✅ История с датой и временем добавления

 ИНТЕГРАЦИЯ С ДРУГИМИ ФУНКЦИЯМИ
 ===============================

 Можно комбинировать с:
 - Эмодзи-реакциями на фото (pampGramAddMessageReaction)
 - Визуальной переиской (pampGramPresentVisualChatMenu)
 - Фото от собеседника (как в личных чатах)

 ПРИМЕЧАНИЕ О ОГРАНИЧЕНИЯХ
 =========================

 Функция корректно работает в:
 - Каналах с запрещением загрузки медиа
 - Каналах с ограничениями на пересылку
 - Каналах доступных только для чтения
 - Супергруппах с требованием одобрения
 - Любых других контекстах с ограничениями
 */

/// Расширение для удобства проверки возможности загрузки медиа
public extension ChatLocation {
    func canUploadMediaInThisLocation(in context: AccountContext) -> Bool {
        // Эта логика должна быть в ChatController.swift
        // Здесь просто пример структуры
        switch self {
        case .peer(let peerId):
            // Проверить ограничения для этого peer'а
            return true  // Default - можно загружать
        default:
            return false
        }
    }
}

/// Быстрый доступ из контекста
public extension AccountContext {
    func presentChannelVisualPhotoMenu(channelId: EnginePeer.Id) {
        pampGramPresentChannelVisualPhotoMenu(context: self, channelId: channelId)
    }
}
