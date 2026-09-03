import Foundation
import UIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import AccountContext
import PampGramCore

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

    // Top-right "double-click the side button" callout (Face ID devices only).
    private let calloutContainer = UIView()
    private let calloutLabel = UILabel()
    private let calloutChevrons = UIImageView()

    // The whole middle content block (icon → name → developer → "Встроенная покупка" → card),
    // centred between the header and the footer.
    private let contentStack = UIStackView()
    private let iconView = UIView()
    private let iconGradient = CAGradientLayer()
    private let planeView = UIImageView()

    // Biometric footer: glyph + prompt, replaced by the spinner / checkmark / error indicator.
    private let footerContainer = UIView()
    private let footerGlyph = UIImageView()
    private let footerLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let resultIcon = UIImageView()

    private let sheetBackground = UIColor(red: 0xed/255.0, green: 0xec/255.0, blue: 0xf2/255.0, alpha: 1.0)
    private let sheetPrimary = UIColor(white: 0.02, alpha: 1.0)
    private let sheetSecondary = UIColor(white: 0.44, alpha: 1.0)
    private let successGreen = UIColor(red: 0x0a/255.0, green: 0x84/255.0, blue: 0xff/255.0, alpha: 1.0)
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
        self.dimView.backgroundColor = UIColor.black.withAlphaComponent(0.32)
        self.view.addSubview(self.dimView)

        // The light "App Store" sheet.
        self.sheet.backgroundColor = self.sheetBackground
        self.sheet.layer.cornerRadius = 39.0
        self.sheet.layer.cornerCurve = .continuous
        self.sheet.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        self.sheet.clipsToBounds = true
        self.view.addSubview(self.sheet)

        // Header: circular close button + centered "App Store" title.
        let closeButton = UIButton(type: .system)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.backgroundColor = UIColor(white: 1.0, alpha: 1.0)
        closeButton.layer.cornerRadius = 26.0
        closeButton.tintColor = UIColor(white: 0.1, alpha: 1.0)
        let closeConfig = UIImage.SymbolConfiguration(pointSize: 17.0, weight: .semibold)
        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: closeConfig), for: .normal)
        closeButton.addTarget(self, action: #selector(self.cancelTapped), for: .touchUpInside)
        self.sheet.addSubview(closeButton)

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "App Store"
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.systemFont(ofSize: 22.0, weight: .bold)
        titleLabel.textColor = self.sheetPrimary
        self.sheet.addSubview(titleLabel)

        // App icon: a Telegram-style blue squircle with a white paper plane.
        self.iconView.translatesAutoresizingMaskIntoConstraints = false
        self.iconView.layer.cornerRadius = 30.0
        self.iconView.layer.cornerCurve = .continuous
        self.iconView.clipsToBounds = true
        self.iconGradient.colors = [self.telegramBlueTop.cgColor, self.telegramBlueBottom.cgColor]
        self.iconGradient.startPoint = CGPoint(x: 0.5, y: 0.0)
        self.iconGradient.endPoint = CGPoint(x: 0.5, y: 1.0)
        self.iconView.layer.addSublayer(self.iconGradient)
        self.planeView.translatesAutoresizingMaskIntoConstraints = false
        self.planeView.contentMode = .scaleAspectFit
        self.planeView.tintColor = .white
        let planeConfig = UIImage.SymbolConfiguration(pointSize: 52.0, weight: .medium)
        self.planeView.image = UIImage(systemName: "paperplane.fill", withConfiguration: planeConfig)
        self.iconView.addSubview(self.planeView)

        let nameLabel = UILabel()
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.text = "Telegram"
        nameLabel.textAlignment = .center
        nameLabel.font = UIFont.systemFont(ofSize: 22.0, weight: .bold)
        nameLabel.textColor = self.sheetPrimary

        let developerLabel = UILabel()
        developerLabel.translatesAutoresizingMaskIntoConstraints = false
        developerLabel.text = "Telegram FZ-LLC"
        developerLabel.textAlignment = .center
        developerLabel.font = UIFont.systemFont(ofSize: 16.0, weight: .regular)
        developerLabel.textColor = self.sheetSecondary

        let purchasesLabel = UILabel()
        purchasesLabel.translatesAutoresizingMaskIntoConstraints = false
        purchasesLabel.text = "Встроенная покупка"
        purchasesLabel.textAlignment = .center
        purchasesLabel.font = UIFont.systemFont(ofSize: 16.0, weight: .regular)
        purchasesLabel.textColor = self.sheetSecondary

        // White purchase card: product line + hairline + price line.
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .white
        card.layer.cornerRadius = 18.0
        card.layer.cornerCurve = .continuous

        let cardTitle = UILabel()
        cardTitle.translatesAutoresizingMaskIntoConstraints = false
        cardTitle.text = "\(self.count) звёзд"
        cardTitle.font = UIFont.systemFont(ofSize: 19.0, weight: .semibold)
        cardTitle.textColor = self.sheetPrimary
        card.addSubview(cardTitle)

        let cardSeparator = UIView()
        cardSeparator.translatesAutoresizingMaskIntoConstraints = false
        cardSeparator.backgroundColor = UIColor(white: 0.0, alpha: 0.08)
        card.addSubview(cardSeparator)

        let cardDetailLeft = UILabel()
        cardDetailLeft.translatesAutoresizingMaskIntoConstraints = false
        cardDetailLeft.text = "Telegram Stars"
        cardDetailLeft.font = UIFont.systemFont(ofSize: 16.0, weight: .regular)
        cardDetailLeft.textColor = self.sheetSecondary
        card.addSubview(cardDetailLeft)

        let cardDetailRight = UILabel()
        cardDetailRight.translatesAutoresizingMaskIntoConstraints = false
        cardDetailRight.text = self.priceText
        cardDetailRight.font = UIFont.systemFont(ofSize: 16.0, weight: .semibold)
        cardDetailRight.textColor = self.sheetPrimary
        cardDetailRight.textAlignment = .right
        cardDetailRight.setContentHuggingPriority(.required, for: .horizontal)
        cardDetailRight.setContentCompressionResistancePriority(.required, for: .horizontal)
        card.addSubview(cardDetailRight)

        // Centered content block between header and footer.
        self.contentStack.translatesAutoresizingMaskIntoConstraints = false
        self.contentStack.axis = .vertical
        self.contentStack.alignment = .fill
        self.contentStack.spacing = 0.0
        self.sheet.addSubview(self.contentStack)

        let iconRow = UIView()
        iconRow.translatesAutoresizingMaskIntoConstraints = false
        iconRow.addSubview(self.iconView)
        NSLayoutConstraint.activate([
            self.iconView.centerXAnchor.constraint(equalTo: iconRow.centerXAnchor),
            self.iconView.topAnchor.constraint(equalTo: iconRow.topAnchor),
            self.iconView.bottomAnchor.constraint(equalTo: iconRow.bottomAnchor),
            self.iconView.widthAnchor.constraint(equalToConstant: 96.0),
            self.iconView.heightAnchor.constraint(equalToConstant: 96.0),
            self.planeView.centerXAnchor.constraint(equalTo: self.iconView.centerXAnchor, constant: -1.0),
            self.planeView.centerYAnchor.constraint(equalTo: self.iconView.centerYAnchor)
        ])

        self.contentStack.addArrangedSubview(iconRow)
        self.contentStack.setCustomSpacing(16.0, after: iconRow)
        self.contentStack.addArrangedSubview(nameLabel)
        self.contentStack.setCustomSpacing(4.0, after: nameLabel)
        self.contentStack.addArrangedSubview(developerLabel)
        self.contentStack.setCustomSpacing(2.0, after: developerLabel)
        self.contentStack.addArrangedSubview(purchasesLabel)
        self.contentStack.setCustomSpacing(26.0, after: purchasesLabel)
        self.contentStack.addArrangedSubview(card)

        // Biometric footer.
        self.footerContainer.translatesAutoresizingMaskIntoConstraints = false
        self.sheet.addSubview(self.footerContainer)
        self.footerGlyph.translatesAutoresizingMaskIntoConstraints = false
        self.footerGlyph.contentMode = .scaleAspectFit
        self.footerContainer.addSubview(self.footerGlyph)
        self.spinner.translatesAutoresizingMaskIntoConstraints = false
        self.spinner.hidesWhenStopped = true
        self.spinner.color = self.sheetSecondary
        self.footerContainer.addSubview(self.spinner)
        self.resultIcon.translatesAutoresizingMaskIntoConstraints = false
        self.resultIcon.contentMode = .scaleAspectFit
        self.resultIcon.isHidden = true
        self.footerContainer.addSubview(self.resultIcon)
        self.footerLabel.translatesAutoresizingMaskIntoConstraints = false
        self.footerLabel.numberOfLines = 2
        self.footerLabel.textAlignment = .center
        self.footerLabel.font = UIFont.systemFont(ofSize: 16.0, weight: .medium)
        self.footerLabel.textColor = self.sheetPrimary
        self.footerContainer.addSubview(self.footerLabel)

        // Top-right side-button callout (shown for Face ID devices in animateIn()).
        self.calloutContainer.alpha = 0.0
        self.view.addSubview(self.calloutContainer)
        self.calloutLabel.text = "Дважды нажмите\nбоковую кнопку"
        self.calloutLabel.numberOfLines = 2
        self.calloutLabel.textAlignment = .right
        self.calloutLabel.textColor = .white
        self.calloutLabel.font = UIFont.systemFont(ofSize: 19.0, weight: .semibold)
        self.calloutLabel.translatesAutoresizingMaskIntoConstraints = false
        self.calloutContainer.addSubview(self.calloutLabel)
        self.calloutChevrons.translatesAutoresizingMaskIntoConstraints = false
        self.calloutChevrons.contentMode = .scaleAspectFit
        self.calloutChevrons.tintColor = .white
        let chevronConfig = UIImage.SymbolConfiguration(pointSize: 26.0, weight: .bold)
        self.calloutChevrons.image = UIImage(systemName: "chevron.compact.right", withConfiguration: chevronConfig)
        self.calloutContainer.addSubview(self.calloutChevrons)

        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: self.sheet.leadingAnchor, constant: 22.0),
            closeButton.topAnchor.constraint(equalTo: self.sheet.topAnchor, constant: 20.0),
            closeButton.widthAnchor.constraint(equalToConstant: 52.0),
            closeButton.heightAnchor.constraint(equalToConstant: 52.0),
            titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: self.sheet.centerXAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: closeButton.trailingAnchor, constant: 8.0),

            self.contentStack.leadingAnchor.constraint(equalTo: self.sheet.leadingAnchor, constant: 20.0),
            self.contentStack.trailingAnchor.constraint(equalTo: self.sheet.trailingAnchor, constant: -20.0),
            self.contentStack.topAnchor.constraint(greaterThanOrEqualTo: closeButton.bottomAnchor, constant: 12.0),

            card.leadingAnchor.constraint(equalTo: self.contentStack.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: self.contentStack.trailingAnchor),
            card.heightAnchor.constraint(equalToConstant: 92.0),
            cardTitle.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18.0),
            cardTitle.topAnchor.constraint(equalTo: card.topAnchor, constant: 16.0),
            cardTitle.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18.0),
            cardSeparator.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18.0),
            cardSeparator.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18.0),
            cardSeparator.topAnchor.constraint(equalTo: cardTitle.bottomAnchor, constant: 12.0),
            cardSeparator.heightAnchor.constraint(equalToConstant: 1.0),
            cardDetailLeft.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18.0),
            cardDetailLeft.topAnchor.constraint(equalTo: cardSeparator.bottomAnchor, constant: 12.0),
            cardDetailRight.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18.0),
            cardDetailRight.centerYAnchor.constraint(equalTo: cardDetailLeft.centerYAnchor),
            cardDetailRight.leadingAnchor.constraint(greaterThanOrEqualTo: cardDetailLeft.trailingAnchor, constant: 8.0),

            self.footerContainer.centerXAnchor.constraint(equalTo: self.sheet.centerXAnchor),
            self.footerContainer.leadingAnchor.constraint(greaterThanOrEqualTo: self.sheet.leadingAnchor, constant: 20.0),
            self.footerContainer.trailingAnchor.constraint(lessThanOrEqualTo: self.sheet.trailingAnchor, constant: -20.0),
            self.footerContainer.topAnchor.constraint(greaterThanOrEqualTo: self.contentStack.bottomAnchor, constant: 20.0),

            self.footerGlyph.leadingAnchor.constraint(equalTo: self.footerContainer.leadingAnchor),
            self.footerGlyph.centerYAnchor.constraint(equalTo: self.footerContainer.centerYAnchor),
            self.footerGlyph.widthAnchor.constraint(equalToConstant: 30.0),
            self.footerGlyph.heightAnchor.constraint(equalToConstant: 30.0),
            self.spinner.centerXAnchor.constraint(equalTo: self.footerGlyph.centerXAnchor),
            self.spinner.centerYAnchor.constraint(equalTo: self.footerGlyph.centerYAnchor),
            self.resultIcon.centerXAnchor.constraint(equalTo: self.footerGlyph.centerXAnchor),
            self.resultIcon.centerYAnchor.constraint(equalTo: self.footerGlyph.centerYAnchor),
            self.resultIcon.widthAnchor.constraint(equalToConstant: 30.0),
            self.resultIcon.heightAnchor.constraint(equalToConstant: 30.0),
            self.footerLabel.leadingAnchor.constraint(equalTo: self.footerGlyph.trailingAnchor, constant: 10.0),
            self.footerLabel.trailingAnchor.constraint(equalTo: self.footerContainer.trailingAnchor),
            self.footerLabel.topAnchor.constraint(equalTo: self.footerContainer.topAnchor),
            self.footerLabel.bottomAnchor.constraint(equalTo: self.footerContainer.bottomAnchor),

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
        let glyphConfig = UIImage.SymbolConfiguration(pointSize: 25.0, weight: .regular)
        if self.isFaceID {
            self.footerGlyph.image = UIImage(systemName: "faceid", withConfiguration: glyphConfig)
            self.footerGlyph.tintColor = self.sheetPrimary
            self.footerLabel.text = "Подтвердите\nбоковой кнопкой"
        } else {
            self.footerGlyph.image = UIImage(systemName: "touchid", withConfiguration: glyphConfig)
            self.footerGlyph.tintColor = self.sheetPrimary
            self.footerLabel.text = "Оплатите\nс помощью Touch ID"
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Face ID devices have a notch / Dynamic Island → a large top safe-area inset.
        let topInset = self.view.safeAreaInsets.top
        let faceID = topInset > 24.0
        if faceID != self.isFaceID {
            self.isFaceID = faceID
            self.applyBiometryPrompt()
        }

        let width = self.view.bounds.width
        let height = self.view.bounds.height
        let sheetHeight = min(max(height * 0.62, 520.0), height - self.view.safeAreaInsets.top - 8.0)
        // The extra 60pt keeps the bottom rounded corners off-screen below the home indicator.
        self.sheet.frame = CGRect(x: 0.0, y: height - sheetHeight, width: width, height: sheetHeight + 60.0)
        self.iconGradient.frame = self.iconView.bounds

        // Position the side-button callout at the side-button height on the right edge.
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

        // The side-button prompt only exists on Face ID devices; on Touch ID the footer already
        // shows the fingerprint prompt and there is no side button to point at.
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
        self.footerLabel.textColor = self.sheetSecondary

        self.attemptPayment({ [weak self] success in
            guard let self else {
                return
            }
            // A short beat so the spinner reads as "processing".
            Queue.mainQueue().after(0.6, {
                self.spinner.stopAnimating()
                let resultConfig = UIImage.SymbolConfiguration(pointSize: 30.0, weight: .regular)
                if success {
                    self.resultIcon.image = UIImage(systemName: "checkmark.circle", withConfiguration: resultConfig)
                    self.resultIcon.tintColor = self.successGreen
                    self.resultIcon.isHidden = false
                    self.footerLabel.text = "Готово"
                    self.footerLabel.textColor = self.sheetPrimary
                    Queue.mainQueue().after(0.9, {
                        self.onSuccess()
                        self.close()
                    })
                } else {
                    self.resultIcon.image = UIImage(systemName: "xmark.circle", withConfiguration: resultConfig)
                    self.resultIcon.tintColor = self.errorRed
                    self.resultIcon.isHidden = false
                    self.footerLabel.text = "Платёж не выполнен.\nНедостаточно средств"
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
