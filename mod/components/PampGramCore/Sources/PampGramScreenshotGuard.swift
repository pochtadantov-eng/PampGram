import Foundation
import UIKit
import Postbox
import SwiftSignalKit

/// Backs "Затемнять экран при скриншоте" (Дополнительно → `screenshotGuardEnabled`): on
/// `UIApplication.userDidTakeScreenshotNotification`, briefly covers this device's own key
/// window in black.
///
/// This is a cosmetic, local-only reaction, not a leak-prevention mechanism, and the toggle's
/// footer in Settings says so: iOS gives third-party apps no API to stop the screenshot
/// shortcut itself (there's no equivalent of Android's `FLAG_SECURE`), and this notification
/// only fires *after* the image has already been written to Photos. So the black flash can be
/// turned off (or simply left off — it defaults off) without weakening any real protection,
/// because it never provided one. Telegram's own server-side "screenshot taken" notice sent to
/// the other side in a genuine Secret Chat is a separate, unrelated mechanism and nothing here
/// reads, delays, or suppresses it.
public final class PampGramScreenshotGuard {
    public static let shared = PampGramScreenshotGuard()

    private let enabledState = Atomic<Bool>(value: false)
    private var settingsDisposable: Disposable?
    private var observerToken: NSObjectProtocol?
    private var didActivate = false

    private init() {}

    /// Starts watching for screenshots and following `screenshotGuardEnabled`. Safe to call
    /// every time the PampGram settings hub is opened — only the first call does anything, so
    /// callers don't need to track activation state themselves.
    public func activate(postbox: Postbox) {
        if self.didActivate {
            return
        }
        self.didActivate = true

        self.settingsDisposable = (PampGramCore.settingsSignal(postbox: postbox)
        |> map { settings -> Bool in
            return settings.screenshotGuardEnabled
        }
        |> distinctUntilChanged
        |> deliverOnMainQueue).start(next: { [weak self] enabled in
            let _ = self?.enabledState.modify { _ in enabled }
        })

        self.observerToken = NotificationCenter.default.addObserver(forName: UIApplication.userDidTakeScreenshotNotification, object: nil, queue: .main) { [weak self] _ in
            self?.flashOverlay()
        }
    }

    private func flashOverlay() {
        guard self.enabledState.with({ $0 }) else {
            return
        }
        guard let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) else {
            return
        }

        let overlay = UIView(frame: window.bounds)
        overlay.backgroundColor = .black
        overlay.alpha = 0
        overlay.isUserInteractionEnabled = false
        window.addSubview(overlay)

        UIView.animate(withDuration: 0.12, animations: {
            overlay.alpha = 1
        }, completion: { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                UIView.animate(withDuration: 0.25, animations: {
                    overlay.alpha = 0
                }, completion: { _ in
                    overlay.removeFromSuperview()
                })
            }
        })
    }

    deinit {
        if let observerToken = self.observerToken {
            NotificationCenter.default.removeObserver(observerToken)
        }
        self.settingsDisposable?.dispose()
    }
}
