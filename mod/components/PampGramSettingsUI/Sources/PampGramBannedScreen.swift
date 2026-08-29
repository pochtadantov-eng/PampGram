import Foundation
import UIKit
import Display
import SwiftSignalKit
import AccountContext
import PampGramCore

/// The screen a banned account sees instead of a gated section (or the whole hub, for a full
/// ban) — a closing-padlock animation, the fixed headline the admin panel always uses, and the
/// admin's own free-text reason underneath. Plain UIKit presented modally, same reasoning as
/// `PampGramIconPickerScreen.swift`: this replaces a pushed screen entirely rather than sitting
/// inside Telegram's own navigation stack, so there's no Display `ViewController` contract to
/// satisfy here.
private final class PampGramBannedViewController: UIViewController {
    private let reason: String

    private let lockContainer = UIView()
    private let lockImageView = UIImageView()
    private let titleLabel = UILabel()
    private let reasonLabel = UILabel()
    private let closeButton = UIButton(type: .system)

    init(reason: String) {
        self.reason = reason
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

        self.lockContainer.backgroundColor = UIColor(rgb: 0xff3b30).withAlphaComponent(0.15)
        self.lockContainer.layer.cornerRadius = 44.0
        self.view.addSubview(self.lockContainer)

        self.lockImageView.image = UIImage(systemName: "lock.open.fill")?.withRenderingMode(.alwaysTemplate)
        self.lockImageView.tintColor = UIColor(rgb: 0xff3b30)
        self.lockImageView.contentMode = .scaleAspectFit
        self.lockContainer.addSubview(self.lockImageView)

        self.titleLabel.text = "Временно недоступно для вашего устройства"
        self.titleLabel.font = UIFont.systemFont(ofSize: 20.0, weight: .semibold)
        self.titleLabel.textColor = .white
        self.titleLabel.textAlignment = .center
        self.titleLabel.numberOfLines = 0
        self.view.addSubview(self.titleLabel)

        self.reasonLabel.text = "Причина: \(self.reason)"
        self.reasonLabel.font = UIFont.systemFont(ofSize: 15.0, weight: .regular)
        self.reasonLabel.textColor = UIColor(white: 1.0, alpha: 0.6)
        self.reasonLabel.textAlignment = .center
        self.reasonLabel.numberOfLines = 0
        self.view.addSubview(self.reasonLabel)

        self.closeButton.setTitle("Закрыть", for: .normal)
        self.closeButton.setTitleColor(UIColor(rgb: 0x8e44ec), for: .normal)
        self.closeButton.titleLabel?.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        self.closeButton.addTarget(self, action: #selector(self.closePressed), for: .touchUpInside)
        self.view.addSubview(self.closeButton)

        self.playLockAnimation()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let width = self.view.bounds.width
        let centerY = self.view.bounds.height * 0.42

        let containerSide: CGFloat = 88.0
        self.lockContainer.frame = CGRect(x: (width - containerSide) / 2.0, y: centerY - containerSide - 24.0, width: containerSide, height: containerSide)
        let iconSide: CGFloat = 40.0
        self.lockImageView.frame = CGRect(x: (containerSide - iconSide) / 2.0, y: (containerSide - iconSide) / 2.0, width: iconSide, height: iconSide)

        let textWidth = min(300.0, width - 48.0)
        let titleSize = self.titleLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))
        self.titleLabel.frame = CGRect(x: (width - textWidth) / 2.0, y: self.lockContainer.frame.maxY + 24.0, width: textWidth, height: titleSize.height)

        let reasonSize = self.reasonLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))
        self.reasonLabel.frame = CGRect(x: (width - textWidth) / 2.0, y: self.titleLabel.frame.maxY + 12.0, width: textWidth, height: reasonSize.height)

        self.closeButton.sizeToFit()
        self.closeButton.frame = CGRect(x: (width - self.closeButton.frame.width) / 2.0, y: self.view.bounds.height - self.view.safeAreaInsets.bottom - 60.0, width: self.closeButton.frame.width, height: 44.0)
    }

    /// Padlock opens on appear, then snaps shut with a small overshoot pulse — "closing", not
    /// just "appearing", since that's specifically what was asked for.
    private func playLockAnimation() {
        self.lockContainer.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        UIView.animate(withDuration: 0.35, delay: 0.0, usingSpringWithDamping: 0.65, initialSpringVelocity: 0.3, options: [], animations: {
            self.lockContainer.transform = .identity
        }, completion: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            guard let self else {
                return
            }
            UIView.transition(with: self.lockImageView, duration: 0.25, options: .transitionCrossDissolve, animations: {
                self.lockImageView.image = UIImage(systemName: "lock.fill")?.withRenderingMode(.alwaysTemplate)
            }, completion: { _ in
                UIView.animate(withDuration: 0.15, animations: {
                    self.lockImageView.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
                }, completion: { _ in
                    UIView.animate(withDuration: 0.15) {
                        self.lockImageView.transform = .identity
                    }
                })
            })
        }
    }

    @objc private func closePressed() {
        self.dismiss(animated: true, completion: nil)
    }
}

public func pampGramPresentBannedScreen(context: AccountContext, reason: String) {
    guard let presentingController = (context.sharedContext.mainWindow?.viewController as? NavigationController)?.topViewController else {
        return
    }
    presentingController.present(PampGramBannedViewController(reason: reason), animated: true, completion: nil)
}

/// Opens `openReal` immediately — never waits on the network — and checks this account's ban
/// status for `section` in parallel; if the admin has banned the whole account or just this
/// section, the lock screen is presented right on top a moment later. The overwhelmingly
/// common case (not banned) used to pay for a round trip to the ban-status endpoint before the
/// section would even open, which on a slow or flaky connection reads as the whole tap having
/// done nothing — this way navigation is instant and only the rare banned case pays for the
/// check, exactly like the hub's own full-ban check already works. Shared by every navigation
/// point that can reach a gated section — the hub's own rows and "Статус"'s mirror of the same
/// rows both call this rather than pushing straight through.
public func pampGramGateSection(context: AccountContext, section: PampGramBanSection, openReal: @escaping () -> Void) {
    openReal()

    let _ = (PampGramSubscriptionAPI.fetchBanStatus(userId: context.account.peerId.id._internalGetInt64Value())
    |> deliverOnMainQueue).start(next: { status in
        if let reason = status.full ?? status.reason(for: section) {
            pampGramPresentBannedScreen(context: context, reason: reason)
        }
    })
}
