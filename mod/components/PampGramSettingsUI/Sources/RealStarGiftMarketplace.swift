import UIKit
import TelegramCore
import AccountContext
import SwiftSignalKit
import Display

// MARK: - Real Star Gift Marketplace Integration

final class RealStarGiftMarketplaceController: UIViewController {
    let context: AccountContext
    let peerId: EnginePeer.Id

    var onGiftSelected: ((StarGift) -> Void)?
    var onDismiss: (() -> Void)?

    init(context: AccountContext, peerId: EnginePeer.Id) {
        self.context = context
        self.peerId = peerId
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
        loadGifts()
    }

    private func setupUI() {
        let closeButton = UIButton(type: .system)
        closeButton.setTitle("Закрыть", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            closeButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            closeButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
    }

    private func loadGifts() {
        let _ = context.engine.payments.cachedStarGifts().start(next: { [weak self] gifts in
            guard let self else { return }
            // TODO: Отобразить список подарков
            print("Загружено подарков: \(gifts?.count ?? 0)")
        })
    }

    @objc private func closeButtonTapped() {
        dismiss(animated: true)
        onDismiss?()
    }
}

// MARK: - Gift Marketplace Integration Manager

public enum RealStarGiftMarketplaceManager {

    public static func presentMarketplace(
        context: AccountContext,
        peerId: EnginePeer.Id,
        sourceViewController: UIViewController
    ) {
        let controller = RealStarGiftMarketplaceController(
            context: context,
            peerId: peerId
        )

        controller.onGiftSelected = { [weak sourceViewController] gift in
            // При выборе подарка - купить и отправить
            Self.buyAndSendGift(
                context: context,
                gift: gift,
                peerId: peerId,
                sourceViewController: sourceViewController
            )
        }

        sourceViewController.present(controller, animated: true)
    }

    private static func buyAndSendGift(
        context: AccountContext,
        gift: StarGift,
        peerId: EnginePeer.Id,
        sourceViewController: UIViewController?
    ) {
        guard let slug = gift.slug else { return }

        // Получить цену подарка
        let price: CurrencyAmount?
        switch gift {
        case let .generic(g):
            price = g.price.flatMap { CurrencyAmount(currency: "XTR", amount: $0) }
        case let .unique(g):
            price = g.price.flatMap { CurrencyAmount(currency: "XTR", amount: $0) }
        }

        // Попытаться купить подарок
        let _ = context.engine.payments.buyStarGift(slug: slug, peerId: peerId, price: price).start(
            completed: {
                // После успешной покупки - отправить подарок
                // TODO: Реализовать отправку после покупки
            },
            error: { error in
                print("Ошибка при покупке подарка: \(error)")
            }
        )
    }
}

// MARK: - Extension для получения slug и цены из StarGift

extension StarGift {
    var slug: String? {
        switch self {
        case let .generic(gift):
            return nil
        case let .unique(gift):
            return gift.slug
        }
    }
}
