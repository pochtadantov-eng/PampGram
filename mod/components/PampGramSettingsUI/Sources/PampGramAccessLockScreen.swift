import Foundation
import UIKit
import PampGramCore

/// The Telegram account customers write to for a key or a renewal. Opened in the regular
/// Telegram app (an https link), not inside this client — the client itself is locked at that
/// point, so a chat opened inside it would sit behind the lock.
private let pampGramAccessContactUsername = "Claps555"

/// What the lock screen says for each reason the app is locked.
private struct PampGramAccessLockContent {
    let title: String
    let body: String
    let showBuy: Bool
    let showActivate: Bool
    let showRetry: Bool
    let showSpinner: Bool
}

private func pampGramAccessLockContent(for kind: PampGramAccessLockKind) -> PampGramAccessLockContent {
    switch kind {
    case .checking:
        return PampGramAccessLockContent(title: "Проверка лицензии", body: "Подождите, проверяем вашу подписку…", showBuy: false, showActivate: false, showRetry: true, showSpinner: true)
    case .needsKey(let expired):
        if expired {
            return PampGramAccessLockContent(title: "Подписка закончилась", body: "Продлите подписку, написав @\(pampGramAccessContactUsername) через обычный Telegram, и активируйте полученный ключ.", showBuy: true, showActivate: true, showRetry: false, showSpinner: false)
        }
        return PampGramAccessLockContent(title: "Нужен ключ", body: "Чтобы пользоваться приложением, активируйте ключ. Купить ключ можно у @\(pampGramAccessContactUsername) в обычном Telegram.", showBuy: true, showActivate: true, showRetry: false, showSpinner: false)
    case .banned(let reason):
        var body = "Вы заблокированы за неправильное выполнение требований и нарушение правил."
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            body += "\n\nПричина: \(trimmed)"
        }
        return PampGramAccessLockContent(title: "Доступ заблокирован", body: body, showBuy: false, showActivate: false, showRetry: false, showSpinner: false)
    case .unreachable:
        return PampGramAccessLockContent(title: "Нет связи с сервером", body: "Подключитесь к интернету, чтобы подтвердить подписку.", showBuy: false, showActivate: false, showRetry: true, showSpinner: false)
    case .clockTampered:
        return PampGramAccessLockContent(title: "Неверное время", body: "Включите автоматическую установку даты и времени и подключитесь к интернету, чтобы подтвердить подписку.", showBuy: false, showActivate: false, showRetry: true, showSpinner: false)
    }
}

private final class PampGramAccessLockViewController: UIViewController {
    private let stack = UIStackView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let buyButton = UIButton(type: .system)
    private let activateButton = UIButton(type: .system)
    private let retryButton = UIButton(type: .system)
    private let idLabel = UILabel()

    private var isRedeeming = false

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = UIColor(red: 0.055, green: 0.055, blue: 0.078, alpha: 1.0)

        self.iconView.image = UIImage(systemName: "lock.fill")
        self.iconView.tintColor = UIColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1.0)
        self.iconView.contentMode = .scaleAspectFit
        self.iconView.heightAnchor.constraint(equalToConstant: 56.0).isActive = true

        self.titleLabel.font = UIFont.systemFont(ofSize: 26.0, weight: .bold)
        self.titleLabel.textColor = .white
        self.titleLabel.textAlignment = .center
        self.titleLabel.numberOfLines = 0

        self.bodyLabel.font = UIFont.systemFont(ofSize: 16.0, weight: .regular)
        self.bodyLabel.textColor = UIColor(white: 1.0, alpha: 0.72)
        self.bodyLabel.textAlignment = .center
        self.bodyLabel.numberOfLines = 0

        self.spinner.color = .white

        self.configure(button: self.buyButton, title: "Купить ключ", filled: true, action: #selector(self.buyPressed))
        self.configure(button: self.activateButton, title: "Активировать ключ", filled: false, action: #selector(self.activatePressed))
        self.configure(button: self.retryButton, title: "Проверить снова", filled: false, action: #selector(self.retryPressed))

        self.idLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 13.0, weight: .regular)
        self.idLabel.textColor = UIColor(white: 1.0, alpha: 0.4)
        self.idLabel.textAlignment = .center

        self.stack.axis = .vertical
        self.stack.alignment = .fill
        self.stack.spacing = 14.0
        self.stack.translatesAutoresizingMaskIntoConstraints = false
        for item in [self.iconView, self.titleLabel, self.bodyLabel, self.spinner, self.buyButton, self.activateButton, self.retryButton, self.idLabel] as [UIView] {
            self.stack.addArrangedSubview(item)
        }
        self.stack.setCustomSpacing(24.0, after: self.bodyLabel)
        self.view.addSubview(self.stack)
        NSLayoutConstraint.activate([
            self.stack.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
            self.stack.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 28.0),
            self.stack.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -28.0)
        ])

        self.refresh()
    }

    private func configure(button: UIButton, title: String, filled: Bool, action: Selector) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        button.backgroundColor = filled ? UIColor(red: 0.557, green: 0.267, blue: 0.925, alpha: 1.0) : UIColor(white: 1.0, alpha: 0.12)
        button.layer.cornerRadius = 14.0
        button.heightAnchor.constraint(equalToConstant: 52.0).isActive = true
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    /// Re-reads the gate and redraws. Called whenever the gate's state changes.
    func refresh() {
        guard self.isViewLoaded else {
            return
        }
        let snapshot = PampGramAccessGate.shared.snapshot
        guard case .locked(let kind) = snapshot.state else {
            return
        }
        let content = pampGramAccessLockContent(for: kind)
        self.titleLabel.text = content.title
        self.bodyLabel.text = content.body
        self.buyButton.isHidden = !content.showBuy
        self.activateButton.isHidden = !content.showActivate
        self.retryButton.isHidden = !content.showRetry
        self.spinner.isHidden = !(content.showSpinner || self.isRedeeming)
        if content.showSpinner || self.isRedeeming {
            self.spinner.startAnimating()
        } else {
            self.spinner.stopAnimating()
        }
        if let userId = snapshot.userId {
            self.idLabel.text = "Ваш ID: \(userId)"
        } else {
            self.idLabel.text = nil
        }
    }

    @objc private func buyPressed() {
        guard let url = URL(string: "https://t.me/\(pampGramAccessContactUsername)") else {
            return
        }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    @objc private func retryPressed() {
        PampGramAccessGate.shared.refreshNow()
    }

    @objc private func activatePressed() {
        let alert = UIAlertController(title: "Активировать ключ", message: "Введите ключ, который вы получили.", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "PMP-XXXXX-XXXXX-XXXXX-XXXXX"
            field.autocapitalizationType = .allCharacters
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Активировать", style: .default, handler: { [weak self, weak alert] _ in
            let key = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            self?.redeem(key: key)
        }))
        self.present(alert, animated: true, completion: nil)
    }

    private func redeem(key: String) {
        guard !key.isEmpty, !self.isRedeeming, let userId = PampGramAccessGate.shared.snapshot.userId else {
            return
        }
        self.isRedeeming = true
        self.refresh()
        // The server's reply to the redemption is NOT what unlocks the app: it only triggers a
        // fresh, signed /access check, and that signed answer is what the gate believes.
        PampGramSubscriptionAPI.redeemKey(userId: userId, key: key, completion: { [weak self] status in
            self?.isRedeeming = false
            self?.refresh()
            PampGramAccessGate.shared.refreshNow()
            if status == nil {
                let alert = UIAlertController(title: "Не удалось активировать", message: "Проверьте ключ и интернет. Если ключ уже использован — напишите @\(pampGramAccessContactUsername).", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                self?.present(alert, animated: true, completion: nil)
            }
        })
    }
}

/// Owns the full-screen lock: a dedicated `UIWindow` above everything else the app can show
/// (including alerts), present for as long as `PampGramAccessGate` says the app is not allowed.
/// A once-a-second watchdog puts it back if anything hides or removes it, and tells the gate
/// (which reports it to the server) when that happens.
public final class PampGramAccessLockOverlay {
    public static let shared = PampGramAccessLockOverlay()

    private var window: UIWindow?
    private var controller: PampGramAccessLockViewController?
    private var previousKeyWindow: UIWindow?
    private var installed = false

    private init() {
    }

    /// Call once on the main thread at launch (see `pampGramInstallStatusBadgeOverlay`).
    public func install() {
        guard !self.installed else {
            return
        }
        self.installed = true
        NotificationCenter.default.addObserver(forName: PampGramAccessGate.didChangeNotification, object: nil, queue: .main) { _ in
            PampGramAccessLockOverlay.shared.update()
        }
        self.update()
        self.scheduleWatchdog()
    }

    private func scheduleWatchdog() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            PampGramAccessLockOverlay.shared.watchdogTick()
            PampGramAccessLockOverlay.shared.scheduleWatchdog()
        }
    }

    private func update() {
        let snapshot = PampGramAccessGate.shared.snapshot
        switch snapshot.state {
        case .allowed:
            self.dismiss()
        case .locked:
            if self.window == nil {
                self.present()
            }
            self.controller?.refresh()
        }
    }

    private func watchdogTick() {
        let snapshot = PampGramAccessGate.shared.snapshot
        guard case .locked = snapshot.state else {
            return
        }
        guard let window = self.window else {
            self.present()
            return
        }
        let viewAlpha = window.rootViewController?.view.alpha ?? 1.0
        let viewHidden = window.rootViewController?.view.isHidden ?? false
        var tampered = false
        if window.isHidden || viewHidden {
            tampered = true
        }
        if window.alpha < 0.99 || viewAlpha < 0.99 {
            tampered = true
        }
        if window.windowScene == nil || window.rootViewController !== self.controller {
            tampered = true
        }
        if tampered {
            window.alpha = 1.0
            window.isHidden = false
            window.rootViewController?.view.alpha = 1.0
            window.rootViewController?.view.isHidden = false
            PampGramAccessGate.shared.reportOverlayTampering()
        }
    }

    private func present() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else {
            // No scene yet (very early launch): the watchdog tries again a second later.
            return
        }
        self.previousKeyWindow = scenes.flatMap { $0.windows }.first(where: { $0.isKeyWindow })
        let controller = PampGramAccessLockViewController()
        let window = UIWindow(windowScene: scene)
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1000.0)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        self.controller = controller
    }

    private func dismiss() {
        guard let window = self.window else {
            return
        }
        window.isHidden = true
        window.rootViewController = nil
        self.window = nil
        self.controller = nil
        self.previousKeyWindow?.makeKey()
        self.previousKeyWindow = nil
    }
}
