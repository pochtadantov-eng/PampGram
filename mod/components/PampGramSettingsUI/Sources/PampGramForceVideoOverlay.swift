import Foundation
import UIKit
import AVFoundation
import PampGramCore

/// Full-screen forced video window (below the ban lock, above the app). Plays an HTTPS
/// stream the admin pushed via `/force-video`.
public final class PampGramForceVideoOverlay {
    public static let shared = PampGramForceVideoOverlay()

    private var window: UIWindow?
    private var controller: PampGramForceVideoViewController?
    private var currentId: String?
    private var installed = false

    private init() {
    }

    public func install() {
        self.installed = true
    }

    public func apply(_ command: PampGramSubscriptionAPI.PampGramForceVideoCommand?) {
        assert(Thread.isMainThread)
        guard self.installed else {
            return
        }
        guard let command else {
            self.dismiss()
            return
        }
        if self.currentId == command.id, self.window != nil {
            return
        }
        self.present(command)
    }

    private func present(_ command: PampGramSubscriptionAPI.PampGramForceVideoCommand) {
        guard let url = URL(string: command.url) else {
            return
        }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else {
            return
        }
        self.dismiss()
        let controller = PampGramForceVideoViewController(url: url, loop: command.loop, dismissible: command.dismissible) { [weak self] in
            self?.dismiss()
        }
        let window = UIWindow(windowScene: scene)
        // Below ban lock (alert+1000), above normal UI/alerts.
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 500.0)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        self.controller = controller
        self.currentId = command.id
    }

    private func dismiss() {
        self.controller?.tearDown()
        self.window?.isHidden = true
        self.window = nil
        self.controller = nil
        self.currentId = nil
    }
}

private final class PampGramForceVideoViewController: UIViewController {
    private let url: URL
    private let loop: Bool
    private let dismissible: Bool
    private let onClose: () -> Void
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var endObserver: NSObjectProtocol?
    private var closeButton: UIButton?

    init(url: URL, loop: Bool, dismissible: Bool, onClose: @escaping () -> Void) {
        self.url = url
        self.loop = loop
        self.dismissible = dismissible
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .black
        let player = AVPlayer(url: self.url)
        player.isMuted = false
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        layer.frame = self.view.bounds
        self.view.layer.addSublayer(layer)
        self.player = player
        self.playerLayer = layer

        if self.dismissible {
            let button = UIButton(type: .system)
            button.setTitle("  Закрыть  ", for: .normal)
            button.setTitleColor(.white, for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
            button.backgroundColor = UIColor(white: 0.15, alpha: 0.7)
            button.layer.cornerRadius = 14.0
            button.addTarget(self, action: #selector(self.closeTapped), for: .touchUpInside)
            button.sizeToFit()
            var frame = button.frame
            frame.size.width = max(frame.size.width + 20.0, 96.0)
            frame.size.height = max(frame.size.height + 12.0, 40.0)
            button.frame = frame
            self.view.addSubview(button)
            self.closeButton = button
        }

        if self.loop {
            self.endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { [weak player] _ in
                player?.seek(to: .zero)
                player?.play()
            }
        } else {
            self.endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { [weak self] _ in
                self?.onClose()
            }
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
        }
        player.play()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.playerLayer?.frame = self.view.bounds
        if let button = self.closeButton {
            let inset = self.view.safeAreaInsets
            var frame = button.frame
            frame.origin.x = self.view.bounds.width - inset.right - frame.size.width - 16.0
            frame.origin.y = inset.top + 16.0
            button.frame = frame
        }
    }

    @objc private func closeTapped() {
        self.onClose()
    }

    func tearDown() {
        if let endObserver = self.endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        self.player?.pause()
        self.player = nil
        self.playerLayer?.removeFromSuperlayer()
        self.playerLayer = nil
    }

    deinit {
        self.tearDown()
    }
}
