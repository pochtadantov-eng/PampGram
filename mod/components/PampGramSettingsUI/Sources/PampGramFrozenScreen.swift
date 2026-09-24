import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import PampGramCore

private let pampGramFreezeChannelUrl = "https://t.me/\(pampGramRequiredChannelUsername)"

/// Shown instead of a gated section (or the whole hub) the moment
/// `PampGramSettings.channelUnsubscribedLocally` is set — see `PampGramChannelSubscriptionEnforcer`
/// for how that flag gets written, and `pampGramGateSection`/`pampGramGateFullAccess` in
/// `PampGramBannedScreen.swift` for where this is checked, right alongside the ban check. Plain
/// UIKit presented modally, same reasoning as `PampGramBannedScreen.swift`: this replaces a
/// pushed screen entirely rather than sitting inside Telegram's own navigation stack.
private final class PampGramFrozenViewController: UIViewController {
    private let context: AccountContext

    private let iconContainer = UIView()
    private let iconImageView = UIImageView()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let subscribeButton = UIButton(type: .system)
    private let checkAgainButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let closeButton = UIButton(type: .system)

    init(context: AccountContext) {
        self.context = context
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

        self.iconContainer.backgroundColor = UIColor(rgb: 0x0a84ff).withAlphaComponent(0.15)
        self.iconContainer.layer.cornerRadius = 36.0
        self.view.addSubview(self.iconContainer)

        self.iconImageView.image = UIImage(systemName: "snowflake")?.withRenderingMode(.alwaysTemplate)
        self.iconImageView.tintColor = UIColor(rgb: 0x0a84ff)
        self.iconImageView.contentMode = .scaleAspectFit
        self.iconContainer.addSubview(self.iconImageView)

        self.titleLabel.text = "Вы заморожены!"
        self.titleLabel.font = UIFont.systemFont(ofSize: 24.0, weight: .bold)
        self.titleLabel.textColor = .white
        self.titleLabel.textAlignment = .center
        self.titleLabel.numberOfLines = 0
        self.view.addSubview(self.titleLabel)

        self.bodyLabel.text = "Все функции PampGram отключены — вы отписались от нашего Telegram-канала. Подпишитесь заново, и я сразу верну вам доступ."
        self.bodyLabel.font = UIFont.systemFont(ofSize: 15.5, weight: .regular)
        self.bodyLabel.textColor = UIColor(white: 1.0, alpha: 0.7)
        self.bodyLabel.textAlignment = .center
        self.bodyLabel.numberOfLines = 0
        self.view.addSubview(self.bodyLabel)

        self.subscribeButton.setTitle("Подписаться на канал", for: .normal)
        self.subscribeButton.setTitleColor(.white, for: .normal)
        self.subscribeButton.titleLabel?.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        self.subscribeButton.backgroundColor = UIColor(rgb: 0x0a84ff)
        self.subscribeButton.layer.cornerRadius = 14.0
        self.subscribeButton.addTarget(self, action: #selector(self.subscribePressed), for: .touchUpInside)
        self.view.addSubview(self.subscribeButton)

        self.checkAgainButton.setTitle("Я подписался — проверить", for: .normal)
        self.checkAgainButton.setTitleColor(UIColor(white: 1.0, alpha: 0.75), for: .normal)
        self.checkAgainButton.titleLabel?.font = UIFont.systemFont(ofSize: 15.0, weight: .medium)
        self.checkAgainButton.addTarget(self, action: #selector(self.checkAgainPressed), for: .touchUpInside)
        self.view.addSubview(self.checkAgainButton)

        self.statusLabel.font = UIFont.systemFont(ofSize: 13.0, weight: .regular)
        self.statusLabel.textColor = UIColor(white: 1.0, alpha: 0.4)
        self.statusLabel.textAlignment = .center
        self.statusLabel.numberOfLines = 0
        self.view.addSubview(self.statusLabel)

        self.closeButton.setTitle("Закрыть", for: .normal)
        self.closeButton.setTitleColor(UIColor(white: 1.0, alpha: 0.35), for: .normal)
        self.closeButton.titleLabel?.font = UIFont.systemFont(ofSize: 15.0, weight: .regular)
        self.closeButton.addTarget(self, action: #selector(self.closePressed), for: .touchUpInside)
        self.view.addSubview(self.closeButton)

        self.iconContainer.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        UIView.animate(withDuration: 0.35, delay: 0.0, usingSpringWithDamping: 0.65, initialSpringVelocity: 0.3, options: [], animations: {
            self.iconContainer.transform = .identity
        }, completion: { _ in
            self.startSpin()
        })
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let width = self.view.bounds.width
        let safeTop = self.view.safeAreaInsets.top
        let textWidth = min(340.0, width - 40.0)

        var y = safeTop + 40.0

        let containerSide: CGFloat = 72.0
        self.iconContainer.frame = CGRect(x: (width - containerSide) / 2.0, y: y, width: containerSide, height: containerSide)
        let iconSide: CGFloat = 34.0
        self.iconImageView.frame = CGRect(x: (containerSide - iconSide) / 2.0, y: (containerSide - iconSide) / 2.0, width: iconSide, height: iconSide)
        y = self.iconContainer.frame.maxY + 20.0

        let titleSize = self.titleLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))
        self.titleLabel.frame = CGRect(x: (width - textWidth) / 2.0, y: y, width: textWidth, height: titleSize.height)
        y = self.titleLabel.frame.maxY + 12.0

        let bodySize = self.bodyLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))
        self.bodyLabel.frame = CGRect(x: (width - textWidth) / 2.0, y: y, width: textWidth, height: bodySize.height)
        y = self.bodyLabel.frame.maxY + 32.0

        let ctaHeight: CGFloat = 52.0
        self.subscribeButton.frame = CGRect(x: (width - textWidth) / 2.0, y: y, width: textWidth, height: ctaHeight)
        y = self.subscribeButton.frame.maxY + 16.0

        self.checkAgainButton.sizeToFit()
        self.checkAgainButton.frame = CGRect(x: (width - self.checkAgainButton.frame.width) / 2.0, y: y, width: self.checkAgainButton.frame.width, height: 24.0)
        y = self.checkAgainButton.frame.maxY + 8.0

        let statusSize = self.statusLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))
        self.statusLabel.frame = CGRect(x: (width - textWidth) / 2.0, y: y, width: textWidth, height: statusSize.height)
        y = self.statusLabel.frame.maxY + 20.0

        self.closeButton.sizeToFit()
        self.closeButton.frame = CGRect(x: (width - self.closeButton.frame.width) / 2.0, y: y, width: self.closeButton.frame.width, height: 32.0)
    }

    /// Keeps re-scheduling for as long as the screen is on screen — `self.view.window` goes nil
    /// the moment this controller is dismissed, which naturally breaks the chain instead of
    /// needing an explicit "stop" flag. A plain looping `CABasicAnimation` (rather than the
    /// banned screen's discrete icon-swap toggle) reads as "frozen/spinning", not "locked".
    private func startSpin() {
        guard self.view.window != nil else {
            return
        }
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = 0.0
        animation.toValue = Double.pi * 2.0
        animation.duration = 3.0
        animation.repeatCount = .infinity
        self.iconImageView.layer.add(animation, forKey: "pampGramFrozenSpin")
    }

    @objc private func subscribePressed() {
        guard let navigationController = self.context.sharedContext.mainWindow?.viewController as? NavigationController else {
            return
        }
        let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
        self.context.sharedContext.openExternalUrl(context: self.context, urlContext: .generic, url: pampGramFreezeChannelUrl, forceExternal: false, presentationData: presentationData, navigationController: navigationController, dismissInput: {})
    }

    @objc private func checkAgainPressed() {
        self.statusLabel.text = "Проверяю…"
        let context = self.context
        let _ = (PampGramChannelSubscriptionEnforcer.checkNow(account: context.account)
        |> deliverOnMainQueue).start(next: { [weak self] isSubscribed in
            guard let self else {
                return
            }
            if isSubscribed {
                let _ = context.account.postbox.transaction { transaction -> Void in
                    PampGramCore.updateSettings(transaction: transaction, { settings in
                        var settings = settings
                        settings.channelUnsubscribedLocally = false
                        return settings
                    })
                }.start()
                self.dismiss(animated: true, completion: nil)
            } else {
                self.statusLabel.text = "Пока не вижу подписку — попробуйте ещё раз через пару секунд."
            }
        })
    }

    @objc private func closePressed() {
        self.dismiss(animated: true, completion: nil)
    }
}

public func pampGramPresentFrozenScreen(context: AccountContext) {
    guard let presentingController = (context.sharedContext.mainWindow?.viewController as? NavigationController)?.topViewController else {
        return
    }
    presentingController.present(PampGramFrozenViewController(context: context), animated: true, completion: nil)
}
