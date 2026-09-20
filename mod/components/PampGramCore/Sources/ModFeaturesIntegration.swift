import Foundation

/**
 INTEGRATION GUIDE для ModFeaturesController
 ============================================

 ModFeaturesController — мост между Telegram-хуками и Postbox-настройками PampGram.
 Все состояние хранится в PampGramSettings (Postbox). Кэш обновляется из настроек через
 `updateFromSettings(_:)` — вызывайте его при каждом изменении PampGramSettings.

 Каждая функция ниже: где в Telegram-iOS вставлять вызов ModFeaturesController.shared.
 */

// MARK: - Инициализация кэша
/**
 При старте приложения и при каждом обновлении PampGramSettings:

 ```swift
 let _ = PampGramCore.settingsSignal(postbox: account.postbox)
 |> deliverOnMainQueue
 |> start(next: { settings in
     ModFeaturesController.shared.updateFromSettings(settings)
 })
 ```
 */

// MARK: - 1. COPY PROTECTION — Обход защиты копирования
/**
 ```swift
 let defaultValue = !self.message.isCopyProtected
 return ModFeaturesController.shared.canCopyMessage(
     from: self.message,
     withDefaultValue: defaultValue
 )
 ```
 */

// MARK: - 2. AUTO-DELETE BYPASS — Отключение автоудаления
/**
 ```swift
 if ModFeaturesController.shared.shouldAutoDeleteMessage(with: message.autoremoveTimeout) {
     scheduleCleanup(after: ttl)
 }
 ```
 */

// MARK: - 3. SCREENSHOT PROTECTION — Защита от скриншотов
/**
 ```swift
 ModFeaturesController.shared.applyScreenshotProtection(to: self.view)
 ```
 Если `screenshotBypassEnabled` включен, вызов ничего не делает.
 Blur при скриншоте работает автоматически через notification observer.
 */

// MARK: - 4. BLOCK ADS — Скрытие спонсорских сообщений
/**
 ```swift
 if ModFeaturesController.shared.shouldDisplayMessage(message, isSponsoredContent: true) {
     displaySponsoredContent(message)
 }
 ```
 */
