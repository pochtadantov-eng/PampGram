import UIKit
import TelegramCore
import AccountContext
import SwiftSignalKit
import PhantomGiftKit

// MARK: - Gift Fireworks Effect

final class GiftFireworksEffect {
    static let shared = GiftFireworksEffect()

    private weak var fireworksContainer: UIView?
    private weak var overlayView: UIView?
    private var emitterLayers: [CAEmitterLayer] = []
    private var isShowing = false

    private init() {}

    func showFireworks(
        in view: UIView,
        completion: (() -> Void)? = nil
    ) {
        guard !isShowing else {
            completion?()
            return
        }

        isShowing = true

        let overlay = UIView(frame: view.bounds)
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(overlay)
        overlayView = overlay

        let container = UIView(frame: view.bounds)
        container.backgroundColor = .clear
        container.isUserInteractionEnabled = false
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(container)
        fireworksContainer = container

        let positions: [CGPoint] = [
            CGPoint(x: view.bounds.width * 0.20, y: view.bounds.height * 0.30),
            CGPoint(x: view.bounds.width * 0.50, y: view.bounds.height * 0.20),
            CGPoint(x: view.bounds.width * 0.80, y: view.bounds.height * 0.35),
            CGPoint(x: view.bounds.width * 0.35, y: view.bounds.height * 0.15),
            CGPoint(x: view.bounds.width * 0.65, y: view.bounds.height * 0.25)
        ]

        for (index, position) in positions.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.15) { [weak self, weak container] in
                guard let self, let container, self.isShowing else { return }
                self.createFireworkBurst(at: position, in: container)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self, weak container] in
            guard let self, let container, self.isShowing else { return }
            self.createSecondaryBurst(in: container)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.dismissFireworks(completion: completion)
        }
    }

    private func createFireworkBurst(at position: CGPoint, in container: UIView) {
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = position
        emitter.emitterShape = .circle
        emitter.emitterSize = CGSize(width: 20, height: 20)
        emitter.renderMode = .unordered
        emitter.birthRate = 1

        let colors: [UIColor] = [
            .systemRed, .systemOrange, .systemYellow, .systemGreen,
            .systemBlue, .systemPurple, .systemPink, .white
        ]

        let cells = colors
            .shuffled()
            .prefix(Int.random(in: 3...5))
            .map(createParticleCell)

        emitter.emitterCells = Array(cells)
        container.layer.addSublayer(emitter)
        emitterLayers.append(emitter)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            emitter.birthRate = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self, weak emitter] in
            emitter?.removeFromSuperlayer()
            self?.emitterLayers.removeAll { $0 === emitter }
        }
    }

    private func createParticleCell(color: UIColor) -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.contents = createSparkImage(color: color)
        cell.birthRate = 40
        cell.lifetime = 1.5
        cell.lifetimeRange = 0.5
        cell.velocity = 300
        cell.velocityRange = 150
        cell.emissionRange = .pi * 2
        cell.scale = 0.2
        cell.scaleRange = 0.15
        cell.scaleSpeed = -0.05
        cell.alphaSpeed = -0.5
        cell.spin = .pi / 2
        cell.spinRange = .pi / 4
        return cell
    }

    private func createSparkImage(color: UIColor) -> CGImage? {
        let size = CGSize(width: 20, height: 20)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let cgContext = context.cgContext
            let rect = CGRect(origin: .zero, size: size)
            cgContext.setFillColor(color.withAlphaComponent(0.35).cgColor)
            cgContext.fillEllipse(in: rect)
            let center = rect.insetBy(dx: 5, dy: 5)
            cgContext.setFillColor(color.cgColor)
            cgContext.fillEllipse(in: center)
        }
        return image.cgImage
    }

    private func createSecondaryBurst(in container: UIView) {
        let positions: [CGPoint] = [
            CGPoint(x: container.bounds.width * 0.15, y: container.bounds.height * 0.50),
            CGPoint(x: container.bounds.width * 0.45, y: container.bounds.height * 0.40),
            CGPoint(x: container.bounds.width * 0.75, y: container.bounds.height * 0.55)
        ]

        for (index, position) in positions.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.2) { [weak self, weak container] in
                guard let self, let container, self.isShowing else { return }
                self.createFireworkBurst(at: position, in: container)
            }
        }
    }

    private func dismissFireworks(completion: (() -> Void)?) {
        emitterLayers.forEach { $0.birthRate = 0; $0.removeFromSuperlayer() }
        emitterLayers.removeAll()

        let group = DispatchGroup()

        if let container = fireworksContainer {
            group.enter()
            UIView.animate(
                withDuration: 0.4,
                animations: { container.alpha = 0 },
                completion: { _ in
                    container.removeFromSuperview()
                    group.leave()
                }
            )
        }

        if let overlay = overlayView {
            group.enter()
            UIView.animate(
                withDuration: 0.3,
                animations: { overlay.alpha = 0 },
                completion: { _ in
                    overlay.removeFromSuperview()
                    group.leave()
                }
            )
        }

        group.notify(queue: .main) { [weak self] in
            self?.isShowing = false
            completion?()
        }
    }
}

// MARK: - Visual Gift Transfer Controller

final class VisualGiftTransferController: UIViewController {
    let context: AccountContext
    let peerId: EnginePeer.Id
    let gift: StarGift
    let starPrice: Int64
    let isPhantom: Bool

    var onComplete: (() -> Void)?

    init(
        context: AccountContext,
        peerId: EnginePeer.Id,
        gift: StarGift,
        starPrice: Int64,
        isPhantom: Bool
    ) {
        self.context = context
        self.peerId = peerId
        self.gift = gift
        self.starPrice = starPrice
        self.isPhantom = isPhantom
        super.init(nibName: nil, bundle: nil)
        self.modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        playGiftAnimation()
    }

    private func setupUI() {
        let giftLabel = UILabel()
        let giftTitle: String
        switch gift {
        case let .generic(g):
            giftTitle = g.title ?? "Gift"
        case let .unique(g):
            giftTitle = g.title
        }
        giftLabel.text = giftTitle
        giftLabel.font = .systemFont(ofSize: 28, weight: .bold)
        giftLabel.textColor = .white
        giftLabel.textAlignment = .center
        giftLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(giftLabel)

        let priceLabel = UILabel()
        priceLabel.text = "⭐ \(starPrice)"
        priceLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        priceLabel.textColor = .systemYellow
        priceLabel.textAlignment = .center
        priceLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(priceLabel)

        var statusText = "Gift Sent!"
        if isPhantom {
            statusText = "Phantom Gift Sent!"
        }

        let statusLabel = UILabel()
        statusLabel.text = statusText
        statusLabel.font = .systemFont(ofSize: 16, weight: .regular)
        statusLabel.textColor = .white
        statusLabel.alpha = 0.7
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        let closeButton = UIButton(type: .system)
        closeButton.setTitle("Close", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.backgroundColor = .systemBlue
        closeButton.layer.cornerRadius = 8
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            giftLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            giftLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -60),

            priceLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            priceLabel.topAnchor.constraint(equalTo: giftLabel.bottomAnchor, constant: 20),

            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: priceLabel.bottomAnchor, constant: 16),

            closeButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            closeButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            closeButton.widthAnchor.constraint(equalToConstant: 120),
            closeButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func playGiftAnimation() {
        GiftFireworksEffect.shared.showFireworks(in: view) { [weak self] in
            self?.onComplete?()
        }
    }

    @objc private func closeButtonTapped() {
        dismiss(animated: true)
    }
}

// MARK: - Gift Transfer Manager

public enum VisualGiftTransferManager {
    public static func transferGift(
        context: AccountContext,
        peerId: EnginePeer.Id,
        gift: StarGift,
        starPrice: Int64,
        isPhantom: Bool,
        sourceViewController: UIViewController
    ) -> Signal<Never, NoError> {
        return Signal { subscriber in
            let controller = VisualGiftTransferController(
                context: context,
                peerId: peerId,
                gift: gift,
                starPrice: starPrice,
                isPhantom: isPhantom
            )

            controller.onComplete = {
                subscriber.putCompletion()
            }

            DispatchQueue.main.async {
                sourceViewController.present(controller, animated: true)
            }

            return EmptyDisposable
        }
    }

    public static func transferPhantomGift(
        context: AccountContext,
        peerId: EnginePeer.Id,
        baseGift: StarGift.Gift,
        starPrice: Int64,
        asCollectible: Bool = false,
        sourceViewController: UIViewController
    ) -> Signal<Never, NoError> {
        return PampGramPhantomGiftManager.send(
            context: context,
            peerId: peerId,
            baseGift: baseGift,
            starPrice: starPrice,
            asCollectible: asCollectible
        )
        |> mapToSignal { (result: Result<PampGramPhantomGiftManager.SendResult, PampGramPhantomGiftManager.SendError>) -> Signal<Never, NoError> in
            switch result {
            case .success(let sendResult):
                let starGift = sendResult.phantomGift.gift
                return self.transferGift(
                    context: context,
                    peerId: peerId,
                    gift: starGift,
                    starPrice: starPrice,
                    isPhantom: true,
                    sourceViewController: sourceViewController
                )
            case .failure:
                return .complete()
            }
        }
    }
}
