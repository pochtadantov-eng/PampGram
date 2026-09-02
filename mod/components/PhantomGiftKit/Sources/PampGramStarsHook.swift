import Foundation
import UIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import AccountContext
import PampGramCore

/// The visual "Apple Pay" confirmation used when a star package is tapped on Telegram's real
/// "Пополнить" screen. Nothing here talks to StoreKit or the network: the real
/// `StarsPurchaseScreen.buy(product:)` is intercepted (see the telegram-ios.patch hunk), this
/// imitation sheet is shown, and on a double-tap the local fake Stars balance is credited. The
/// genuine Apple side-button double-press cannot be summoned or intercepted by an app, so this
/// is a look-alike overlay that confirms on a double-tap of the sheet itself.
public enum PampGramStarsHook {
    public static func presentFakeApplePay(context: AccountContext, count: Int64, priceText: String, onCancel: @escaping () -> Void, onConfirm: @escaping () -> Void) {
        Queue.mainQueue().async {
            guard let window = self.keyWindow() else {
                onCancel()
                return
            }
            let overlay = PampGramApplePayOverlayView(frame: window.bounds, count: count, priceText: priceText, onCancel: {
                onCancel()
            }, onConfirm: {
                self.credit(context: context, count: count)
                onConfirm()
            })
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            window.addSubview(overlay)
            overlay.animateIn()
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
}

private final class PampGramApplePayOverlayView: UIView {
    private let onCancel: () -> Void
    private let onConfirm: () -> Void
    private var finished = false

    private let dimView = UIView()
    private let card = UIView()
    private let contentStack = UIStackView()
    private let hintLabel = UILabel()
    private let sideButton = UIView()

    init(frame: CGRect, count: Int64, priceText: String, onCancel: @escaping () -> Void, onConfirm: @escaping () -> Void) {
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        super.init(frame: frame)

        self.dimView.frame = self.bounds
        self.dimView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.dimView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        self.addSubview(self.dimView)
        self.dimView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.cancelTapped)))

        // Side-button hint (right screen edge) — imitates the "double-click side button" cue.
        self.sideButton.backgroundColor = UIColor.white.withAlphaComponent(0.9)
        self.sideButton.layer.cornerRadius = 3.0
        self.addSubview(self.sideButton)

        self.card.backgroundColor = UIColor(red: 0x1c/255.0, green: 0x1c/255.0, blue: 0x1e/255.0, alpha: 1.0)
        self.card.layer.cornerRadius = 22.0
        self.card.layer.cornerCurve = .continuous
        self.addSubview(self.card)

        let header = UILabel()
        header.attributedText = self.headerText()
        header.textAlignment = .center

        let separator = UIView()
        separator.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 1.0).isActive = true

        let merchantRow = self.row(left: "Telegram", right: "★ \(count)", rightBold: true)
        let totalRow = self.row(left: "Итого", right: priceText, rightBold: true)

        self.hintLabel.text = "Дважды нажмите\nбоковую кнопку"
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

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(self.confirmTapped))
        doubleTap.numberOfTapsRequired = 2
        self.card.addGestureRecognizer(doubleTap)
        self.card.isUserInteractionEnabled = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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

    override func layoutSubviews() {
        super.layoutSubviews()
        let cardWidth = min(self.bounds.width - 40.0, 360.0)
        let cardHeight: CGFloat = 220.0
        self.card.frame = CGRect(x: (self.bounds.width - cardWidth) / 2.0, y: self.bounds.height - cardHeight - self.safeBottom() - 24.0, width: cardWidth, height: cardHeight)
        let sideHeight: CGFloat = 92.0
        self.sideButton.frame = CGRect(x: self.bounds.width - 4.0, y: self.card.frame.minY + 20.0, width: 4.0, height: sideHeight)
    }

    private func safeBottom() -> CGFloat {
        if #available(iOS 11.0, *) {
            return self.safeAreaInsets.bottom
        }
        return 0.0
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
        self.finish()
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

    private func finish() {
        guard !self.finished else {
            return
        }
        self.finished = true
        self.onCancel()
        self.close()
    }

    private func close() {
        UIView.animate(withDuration: 0.2, animations: {
            self.alpha = 0.0
        }, completion: { _ in
            self.removeFromSuperview()
        })
    }
}
