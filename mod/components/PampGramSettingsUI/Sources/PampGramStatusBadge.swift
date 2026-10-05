import Foundation
import UIKit
import Display
import AppBundle
import DeviceModel

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

private func pampGramFloorToScreenPixels(_ value: CGFloat) -> CGFloat {
    let scale = UIScreen.main.scale
    guard scale > 0 else {
        return value
    }
    return (value * scale).rounded(.down) / scale
}

/// How far below the very top of the screen the badge should sit, so it clears the notch/
/// Dynamic Island on *this* device instead of overlapping it. Ported from Swiftgram's own
/// `DeviceMetrics.sgAppBadgeOffset()` (`Swiftgram/SGAppBadgeOffset/Sources/SGAppBadgeOffset.swift`)
/// — a hand-measured value per device model, not a formula derived from `safeAreaInsets.top`
/// (which doesn't vary finely enough between, say, an iPhone 14 Pro's smaller Dynamic Island and
/// an iPhone 17 Pro's larger one to place a badge cleanly below either). Devices that table
/// doesn't name — older notch-less phones, and anything newer than this list knows about —
/// fall back to half the real safe-area inset, which is a reasonable generic clearance either
/// way (a flat status bar on an old device, or "assume Dynamic-Island class" for a future one).
private func pampGramBadgeTopOffset(window: UIWindow) -> CGFloat {
    let defaultOffset: CGFloat
    switch DeviceModel.current {
    case .iPhoneX, .iPhoneXS, .iPhone11Pro, .iPhone12Mini, .iPhone13Mini:
        defaultOffset = 2.0
    case .iPhone11, .iPhoneXR:
        defaultOffset = 6.0
    case .iPhone11ProMax, .iPhoneXSMax:
        defaultOffset = 4.0
    case .iPhone12, .iPhone12Pro, .iPhone13, .iPhone13Pro, .iPhone14, .iPhone16e:
        defaultOffset = 4.0
    case .iPhone12ProMax, .iPhone13ProMax, .iPhone14Plus:
        defaultOffset = 6.0
    case .iPhone14Pro, .iPhone15, .iPhone15Pro, .iPhone16:
        defaultOffset = 18.0
    case .iPhone14ProMax, .iPhone15Plus, .iPhone15ProMax, .iPhone16Plus:
        defaultOffset = 19.0
    case .iPhone16Pro, .iPhone17, .iPhone17Pro:
        defaultOffset = 21.0
    case .iPhone16ProMax, .iPhone17ProMax, .iPhoneAir:
        defaultOffset = 22.0
    default:
        let topInset = window.safeAreaInsets.top
        return topInset > 0.0 ? pampGramFloorToScreenPixels(topInset * 0.4) : 11.0
    }
    // Compensates for Settings → Display & Brightness → "Larger Text"/zoomed display modes,
    // where UIScreen.main.scale and .nativeScale diverge — same reasoning as Swiftgram's own
    // `sgScaleFactor`.
    let scaleFactor = UIScreen.main.scale / UIScreen.main.nativeScale
    return pampGramFloorToScreenPixels(defaultOffset * scaleFactor)
}

private final class PampGramStatusBadgeView: UIView {
    private let gradientLayer = CAGradientLayer()
    private let iconView = UIImageView()
    private let label = UILabel()
    private let realImageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.isUserInteractionEnabled = false
        self.isHidden = true
        self.clipsToBounds = true

        self.gradientLayer.startPoint = CGPoint(x: 0.0, y: 0.5)
        self.gradientLayer.endPoint = CGPoint(x: 1.0, y: 0.5)
        self.layer.addSublayer(self.gradientLayer)

        self.iconView.contentMode = .scaleAspectFit
        self.iconView.tintColor = .white
        self.addSubview(self.iconView)

        self.label.font = UIFont.systemFont(ofSize: 13.0, weight: .heavy)
        self.label.textColor = .white
        self.addSubview(self.label)

        self.realImageView.contentMode = .scaleAspectFit
        self.addSubview(self.realImageView)
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
            // The actual "TELEGRAM" badge image Telegram's own stock code ships and draws
            // (`submodules/TelegramUI/Images.xcassets/Components/AppBadge.imageset` — the same
            // file `WindowContent.swift`'s own badge uses) — confirmed by actually opening the
            // PNG, not assumed. A previous version of this code had this swapped with
            // `.swiftgram` below, despite both cases already being correctly *named* for what
            // they should show.
            self.isHidden = false
            self.gradientLayer.isHidden = true
            self.iconView.isHidden = true
            self.iconView.image = nil
            self.label.isHidden = true
            self.realImageView.isHidden = false
            self.realImageView.image = UIImage(bundleImageName: "Components/AppBadge")
        case .swiftgram:
            // Colors and gradient direction sampled directly from the user's reference
            // screenshot (dark red-orange at the bottom-left corner, lighter amber-orange at
            // the top-right) rather than approximated — no real "Swiftgram" badge asset exists
            // in this codebase to source instead.
            self.isHidden = false
            self.realImageView.image = nil
            self.realImageView.isHidden = true
            self.gradientLayer.isHidden = false
            self.gradientLayer.startPoint = CGPoint(x: 0.0, y: 1.0)
            self.gradientLayer.endPoint = CGPoint(x: 1.0, y: 0.0)
            self.gradientLayer.colors = [UIColor(rgb: 0xee3e22).cgColor, UIColor(rgb: 0xf78147).cgColor]
            self.iconView.isHidden = false
            self.iconView.image = UIImage(systemName: "bolt.fill")
            self.label.isHidden = false
            self.label.text = "SWIFTGRAM"
        }
        self.sizeAndLayout()
    }

    private func sizeAndLayout() {
        if !self.realImageView.isHidden, let image = self.realImageView.image {
            let center = self.center
            self.bounds = CGRect(origin: .zero, size: image.size)
            self.center = center
            self.layer.cornerRadius = 0.0
            self.gradientLayer.frame = .zero
            self.realImageView.frame = self.bounds
            return
        }

        self.label.sizeToFit()
        let hasIcon = self.iconView.image != nil
        let iconSide: CGFloat = 13.0
        let spacing: CGFloat = 5.0
        let horizontalPadding: CGFloat = 13.0
        let height: CGFloat = 24.0
        let contentWidth = self.label.frame.width + (hasIcon ? iconSide + spacing : 0.0)
        let width = contentWidth + horizontalPadding * 2.0

        let center = self.center
        self.bounds = CGRect(x: 0.0, y: 0.0, width: width, height: height)
        self.center = center
        self.layer.cornerRadius = height / 2.0
        self.gradientLayer.frame = self.bounds
        self.realImageView.frame = .zero

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
/// anywhere else. Horizontally centered on the screen (the notch/Dynamic Island always is too,
/// on every device); vertically placed just below it, using `pampGramBadgeTopOffset` — a value
/// calibrated per device model rather than a one-size-fits-all fraction of the safe area, so the
/// badge sits in the same clean spot below the island on an iPhone 13 as it does on an iPhone 17
/// Pro, instead of overlapping or ending up oddly far from it on whichever devices the old
/// one-size formula wasn't tuned for. Call once, right after `window.makeKeyAndVisible()` in
/// AppDelegate.swift, same spot as `pampGramPresentOnboardingIfNeeded`.
public func pampGramInstallStatusBadgeOverlay(on window: UIWindow) {
    let badge = PampGramStatusBadgeView(frame: .zero)
    window.addSubview(badge)

    func reposition() {
        let topOffset = pampGramBadgeTopOffset(window: window)
        let x = pampGramFloorToScreenPixels((window.bounds.width - badge.bounds.width) / 2.0)
        badge.frame = CGRect(x: x, y: topOffset, width: badge.bounds.width, height: badge.bounds.height)
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
