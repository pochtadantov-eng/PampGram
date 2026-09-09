import Foundation
import UIKit
import Postbox
import SwiftSignalKit

public final class PampGramScreenshotGuard {
    public static let shared = PampGramScreenshotGuard()

    private var observer: NSObjectProtocol?
    private var settingsDisposable: Disposable?
    public var enabled = false

    private init() {}

    public func start(postbox: Postbox) {
        guard observer == nil else { return }

        settingsDisposable = (PampGramCore.settingsSignal(postbox: postbox)
        |> deliverOnMainQueue).startStrict(next: { [weak self] settings in
            self?.enabled = settings.hideChatOnScreenshot
        })

        observer = NotificationCenter.default.addObserver(
            forName: UIApplication.userDidTakeScreenshotNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.enabled else { return }
            self.applyBlur()
        }
    }

    private func applyBlur() {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) else { return }

        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        blur.frame = window.bounds
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blur.alpha = 1.0
        window.addSubview(blur)

        UIView.animate(withDuration: 0.4, delay: 0.6, options: .curveEaseOut, animations: {
            blur.alpha = 0.0
        }) { _ in
            blur.removeFromSuperview()
        }
    }
}
