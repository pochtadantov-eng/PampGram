import Foundation
import UIKit
import Postbox
import SwiftSignalKit

// MARK: - Хранилище настроек (UserDefaults-based для быстрого доступа)
public final class ModSettings {
    public static let shared = ModSettings()
    private let defaults = UserDefaults.standard
    private let notificationCenter = NotificationCenter.default
    
    private init() {
        setupObservers()
    }
    
    private func setupObservers() {
        // При изменении любого параметра отправляем уведомление для обновления UI
        notificationCenter.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            self?.notificationCenter.post(name: NSNotification.Name("ModSettingsDidChange"), object: nil)
        }
    }
    
    // MARK: Copy Protection
    @objc public dynamic var bypassCopyProtection: Bool {
        get { defaults.bool(forKey: "mod_bypassCopyProtection") }
        set {
            defaults.set(newValue, forKey: "mod_bypassCopyProtection")
            broadcastChange()
        }
    }
    
    @objc public dynamic var alwaysKeepForwardAuthor: Bool {
        get { defaults.bool(forKey: "mod_alwaysKeepForwardAuthor") }
        set {
            defaults.set(newValue, forKey: "mod_alwaysKeepForwardAuthor")
            broadcastChange()
        }
    }
    
    // MARK: Auto-Delete
    @objc public dynamic var disableAutoDelete: Bool {
        get { defaults.bool(forKey: "mod_disableAutoDelete") }
        set {
            defaults.set(newValue, forKey: "mod_disableAutoDelete")
            broadcastChange()
        }
    }
    
    // MARK: Screenshot Protection
    @objc public dynamic var bypassScreenshotProtection: Bool {
        get { defaults.bool(forKey: "mod_bypassScreenshotProtection") }
        set {
            defaults.set(newValue, forKey: "mod_bypassScreenshotProtection")
            broadcastChange()
        }
    }
    
    @objc public dynamic var hideChatOnScreenshot: Bool {
        get { defaults.bool(forKey: "mod_hideChatOnScreenshot") }
        set {
            defaults.set(newValue, forKey: "mod_hideChatOnScreenshot")
            broadcastChange()
        }
    }
    
    // MARK: Ads Blocking
    @objc public dynamic var blockAds: Bool {
        get { defaults.bool(forKey: "mod_blockAds") }
        set {
            defaults.set(newValue, forKey: "mod_blockAds")
            broadcastChange()
        }
    }
    
    private func broadcastChange() {
        DispatchQueue.main.async {
            self.notificationCenter.post(name: NSNotification.Name("ModSettingsDidChange"), object: nil)
        }
    }
}

// MARK: - Главный контроллер модификаций
public final class ModFeaturesController {
    public static let shared = ModFeaturesController()
    
    private var screenshotBlurView: UIVisualEffectView?
    private var copyObservationToken: NSObjectProtocol?
    private var messageInterceptionActive = false
    
    private init() {
        setupScreenshotObserver()
        setupSettingsObserver()
    }
    
    // MARK: - Copy Protection Integration
    /// Вызвать Перед попыткой копирования сообщения
    /// Используется в: TelegramUI/Views/Chat/TextSelectionController
    public func canCopyMessage(from message: Any?, withDefaultValue defaultCanCopy: Bool) -> Bool {
        // Если включена защита от копирования, проверяем bypassCopyProtection
        if ModSettings.shared.bypassCopyProtection {
            return true // Разрешаем копирование, несмотря на защиту
        }
        return defaultCanCopy
    }
    
    /// Обработка скопированного текста перед сохранением в буфер обмена
    /// Используется в: TelegramUI/Views/Chat/ChatController
    public func processCopiedText(_ text: String) -> String {
        var result = text
        
        // Если включено "Всегда сохранять автора при пересылке"
        if ModSettings.shared.alwaysKeepForwardAuthor {
            // Добавляем информацию об авторе, если её нет
            if !result.contains("via @") {
                result += "\n\n[Source preserved]"
            }
        }
        
        return result
    }
    
    // MARK: - Auto-Delete Override
    /// Перехватывает TTL (Time-To-Live) сообщения перед удалением
    /// Используется в: TelegramCore/Messages/MessageCleanupManager
    public func shouldAutoDeleteMessage(with ttlSeconds: Int32?) -> Bool {
        if ModSettings.shared.disableAutoDelete {
            return false // Отключаем автоудаление
        }
        return ttlSeconds != nil && ttlSeconds! > 0
    }
    
    // MARK: - Screenshot Protection
    /// Применяется к UIView, чтобы сделать его невидимым при скриншоте
    /// Используется в: TelegramUI/Views/Chat/ChatController viewDidLoad()
    public func applyScreenshotProtection(to view: UIView) {
        if ModSettings.shared.bypassScreenshotProtection {
            // Если защита отключена, ничего не делаем
            return
        }
        
        // Используем UITextView-style подход для пеумышленной защиты
        view.layer.setValue(NSNumber(value: true), forKey: "hideFromScreenshot")
    }
    
    private func setupScreenshotObserver() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.userDidTakeScreenshotNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreenshotTaken()
        }
    }
    
    private func handleScreenshotTaken() {
        guard ModSettings.shared.hideChatOnScreenshot else { return }
        guard !ModSettings.shared.bypassScreenshotProtection else { return }
        
        // Находим main window
        guard let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) else {
            return
        }
        
        // Создаём blur view
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))
        blur.frame = window.bounds
        blur.tag = 9999 // Специальный тег для идентификации
        blur.alpha = 0.0
        
        window.addSubview(blur)
        
        // Анимируем появление и исчезновение
        UIView.animate(withDuration: 0.2, animations: {
            blur.alpha = 1.0
        }) { _ in
            // Продержим blur 0.5 секунды
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                UIView.animate(withDuration: 0.3, animations: {
                    blur.alpha = 0.0
                }) { _ in
                    blur.removeFromSuperview()
                }
            }
        }
    }
    
    // MARK: - Sponsored Messages Filter
    /// Фильтрует спонсорские/рекламные сообщения перед отображением
    /// Используется в: TelegramUI/Views/Chat/ChatMessageItemView
    public func shouldDisplayMessage(_ message: Any?, isSponsoredContent: Bool) -> Bool {
        if isSponsoredContent && ModSettings.shared.blockAds {
            return false // Скрываем рекламу
        }
        return true
    }
    
    /// Альтернативный способ для фильтрации в списке сообщений
    public func filterOutAdsFromMessages(_ messages: [Any]) -> [Any] {
        guard ModSettings.shared.blockAds else { return messages }
        
        // Фильтруем спонсорские сообщения
        return messages.filter { message in
            // Здесь нужна логика определения спонсорского контента
            // В реальности это проверяется через свойство message.isSponsoredMessage
            return true
        }
    }
    
    // MARK: - Settings Observer
    private func setupSettingsObserver() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ModSettingsDidChange"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Обновляем UI при изменении настроек
            self?.notifyAboutSettingsChange()
        }
    }
    
    private func notifyAboutSettingsChange() {
        NotificationCenter.default.post(
            name: NSNotification.Name("ModFeaturesDidChange"),
            object: nil
        )
    }
    
    deinit {
        if let token = copyObservationToken {
            NotificationCenter.default.removeObserver(token)
        }
    }
}
