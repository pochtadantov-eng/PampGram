import Foundation
import AccountContext
import TelegramCore

/**
 INTEGRATION GUIDE для PampGramChannelScreenCapture
 ==================================================

 Интеграция функции захвата экрана в каналах, где блокируется скриншот.
 Обходит защиту от скриншотов и позволяет сохранять изображение экрана.

 ЗАДАЧА:
 Когда пользователь в канале с блокировкой скриншотов видит черный экран
 (защита от захвата), предложить встроенный захват через меню.

 МЕСТО ИНТЕГРАЦИИ
 ================

 1. Как отдельное меню в канале (главный способ)
    Файл: ChatController.swift

 2. Кнопка в контекстном меню сообщения
    Файл: ChatInterfaceStateContextMenus.swift

 3. Горячая клавиша при попытке скриншота
    Файл: ChatController.swift или похожий

 СПОСОБ 1: Отдельная кнопка в canale (РЕКОМЕНДУЕТСЯ)
 ===================================================

 БЫЛО:
 ```swift
 class ChatController {
     func setupChannelUI() {
         // Только стандартные кнопки
     }
 }
 ```

 СТАЛО:
 ```swift
 class ChatController {
     func setupChannelUI() {
         // Если это канал с блокировкой скриншотов
         if isScreenshotBlockedChannel() {
             let screenshotButton = UIButton()
             screenshotButton.setImage(UIImage(systemName: "camera.fill"), for: .normal)
             screenshotButton.tintColor = .systemBlue
             screenshotButton.addTarget(self, action: #selector(openScreenCaptureMenu), for: .touchUpInside)

             self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: screenshotButton)
         }
     }

     @objc func openScreenCaptureMenu() {
         pampGramPresentChannelScreenCaptureMenu(
             context: self.context,
             channelId: self.chatLocation.peerId
         )
     }
 }
 ```

 СПОСОБ 2: В меню долгого клика сообщения
 ==========================================

 БЫЛО (в ChatInterfaceStateContextMenus.swift):
 ```swift
 if message.isCopyProtected {
     // Обработка защиты от копирования
 }
 ```

 СТАЛО:
 ```swift
 if message.isCopyProtected || isScreenshotBlocked {
     items.append(
         ContextMenuActionItem(title: "📸 Захватить экран", action: {
             pampGramPresentChannelScreenCaptureMenu(
                 context: self.context,
                 channelId: self.chatLocation.peerId
             )
         })
     )
 }
 ```

 СПОСОБ 3: Обработка UIKeyCommand (горячая клавиша)
 ===================================================

 При нажатии Volume Up + Volume Down для скриншота:

 ```swift
 override var keyCommands: [UIKeyCommand]? {
     var commands = super.keyCommands ?? []

     // При попытке скриншота вызываем меню
     commands.append(UIKeyCommand(
         input: "S",
         modifierFlags: .command,
         action: #selector(handleScreenshotAttempt)
     ))

     return commands
 }

 @objc func handleScreenshotAttempt() {
     if isScreenshotBlockedChannel() {
         pampGramPresentChannelScreenCaptureMenu(
             context: self.context,
             channelId: self.chatLocation.peerId
         )
     }
 }
 ```

 СПОСОБ 4: При срабатывании UIApplication.userDidTakeScreenshotNotification
 ===========================================================================

 Обнаружение попытки скриншота:

 ```swift
 override func viewDidLoad() {
     super.viewDidLoad()

     NotificationCenter.default.addObserver(
         forName: UIApplication.userDidTakeScreenshotNotification,
         object: nil,
         queue: .main
     ) { [weak self] _ in
         if self?.isScreenshotBlockedChannel() == true {
             // Показываем меню вместо черного экрана
             self?.showScreenCaptureAlternative()
         }
     }
 }

 func showScreenCaptureAlternative() {
     let alert = UIAlertController(
         title: "📸 Захват экрана заблокирован",
         message: "Используйте встроенный захват экрана",
         preferredStyle: .alert
     )

     alert.addAction(UIAlertAction(title: "Захватить", style: .default) { [weak self] _ in
         guard let self = self else { return }
         pampGramPresentChannelScreenCaptureMenu(
             context: self.context,
             channelId: self.chatLocation.peerId
         )
     })

     alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
     self.present(alert, animated: true)
 }
 ```

 ДЛЯ PATCH ФАЙЛА
 ===============

 diff --git a/Telegram/TelegramUI/Views/Chat/ChatController.swift
 index original..modified 100644
 --- a/Telegram/TelegramUI/Views/Chat/ChatController.swift
 +++ b/Telegram/TelegramUI/Views/Chat/ChatController.swift
 @@ -450,6 +450,15 @@ class ChatController {
      override func viewDidLoad() {
          super.viewDidLoad()

 +        // Слушаем попытки скриншота в каналах с блокировкой
 +        if self.isChannelWithScreenshotBlock() {
 +            NotificationCenter.default.addObserver(
 +                forName: UIApplication.userDidTakeScreenshotNotification,
 +                object: nil,
 +                queue: .main
 +            ) { [weak self] _ in
 +                self?.handleScreenshotAttempt()
 +            }
 +        }
      }

  +    @objc func handleScreenshotAttempt() {
 +        pampGramPresentChannelScreenCaptureMenu(
 +            context: self.context, channelId: self.chatLocation.peerId)
 +    }

 ИСПОЛЬЗОВАНИЕ API
 ==================

 Показать меню захвата:
 ```swift
 pampGramPresentChannelScreenCaptureMenu(context: context, channelId: channelId)
 ```

 Получить все захваты:
 ```swift
 let captures = pampGramGetChannelScreenCaptures(channelId: channelId)
 ```

 Сохранить захват вручную:
 ```swift
 pampGramSaveChannelScreenCapture(
     channelId: channelId,
     imagePath: "/path/to/screenshot.jpg",
     screenSize: CGSize(width: 1125, height: 2436)
 )
 ```

 Удалить захват:
 ```swift
 pampGramRemoveChannelScreenCapture(channelId: channelId, captureId: captureUUID)
 ```

 ТЕСТИРОВАНИЕ
 ============

 1. Откройте канал с включенной блокировкой скриншотов
 2. Попробуйте сделать скриншот - должен появиться черный экран (защита)
 3. Нажмите на кнопку меню захвата (или используйте горячую клавишу)
 4. Откроется меню PampGram с опциями захвата
 5. Нажмите "Захватить экран"
 6. Скриншот сохранится в памяти приложения
 7. Откройте "Просмотреть захваты" для просмотра

 ОСОБЕННОСТИ
 ===========

 - ✅ Работает несмотря на блокировку скриншотов канала
 - ✅ Обходит защиту от UIScreen.main.brightness = 0
 - ✅ Захватывает весь видимый контент экрана
 - ✅ Сохраняет в высоком качестве (JPEG 85%)
 - ✅ История всех захватов с датой и временем
 - ✅ Сохраняется локально на устройстве
 - ✅ Не отправляется на сервер
 - ✅ Видно только тому, кто захватил
 - ✅ Быстрый захват через большую красную кнопку

 КОМБИНАЦИЯ С ДРУГИМИ ФУНКЦИЯМИ
 ==============================

 Захватанные скриншоты можно:
 - Просматривать через историю
 - Добавлять реакции (pampGramAddMessageReaction)
 - Отправлять как визуальное фото в личный чат
 - Комбинировать с другими визуальными функциями

 ПРИМЕЧАНИЯ
 ==========

 - Функция работает ТОЛЬКО в каналах с блокировкой скриншотов
 - В обычных каналах обычный скриншот работает нормально
 - Захват НЕ уведомляет администратора канала (локально)
 - Контент остается в памяти устройства
 - Длительное хранение: до удаления приложения

 ОТЛИЧИЕ ОТ ОБЫЧНОГО СКРИНШОТА
 ==============================

 Обычный скриншот (системный):
 - Блокируется в защищенных каналах (черный экран)
 - Сохраняется в фотопленку с уведомлением
 - Может быть отредактирован и отправлен

 Захват через PampGram:
 - Работает даже в защищенных каналах
 - Сохраняется ТОЛЬКО локально в приложении
 - Не попадает в фотопленку или историю системы
 - Под полным контролем пользователя
 */

/// Расширение для удобства работы с меню захвата
public extension AccountContext {
    func presentChannelScreenCaptureMenu(channelId: EnginePeer.Id) {
        pampGramPresentChannelScreenCaptureMenu(context: self, channelId: channelId)
    }
}

/// Проверка, заблокирован ли скриншот в канале
public extension ChatLocation {
    func isScreenshotBlockedInThisLocation() -> Bool {
        // Эта логика должна быть в ChatController.swift
        // Здесь пример структуры
        switch self {
        case .peer(let peerId):
            // Проверить флаги канала и сообщений
            return false  // Default - обычное поведение
        default:
            return false
        }
    }
}
