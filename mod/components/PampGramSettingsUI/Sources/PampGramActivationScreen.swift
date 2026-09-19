import Foundation
import UIKit
import Display
import SwiftSignalKit
import AccountContext
import PampGramCore

/// The screen shown instead of the PampGram hub when this account hasn't redeemed an activation
/// key yet (`PampGramSettings.licenseActivated == false`) — a one-time key, handed over by
/// whoever the mod was bought from, ties this copy to this Telegram account server-side (see
/// `server/pampgram-subs-worker/`'s `/keys/redeem`), so the same key can't also unlock a copy of
/// the file someone passed along for free. Plain UIKit presented modally, same reasoning as
/// `PampGramBannedScreen.swift`: this replaces the hub push entirely, no Display `ViewController`
/// contract to satisfy.
private final class PampGramActivationViewController: UIViewController, UITextFieldDelegate {
    private let context: AccountContext
    private let onActivated: () -> Void

    private let iconContainer = UIView()
    private let iconImageView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let fieldContainer = UIView()
    private let textField = UITextField()
    private let errorLabel = UILabel()
    private let activateButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let closeButton = UIButton(type: .system)

    init(context: AccountContext, onActivated: @escaping () -> Void) {
        self.context = context
        self.onActivated = onActivated
        super.init(nibName: nil, bundle: nil)
        self.modalPresentationStyle = .fullScreen
        self.isModalInPresentation = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = UIColor(rgb: 0x0e0e14)

        self.iconContainer.backgroundColor = UIColor(rgb: 0x8e44ec).withAlphaComponent(0.15)
        self.iconContainer.layer.cornerRadius = 44.0
        self.view.addSubview(self.iconContainer)

        self.iconImageView.image = UIImage(systemName: "key.fill")?.withRenderingMode(.alwaysTemplate)
        self.iconImageView.tintColor = UIColor(rgb: 0x8e44ec)
        self.iconImageView.contentMode = .scaleAspectFit
        self.iconContainer.addSubview(self.iconImageView)

        self.titleLabel.text = "Активируй PampGram"
        self.titleLabel.font = UIFont.systemFont(ofSize: 20.0, weight: .semibold)
        self.titleLabel.textColor = .white
        self.titleLabel.textAlignment = .center
        self.titleLabel.numberOfLines = 0
        self.view.addSubview(self.titleLabel)

        self.subtitleLabel.text = "Введи одноразовый ключ активации, который тебе дали при покупке"
        self.subtitleLabel.font = UIFont.systemFont(ofSize: 15.0, weight: .regular)
        self.subtitleLabel.textColor = UIColor(white: 1.0, alpha: 0.6)
        self.subtitleLabel.textAlignment = .center
        self.subtitleLabel.numberOfLines = 0
        self.view.addSubview(self.subtitleLabel)

        self.fieldContainer.backgroundColor = UIColor(white: 1.0, alpha: 0.08)
        self.fieldContainer.layer.cornerRadius = 12.0
        self.view.addSubview(self.fieldContainer)

        self.textField.textColor = .white
        self.textField.font = UIFont.monospacedSystemFont(ofSize: 16.0, weight: .medium)
        self.textField.textAlignment = .center
        self.textField.autocapitalizationType = .allCharacters
        self.textField.autocorrectionType = .no
        self.textField.spellCheckingType = .no
        self.textField.returnKeyType = .go
        self.textField.attributedPlaceholder = NSAttributedString(string: "PMP-XXXXX-XXXXX-XXXXX-XXXXX", attributes: [.foregroundColor: UIColor(white: 1.0, alpha: 0.3)])
        self.textField.delegate = self
        self.textField.addTarget(self, action: #selector(self.textChanged), for: .editingChanged)
        self.fieldContainer.addSubview(self.textField)

        self.errorLabel.font = UIFont.systemFont(ofSize: 13.0, weight: .regular)
        self.errorLabel.textColor = UIColor(rgb: 0xff3b30)
        self.errorLabel.textAlignment = .center
        self.errorLabel.numberOfLines = 0
        self.errorLabel.alpha = 0.0
        self.view.addSubview(self.errorLabel)

        self.activateButton.setTitle("Активировать", for: .normal)
        self.activateButton.setTitleColor(.white, for: .normal)
        self.activateButton.titleLabel?.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        self.activateButton.backgroundColor = UIColor(rgb: 0x8e44ec)
        self.activateButton.layer.cornerRadius = 12.0
        self.activateButton.alpha = 0.4
        self.activateButton.isEnabled = false
        self.activateButton.addTarget(self, action: #selector(self.activatePressed), for: .touchUpInside)
        self.view.addSubview(self.activateButton)

        self.spinner.hidesWhenStopped = true
        self.spinner.color = .white
        self.view.addSubview(self.spinner)

        self.closeButton.setTitle("Закрыть", for: .normal)
        self.closeButton.setTitleColor(UIColor(white: 1.0, alpha: 0.5), for: .normal)
        self.closeButton.titleLabel?.font = UIFont.systemFont(ofSize: 15.0, weight: .regular)
        self.closeButton.addTarget(self, action: #selector(self.closePressed), for: .touchUpInside)
        self.view.addSubview(self.closeButton)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let width = self.view.bounds.width
        let centerY = self.view.bounds.height * 0.36

        let containerSide: CGFloat = 88.0
        self.iconContainer.frame = CGRect(x: (width - containerSide) / 2.0, y: centerY - containerSide - 24.0, width: containerSide, height: containerSide)
        let iconSide: CGFloat = 40.0
        self.iconImageView.frame = CGRect(x: (containerSide - iconSide) / 2.0, y: (containerSide - iconSide) / 2.0, width: iconSide, height: iconSide)

        let textWidth = min(300.0, width - 48.0)
        let titleSize = self.titleLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))
        self.titleLabel.frame = CGRect(x: (width - textWidth) / 2.0, y: self.iconContainer.frame.maxY + 24.0, width: textWidth, height: titleSize.height)

        let subtitleSize = self.subtitleLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))
        self.subtitleLabel.frame = CGRect(x: (width - textWidth) / 2.0, y: self.titleLabel.frame.maxY + 10.0, width: textWidth, height: subtitleSize.height)

        let fieldWidth = min(320.0, width - 40.0)
        self.fieldContainer.frame = CGRect(x: (width - fieldWidth) / 2.0, y: self.subtitleLabel.frame.maxY + 24.0, width: fieldWidth, height: 50.0)
        self.textField.frame = self.fieldContainer.bounds.insetBy(dx: 12.0, dy: 0.0)

        let errorSize = self.errorLabel.sizeThatFits(CGSize(width: fieldWidth, height: .greatestFiniteMagnitude))
        self.errorLabel.frame = CGRect(x: (width - fieldWidth) / 2.0, y: self.fieldContainer.frame.maxY + 10.0, width: fieldWidth, height: errorSize.height)

        let buttonTop = self.errorLabel.frame.maxY + (self.errorLabel.alpha > 0.0 ? 10.0 : 16.0)
        self.activateButton.frame = CGRect(x: (width - fieldWidth) / 2.0, y: buttonTop, width: fieldWidth, height: 50.0)
        self.spinner.center = self.activateButton.center

        self.closeButton.sizeToFit()
        self.closeButton.frame = CGRect(x: (width - self.closeButton.frame.width) / 2.0, y: self.view.bounds.height - self.view.safeAreaInsets.bottom - 44.0, width: self.closeButton.frame.width, height: 30.0)
    }

    @objc private func textChanged() {
        let hasText = !(self.textField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        self.activateButton.alpha = hasText ? 1.0 : 0.4
        self.activateButton.isEnabled = hasText
        self.setError(nil)
    }

    private func setError(_ text: String?) {
        self.errorLabel.text = text
        UIView.animate(withDuration: 0.2) {
            self.errorLabel.alpha = text == nil ? 0.0 : 1.0
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
        }
    }

    private func setLoading(_ loading: Bool) {
        self.activateButton.isEnabled = !loading
        self.activateButton.setTitleColor(loading ? .clear : .white, for: .normal)
        self.textField.isEnabled = !loading
        if loading {
            self.spinner.startAnimating()
        } else {
            self.spinner.stopAnimating()
        }
    }

    @objc private func activatePressed() {
        let key = (self.textField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            return
        }
        self.textField.resignFirstResponder()
        self.setLoading(true)

        let userId = self.context.account.peerId.id._internalGetInt64Value()
        PampGramSubscriptionAPI.redeemKey(key: key, userId: userId) { [weak self] result in
            guard let self else {
                return
            }
            self.setLoading(false)
            switch result {
            case .success:
                let _ = self.context.account.postbox.transaction { transaction in
                    PampGramCore.updateSettings(transaction: transaction, { settings in
                        var settings = settings
                        settings.licenseActivated = true
                        return settings
                    })
                }.start()
                self.onActivated()
                self.dismiss(animated: true, completion: nil)
            case .alreadyUsed:
                self.setError("Этот ключ уже активирован на другом аккаунте.")
            case .invalidKey:
                self.setError("Неверный ключ активации.")
            case .networkError:
                self.setError("Не удалось связаться с сервером. Проверь интернет и попробуй снова.")
            }
        }
    }

    @objc private func closePressed() {
        self.dismiss(animated: true, completion: nil)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.activatePressed()
        return true
    }
}

/// Presents the activation-key screen on top of whatever's currently showing — same entry-point
/// pattern as `pampGramPresentBannedScreen`. `onActivated` lets the caller (the hub screen)
/// react the moment a key is redeemed, without waiting for the next open.
public func pampGramPresentActivationScreen(context: AccountContext, onActivated: @escaping () -> Void) {
    guard let presentingController = (context.sharedContext.mainWindow?.viewController as? NavigationController)?.topViewController else {
        return
    }
    presentingController.present(PampGramActivationViewController(context: context, onActivated: onActivated), animated: true, completion: nil)
}
