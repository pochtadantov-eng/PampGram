import Foundation
import UIKit
import PampGramCore

public final class PampGramFakeCallViewController: UIViewController {
    private let peerName: String
    private let avatarImage: UIImage?

    private let avatarView = UIImageView()
    private let initialLabel = UILabel()
    private let nameLabel = UILabel()
    private let statusLabel = UILabel()
    private let acceptButton = UIButton(type: .custom)
    private let declineButton = UIButton(type: .custom)

    public init(peerName: String, avatarImage: UIImage?) {
        self.peerName = peerName
        self.avatarImage = avatarImage
        super.init(nibName: nil, bundle: nil)
        self.modalPresentationStyle = .overFullScreen
        self.modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        preconditionFailure()
    }

    public override var prefersStatusBarHidden: Bool {
        return true
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = UIColor(red: 0.07, green: 0.09, blue: 0.14, alpha: 1.0)

        self.avatarView.contentMode = .scaleAspectFill
        self.avatarView.clipsToBounds = true
        self.avatarView.layer.cornerRadius = 70.0
        self.avatarView.backgroundColor = UIColor(red: 0.25, green: 0.45, blue: 0.8, alpha: 1.0)
        self.avatarView.image = self.avatarImage
        self.view.addSubview(self.avatarView)

        self.initialLabel.text = String(self.peerName.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
        self.initialLabel.font = UIFont.systemFont(ofSize: 56.0, weight: .medium)
        self.initialLabel.textColor = .white
        self.initialLabel.textAlignment = .center
        self.initialLabel.isHidden = self.avatarImage != nil
        self.avatarView.addSubview(self.initialLabel)

        self.nameLabel.text = self.peerName
        self.nameLabel.font = UIFont.systemFont(ofSize: 30.0, weight: .semibold)
        self.nameLabel.textColor = .white
        self.nameLabel.textAlignment = .center
        self.nameLabel.adjustsFontSizeToFitWidth = true
        self.nameLabel.minimumScaleFactor = 0.6
        self.view.addSubview(self.nameLabel)

        self.statusLabel.font = UIFont.systemFont(ofSize: 17.0)
        self.statusLabel.textColor = UIColor(white: 1.0, alpha: 0.7)
        self.statusLabel.textAlignment = .center
        self.view.addSubview(self.statusLabel)

        self.configure(button: self.declineButton, color: UIColor(red: 0.93, green: 0.26, blue: 0.24, alpha: 1.0), symbol: "phone.down.fill")
        self.declineButton.addTarget(self, action: #selector(self.declinePressed), for: .touchUpInside)
        self.view.addSubview(self.declineButton)

        self.configure(button: self.acceptButton, color: UIColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1.0), symbol: "phone.fill")
        self.acceptButton.addTarget(self, action: #selector(self.acceptPressed), for: .touchUpInside)
        self.view.addSubview(self.acceptButton)

        self.apply(state: PampGramFakeIncomingCallRuntime.shared.state)

        PampGramFakeIncomingCallRuntime.shared.onStateChanged = { [weak self] state, _ in
            DispatchQueue.main.async {
                self?.apply(state: state)
            }
        }
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let width = self.view.bounds.width
        let top = self.view.safeAreaInsets.top
        let bottom = self.view.safeAreaInsets.bottom

        self.avatarView.frame = CGRect(x: (width - 140.0) / 2.0, y: top + 90.0, width: 140.0, height: 140.0)
        self.initialLabel.frame = self.avatarView.bounds
        self.nameLabel.frame = CGRect(x: 24.0, y: self.avatarView.frame.maxY + 28.0, width: width - 48.0, height: 38.0)
        self.statusLabel.frame = CGRect(x: 24.0, y: self.nameLabel.frame.maxY + 6.0, width: width - 48.0, height: 24.0)

        let buttonSize: CGFloat = 72.0
        let y = self.view.bounds.height - bottom - buttonSize - 56.0
        if self.acceptButton.isHidden {
            self.declineButton.frame = CGRect(x: (width - buttonSize) / 2.0, y: y, width: buttonSize, height: buttonSize)
        } else {
            self.declineButton.frame = CGRect(x: width * 0.25 - buttonSize / 2.0, y: y, width: buttonSize, height: buttonSize)
            self.acceptButton.frame = CGRect(x: width * 0.75 - buttonSize / 2.0, y: y, width: buttonSize, height: buttonSize)
        }
    }

    private func configure(button: UIButton, color: UIColor, symbol: String) {
        button.backgroundColor = color
        button.layer.cornerRadius = 36.0
        button.tintColor = .white
        let configuration = UIImage.SymbolConfiguration(pointSize: 28.0, weight: .semibold)
        button.setImage(UIImage(systemName: symbol, withConfiguration: configuration), for: .normal)
    }

    private func apply(state: PampGramFakeIncomingCallRuntime.FakeCallState) {
        switch state {
        case .idle:
            self.finish()
        case .ringing:
            self.statusLabel.text = "Telegram Audio…"
            self.acceptButton.isHidden = false
        case let .active(duration):
            self.statusLabel.text = PampGramFakeIncomingCallRuntime.formatDuration(duration)
            self.acceptButton.isHidden = true
            self.view.setNeedsLayout()
        case .ended:
            self.statusLabel.text = "Звонок завершён"
            self.acceptButton.isHidden = true
            self.view.setNeedsLayout()
        }
    }

    private func finish() {
        PampGramFakeIncomingCallRuntime.shared.onStateChanged = nil
        if self.presentingViewController != nil {
            self.dismiss(animated: true)
        }
    }

    @objc private func acceptPressed() {
        PampGramFakeIncomingCallRuntime.shared.acceptCall()
    }

    @objc private func declinePressed() {
        PampGramFakeIncomingCallRuntime.shared.endCall()
    }
}

public func pampGramPresentFakeCall(peerName: String, from presenter: UIViewController) {
    PampGramFakeIncomingCallRuntime.shared.triggerFakeCall(peerName: peerName, avatarImage: nil)
    presenter.present(PampGramFakeCallViewController(peerName: peerName, avatarImage: nil), animated: true)
}
