import Foundation
import UIKit
import Display

/// What text/color the persistent top-of-screen badge shows, if anything. Purely cosmetic —
/// see `pampGramInstallStatusBadgeOverlay` for where it actually gets drawn.
public enum PampGramStatusBadgeStyle: String, CaseIterable {
    case off
    case telegram
    case swiftgram

    public var displayName: String {
        switch self {
        case .off: return "Выключено"
        case .telegram: return "Telegram"
        case .swiftgram: return "Swiftgram"
        }
    }
}

private let pampGramStatusBadgeStyleKey = "PampGram_StatusBadgeStyle_v1"

/// Posted whenever `PampGramStatusBadgeStore.style` changes, so the already-installed overlay
/// (added once at launch, long before any settings screen exists) can pick up the new choice
/// immediately instead of only on next launch.
public let pampGramStatusBadgeStyleDidChangeNotification = Notification.Name("PampGramStatusBadgeStyleDidChange")

/// Plain `UserDefaults`, not the Postbox-backed `PampGramSettings` — the badge has to be able
/// to draw itself from `AppDelegate` right after `window.makeKeyAndVisible()`, before any
/// account (and so any Postbox) exists yet, exactly like `PampGramOnboardingScreen.swift`'s own
/// first-launch flag.
public enum PampGramStatusBadgeStore {
    public static var style: PampGramStatusBadgeStyle {
        get {
            guard let raw = UserDefaults.standard.string(forKey: pampGramStatusBadgeStyleKey) else {
                return .off
            }
            return PampGramStatusBadgeStyle(rawValue: raw) ?? .off
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: pampGramStatusBadgeStyleKey)
            NotificationCenter.default.post(name: pampGramStatusBadgeStyleDidChangeNotification, object: nil)
        }
    }
}

private final class PampGramStatusBadgeView: UIView {
    private let iconView = UIImageView()
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.isUserInteractionEnabled = false
        self.isHidden = true
        self.clipsToBounds = true

        self.iconView.contentMode = .scaleAspectFit
        self.iconView.tintColor = .white
        self.addSubview(self.iconView)

        self.label.font = UIFont.systemFont(ofSize: 11.0, weight: .heavy)
        self.label.textColor = .white
        self.addSubview(self.label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(_ style: PampGramStatusBadgeStyle) {
        switch style {
        case .off:
            self.isHidden = true
            return
        case .telegram:
            self.isHidden = false
            self.backgroundColor = UIColor(rgb: 0x229ED9)
            self.iconView.image = nil
            self.label.text = "TELEGRAM"
        case .swiftgram:
            self.isHidden = false
            self.backgroundColor = UIColor(rgb: 0xff5b2e)
            self.iconView.image = UIImage(systemName: "bolt.fill")?.withRenderingMode(.alwaysTemplate)
            self.label.text = "SWIFTGRAM"
        }
        self.sizeAndLayout()
    }

    private func sizeAndLayout() {
        self.label.sizeToFit()
        let hasIcon = self.iconView.image != nil
        let iconSide: CGFloat = 11.0
        let spacing: CGFloat = 4.0
        let horizontalPadding: CGFloat = 11.0
        let height: CGFloat = 22.0
        let contentWidth = self.label.frame.width + (hasIcon ? iconSide + spacing : 0.0)
        let width = contentWidth + horizontalPadding * 2.0

        let center = self.center
        self.bounds = CGRect(x: 0.0, y: 0.0, width: width, height: height)
        self.center = center
        self.layer.cornerRadius = height / 2.0

        var x = horizontalPadding
        if hasIcon {
            self.iconView.frame = CGRect(x: x, y: (height - iconSide) / 2.0, width: iconSide, height: iconSide)
            x += iconSide + spacing
        } else {
            self.iconView.frame = .zero
        }
        self.label.frame = CGRect(x: x, y: (height - self.label.frame.height) / 2.0, width: self.label.frame.width, height: self.label.frame.height)
    }
}

/// Adds the "Бейджик" overlay once, as a direct subview of the app's real `UIWindow` — so it
/// keeps drawing on top of every pushed/presented screen without needing to be re-added
/// anywhere else — and keeps it centered near the top of the screen (roughly where the
/// notch/Dynamic Island sits) across rotation and future style changes. Call once, right after
/// `window.makeKeyAndVisible()` in AppDelegate.swift, same spot as
/// `pampGramPresentOnboardingIfNeeded`.
public func pampGramInstallStatusBadgeOverlay(on window: UIWindow) {
    let badge = PampGramStatusBadgeView(frame: .zero)
    window.addSubview(badge)

    func reposition() {
        let topInset = window.safeAreaInsets.top
        let centerY = topInset > 0.0 ? min(topInset * 0.5, 24.0) : 11.0
        badge.center = CGPoint(x: window.bounds.width / 2.0, y: centerY)
    }

    func update() {
        badge.apply(PampGramStatusBadgeStore.style)
        reposition()
    }

    update()

    NotificationCenter.default.addObserver(forName: pampGramStatusBadgeStyleDidChangeNotification, object: nil, queue: .main) { _ in
        update()
    }
    NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { _ in
        reposition()
    }
}
