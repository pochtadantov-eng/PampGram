import Foundation
import UIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import AccountContext
import PampGramCore

/// A UIColor that resolves to `light` or `dark` depending on the viewer's interface style, so the
/// look-alike sheet matches the real App Store sheet in both themes.
private func pampGramDynamicColor(_ light: UIColor, _ dark: UIColor) -> UIColor {
    if #available(iOS 13.0, *) {
        return UIColor { trait in trait.userInterfaceStyle == .dark ? dark : light }
    }
    return light
}

/// The visual system-style purchase confirmation shown when a star package is tapped on Telegram's
/// real "Купить звёзды" screen. Nothing here talks to StoreKit or the network: the real
/// `StarsPurchaseScreen.buy(product:)` is intercepted (see the telegram-ios.patch hunk), this
/// look-alike App Store in-app-purchase sheet is shown as a presented view controller, and on the
/// confirmation gesture the payment is settled against the *local* ruble wallet (0 real ₽, no
/// StoreKit and no server).
///
/// The sheet is modelled 1:1 on the real iOS App Store IAP sheet (light "App Store" sheet with the
/// app icon, name, developer, "Встроенная покупка", a white purchase card, and a biometric footer
/// that turns into a blue checkmark on success). It adapts to the device: Face ID phones show the
/// "double-click the side button" prompt near the side button, Touch ID phones show the Touch ID
/// prompt instead.
///
/// If the local ruble balance does not cover the package price the sheet shows a payment error and
/// nothing is credited — mirroring a declined charge. If it does, the rubles are debited, the fake
/// Stars balance is credited, and both are logged to the local ledger.
///
/// The real biometric/side-button confirmation is handled by iOS in a separate secure process and
/// cannot be summoned, detected, or intercepted by an app (a single side-button press just locks the
/// device). So the actual confirmation gesture is a double-tap on the screen.
public enum PampGramStarsHook {
    public static func presentFakeApplePay(context: AccountContext, count: Int64, priceText: String, priceKopecks: Int64, onCancel: @escaping () -> Void, onConfirm: @escaping () -> Void) {
        Queue.mainQueue().async {
            guard let presenter = self.topViewController() else {
                onCancel()
                return
            }
            let controller = PampGramStarsPaymentSheetController(count: count, priceText: priceText, attemptPayment: { completion in
                self.attemptPayment(context: context, count: count, priceKopecks: priceKopecks, completion: completion)
            }, onCancel: {
                onCancel()
            }, onSuccess: {
                onConfirm()
            })
            controller.modalPresentationStyle = .overFullScreen
            controller.modalTransitionStyle = .crossDissolve
            presenter.present(controller, animated: false, completion: {
                controller.animateIn()
            })
        }
    }

    /// Settles the purchase against the local ruble wallet. Calls `completion(true)` and credits the
    /// fake Stars balance when the balance covers `priceKopecks` (or the price is unknown / 0), and
    /// `completion(false)` without any change when it does not.
    public static func attemptPayment(context: AccountContext, count: Int64, priceKopecks: Int64, completion: @escaping (Bool) -> Void) {
        let _ = (context.account.postbox.transaction { transaction -> Bool in
            var ok = true
            var starsAfter: Int64 = 0
            var rublesAfter: Int64 = 0
            PampGramCore.updateSettings(transaction: transaction, { settings in
                var settings = settings
                if priceKopecks > 0 && settings.localRublesBalanceKopecks < priceKopecks {
                    ok = false
                    return settings
                }
                if priceKopecks > 0 {
                    settings.localRublesBalanceKopecks -= priceKopecks
                }
                settings.fakeStarsBalance += count
                starsAfter = settings.fakeStarsBalance
                rublesAfter = settings.localRublesBalanceKopecks
                return settings
            })
            if ok {
                if priceKopecks > 0 {
                    PampGramLocalLedgerStore.add(transaction: transaction, operation: PampGramLocalOperation(
                        currency: .rubles,
                        kind: .purchase,
                        amount: priceKopecks,
                        title: "Покупка Stars",
                        details: "\(count) звёзд",
                        balanceAfter: rublesAfter
                    ))
                }
                PampGramLocalLedgerStore.add(transaction: transaction, operation: PampGramLocalOperation(
                    currency: .stars,
                    kind: .topUp,
                    amount: count,
                    title: "Пополнение Stars",
                    details: "Покупка звёзд Telegram",
                    balanceAfter: starsAfter
                ))
            }
            return ok
        }
        |> deliverOnMainQueue).start(next: { ok in
            if ok {
                let _ = PampGramPhantomGiftMessage.insertLocalStarsTopUpMessage(context: context, starCount: count, fiatKopecks: priceKopecks).start()
            }
            completion(ok)
        })
    }

    private static func keyWindow() -> UIWindow? {
        if #available(iOS 13.0, *) {
            for scene in UIApplication.shared.connectedScenes {
                if let windowScene = scene as? UIWindowScene {
                    if let key = windowScene.windows.first(where: { $0.isKeyWindow }) {
                        return key
                    }
                }
            }
        }
        return UIApplication.shared.windows.first(where: { $0.isKeyWindow }) ?? UIApplication.shared.windows.first
    }

    private static func topViewController() -> UIViewController? {
        guard let window = self.keyWindow(), var top = window.rootViewController else {
            return nil
        }
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}

private final class PampGramStarsPaymentSheetController: UIViewController {
    private let count: Int64
    private let priceText: String
    private let attemptPayment: (@escaping (Bool) -> Void) -> Void
    private let onCancel: () -> Void
    private let onSuccess: () -> Void
    private var finished = false
    private var isFaceID = true

    private let dimView = UIView()
    private let sheet = UIView()

    // Top-right "double-click / press the side button" callout (Face ID devices only).
    private let calloutContainer = UIView()
    private let calloutLabel = UILabel()
    private let calloutChevrons = UIImageView()

    private let iconView = UIView()
    private let iconGradient = CAGradientLayer()
    private let planeView = UIImageView()

    // Biometric footer: glyph + prompt, replaced by the spinner / checkmark / error indicator.
    private let footerGlyph = UIImageView()
    private let footerLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let resultIcon = UIImageView()

    // Theme-aware palette (matches the real App Store sheet in both light and dark).
    private let sheetBackground = pampGramDynamicColor(UIColor(red: 0xf2/255.0, green: 0xf2/255.0, blue: 0xf7/255.0, alpha: 1.0), UIColor(red: 0x1c/255.0, green: 0x1c/255.0, blue: 0x1e/255.0, alpha: 1.0))
    private let cardBackground = pampGramDynamicColor(.white, UIColor(red: 0x2c/255.0, green: 0x2c/255.0, blue: 0x2e/255.0, alpha: 1.0))
    private let closeBackground = pampGramDynamicColor(UIColor(red: 0xe3/255.0, green: 0xe3/255.0, blue: 0xe8/255.0, alpha: 1.0), UIColor(red: 0x3a/255.0, green: 0x3a/255.0, blue: 0x3c/255.0, alpha: 1.0))
    private let primaryColor = pampGramDynamicColor(UIColor(white: 0.05, alpha: 1.0), .white)
    private let secondaryColor = pampGramDynamicColor(UIColor(white: 0.55, alpha: 1.0), UIColor(white: 0.62, alpha: 1.0))
    private let separatorColor = pampGramDynamicColor(UIColor(white: 0.0, alpha: 0.10), UIColor(white: 1.0, alpha: 0.14))
    private let accentBlue = UIColor(red: 0x0a/255.0, green: 0x84/255.0, blue: 0xff/255.0, alpha: 1.0)
    private let errorRed = UIColor(red: 0xff/255.0, green: 0x3b/255.0, blue: 0x30/255.0, alpha: 1.0)
    private let telegramBlueTop = UIColor(red: 0x2a/255.0, green: 0xab/255.0, blue: 0xee/255.0, alpha: 1.0)
    private let telegramBlueBottom = UIColor(red: 0x22/255.0, green: 0x9e/255.0, blue: 0xd9/255.0, alpha: 1.0)

    init(count: Int64, priceText: String, attemptPayment: @escaping (@escaping (Bool) -> Void) -> Void, onCancel: @escaping () -> Void, onSuccess: @escaping () -> Void) {
        self.count = count
        self.priceText = priceText
        self.attemptPayment = attemptPayment
        self.onCancel = onCancel
        self.onSuccess = onSuccess
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        self.view = UIView()
        self.view.backgroundColor = .clear
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.dimView.frame = self.view.bounds
        self.dimView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.dimView.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        self.view.addSubview(self.dimView)

        // The "App Store" sheet.
        self.sheet.backgroundColor = self.sheetBackground
        self.sheet.layer.cornerRadius = 12.0
        self.sheet.layer.cornerCurve = .continuous
        self.sheet.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        self.sheet.clipsToBounds = true
        self.view.addSubview(self.sheet)

        // Header: "App Store" (left) + circular close button (right).
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "App Store"
        titleLabel.font = UIFont.systemFont(ofSize: 22.0, weight: .bold)
        titleLabel.textColor = self.primaryColor
        self.sheet.addSubview(titleLabel)

        let closeButton = UIButton(type: .system)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.backgroundColor = self.closeBackground
        closeButton.layer.cornerRadius = 15.0
        closeButton.tintColor = self.secondaryColor
        let closeConfig = UIImage.SymbolConfiguration(pointSize: 14.0, weight: .bold)
        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: closeConfig), for: .normal)
        closeButton.addTarget(self, action: #selector(self.cancelTapped), for: .touchUpInside)
        self.sheet.addSubview(closeButton)

        // App icon: a Telegram-style blue squircle with a white paper plane.
        self.iconView.translatesAutoresizingMaskIntoConstraints = false
        self.iconView.layer.cornerRadius = 13.0
        self.iconView.layer.cornerCurve = .continuous
        self.iconView.clipsToBounds = true
        self.iconGradient.colors = [self.telegramBlueTop.cgColor, self.telegramBlueBottom.cgColor]
        self.iconGradient.startPoint = CGPoint(x: 0.5, y: 0.0)
        self.iconGradient.endPoint = CGPoint(x: 0.5, y: 1.0)
        self.iconView.layer.addSublayer(self.iconGradient)
        self.planeView.translatesAutoresizingMaskIntoConstraints = false
        self.planeView.contentMode = .scaleAspectFit
        self.planeView.tintColor = .white
        let planeConfig = UIImage.SymbolConfiguration(pointSize: 30.0, weight: .medium)
        self.planeView.image = UIImage(systemName: "paperplane.fill", withConfiguration: planeConfig)
        self.iconView.addSubview(self.planeView)
        self.sheet.addSubview(self.iconView)

        // Product line, developer + age badge, "In-App Purchase" — stacked to the right of the icon.
        let productLabel = UILabel()
        productLabel.translatesAutoresizingMaskIntoConstraints = false
        productLabel.text = "\(self.count) Telegram Stars"
        productLabel.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        productLabel.textColor = self.primaryColor
        self.sheet.addSubview(productLabel)

        let developerLabel = UILabel()
        developerLabel.translatesAutoresizingMaskIntoConstraints = false
        developerLabel.text = "Telegram Messenger"
        developerLabel.font = UIFont.systemFont(ofSize: 14.0, weight: .regular)
        developerLabel.textColor = self.secondaryColor
        self.sheet.addSubview(developerLabel)

        let ageBadge = UILabel()
        ageBadge.translatesAutoresizingMaskIntoConstraints = false
        ageBadge.text = " 13+ "
        ageBadge.font = UIFont.systemFont(ofSize: 11.0, weight: .semibold)
        ageBadge.textColor = self.secondaryColor
        ageBadge.layer.borderWidth = 1.0
        ageBadge.layer.borderColor = self.separatorColor.cgColor
        ageBadge.layer.cornerRadius = 4.0
        ageBadge.clipsToBounds = true
        ageBadge.setContentHuggingPriority(.required, for: .horizontal)
        ageBadge.setContentCompressionResistancePriority(.required, for: .horizontal)
        self.sheet.addSubview(ageBadge)

        let purchaseLabel = UILabel()
        purchaseLabel.translatesAutoresizingMaskIntoConstraints = false
        purchaseLabel.text = "In-App Purchase"
        purchaseLabel.font = UIFont.systemFont(ofSize: 14.0, weight: .regular)
        purchaseLabel.textColor = self.secondaryColor
        self.sheet.addSubview(purchaseLabel)

        // Purchase card: price + "One-time charge" + separator + account.
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = self.cardBackground
        card.layer.cornerRadius = 12.0
        card.layer.cornerCurve = .continuous
        self.sheet.addSubview(card)

        let priceLabel = UILabel()
        priceLabel.translatesAutoresizingMaskIntoConstraints = false
        priceLabel.text = self.priceText
        priceLabel.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        priceLabel.textColor = self.primaryColor
        card.addSubview(priceLabel)

        let chargeLabel = UILabel()
        chargeLabel.translatesAutoresizingMaskIntoConstraints = false
        chargeLabel.text = "One-time charge"
        chargeLabel.font = UIFont.systemFont(ofSize: 13.0, weight: .regular)
        chargeLabel.textColor = self.secondaryColor
        card.addSubview(chargeLabel)

        let cardSeparator = UIView()
        cardSeparator.translatesAutoresizingMaskIntoConstraints = false
        cardSeparator.backgroundColor = self.separatorColor
        card.addSubview(cardSeparator)

        let accountLabel = UILabel()
        accountLabel.translatesAutoresizingMaskIntoConstraints = false
        accountLabel.text = "Account: ••••••••"
        accountLabel.font = UIFont.systemFont(ofSize: 15.0, weight: .regular)
        accountLabel.textColor = self.secondaryColor
        card.addSubview(accountLabel)

        // Biometric footer: glyph on top, prompt below (centered).
        self.footerGlyph.translatesAutoresizingMaskIntoConstraints = false
        self.footerGlyph.contentMode = .scaleAspectFit
        self.sheet.addSubview(self.footerGlyph)
        self.spinner.translatesAutoresizingMaskIntoConstraints = false
        self.spinner.hidesWhenStopped = true
        self.spinner.color = self.secondaryColor
        self.sheet.addSubview(self.spinner)
        self.resultIcon.translatesAutoresizingMaskIntoConstraints = false
        self.resultIcon.contentMode = .scaleAspectFit
        self.resultIcon.isHidden = true
        self.sheet.addSubview(self.resultIcon)
        self.footerLabel.translatesAutoresizingMaskIntoConstraints = false
        self.footerLabel.numberOfLines = 1
        self.footerLabel.textAlignment = .center
        self.footerLabel.font = UIFont.systemFont(ofSize: 15.0, weight: .regular)
        self.footerLabel.textColor = self.primaryColor
        self.sheet.addSubview(self.footerLabel)

        // Top-right "press the side button twice" callout (shown for Face ID devices in animateIn()).
        self.calloutContainer.alpha = 0.0
        self.view.addSubview(self.calloutContainer)
        self.calloutLabel.text = "Нажмите дважды\nдля оплаты"
        self.calloutLabel.numberOfLines = 2
        self.calloutLabel.textAlignment = .right
        self.calloutLabel.textColor = .white
        self.calloutLabel.font = UIFont.systemFont(ofSize: 20.0, weight: .semibold)
        self.calloutLabel.translatesAutoresizingMaskIntoConstraints = false
        self.calloutContainer.addSubview(self.calloutLabel)
        self.calloutChevrons.translatesAutoresizingMaskIntoConstraints = false
        self.calloutChevrons.contentMode = .scaleAspectFit
        self.calloutChevrons.tintColor = .white
        let chevronConfig = UIImage.SymbolConfiguration(pointSize: 28.0, weight: .semibold)
        self.calloutChevrons.image = UIImage(systemName: "chevron.compact.right", withConfiguration: chevronConfig)
        self.calloutContainer.addSubview(self.calloutChevrons)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: self.sheet.leadingAnchor, constant: 20.0),
            titleLabel.topAnchor.constraint(equalTo: self.sheet.topAnchor, constant: 20.0),
            closeButton.trailingAnchor.constraint(equalTo: self.sheet.trailingAnchor, constant: -16.0),
            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 30.0),
            closeButton.heightAnchor.constraint(equalToConstant: 30.0),

            self.iconView.leadingAnchor.constraint(equalTo: self.sheet.leadingAnchor, constant: 20.0),
            self.iconView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 22.0),
            self.iconView.widthAnchor.constraint(equalToConstant: 58.0),
            self.iconView.heightAnchor.constraint(equalToConstant: 58.0),
            self.planeView.centerXAnchor.constraint(equalTo: self.iconView.centerXAnchor, constant: -1.0),
            self.planeView.centerYAnchor.constraint(equalTo: self.iconView.centerYAnchor),

            productLabel.leadingAnchor.constraint(equalTo: self.iconView.trailingAnchor, constant: 14.0),
            productLabel.topAnchor.constraint(equalTo: self.iconView.topAnchor, constant: 1.0),
            productLabel.trailingAnchor.constraint(lessThanOrEqualTo: self.sheet.trailingAnchor, constant: -20.0),

            developerLabel.leadingAnchor.constraint(equalTo: productLabel.leadingAnchor),
            developerLabel.topAnchor.constraint(equalTo: productLabel.bottomAnchor, constant: 4.0),
            ageBadge.leadingAnchor.constraint(equalTo: developerLabel.trailingAnchor, constant: 6.0),
            ageBadge.centerYAnchor.constraint(equalTo: developerLabel.centerYAnchor),
            ageBadge.heightAnchor.constraint(equalToConstant: 17.0),
            ageBadge.trailingAnchor.constraint(lessThanOrEqualTo: self.sheet.trailingAnchor, constant: -20.0),

            purchaseLabel.leadingAnchor.constraint(equalTo: productLabel.leadingAnchor),
            purchaseLabel.topAnchor.constraint(equalTo: developerLabel.bottomAnchor, constant: 3.0),

            card.leadingAnchor.constraint(equalTo: self.sheet.leadingAnchor, constant: 20.0),
            card.trailingAnchor.constraint(equalTo: self.sheet.trailingAnchor, constant: -20.0),
            card.topAnchor.constraint(equalTo: self.iconView.bottomAnchor, constant: 22.0),

            priceLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16.0),
            priceLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 14.0),
            chargeLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16.0),
            chargeLabel.topAnchor.constraint(equalTo: priceLabel.bottomAnchor, constant: 2.0),
            cardSeparator.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16.0),
            cardSeparator.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16.0),
            cardSeparator.topAnchor.constraint(equalTo: chargeLabel.bottomAnchor, constant: 12.0),
            cardSeparator.heightAnchor.constraint(equalToConstant: 1.0),
            accountLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16.0),
            accountLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16.0),
            accountLabel.topAnchor.constraint(equalTo: cardSeparator.bottomAnchor, constant: 12.0),
            accountLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14.0),

            self.footerGlyph.centerXAnchor.constraint(equalTo: self.sheet.centerXAnchor),
            self.footerGlyph.widthAnchor.constraint(equalToConstant: 34.0),
            self.footerGlyph.heightAnchor.constraint(equalToConstant: 34.0),
            self.footerGlyph.topAnchor.constraint(greaterThanOrEqualTo: card.bottomAnchor, constant: 20.0),
            self.spinner.centerXAnchor.constraint(equalTo: self.footerGlyph.centerXAnchor),
            self.spinner.centerYAnchor.constraint(equalTo: self.footerGlyph.centerYAnchor),
            self.resultIcon.centerXAnchor.constraint(equalTo: self.footerGlyph.centerXAnchor),
            self.resultIcon.centerYAnchor.constraint(equalTo: self.footerGlyph.centerYAnchor),
            self.resultIcon.widthAnchor.constraint(equalToConstant: 34.0),
            self.resultIcon.heightAnchor.constraint(equalToConstant: 34.0),
            self.footerLabel.topAnchor.constraint(equalTo: self.footerGlyph.bottomAnchor, constant: 8.0),
            self.footerLabel.leadingAnchor.constraint(equalTo: self.sheet.leadingAnchor, constant: 20.0),
            self.footerLabel.trailingAnchor.constraint(equalTo: self.sheet.trailingAnchor, constant: -20.0),
            self.footerLabel.bottomAnchor.constraint(equalTo: self.sheet.bottomAnchor, constant: -96.0),

            self.calloutLabel.topAnchor.constraint(equalTo: self.calloutContainer.topAnchor),
            self.calloutLabel.leadingAnchor.constraint(equalTo: self.calloutContainer.leadingAnchor),
            self.calloutLabel.bottomAnchor.constraint(equalTo: self.calloutContainer.bottomAnchor),
            self.calloutChevrons.leadingAnchor.constraint(equalTo: self.calloutLabel.trailingAnchor, constant: 6.0),
            self.calloutChevrons.trailingAnchor.constraint(equalTo: self.calloutContainer.trailingAnchor),
            self.calloutChevrons.centerYAnchor.constraint(equalTo: self.calloutContainer.centerYAnchor)
        ])

        // A double-tap anywhere confirms (matches the "press twice" cue); the X button cancels.
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(self.confirmTapped))
        doubleTap.numberOfTapsRequired = 2
        self.view.addGestureRecognizer(doubleTap)

        self.applyBiometryPrompt()
    }

    private func applyBiometryPrompt() {
        let glyphConfig = UIImage.SymbolConfiguration(pointSize: 30.0, weight: .regular)
        if self.isFaceID {
            self.footerGlyph.image = UIImage(systemName: "faceid", withConfiguration: glyphConfig)
            self.footerGlyph.tintColor = self.accentBlue
            self.footerLabel.text = "Подтвердите боковой кнопкой"
        } else {
            self.footerGlyph.image = UIImage(systemName: "touchid", withConfiguration: glyphConfig)
            self.footerGlyph.tintColor = self.accentBlue
            self.footerLabel.text = "Оплатите с помощью Touch ID"
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Face ID devices have a notch / Dynamic Island → a large top safe-area inset.
        let faceID = self.view.safeAreaInsets.top > 24.0
        if faceID != self.isFaceID {
            self.isFaceID = faceID
            self.applyBiometryPrompt()
        }

        let width = self.view.bounds.width
        let height = self.view.bounds.height
        let sheetHeight = min(max(height * 0.5, 430.0), height - self.view.safeAreaInsets.top - 8.0)
        // The extra 60pt keeps the bottom rounded corners off-screen below the home indicator.
        self.sheet.frame = CGRect(x: 0.0, y: height - sheetHeight, width: width, height: sheetHeight + 60.0)
        self.iconGradient.frame = self.iconView.bounds

        let calloutWidth: CGFloat = 260.0
        let calloutY = max(self.view.safeAreaInsets.top + 8.0, height * 0.16)
        self.calloutContainer.frame = CGRect(x: width - calloutWidth - 16.0, y: calloutY, width: calloutWidth, height: 60.0)
    }

    func animateIn() {
        self.dimView.alpha = 0.0
        self.sheet.transform = CGAffineTransform(translationX: 0.0, y: self.sheet.frame.height)
        UIView.animate(withDuration: 0.42, delay: 0.0, usingSpringWithDamping: 0.86, initialSpringVelocity: 0.0, options: [.curveEaseOut], animations: {
            self.dimView.alpha = 1.0
            self.sheet.transform = .identity
        }, completion: nil)

        if self.isFaceID {
            self.calloutContainer.transform = CGAffineTransform(translationX: 20.0, y: 0.0)
            UIView.animate(withDuration: 0.3, delay: 0.34, options: [.curveEaseOut], animations: {
                self.calloutContainer.alpha = 1.0
                self.calloutContainer.transform = .identity
            }, completion: { [weak self] _ in
                self?.startChevronPulse()
            })
        }
    }

    private func startChevronPulse() {
        guard !self.finished else {
            return
        }
        UIView.animate(withDuration: 0.55, delay: 0.0, options: [.repeat, .autoreverse, .curveEaseInOut], animations: {
            self.calloutChevrons.transform = CGAffineTransform(translationX: 7.0, y: 0.0)
        }, completion: nil)
    }

    @objc private func cancelTapped() {
        guard !self.finished else {
            return
        }
        self.finished = true
        self.onCancel()
        self.close()
    }

    @objc private func confirmTapped() {
        guard !self.finished else {
            return
        }
        self.finished = true

        self.calloutChevrons.layer.removeAllAnimations()
        UIView.animate(withDuration: 0.2, animations: {
            self.calloutContainer.alpha = 0.0
        })

        // Processing state.
        self.footerGlyph.isHidden = true
        self.spinner.startAnimating()
        self.footerLabel.text = "Оплата…"
        self.footerLabel.textColor = self.secondaryColor

        self.attemptPayment({ [weak self] success in
            guard let self else {
                return
            }
            Queue.mainQueue().after(0.6, {
                self.spinner.stopAnimating()
                let resultConfig = UIImage.SymbolConfiguration(pointSize: 34.0, weight: .regular)
                if success {
                    self.resultIcon.image = UIImage(systemName: "checkmark.circle", withConfiguration: resultConfig)
                    self.resultIcon.tintColor = self.accentBlue
                    self.resultIcon.isHidden = false
                    self.footerLabel.text = "Готово"
                    self.footerLabel.textColor = self.primaryColor
                    Queue.mainQueue().after(0.9, {
                        self.onSuccess()
                        self.close()
                    })
                } else {
                    self.resultIcon.image = UIImage(systemName: "xmark.circle", withConfiguration: resultConfig)
                    self.resultIcon.tintColor = self.errorRed
                    self.resultIcon.isHidden = false
                    self.footerLabel.text = "Платёж не выполнен. Недостаточно средств"
                    self.footerLabel.textColor = self.errorRed
                    Queue.mainQueue().after(1.7, {
                        self.onCancel()
                        self.close()
                    })
                }
            })
        })
    }

    private func close() {
        self.calloutChevrons.layer.removeAllAnimations()
        UIView.animate(withDuration: 0.28, delay: 0.0, options: [.curveEaseIn], animations: {
            self.calloutContainer.alpha = 0.0
            self.dimView.alpha = 0.0
            self.sheet.transform = CGAffineTransform(translationX: 0.0, y: self.sheet.frame.height)
        }, completion: { _ in
            self.dismiss(animated: false, completion: nil)
        })
    }
}
