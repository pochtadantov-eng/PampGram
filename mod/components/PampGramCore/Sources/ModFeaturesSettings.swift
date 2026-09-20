import Foundation
import UIKit
import Postbox
import SwiftSignalKit

/// Bridge between Telegram's runtime hooks and PampGram's Postbox-stored settings.
/// The old UserDefaults-based `ModSettings` is replaced: all state now lives in
/// `PampGramSettings` (Postbox), ensuring it survives across sessions and gets reset
/// on ban like every other PampGram feature.
public final class ModFeaturesController {
    public static let shared = ModFeaturesController()

    private init() {
        setupScreenshotObserver()
    }

    private var cachedScreenshotBypass = false
    private var cachedScreenshotBlur = false
    private var cachedCopyBypass = false
    private var cachedAutoDeleteBypass = false
    private var cachedBlockAds = false

    public func updateFromSettings(_ settings: PampGramSettings) {
        self.cachedScreenshotBypass = settings.screenshotBypassEnabled
        self.cachedScreenshotBlur = settings.screenshotBlurOnCapture
        self.cachedCopyBypass = settings.copyProtectionBypassEnabled
        self.cachedAutoDeleteBypass = settings.autoDeleteBypassEnabled
        self.cachedBlockAds = settings.blockAdsEnabled
    }

    // MARK: - Copy Protection

    public func canCopyMessage(from message: Any?, withDefaultValue defaultCanCopy: Bool) -> Bool {
        if self.cachedCopyBypass {
            return true
        }
        return defaultCanCopy
    }

    // MARK: - Auto-Delete

    public func shouldAutoDeleteMessage(with ttlSeconds: Int32?) -> Bool {
        if self.cachedAutoDeleteBypass {
            return false
        }
        return ttlSeconds != nil && ttlSeconds! > 0
    }

    // MARK: - Screenshot Protection

    public var isScreenshotBypassEnabled: Bool {
        return self.cachedScreenshotBypass
    }

    public func applyScreenshotProtection(to view: UIView) {
        if self.cachedScreenshotBypass {
            return
        }
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
        guard self.cachedScreenshotBlur else { return }
        guard !self.cachedScreenshotBypass else { return }

        guard let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) else {
            return
        }

        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))
        blur.frame = window.bounds
        blur.tag = 9999
        blur.alpha = 0.0

        window.addSubview(blur)

        UIView.animate(withDuration: 0.2, animations: {
            blur.alpha = 1.0
        }) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                UIView.animate(withDuration: 0.3, animations: {
                    blur.alpha = 0.0
                }) { _ in
                    blur.removeFromSuperview()
                }
            }
        }
    }

    // MARK: - Ads

    public func shouldDisplayMessage(_ message: Any?, isSponsoredContent: Bool) -> Bool {
        if isSponsoredContent && self.cachedBlockAds {
            return false
        }
        return true
    }

    public func filterOutAdsFromMessages(_ messages: [Any]) -> [Any] {
        guard self.cachedBlockAds else { return messages }
        return messages
    }
}
