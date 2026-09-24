import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import PampGramCore

/// Same contact the "Обновить план" and Premium-paywall flows already message — see
/// `PampGramAboutScreen.swift`'s `pampGramOpenUpgradeRequestChat`. Reused here so "написать мне"
/// on the ban screen reaches the same place asking for a key or a plan upgrade does: one real
/// person on the other end of every "contact us" button in the mod, not three different ones.
private let pampGramBanContactUsername = "Claps228"

/// The screen a banned account sees instead of a gated section (or the whole hub, for a full
/// ban) — styled as a short personal note from the admin (not a generic "ACCESS DENIED" panel),
/// with the admin's own free-text reason worked into the body rather than shown as a separate
/// labeled field, and a real "Написать мне" button that opens an actual chat with the contact
/// behind every other "contact us" flow in the mod — so someone who wants their access back has
/// an immediate, obvious way to ask, not just a dead end. Plain UIKit presented modally, same
/// reasoning as `PampGramIconPickerScreen.swift`: this replaces a pushed screen entirely rather
/// than sitting inside Telegram's own navigation stack, so there's no Display `ViewController`
/// contract to satisfy here.
private final class PampGramBannedViewController: UIViewController {
    private let context: AccountContext
    private let reason: String

    private let lockContainer = UIView()
    private let lockImageView = UIImageView()
    private let titleLabel = UILabel()
    private let letterCard = UIView()
    private let letterAccentBar = UIView()
    private let letterBodyLabel = UILabel()
    private let letterSignatureLabel = UILabel()
    private let contactButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)

    private var isLockOpen = true

    init(context: AccountContext, reason: String) {
        self.context = context
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
        self.lockContainer.layer.cornerRadius = 36.0
        self.view.addSubview(self.lockContainer)

        self.lockImageView.image = UIImage(systemName: "lock.open.fill")?.withRenderingMode(.alwaysTemplate)
        self.lockImageView.tintColor = UIColor(rgb: 0xff3b30)
        self.lockImageView.contentMode = .scaleAspectFit
        self.lockContainer.addSubview(self.lockImageView)

        self.titleLabel.text = "Личное сообщение от администратора"
        self.titleLabel.font = UIFont.systemFont(ofSize: 15.0, weight: .semibold)
        self.titleLabel.textColor = UIColor(white: 1.0, alpha: 0.5)
        self.titleLabel.textAlignment = .center
        self.titleLabel.numberOfLines = 0
        self.view.addSubview(self.titleLabel)

        // The "letter": a rounded card with a red accent bar down the left edge (an envelope/
        // note feel, echoing the lock's own red without repeating the icon), holding the reason
        // worked directly into a personal paragraph rather than a separate "Причина:" row.
        self.letterCard.backgroundColor = UIColor(white: 1.0, alpha: 0.06)
        self.letterCard.layer.cornerRadius = 18.0
        self.view.addSubview(self.letterCard)

        self.letterAccentBar.backgroundColor = UIColor(rgb: 0xff3b30)
        self.letterAccentBar.layer.cornerRadius = 2.0
        self.letterCard.addSubview(self.letterAccentBar)

        let trimmedReason = self.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        self.letterBodyLabel.text = "Здравствуйте.\n\nМне пришлось ограничить вам доступ к PampGram — вот причина, как я её вижу:\n\n«\(trimmedReason)»\n\nЕсли считаете, что это ошибка, или хотите всё обсудить и вернуть доступ — напишите мне лично, разберёмся."
        self.letterBodyLabel.font = UIFont.systemFont(ofSize: 15.5, weight: .regular)
        self.letterBodyLabel.textColor = UIColor(white: 1.0, alpha: 0.92)
        self.letterBodyLabel.numberOfLines = 0
        self.letterCard.addSubview(self.letterBodyLabel)

        self.letterSignatureLabel.text = "— Администратор PampGram"
        self.letterSignatureLabel.font = UIFont.italicSystemFont(ofSize: 14.0)
        self.letterSignatureLabel.textColor = UIColor(white: 1.0, alpha: 0.55)
        self.letterCard.addSubview(self.letterSignatureLabel)

        self.contactButton.setTitle("Написать мне", for: .normal)
        self.contactButton.setTitleColor(.white, for: .normal)
        self.contactButton.titleLabel?.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        self.contactButton.backgroundColor = UIColor(rgb: 0xff3b30)
        self.contactButton.layer.cornerRadius = 14.0
        self.contactButton.addTarget(self, action: #selector(self.contactPressed), for: .touchUpInside)
        self.view.addSubview(self.contactButton)

        self.closeButton.setTitle("Закрыть", for: .normal)
        self.closeButton.setTitleColor(UIColor(white: 1.0, alpha: 0.5), for: .normal)
        self.closeButton.titleLabel?.font = UIFont.systemFont(ofSize: 15.0, weight: .regular)
        self.closeButton.addTarget(self, action: #selector(self.closePressed), for: .touchUpInside)
        self.view.addSubview(self.closeButton)

        self.lockContainer.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        UIView.animate(withDuration: 0.35, delay: 0.0, usingSpringWithDamping: 0.65, initialSpringVelocity: 0.3, options: [], animations: {
            self.lockContainer.transform = .identity
        }, completion: { _ in
            self.scheduleLockToggle()
        })
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let width = self.view.bounds.width
        let safeTop = self.view.safeAreaInsets.top
        let textWidth = min(340.0, width - 40.0)

        var y = safeTop + 28.0

        let containerSide: CGFloat = 72.0
        self.lockContainer.frame = CGRect(x: (width - containerSide) / 2.0, y: y, width: containerSide, height: containerSide)
        let iconSide: CGFloat = 32.0
        self.lockImageView.frame = CGRect(x: (containerSide - iconSide) / 2.0, y: (containerSide - iconSide) / 2.0, width: iconSide, height: iconSide)
        y = self.lockContainer.frame.maxY + 14.0

        let titleSize = self.titleLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))
        self.titleLabel.frame = CGRect(x: (width - textWidth) / 2.0, y: y, width: textWidth, height: titleSize.height)
        y = self.titleLabel.frame.maxY + 20.0

        let cardInnerWidth = textWidth - 24.0 - 16.0
        let bodySize = self.letterBodyLabel.sizeThatFits(CGSize(width: cardInnerWidth, height: .greatestFiniteMagnitude))
        self.letterBodyLabel.frame = CGRect(x: 24.0, y: 20.0, width: cardInnerWidth, height: bodySize.height)
        let signatureSize = self.letterSignatureLabel.sizeThatFits(CGSize(width: cardInnerWidth, height: .greatestFiniteMagnitude))
        self.letterSignatureLabel.frame = CGRect(x: 24.0, y: self.letterBodyLabel.frame.maxY + 14.0, width: cardInnerWidth, height: signatureSize.height)
        let cardHeight = self.letterSignatureLabel.frame.maxY + 20.0
        self.letterCard.frame = CGRect(x: (width - textWidth) / 2.0, y: y, width: textWidth, height: cardHeight)
        self.letterAccentBar.frame = CGRect(x: 0.0, y: 14.0, width: 4.0, height: cardHeight - 28.0)

        let ctaHeight: CGFloat = 52.0
        self.contactButton.frame = CGRect(x: (width - textWidth) / 2.0, y: self.letterCard.frame.maxY + 24.0, width: textWidth, height: ctaHeight)

        self.closeButton.sizeToFit()
        self.closeButton.frame = CGRect(x: (width - self.closeButton.frame.width) / 2.0, y: self.contactButton.frame.maxY + 16.0, width: self.closeButton.frame.width, height: 32.0)
    }

    /// Keeps re-scheduling itself for as long as the screen is on screen — `self.view.window`
    /// goes nil the moment this controller is dismissed, which naturally breaks the chain instead
    /// of needing an explicit "stop" flag.
    private func scheduleLockToggle() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
            guard let self, self.view.window != nil else {
                return
            }
            self.toggleLockIcon()
            self.scheduleLockToggle()
        }
    }

    private func toggleLockIcon() {
        self.isLockOpen.toggle()
        let iconName = self.isLockOpen ? "lock.open.fill" : "lock.fill"
        UIView.transition(with: self.lockImageView, duration: 0.25, options: .transitionCrossDissolve, animations: {
            self.lockImageView.image = UIImage(systemName: iconName)?.withRenderingMode(.alwaysTemplate)
        }, completion: nil)
        UIView.animate(withDuration: 0.15, animations: {
            self.lockImageView.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
        }, completion: { _ in
            UIView.animate(withDuration: 0.15) {
                self.lockImageView.transform = .identity
            }
        })
    }

    @objc private func contactPressed() {
        guard let navigationController = self.context.sharedContext.mainWindow?.viewController as? NavigationController else {
            return
        }
        let context = self.context
        let reason = self.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let _ = (context.engine.peers.resolvePeerByName(name: pampGramBanContactUsername, referrer: nil)
        |> mapToSignal { result -> Signal<EnginePeer?, NoError> in
            guard case let .result(peer) = result else {
                return .complete()
            }
            return .single(peer)
        }
        |> deliverOnMainQueue).startStandalone(next: { [weak self] peer in
            guard let self, let peer else {
                return
            }
            self.dismiss(animated: true, completion: {
                context.sharedContext.navigateToChatController(NavigateToChatControllerParams(
                    navigationController: navigationController,
                    context: context,
                    chatLocation: .peer(peer),
                    updateTextInputState: ChatTextInputState(inputText: NSAttributedString(string: "Здравствуйте! Меня заблокировали в PampGram по причине «\(reason)», хочу это обсудить.")),
                    activateInput: .text,
                    keepStack: .always
                ))
            })
        })
    }

    @objc private func closePressed() {
        self.dismiss(animated: true, completion: nil)
    }
}

public func pampGramPresentBannedScreen(context: AccountContext, reason: String) {
    guard let presentingController = (context.sharedContext.mainWindow?.viewController as? NavigationController)?.topViewController else {
        return
    }
    presentingController.present(PampGramBannedViewController(context: context, reason: reason), animated: true, completion: nil)
}

/// Checks this build's version and this account's ban status for `section` FIRST and only calls
/// `openReal` if the build isn't retired and neither the whole account nor this section is
/// banned; a blocked account sees the lock/update screen instead and `openReal` never runs, so
/// there is no window where the real section is reachable while the checks are still in flight.
/// (An earlier version opened the section immediately and only corrected course once the check
/// came back — on top of the real section rather than instead of it, so dismissing the lock
/// screen left the banned section fully usable underneath. Ban enforcement that can be raced by
/// a fast tap isn't enforcement.) The version check runs first: a retired build shows "update
/// required" even for an account that was never banned at all, since the point of retiring a
/// build is to stop it from being usable regardless of who's signed in. The one real cost is
/// that every open — including the overwhelmingly common allowed case — now pays for two round
/// trips before the section appears; neither `fetchMinVersion` nor `fetchBanStatus` ever fails
/// outward (any network problem resolves to "not banned"/"no minimum"), so a flaky connection
/// costs a beat of latency, never a false lockout. Shared by every navigation point that can
/// reach a gated section — the hub's own rows and "Статус"'s mirror of the same rows both call
/// this rather than pushing straight through.
public func pampGramGateSection(context: AccountContext, section: PampGramBanSection, openReal: @escaping () -> Void) {
    let _ = (combineLatest(
        PampGramSubscriptionAPI.fetchMinVersion(),
        PampGramSubscriptionAPI.fetchBanStatus(userId: context.account.peerId.id._internalGetInt64Value())
    )
    |> deliverOnMainQueue).start(next: { minVersion, status in
        if PampGramSubscriptionAPI.currentBuildVersion < minVersion {
            pampGramPresentUpdateRequiredScreen(context: context)
        } else if let reason = status.full ?? status.reason(for: section) {
            pampGramPresentBannedScreen(context: context, reason: reason)
        } else {
            openReal()
        }
    })
}

/// Same before-not-after gate as `pampGramGateSection`, but for entry points that aren't tied
/// to one section — a full ban blocks these outright, a section ban doesn't apply since none of
/// them are scoped to a single section. Used to gate opening the hub itself and the two PampGram
/// entry points that live entirely outside the hub (message long-press menu, attachment-button
/// long-press) so a full ban actually reaches every way into PampGram, not just the hub.
public func pampGramGateFullAccess(context: AccountContext, onAllowed: @escaping () -> Void) {
    let _ = (combineLatest(
        PampGramSubscriptionAPI.fetchMinVersion(),
        PampGramSubscriptionAPI.fetchBanStatus(userId: context.account.peerId.id._internalGetInt64Value())
    )
    |> deliverOnMainQueue).start(next: { minVersion, status in
        if PampGramSubscriptionAPI.currentBuildVersion < minVersion {
            pampGramPresentUpdateRequiredScreen(context: context)
        } else if let reason = status.full {
            pampGramPresentBannedScreen(context: context, reason: reason)
        } else {
            onAllowed()
        }
    })
}

/// "Подарки" and "Внешний вид" are the two hub sections Standard doesn't include — Чаты, Ghost
/// and Дополнительно aren't tier-gated at all, only by whatever `pampGramGateSection` already
/// checks. Tier and per-user admin bans are independent concerns (a PRO account can still be
/// banned from a section by the admin; a Standard account is blocked here regardless of ban
/// status), so this runs as its own check rather than folding into `pampGramGateSection` —
/// every call site that can reach either of these two sections runs this first, `openReal` only
/// firing for `.pro`; anything else (including a network hiccup, so a flaky connection can never
/// grant Premium it shouldn't) pushes the subscription screen instead, which is also where
/// "Активировать премиум" lives.
public func pampGramGateTier(context: AccountContext, push: @escaping (ViewController) -> Void, openReal: @escaping () -> Void) {
    let selfAccountId = context.account.peerId.id._internalGetInt64Value()
    let _ = (PampGramSubscriptionAPI.fetchTier(userId: selfAccountId)
    |> deliverOnMainQueue).start(next: { tier in
        if tier == .pro {
            openReal()
        } else {
            push(pampGramSubscriptionController(context: context))
        }
    })
}
