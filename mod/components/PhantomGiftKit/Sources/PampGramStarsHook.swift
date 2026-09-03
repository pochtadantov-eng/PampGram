import Foundation
import UIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import AccountContext
import PampGramCore

/// The visual system-style payment confirmation shown when a star package is tapped on Telegram's
/// real "Купить звёзды" screen. Nothing here talks to StoreKit or the network: the real
/// `StarsPurchaseScreen.buy(product:)` is intercepted (see the telegram-ios.patch hunk), this
/// look-alike App Store / side-button sheet is shown as a presented view controller, and on a
/// double-tap anywhere the local fake Stars balance is credited (0 ₽, no money, no server).
///
/// The sheet mimics iOS's "double-click the side button to confirm" prompt, but a real side-button
/// confirmation is handled by iOS in a separate secure process and cannot be summoned, detected, or
/// intercepted by an app (a single side-button press just locks the device). So the actual
/// confirmation gesture is a double-tap on the screen.
public enum PampGramStarsHook {
    public static func presentFakeApplePay(context: AccountContext, count: Int64, priceText: String, onCancel: @escaping () -> Void, onConfirm: @escaping () -> Void) {
        Queue.mainQueue().async {
            guard let presenter = self.topViewController() else {
                onCancel()
                return
            }
            let controller = PampGramStarsPaymentSheetController(count: count, priceText: priceText, onCancel: {
                onCancel()
            }, onConfirm: {
                self.credit(context: context, count: count)
                onConfirm()
            })
            controller.modalPresentationStyle = .overFullScreen
            controller.modalTransitionStyle = .crossDissolve
            presenter.present(controller, animated: false, completion: {
                controller.animateIn()
            })
        }
    }

    /// Credits the local fake Stars balance, logs a ledger top-up, and drops the native
    /// star-topup plaque into the Telegram service chat — the same result a real purchase has,
    /// but entirely local and with a 0 ₽ charge.
    public static func credit(context: AccountContext, count: Int64) {
        let _ = context.account.postbox.transaction { transaction -> Void in
            var balanceAfter: Int64 = 0
            PampGramCore.updateSettings(transaction: transaction, { settings in
                var settings = settings
                settings.fakeStarsBalance += count
                balanceAfter = settings.fakeStarsBalance
                return settings
            })
            PampGramLocalLedgerStore.add(transaction: transaction, operation: PampGramLocalOperation(
                currency: .stars,
                kind: .topUp,
                amount: count,
                title: "Пополнение Stars",
                details: "Покупка звёзд Telegram",
                balanceAfter: balanceAfter
            ))
        }.start()
        let _ = PampGramPhantomGiftMessage.insertLocalStarsTopUpMessage(context: context, starCount: count, fiatKopecks: 0).start()
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
    private let onCancel: () -> Void
    private let onConfirm: () -> Void
    private var finished = false

    private let dimView = UIView()
    private let hintLabel = UILabel()
    private let pointerLine = UIView()
    private let sheet = UIView()

    private let confirmIcon = UIImageView()
    private let confirmLabel = UILabel()

    private let sheetPrimary = UIColor(white: 0.04, alpha: 1.0)
    private let sheetSecondary = UIColor(white: 0.45, alpha: 1.0)
    private let accentBlue = UIColor(red: 0x0a/255.0, green: 0x84/255.0, blue: 0xff/255.0, alpha: 1.0)
    private let starGold = UIColor(red: 0xf5/255.0, green: 0xb2/255.0, blue: 0x0a/255.0, alpha: 1.0)

    init(count: Int64, priceText: String, onCancel: @escaping () -> Void, onConfirm: @escaping () -> Void) {
        self.count = count
        self.priceText = priceText
        self.onCancel = onCancel
        self.onConfirm = onConfirm
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

        // Floating "double-tap" cue over the dimmed area, pointing at the side button (right edge).
        self.hintLabel.text = "Нажмите дважды,\nчтобы оплатить"
        self.hintLabel.numberOfLines = 2
        self.hintLabel.textAlignment = .right
        self.hintLabel.textColor = .white
        self.hintLabel.font = UIFont.systemFont(ofSize: 24.0, weight: .semibold)
        self.view.addSubview(self.hintLabel)

        self.pointerLine.backgroundColor = .white
        self.pointerLine.layer.cornerRadius = 1.5
        self.view.addSubview(self.pointerLine)

        // The light system-style sheet.
        self.sheet.backgroundColor = UIColor(red: 0xf1/255.0, green: 0xf1/255.0, blue: 0xf6/255.0, alpha: 1.0)
        self.sheet.layer.cornerRadius = 40.0
        self.sheet.layer.cornerCurve = .continuous
        self.sheet.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        self.sheet.clipsToBounds = true
        self.view.addSubview(self.sheet)

        // Top bar: close button + centered title.
        let closeButton = UIButton(type: .system)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.backgroundColor = UIColor(white: 0.86, alpha: 1.0)
        closeButton.layer.cornerRadius = 18.0
        closeButton.tintColor = UIColor(white: 0.2, alpha: 1.0)
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.addTarget(self, action: #selector(self.cancelTapped), for: .touchUpInside)
        self.sheet.addSubview(closeButton)

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Telegram Stars"
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.systemFont(ofSize: 22.0, weight: .bold)
        titleLabel.textColor = self.sheetPrimary
        self.sheet.addSubview(titleLabel)

        // Hero: a gold "app icon"-style tile with a star.
        let hero = UIView()
        hero.translatesAutoresizingMaskIntoConstraints = false
        hero.backgroundColor = self.starGold
        hero.layer.cornerRadius = 30.0
        hero.layer.cornerCurve = .continuous
        let heroStar = UILabel()
        heroStar.translatesAutoresizingMaskIntoConstraints = false
        heroStar.text = "★"
        heroStar.font = UIFont.systemFont(ofSize: 78.0, weight: .bold)
        heroStar.textColor = .white
        heroStar.textAlignment = .center
        hero.addSubview(heroStar)

        let nameLabel = UILabel()
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.text = "\(self.count) звёзд"
        nameLabel.textAlignment = .center
        nameLabel.font = UIFont.systemFont(ofSize: 22.0, weight: .bold)
        nameLabel.textColor = self.sheetPrimary

        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "Telegram"
        subtitleLabel.textAlignment = .center
        subtitleLabel.font = UIFont.systemFont(ofSize: 16.0, weight: .regular)
        subtitleLabel.textColor = self.sheetSecondary

        // White info card: purchase + total.
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .white
        card.layer.cornerRadius = 18.0
        card.layer.cornerCurve = .continuous

        let cardTitle = UILabel()
        cardTitle.translatesAutoresizingMaskIntoConstraints = false
        cardTitle.text = "Покупка Stars"
        cardTitle.font = UIFont.systemFont(ofSize: 19.0, weight: .semibold)
        cardTitle.textColor = self.sheetPrimary
        card.addSubview(cardTitle)

        let cardSeparator = UIView()
        cardSeparator.translatesAutoresizingMaskIntoConstraints = false
        cardSeparator.backgroundColor = UIColor(white: 0.0, alpha: 0.08)
        card.addSubview(cardSeparator)

        let cardDetail = UILabel()
        cardDetail.translatesAutoresizingMaskIntoConstraints = false
        cardDetail.text = "\(self.count) звёзд · \(self.priceText)"
        cardDetail.font = UIFont.systemFont(ofSize: 16.0, weight: .regular)
        cardDetail.textColor = self.sheetSecondary
        card.addSubview(cardDetail)

        self.sheet.addSubview(hero)
        self.sheet.addSubview(nameLabel)
        self.sheet.addSubview(subtitleLabel)
        self.sheet.addSubview(card)

        // Bottom confirm row: side-button cue + label (swaps to a checkmark on success).
        let confirmRow = UIView()
        confirmRow.translatesAutoresizingMaskIntoConstraints = false
        self.confirmIcon.translatesAutoresizingMaskIntoConstraints = false
        self.confirmIcon.contentMode = .scaleAspectFit
        self.confirmIcon.tintColor = self.accentBlue
        self.confirmIcon.image = UIImage(systemName: "arrow.left.circle.fill")
        confirmRow.addSubview(self.confirmIcon)
        self.confirmLabel.translatesAutoresizingMaskIntoConstraints = false
        self.confirmLabel.text = "Подтвердите боковой кнопкой"
        self.confirmLabel.font = UIFont.systemFont(ofSize: 18.0, weight: .semibold)
        self.confirmLabel.textColor = self.sheetPrimary
        confirmRow.addSubview(self.confirmLabel)
        self.sheet.addSubview(confirmRow)

        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: self.sheet.leadingAnchor, constant: 20.0),
            closeButton.topAnchor.constraint(equalTo: self.sheet.topAnchor, constant: 18.0),
            closeButton.widthAnchor.constraint(equalToConstant: 36.0),
            closeButton.heightAnchor.constraint(equalToConstant: 36.0),
            titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: self.sheet.centerXAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: closeButton.trailingAnchor, constant: 8.0),

            hero.centerXAnchor.constraint(equalTo: self.sheet.centerXAnchor),
            hero.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 26.0),
            hero.widthAnchor.constraint(equalToConstant: 132.0),
            hero.heightAnchor.constraint(equalToConstant: 132.0),
            heroStar.centerXAnchor.constraint(equalTo: hero.centerXAnchor),
            heroStar.centerYAnchor.constraint(equalTo: hero.centerYAnchor),

            nameLabel.topAnchor.constraint(equalTo: hero.bottomAnchor, constant: 18.0),
            nameLabel.leadingAnchor.constraint(equalTo: self.sheet.leadingAnchor, constant: 24.0),
            nameLabel.trailingAnchor.constraint(equalTo: self.sheet.trailingAnchor, constant: -24.0),

            subtitleLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4.0),
            subtitleLabel.leadingAnchor.constraint(equalTo: self.sheet.leadingAnchor, constant: 24.0),
            subtitleLabel.trailingAnchor.constraint(equalTo: self.sheet.trailingAnchor, constant: -24.0),

            card.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 26.0),
            card.leadingAnchor.constraint(equalTo: self.sheet.leadingAnchor, constant: 20.0),
            card.trailingAnchor.constraint(equalTo: self.sheet.trailingAnchor, constant: -20.0),
            card.heightAnchor.constraint(equalToConstant: 92.0),

            cardTitle.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18.0),
            cardTitle.topAnchor.constraint(equalTo: card.topAnchor, constant: 16.0),
            cardTitle.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18.0),
            cardSeparator.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18.0),
            cardSeparator.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18.0),
            cardSeparator.topAnchor.constraint(equalTo: cardTitle.bottomAnchor, constant: 12.0),
            cardSeparator.heightAnchor.constraint(equalToConstant: 1.0),
            cardDetail.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18.0),
            cardDetail.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18.0),
            cardDetail.topAnchor.constraint(equalTo: cardSeparator.bottomAnchor, constant: 12.0),

            confirmRow.centerXAnchor.constraint(equalTo: self.sheet.centerXAnchor),
            confirmRow.bottomAnchor.constraint(equalTo: self.sheet.bottomAnchor, constant: -34.0),
            self.confirmIcon.leadingAnchor.constraint(equalTo: confirmRow.leadingAnchor),
            self.confirmIcon.centerYAnchor.constraint(equalTo: confirmRow.centerYAnchor),
            self.confirmIcon.widthAnchor.constraint(equalToConstant: 26.0),
            self.confirmIcon.heightAnchor.constraint(equalToConstant: 26.0),
            self.confirmLabel.leadingAnchor.constraint(equalTo: self.confirmIcon.trailingAnchor, constant: 8.0),
            self.confirmLabel.trailingAnchor.constraint(equalTo: confirmRow.trailingAnchor),
            self.confirmLabel.centerYAnchor.constraint(equalTo: confirmRow.centerYAnchor),
            confirmRow.topAnchor.constraint(greaterThanOrEqualTo: card.bottomAnchor, constant: 16.0)
        ])

        // A double-tap anywhere confirms (matches the "press twice" cue); the X button cancels.
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(self.confirmTapped))
        doubleTap.numberOfTapsRequired = 2
        self.view.addGestureRecognizer(doubleTap)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = self.view.bounds.width
        let height = self.view.bounds.height
        let sheetHeight = min(height * 0.72, 660.0)
        self.sheet.frame = CGRect(x: 0.0, y: height - sheetHeight, width: width, height: sheetHeight + 40.0)

        let hintWidth: CGFloat = 300.0
        self.hintLabel.frame = CGRect(x: width - hintWidth - 22.0, y: self.sheet.frame.minY - 130.0, width: hintWidth, height: 66.0)
        self.pointerLine.frame = CGRect(x: width - 5.0, y: self.hintLabel.frame.minY - 6.0, width: 3.0, height: 150.0)
    }

    func animateIn() {
        self.dimView.alpha = 0.0
        self.hintLabel.alpha = 0.0
        self.pointerLine.alpha = 0.0
        self.sheet.transform = CGAffineTransform(translationX: 0.0, y: self.sheet.frame.height)
        UIView.animate(withDuration: 0.32, delay: 0.0, options: [.curveEaseOut], animations: {
            self.dimView.alpha = 1.0
            self.sheet.transform = .identity
        }, completion: nil)
        UIView.animate(withDuration: 0.25, delay: 0.28, options: [.curveEaseOut], animations: {
            self.hintLabel.alpha = 1.0
            self.pointerLine.alpha = 0.9
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

        UIView.animate(withDuration: 0.2, animations: {
            self.hintLabel.alpha = 0.0
            self.pointerLine.alpha = 0.0
        })
        self.confirmIcon.image = UIImage(systemName: "checkmark.circle.fill")
        self.confirmIcon.tintColor = UIColor(red: 0x34/255.0, green: 0xc7/255.0, blue: 0x59/255.0, alpha: 1.0)
        self.confirmLabel.text = "Готово"
        self.confirmLabel.textColor = self.sheetPrimary

        Queue.mainQueue().after(0.9, {
            self.onConfirm()
            self.close()
        })
    }

    private func close() {
        UIView.animate(withDuration: 0.25, animations: {
            self.hintLabel.alpha = 0.0
            self.pointerLine.alpha = 0.0
            self.dimView.alpha = 0.0
            self.sheet.transform = CGAffineTransform(translationX: 0.0, y: self.sheet.frame.height)
        }, completion: { _ in
            self.dismiss(animated: false, completion: nil)
        })
    }
}
