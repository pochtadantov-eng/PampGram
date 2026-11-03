import Foundation

/**
 INTEGRATION GUIDE для ModFeaturesController
 ============================================
 
 Этот файл содержит примеры того, КАК И ГДЕ интегрировать функции ModFeaturesController
 в код Telegram-iOS.
 
 ДЛЯ КАЖДОЙ ФУНКЦИИ ниже есть:
 1. Описание что она делает
 2. Где её использовать
 3. Пример кода для интеграции
 4. Что нужно изменить в оригинальном коде Telegram
 */

// MARK: - 1. COPY PROTECTION - Обход защиты копирования
/**
 ФАЙЛ: Telegram/TelegramUI/Views/Chat/ChatMessageItemView.swift
 МЕТОД: func canCopy() -> Bool
 
 БЫЛО:
 ```swift
 func canCopy() -> Bool {
     return !self.message.isCopyProtected
 }
 ```
 
 СТАЛО:
 ```swift
 func canCopy() -> Bool {
     let defaultValue = !self.message.isCopyProtected
     return ModFeaturesController.shared.canCopyMessage(
         from: self.message,
         withDefaultValue: defaultValue
     )
 }
 ```
 */

// MARK: - 2. COPY AUTHOR - Сохранение информации об авторе
/**
 ФАЙЛ: Telegram/TelegramUI/Views/Chat/ChatController.swift
 МЕТОД: func copySelectedMessages()
 
 БЫЛО:
 ```swift
 let text = messageText
 UIPasteboard.general.string = text
 ```
 
 СТАЛО:
 ```swift
 var text = messageText
 text = ModFeaturesController.shared.processCopiedText(text)
 UIPasteboard.general.string = text
 ```
 */

// MARK: - 3. AUTO-DELETE BYPASS - Отключение автоудаления
/**
 ФАЙЛ: Telegram/TelegramCore/Messages/MessageCleanupManager.swift
 МЕТОД: func scheduleMessageCleanup(message:)
 
 БЫЛО:
 ```swift
 if let ttl = message.autoremoveTimeout, ttl > 0 {
     scheduleCleanup(after: ttl)
 }
 ```
 
 СТАЛО:
 ```swift
 if ModFeaturesController.shared.shouldAutoDeleteMessage(with: message.autoremoveTimeout) {
     if let ttl = message.autoremoveTimeout, ttl > 0 {
         scheduleCleanup(after: ttl)
     }
 }
 ```
 */

// MARK: - 4. SCREENSHOT PROTECTION - Защита от скриншотов
/**
 ФАЙЛ: Telegram/TelegramUI/Views/Chat/ChatController.swift
 МЕТОД: override func viewDidLoad()
 
 БЫЛО:
 ```swift
 override func viewDidLoad() {
     super.viewDidLoad()
     // ... init code
 }
 ```
 
 СТАЛО:
 ```swift
 override func viewDidLoad() {
     super.viewDidLoad()
     // ... init code
     
     // Применяем защиту от скриншотов к основному view
     ModFeaturesController.shared.applyScreenshotProtection(to: self.view)
 }
 ```
 */

// MARK: - 5. SCREENSHOT BLUR - Размытие при скриншоте
/**
 ФАЙЛ: Telegram/TelegramUI/Views/Chat/ChatController.swift
 МЕТОД: override func viewDidLoad()
 
 БЫЛО: (то же самое что выше)
 
 СТАЛО: (уже обрабатывается ModFeaturesController автоматически через notification observer)
 
 Когда пользователь делает скриншот:
 1. UIApplication.userDidTakeScreenshotNotification срабатывает
 2. ModFeaturesController перехватывает событие
 3. Если hideChatOnScreenshot включен, появляется blur на 0.5 секунды
 4. Blur исчезает
 */

// MARK: - 6. BLOCK ADS - Скрытие спонсорских сообщений
/**
 ФАЙЛ: Telegram/TelegramUI/Views/Chat/ChatViewController.swift
 МЕТОД: func configureMessageCell(...)
 
 БЫЛО:
 ```swift
 if message.isSponsoredMessage {
     displaySponsoredContent(message)
 }
 ```
 
 СТАЛО:
 ```swift
 if message.isSponsoredMessage {
     if ModFeaturesController.shared.shouldDisplayMessage(message, isSponsoredContent: true) {
         displaySponsoredContent(message)
     }
 }
 ```
 
 ИЛИ в методе получения списка сообщений:
 
 БЫЛО:
 ```swift
 let messages = fetchMessages()
 displayMessages(messages)
 ```
 
 СТАЛО:
 ```swift
 let messages = fetchMessages()
 let filteredMessages = ModFeaturesController.shared.filterOutAdsFromMessages(messages)
 displayMessages(filteredMessages)
 ```
 */

// MARK: - 7. SAVE ONCE MEDIA — Сохранение одноразового фото/видео в галерею
/**
 ФАЙЛ: submodules/TelegramUI/Components/MediaViewer/Sources/MediaViewerController.swift
         (или GalleryController.swift / SecretMediaPreviewController.swift — зависит от версии)
 МЕТОД: func mediaDismissed() / func mediaDidClose() / viewWillDisappear

 Telegram удаляет ресурс одноразового медиа сразу после закрытия просмотрщика.
 Нам нужно перехватить этот момент ДО удаления.

 Ищем в коде паттерн вида:
 ```swift
 // где-то в просмотрщике одноразового контента (view-once / secret)
 if message.minAutoremoveOrClearTimeout == viewOnceTimeout {
     // удаляем ресурс / сообщение
     deleteMessages(...)
 }
 ```

 СТАЛО (вставить ПЕРЕД блоком удаления):
 ```swift
 if message.minAutoremoveOrClearTimeout == viewOnceTimeout,
    let resource = (message.media.first(where: { $0 is TelegramMediaImage || $0 is TelegramMediaFile })),
    let localPath = context.account.postbox.mediaBox.completedResourcePath(resourceId(for: resource)) {

     let isVideo: Bool
     if let file = resource as? TelegramMediaFile {
         isVideo = file.isVideo
     } else {
         isVideo = false
     }
     let _ = ModFeaturesController.shared.handleOnceMediaViewed(localPath: localPath, isVideo: isVideo)
 }
 // ... дальше оригинальный код удаления
 ```

 Альтернативно — поискать `destroySecretMedia` / `clearSecretMedia` / `secretMediaManager` в
 submodules/TelegramCore/Sources/TelegramEngine/SecretMessages/ и добавить тот же вызов перед
 фактическим удалением файла из mediaBox.

 ВАЖНО: `PHPhotoLibrary.requestAuthorization` — запрос идёт один раз; добавить
 NSPhotoLibraryAddUsageDescription в Info.plist проекта (уже должен быть для обычного сохранения).
 */

// MARK: - 8. FORWARD ONCE VOICE — Пересылка одноразовых ГС
/**
 ФАЙЛ: submodules/TelegramUI/Sources/Chat/ChatMessageActionSheetController.swift
         или ChatMessageContextMenuActions.swift
 МЕТОД: buildContextMenuActions / canForward

 Telegram скрывает «Переслать» для сообщений с флагом view-once.
 Ищем паттерн:

 ```swift
 // Проверка перед добавлением кнопки "Переслать"
 let canForward = !message.isCopyProtected && message.minAutoremoveOrClearTimeout == nil
 ```

 или:

 ```swift
 if message.attributes.contains(where: { $0 is AutoremoveTimeoutMessageAttribute }) {
     // не добавляем Forward
 }
 ```

 СТАЛО:
 ```swift
 var isOnceVoice = false
 if let file = message.media.first(as: TelegramMediaFile.self),
    file.isVoice,
    message.attributes.contains(where: { ($0 as? AutoremoveTimeoutMessageAttribute)?.timeout == viewOnceTimeout }) {
     isOnceVoice = true
 }

 let canForward = !message.isCopyProtected
     && (message.minAutoremoveOrClearTimeout == nil
         || (isOnceVoice && ModFeaturesController.shared.canForwardOnceVoice()))
 ```

 После этого кнопка «Переслать» появится для одноразовых ГС при включённой опции.
 Само сообщение при пересылке уже не имеет флага view-once (пересылается как обычное ГС).
 */

// MARK: - PATCH FILE APPROACH (для автоматического применения)
/**
 Если хочешь автоматизировать, нужно добавить в telegram-ios.patch:
 
 diff --git a/Telegram/TelegramUI/Views/Chat/ChatMessageItemView.swift
 index original..modified 100644
 --- a/Telegram/TelegramUI/Views/Chat/ChatMessageItemView.swift
 +++ b/Telegram/TelegramUI/Views/Chat/ChatMessageItemView.swift
 @@ -123,7 +123,9 @@ class ChatMessageItemView {
      func canCopy() -> Bool {
 -        return !self.message.isCopyProtected
 +        let defaultValue = !self.message.isCopyProtected
 +        return ModFeaturesController.shared.canCopyMessage(
 +            from: self.message, withDefaultValue: defaultValue)
      }
  
  Аналогично для всех других методов...
 */

// MARK: - SETTINGS UI INTEGRATION
/**
 Для добавления этих функций в UI:
 Они уже должны быть в PampGramSettingsUI, надо просто связать с ModSettings:
 
 @State var bypassCopyProtection = ModSettings.shared.bypassCopyProtection
 @State var blockAds = ModSettings.shared.blockAds
 
 Toggle("Обход защиты от копирования", isOn: $bypassCopyProtection)
     .onChange(of: bypassCopyProtection) { newValue in
         ModSettings.shared.bypassCopyProtection = newValue
     }
 */

// MARK: - TESTING
/**
 Как тестировать каждую функцию:
 
 1. Copy Protection:
    - Откройте защищённое сообщение
    - Включите "Обход защиты от копирования" в настройках
    - Должны суметь скопировать текст
 
 2. Auto-Delete Bypass:
    - Получите сообщение с таймером удаления
    - Включите "Отключить автоудаление"
    - Сообщение не должно удалиться
 
 3. Screenshot Blur:
    - Откройте чат
    - Включите "Скрыть при скриншоте"
    - Сделайте скриншот
    - Экран должен размыться на 0.5 сек
 
 4. Block Ads:
    - Найдите спонсорское сообщение
    - Включите "Блокировать рекламу"
    - Объявление должно исчезнуть из списка
 */
