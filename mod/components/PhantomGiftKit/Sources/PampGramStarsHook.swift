import Foundation
import UIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import AccountContext
import PampGramCore

/// The visual "Apple Pay" confirmation used when a star package is tapped on Telegram's real
/// "Купить звёзды" screen. Nothing here talks to StoreKit or the network: the real
/// `StarsPurchaseScreen.buy(product:)` is intercepted (see the telegram-ios.patch hunk), this
/// imitation sheet is shown as a presented view controller, and on a double-tap of the card the
/// local fake Stars balance is credited.
///
/// Note: a genuine Apple Pay confirmation uses the physical side button, handled by iOS in a
/// separate secure process — an app cannot summon it, detect it, or intercept it (and a single
/// side-button press just locks the device). So confirmation here is a double-tap of the card.
public enum PampGramStarsHook {
    public static func presentFakeApplePay(context: AccountContext, count: Int64, priceText: String, onCancel: @escaping () -> Void, onConfirm: @escaping () -> Void) {
        Queue.mainQueue().async {
            guard let presenter = self.topViewController() else {
                onCancel()
                return
            }
            let controller = PampGramApplePayViewController(count: count, priceText: priceText, onCancel: {
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

private final class PampGramApplePayViewController: UIViewController {
    private let count: Int64
    private let priceText: String
    private let onCancel: () -> Void
    private let onConfirm: () -> Void
    private var finished = false

    private let dimView = UIView()
    private let card = UIView()
    private let contentStack = UIStackView()
    private let hintLabel = UILabel()
    private let sideButton = UIView()

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
        self.dimView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        self.view.addSubview(self.dimView)
        self.dimView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.cancelTapped)))

        // Side-button hint (right screen edge) — imitates Apple's "confirm with side button" cue.
        self.sideButton.backgroundColor = UIColor.white.withAlphaComponent(0.9)
        self.sideButton.layer.cornerRadius = 3.0
        self.view.addSubview(self.sideButton)

        self.card.backgroundColor = UIColor(red: 0x1c/255.0, green: 0x1c/255.0, blue: 0x1e/255.0, alpha: 1.0)
        self.card.layer.cornerRadius = 22.0
        self.card.layer.cornerCurve = .continuous
        self.view.addSubview(self.card)

        let header = UILabel()
        header.attributedText = self.headerText()
        header.textAlignment = .center

        let separator = UIView()
        separator.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 1.0).isActive = true

        let merchantRow = self.row(left: "Telegram", right: "★ \(self.count)", rightBold: true)
        let totalRow = self.row(left: "Итого", right: self.priceText, rightBold: true)

        self.hintLabel.text = "Дважды коснитесь карты,\nчтобы оплатить"
        self.hintLabel.numberOfLines = 2
        self.hintLabel.textAlignment = .center
        self.hintLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        self.hintLabel.font = UIFont.systemFont(ofSize: 13.0, weight: .medium)

        self.contentStack.axis = .vertical
        self.contentStack.spacing = 14.0
        self.contentStack.alignment = .fill
        self.contentStack.translatesAutoresizingMaskIntoConstraints = false
        self.contentStack.addArrangedSubview(header)
        self.contentStack.addArrangedSubview(separator)
        self.contentStack.addArrangedSubview(merchantRow)
        self.contentStack.addArrangedSubview(totalRow)
        self.contentStack.addArrangedSubview(self.hintLabel)
        self.card.addSubview(self.contentStack)

        NSLayoutConstraint.activate([
            self.contentStack.leadingAnchor.constraint(equalTo: self.card.leadingAnchor, constant: 20.0),
            self.contentStack.trailingAnchor.constraint(equalTo: self.card.trailingAnchor, constant: -20.0),
            self.contentStack.topAnchor.constraint(equalTo: self.card.topAnchor, constant: 20.0),
            self.contentStack.bottomAnchor.constraint(equalTo: self.card.bottomAnchor, constant: -20.0)
        ])

        // A single tap or a double tap on the card both confirm — the double-tap matches the
        // "double press" cue, and the single tap keeps it from feeling broken.
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(self.confirmTapped))
        doubleTap.numberOfTapsRequired = 2
        self.card.addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(self.confirmTapped))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        self.card.addGestureRecognizer(singleTap)
        self.card.isUserInteractionEnabled = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let cardWidth = min(self.view.bounds.width - 40.0, 360.0)
        let cardHeight: CGFloat = 220.0
        self.card.frame = CGRect(x: (self.view.bounds.width - cardWidth) / 2.0, y: self.view.bounds.height - cardHeight - self.view.safeAreaInsets.bottom - 24.0, width: cardWidth, height: cardHeight)
        let sideHeight: CGFloat = 92.0
        self.sideButton.frame = CGRect(x: self.view.bounds.width - 4.0, y: self.card.frame.minY + 20.0, width: 4.0, height: sideHeight)
    }

    private func headerText() -> NSAttributedString {
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: "\u{F8FF} Pay", attributes: [
            .font: UIFont.systemFont(ofSize: 22.0, weight: .semibold),
            .foregroundColor: UIColor.white
        ]))
        return result
    }

    private func row(left: String, right: String, rightBold: Bool) -> UIView {
        let container = UIView()
        let l = UILabel()
        l.text = left
        l.textColor = UIColor.white.withAlphaComponent(0.7)
        l.font = UIFont.systemFont(ofSize: 16.0, weight: .regular)
        l.translatesAutoresizingMaskIntoConstraints = false
        let r = UILabel()
        r.text = right
        r.textColor = .white
        r.font = UIFont.systemFont(ofSize: 16.0, weight: rightBold ? .semibold : .regular)
        r.textAlignment = .right
        r.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(l)
        container.addSubview(r)
        NSLayoutConstraint.activate([
            l.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            l.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            r.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            r.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.heightAnchor.constraint(equalToConstant: 24.0)
        ])
        return container
    }

    func animateIn() {
        self.dimView.alpha = 0.0
        self.card.alpha = 0.0
        self.card.transform = CGAffineTransform(translationX: 0.0, y: 40.0)
        UIView.animate(withDuration: 0.25, animations: {
            self.dimView.alpha = 1.0
            self.card.alpha = 1.0
            self.card.transform = .identity
        })
        UIView.animate(withDuration: 0.6, delay: 0.2, options: [.repeat, .autoreverse, .allowUserInteraction], animations: {
            self.sideButton.alpha = 0.3
        })
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
        // Swap the card content for a success checkmark, then close.
        for subview in self.contentStack.arrangedSubviews {
            subview.isHidden = true
        }
        let success = UILabel()
        success.text = "✓ Оплачено"
        success.textAlignment = .center
        success.textColor = UIColor(red: 0x34/255.0, green: 0xc7/255.0, blue: 0x59/255.0, alpha: 1.0)
        success.font = UIFont.systemFont(ofSize: 22.0, weight: .semibold)
        self.contentStack.addArrangedSubview(success)
        self.sideButton.isHidden = true

        Queue.mainQueue().after(0.9, {
            self.onConfirm()
            self.close()
        })
    }

    private func close() {
        UIView.animate(withDuration: 0.2, animations: {
            self.view.alpha = 0.0
        }, completion: { _ in
            self.dismiss(animated: false, completion: nil)
        })
    }
}
