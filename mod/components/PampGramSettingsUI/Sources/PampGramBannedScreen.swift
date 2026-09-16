import Foundation
import UIKit
import AVFoundation
import Display
import SwiftSignalKit
import AccountContext
import PampGramCore

/// The screen a banned account sees instead of a gated section (or the whole hub, for a full
/// ban) — a continuously animating padlock, the fixed headline the admin panel always uses, the
/// admin's own free-text reason underneath in its own row, and a looping original chime for as
/// long as the screen stays open. Plain UIKit presented modally, same reasoning as
/// `PampGramIconPickerScreen.swift`: this replaces a pushed screen entirely rather than sitting
/// inside Telegram's own navigation stack, so there's no Display `ViewController` contract to
/// satisfy here.
private final class PampGramBannedViewController: UIViewController {
    private let reason: String

    private let lockContainer = UIView()
    private let lockImageView = UIImageView()
    private let titleLabel = UILabel()
    private let reasonContainer = UIView()
    private let reasonLabel = UILabel()
    private let closeButton = UIButton(type: .system)

    private var isLockOpen = true
    private var audioPlayer: AVAudioPlayer?

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

        self.titleLabel.text = "Вы были заблокированы в нашем моде по причине, указанной ниже. Если хотите вернуть доступ — пожалуйста, свяжитесь с владельцем."
        self.titleLabel.font = UIFont.systemFont(ofSize: 20.0, weight: .semibold)
        self.titleLabel.textColor = .white
        self.titleLabel.textAlignment = .center
        self.titleLabel.numberOfLines = 0
        self.view.addSubview(self.titleLabel)

        self.reasonContainer.backgroundColor = UIColor(white: 1.0, alpha: 0.08)
        self.reasonContainer.layer.cornerRadius = 12.0
        self.view.addSubview(self.reasonContainer)

        self.reasonLabel.text = "Причина: \(self.reason)"
        self.reasonLabel.font = UIFont.systemFont(ofSize: 15.0, weight: .medium)
        self.reasonLabel.textColor = UIColor(white: 1.0, alpha: 0.85)
        self.reasonLabel.textAlignment = .center
        self.reasonLabel.numberOfLines = 0
        self.reasonContainer.addSubview(self.reasonLabel)

        self.closeButton.setTitle("Закрыть", for: .normal)
        self.closeButton.setTitleColor(UIColor(rgb: 0x8e44ec), for: .normal)
        self.closeButton.titleLabel?.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        self.closeButton.addTarget(self, action: #selector(self.closePressed), for: .touchUpInside)
        self.view.addSubview(self.closeButton)

        self.lockContainer.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        UIView.animate(withDuration: 0.35, delay: 0.0, usingSpringWithDamping: 0.65, initialSpringVelocity: 0.3, options: [], animations: {
            self.lockContainer.transform = .identity
        }, completion: { _ in
            self.scheduleLockToggle()
        })

        self.startChime()
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

        let reasonTextWidth = textWidth - 32.0
        let reasonSize = self.reasonLabel.sizeThatFits(CGSize(width: reasonTextWidth, height: .greatestFiniteMagnitude))
        let reasonContainerHeight = reasonSize.height + 24.0
        self.reasonContainer.frame = CGRect(x: (width - textWidth) / 2.0, y: self.titleLabel.frame.maxY + 16.0, width: textWidth, height: reasonContainerHeight)
        self.reasonLabel.frame = CGRect(x: 16.0, y: 12.0, width: reasonTextWidth, height: reasonSize.height)

        self.closeButton.sizeToFit()
        self.closeButton.frame = CGRect(x: (width - self.closeButton.frame.width) / 2.0, y: self.view.bounds.height - self.view.safeAreaInsets.bottom - 60.0, width: self.closeButton.frame.width, height: 44.0)
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

    /// A short original chime (two synthesized sine tones, not a real recording — see the
    /// doc comment above) rendered once to a temp `.caf` file and looped for as long as the
    /// screen stays open. `AVAudioFile`/`AVAudioPCMBuffer` write raw PCM straight to disk, no
    /// external encoder needed since `.caf` is native to `AVAudioFile`.
    private func startChime() {
        guard let fileURL = PampGramBannedViewController.synthesizeChime() else {
            return
        }
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true, options: [])
        guard let player = try? AVAudioPlayer(contentsOf: fileURL) else {
            return
        }
        player.numberOfLoops = -1
        player.volume = 0.5
        player.play()
        self.audioPlayer = player
    }

    private func stopChime() {
        self.audioPlayer?.stop()
        self.audioPlayer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private static func synthesizeChime() -> URL? {
        let sampleRate: Double = 44100.0
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false) else {
            return nil
        }
        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pampgram_banned_chime.caf")
        guard let file = try? AVAudioFile(forWriting: fileURL, settings: format.settings) else {
            return nil
        }

        // Two short notes with a silent tail, so the loop reads as a gentle "ding-dong" chime
        // rather than a harsh buzzer repeating back to back.
        let notes: [(frequency: Double, duration: Double)] = [
            (frequency: 659.25, duration: 0.32),
            (frequency: 523.25, duration: 0.5),
            (frequency: 0.0, duration: 0.6)
        ]
        for note in notes {
            let frameCount = AVAudioFrameCount(note.duration * sampleRate)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                continue
            }
            buffer.frameLength = frameCount
            if let channelData = buffer.floatChannelData?[0] {
                for frame in 0..<Int(frameCount) {
                    if note.frequency == 0.0 {
                        channelData[frame] = 0.0
                        continue
                    }
                    let t = Double(frame) / sampleRate
                    let envelope = exp(-t * 3.5)
                    channelData[frame] = Float(sin(2.0 * Double.pi * note.frequency * t) * envelope * 0.4)
                }
            }
            try? file.write(from: buffer)
        }
        return fileURL
    }

    @objc private func closePressed() {
        self.stopChime()
        self.dismiss(animated: true, completion: nil)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.stopChime()
    }
}

public func pampGramPresentBannedScreen(context: AccountContext, reason: String) {
    guard let presentingController = (context.sharedContext.mainWindow?.viewController as? NavigationController)?.topViewController else {
        return
    }
    presentingController.present(PampGramBannedViewController(reason: reason), animated: true, completion: nil)
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
