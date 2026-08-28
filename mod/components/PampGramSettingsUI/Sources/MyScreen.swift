//
//  PhantomGiftMod.swift
//  Visual Telegram Gifts Mod
//

import UIKit
import TelegramCore
import AccountContext
import SDWebImage

// MARK: - Notifications

extension Notification.Name {
    static let phantomGiftSent = Notification.Name("phantomGiftSent")
    static let phantomGiftBalanceChanged = Notification.Name("phantomGiftBalanceChanged")
}

// MARK: - Gift

struct Gift: Hashable {
    let id: String
    let title: String
    let price: Int
    let thumbnail: URL?
    let isNFT: Bool

    let model: String
    let background: String
    let pattern: String

    let rarity: Double
    let totalSupply: Int
    let issued: Int
    let valueUSD: Double

    var shortID: String {
        String(id.suffix(6))
    }

    var displayID: String {
        "#\(shortID)"
    }

    var supplyText: String {
        "\(issued)/\(totalSupply) выпущено"
    }
}

// MARK: - Purchase Error

enum PhantomGiftPurchaseError: LocalizedError {
    case insufficientBalance
    case userUnavailable

    var errorDescription: String? {
        switch self {
        case .insufficientBalance:
            return "Недостаточно звёзд"
        case .userUnavailable:
            return "Пользователь недоступен"
        }
    }
}

// MARK: - Main Mod

final class PhantomGiftMod: NSObject {

    static let shared = PhantomGiftMod()

    private enum StorageKeys {
        static let balance = "phantomGiftBalance"
    }

    private let defaultBalance = 16_700

    private(set) var targetUser: TelegramUser?
    private(set) var context: AccountContext?
    private(set) var gifts: [Gift] = []

    weak var navigationController: UINavigationController?

    private(set) var visualBalance: Int {
        didSet {
            UserDefaults.standard.set(
                visualBalance,
                forKey: StorageKeys.balance
            )

            NotificationCenter.default.post(
                name: .phantomGiftBalanceChanged,
                object: self,
                userInfo: [
                    "balance": visualBalance
                ]
            )
        }
    }

    private override init() {
        if UserDefaults.standard.object(
            forKey: StorageKeys.balance
        ) != nil {
            visualBalance = UserDefaults.standard.integer(
                forKey: StorageKeys.balance
            )
        } else {
            visualBalance = defaultBalance
        }

        super.init()
    }

    // MARK: Entry Point

    func showGiftFlow(
        for user: TelegramUser,
        context: AccountContext,
        nav: UINavigationController
    ) {
        targetUser = user
        self.context = context
        navigationController = nav

        loadGifts { [weak self] gifts in
            guard let self else { return }

            self.gifts = gifts

            DispatchQueue.main.async {
                self.presentMainScreen()
            }
        }
    }

    // MARK: Loading

    private func loadGifts(
        completion: @escaping ([Gift]) -> Void
    ) {
        guard let context else {
            completion([])
            return
        }

        let _ = context.engine.payments
            .getStarGifts()
            .start(
                next: { list in

                    let gifts = list.map { item in
                        Gift(
                            id: item.id,
                            title: item.title,
                            price: item.starsRequired,
                            thumbnail: item.thumbnail,
                            isNFT: item.isNFT,
                            model: item.modelName ?? "Standard",
                            background: item.backgroundName ?? "Default",
                            pattern: item.patternName ?? "None",
                            rarity: item.rarity ?? 1.0,
                            totalSupply: item.totalSupply ?? 0,
                            issued: item.issuedCount ?? 0,
                            valueUSD: item.valueUSD ?? 0.0
                        )
                    }

                    completion(gifts)
                },
                error: { _ in
                    completion([])
                }
            )
    }

    // MARK: Navigation

    private func presentMainScreen() {
        let controller = GiftsMainController()
        controller.mod = self

        navigationController?.pushViewController(
            controller,
            animated: true
        )
    }

    // MARK: Visual Purchase

    func performVisualPurchase(
        gift: Gift,
        completion: @escaping (Result<Void, PhantomGiftPurchaseError>) -> Void
    ) {
        guard targetUser != nil else {
            completion(.failure(.userUnavailable))
            return
        }

        guard visualBalance >= gift.price else {
            completion(.failure(.insufficientBalance))
            return
        }

        visualBalance -= gift.price

        postVisualGiftEvent(gift)

        completion(.success(()))
    }

    private func postVisualGiftEvent(_ gift: Gift) {
        guard let targetUser else { return }

        NotificationCenter.default.post(
            name: .phantomGiftSent,
            object: self,
            userInfo: [
                "user": targetUser,
                "gift": gift
            ]
        )
    }

    // MARK: Optional Balance Reset

    func resetVisualBalance() {
        visualBalance = defaultBalance
    }

    func addVisualStars(_ amount: Int) {
        guard amount > 0 else { return }

        visualBalance += amount
    }
}

// MARK: - Gift Tabs

private enum GiftTab: Int {
    case all = 0
    case mine
    case collectible
    case phantom
}

// MARK: - Main Controller

final class GiftsMainController: UIViewController {

    weak var mod: PhantomGiftMod?

    private let segments = [
        "Все",
        "Мои",
        "Коллекционные",
        "Фантом"
    ]

    private var selectedTab: GiftTab = .all

    private let balanceView = UIView()
    private let balanceLabel = UILabel()

    private var segmentedControl: UISegmentedControl!
    private var collectionView: UICollectionView!

    private var displayedGifts: [Gift] {
        guard let mod else {
            return []
        }

        switch selectedTab {
        case .all:
            return mod.gifts

        case .mine:
            return loadMyGifts()

        case .collectible:
            return mod.gifts.filter(\.isNFT)

        case .phantom:
            return mod.gifts
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Отправить подарок"

        view.backgroundColor = UIColor(
            red: 0.95,
            green: 0.95,
            blue: 0.96,
            alpha: 1
        )

        setupBalance()
        setupSegments()
        setupCollectionView()

        updateBalance()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(balanceDidChange),
            name: .phantomGiftBalanceChanged,
            object: mod
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: Balance

    private func setupBalance() {
        balanceView.backgroundColor = .white
        balanceView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(balanceView)

        balanceLabel.font = .systemFont(
            ofSize: 18,
            weight: .semibold
        )

        balanceLabel.translatesAutoresizingMaskIntoConstraints = false

        let buyButton = UIButton(type: .system)

        buyButton.setTitle(
            "Купить звёзды",
            for: .normal
        )

        buyButton.setTitleColor(
            .systemBlue,
            for: .normal
        )

        buyButton.addTarget(
            self,
            action: #selector(buyStars),
            for: .touchUpInside
        )

        buyButton.translatesAutoresizingMaskIntoConstraints = false

        balanceView.addSubview(balanceLabel)
        balanceView.addSubview(buyButton)

        NSLayoutConstraint.activate([
            balanceView.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor
            ),

            balanceView.leadingAnchor.constraint(
                equalTo: view.leadingAnchor
            ),

            balanceView.trailingAnchor.constraint(
                equalTo: view.trailingAnchor
            ),

            balanceView.heightAnchor.constraint(
                equalToConstant: 56
            ),

            balanceLabel.leadingAnchor.constraint(
                equalTo: balanceView.leadingAnchor,
                constant: 16
            ),

            balanceLabel.centerYAnchor.constraint(
                equalTo: balanceView.centerYAnchor
            ),

            buyButton.trailingAnchor.constraint(
                equalTo: balanceView.trailingAnchor,
                constant: -16
            ),

            buyButton.centerYAnchor.constraint(
                equalTo: balanceView.centerYAnchor
            )
        ])
    }

    private func updateBalance() {
        balanceLabel.text = "⭐ \(mod?.visualBalance ?? 0)"
    }

    @objc private func balanceDidChange() {
        updateBalance()
    }

    // MARK: Segments

    private func setupSegments() {
        segmentedControl = UISegmentedControl(
            items: segments
        )

        segmentedControl.selectedSegmentIndex = 0

        segmentedControl.addTarget(
            self,
            action: #selector(tabChanged),
            for: .valueChanged
        )

        segmentedControl.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(segmentedControl)

        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(
                equalTo: balanceView.bottomAnchor,
                constant: 8
            ),

            segmentedControl.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: 16
            ),

            segmentedControl.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -16
            ),

            segmentedControl.heightAnchor.constraint(
                equalToConstant: 32
            )
        ])
    }

    @objc private func tabChanged() {
        selectedTab = GiftTab(
            rawValue: segmentedControl.selectedSegmentIndex
        ) ?? .all

        collectionView.reloadData()
    }

    // MARK: Collection

    private func setupCollectionView() {
        let layout = UICollectionViewFlowLayout()

        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 12

        collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: layout
        )

        collectionView.register(
            GiftCell.self,
            forCellWithReuseIdentifier: GiftCell.reuseIdentifier
        )

        collectionView.delegate = self
        collectionView.dataSource = self

        collectionView.backgroundColor = .clear

        collectionView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(
                equalTo: segmentedControl.bottomAnchor,
                constant: 12
            ),

            collectionView.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: 8
            ),

            collectionView.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -8
            ),

            collectionView.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor
            )
        ])
    }

    private func loadMyGifts() -> [Gift] {
        // Здесь можно подключить реальные локальные
        // данные пользователя.
        return []
    }

    // MARK: Buy Stars

    @objc private func buyStars() {
        let alert = UIAlertController(
            title: "Покупка звёзд",
            message: "Это визуальный баланс мода.",
            preferredStyle: .alert
        )

        alert.addAction(
            UIAlertAction(
                title: "+1000 ⭐",
                style: .default
            ) { [weak self] _ in
                self?.mod?.addVisualStars(1_000)
            }
        )

        alert.addAction(
            UIAlertAction(
                title: "Отмена",
                style: .cancel
            )
        )

        present(alert, animated: true)
    }
}

// MARK: - Collection View

extension GiftsMainController:
    UICollectionViewDataSource,
    UICollectionViewDelegate,
    UICollectionViewDelegateFlowLayout {

    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        displayedGifts.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {

        guard
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: GiftCell.reuseIdentifier,
                for: indexPath
            ) as? GiftCell
        else {
            return UICollectionViewCell()
        }

        cell.configure(
            with: displayedGifts[indexPath.item]
        )

        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didSelectItemAt indexPath: IndexPath
    ) {
        let gifts = displayedGifts

        guard gifts.indices.contains(indexPath.item) else {
            return
        }

        let controller = GiftDetailController()

        controller.gift = gifts[indexPath.item]
        controller.mod = mod

        navigationController?.pushViewController(
            controller,
            animated: true
        )
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {

        let spacing: CGFloat = 16
        let width = (collectionView.bounds.width - spacing) / 3

        return CGSize(
            width: floor(width),
            height: floor(width) + 50
        )
    }
}

// MARK: - Gift Cell

final class GiftCell: UICollectionViewCell {

    static let reuseIdentifier = "GiftCell"

    private let giftImageView = UIImageView()
    private let titleLabel = UILabel()
    private let priceLabel = UILabel()
    private let idLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        contentView.backgroundColor = .white

        contentView.layer.cornerRadius = 12
        contentView.layer.cornerCurve = .continuous

        contentView.layer.shadowOpacity = 0.05
        contentView.layer.shadowRadius = 4
        contentView.layer.shadowOffset = CGSize(
            width: 0,
            height: 2
        )

        giftImageView.contentMode = .scaleAspectFit
        giftImageView.clipsToBounds = true

        titleLabel.font = .systemFont(
            ofSize: 12,
            weight: .medium
        )

        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 1

        priceLabel.font = .systemFont(ofSize: 10)
        priceLabel.textColor = .secondaryLabel
        priceLabel.textAlignment = .center

        idLabel.font = .systemFont(ofSize: 9)
        idLabel.textColor = .tertiaryLabel
        idLabel.textAlignment = .center

        let stack = UIStackView(
            arrangedSubviews: [
                giftImageView,
                titleLabel,
                priceLabel,
                idLabel
            ]
        )

        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .center

        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(
                equalTo: contentView.topAnchor,
                constant: 8
            ),

            stack.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: 4
            ),

            stack.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -4
            ),

            stack.bottomAnchor.constraint(
                lessThanOrEqualTo: contentView.bottomAnchor,
                constant: -8
            ),

            giftImageView.widthAnchor.constraint(
                equalToConstant: 70
            ),

            giftImageView.heightAnchor.constraint(
                equalToConstant: 70
            )
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        giftImageView.sd_cancelCurrentImageLoad()

        giftImageView.image = nil
        titleLabel.text = nil
        priceLabel.text = nil
        idLabel.text = nil
    }

    func configure(with gift: Gift) {
        titleLabel.text = gift.title
        priceLabel.text = "⭐ \(gift.price)"
        idLabel.text = gift.displayID

        giftImageView.sd_setImage(
            with: gift.thumbnail,
            placeholderImage: UIImage(
                named: "gift_placeholder"
            )
        )
    }
}

// MARK: - Gift Detail

final class GiftDetailController: UIViewController {

    var gift: Gift?
    weak var mod: PhantomGiftMod?

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        title = gift?.title ?? "Подарок"

        setupUI()
    }

    private func setupUI() {
        guard let gift else {
            return
        }

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollView)

        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.addSubview(contentView)

        let imageView = UIImageView()

        imageView.sd_setImage(
            with: gift.thumbnail,
            placeholderImage: UIImage(
                named: "gift_placeholder"
            )
        )

        imageView.contentMode = .scaleAspectFit

        let titleLabel = UILabel()

        titleLabel.text = "\(gift.title) \(gift.displayID)"
        titleLabel.font = .boldSystemFont(ofSize: 20)
        titleLabel.textAlignment = .center

        let issuedLabel = UILabel()

        issuedLabel.text = "Выпущен @\(gift.title.lowercased())"
        issuedLabel.font = .systemFont(ofSize: 14)
        issuedLabel.textColor = .secondaryLabel

        let modelLabel = UILabel()
        modelLabel.text = "Модель: \(gift.model)"

        let backgroundLabel = UILabel()
        backgroundLabel.text = "Фон: \(gift.background)"

        let patternLabel = UILabel()
        patternLabel.text = "Узор: \(gift.pattern)"

        let rarityLabel = UILabel()
        rarityLabel.text = String(
            format: "Редкость: %.2f%%",
            gift.rarity
        )

        rarityLabel.font = .systemFont(ofSize: 12)
        rarityLabel.textColor = .secondaryLabel

        let supplyLabel = UILabel()
        supplyLabel.text = "Наличие: \(gift.supplyText)"
        supplyLabel.font = .systemFont(ofSize: 12)
        supplyLabel.textColor = .secondaryLabel

        let valueLabel = UILabel()

        valueLabel.text = String(
            format: "Ценность: ~%.2f ₽",
            gift.valueUSD
        )

        valueLabel.font = .systemFont(ofSize: 12)
        valueLabel.textColor = .systemBlue

        let buyButton = UIButton(type: .system)

        buyButton.setTitle(
            "Купить за ★\(gift.price)",
            for: .normal
        )

        buyButton.backgroundColor = .systemBlue

        buyButton.setTitleColor(
            .white,
            for: .normal
        )

        buyButton.titleLabel?.font = .systemFont(
            ofSize: 16,
            weight: .semibold
        )

        buyButton.layer.cornerRadius = 12

        buyButton.addTarget(
            self,
            action: #selector(buy),
            for: .touchUpInside
        )

        let stack = UIStackView(
            arrangedSubviews: [
                imageView,
                titleLabel,
                issuedLabel,
                modelLabel,
                backgroundLabel,
                patternLabel,
                rarityLabel,
                supplyLabel,
                valueLabel,
                buyButton
            ]
        )

        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .center

        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor
            ),

            scrollView.leadingAnchor.constraint(
                equalTo: view.leadingAnchor
            ),

            scrollView.trailingAnchor.constraint(
                equalTo: view.trailingAnchor
            ),

            scrollView.bottomAnchor.constraint(
                equalTo: view.bottomAnchor
            ),

            contentView.topAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.topAnchor
            ),

            contentView.leadingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.leadingAnchor
            ),

            contentView.trailingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.trailingAnchor
            ),

            contentView.bottomAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.bottomAnchor
            ),

            contentView.widthAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.widthAnchor
            ),

            stack.topAnchor.constraint(
                equalTo: contentView.topAnchor,
                constant: 20
            ),

            stack.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: 24
            ),

            stack.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -24
            ),

            stack.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor,
                constant: -40
            ),

            imageView.widthAnchor.constraint(
                equalToConstant: 200
            ),

            imageView.heightAnchor.constraint(
                equalToConstant: 200
            ),

            buyButton.widthAnchor.constraint(
                equalToConstant: 220
            ),

            buyButton.heightAnchor.constraint(
                equalToConstant: 50
            )
        ])
    }

    @objc private func buy() {
        guard gift != nil else {
            return
        }

        let controller = GiftConfirmController()

        controller.gift = gift
        controller.mod = mod

        controller.modalPresentationStyle = .overFullScreen
        controller.modalTransitionStyle = .crossDissolve

        present(
            controller,
            animated: true
        )
    }
}

// MARK: - Confirmation

final class GiftConfirmController: UIViewController {

    var gift: Gift?
    weak var mod: PhantomGiftMod?

    private let containerView = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor.black.withAlphaComponent(0.45)

        setupPopup()
    }

    private func setupPopup() {
        guard
            let gift,
            let user = mod?.targetUser
        else {
            return
        }

        containerView.backgroundColor = .systemBackground
        containerView.layer.cornerRadius = 20
        containerView.layer.cornerCurve = .continuous

        containerView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(containerView)

        let titleLabel = UILabel()

        titleLabel.text = "Подтверждение оплаты"
        titleLabel.font = .boldSystemFont(ofSize: 18)
        titleLabel.textAlignment = .center

        let messageLabel = UILabel()

        let userName = user.displayName ?? "пользователю"

        messageLabel.text =
            """
            Вы точно хотите купить \(gift.title) \(gift.displayID) \
            за \(gift.price) звёзд и подарить \(userName)?
            """

        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.font = .systemFont(ofSize: 14)

        let balanceLabel = UILabel()

        balanceLabel.text =
            "Ваш баланс: ⭐ \(mod?.visualBalance ?? 0)"

        balanceLabel.font = .systemFont(
            ofSize: 13,
            weight: .medium
        )

        balanceLabel.textColor = .secondaryLabel

        let buyButton = UIButton(type: .system)

        buyButton.setTitle(
            "Купить за ★\(gift.price)",
            for: .normal
        )

        buyButton.backgroundColor = .systemBlue

        buyButton.setTitleColor(
            .white,
            for: .normal
        )

        buyButton.layer.cornerRadius = 12

        buyButton.addTarget(
            self,
            action: #selector(confirmPurchase),
            for: .touchUpInside
        )

        let cancelButton = UIButton(type: .system)

        cancelButton.setTitle(
            "Отмена",
            for: .normal
        )

        cancelButton.setTitleColor(
            .systemRed,
            for: .normal
        )

        cancelButton.addTarget(
            self,
            action: #selector(cancel),
            for: .touchUpInside
        )

        let stack = UIStackView(
            arrangedSubviews: [
                titleLabel,
                messageLabel,
                balanceLabel,
                buyButton,
                cancelButton
            ]
        )

        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .center

        stack.translatesAutoresizingMaskIntoConstraints = false

        containerView.addSubview(stack)

        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(
                equalTo: view.centerXAnchor
            ),

            containerView.centerYAnchor.constraint(
                equalTo: view.centerYAnchor
            ),

            containerView.leadingAnchor.constraint(
                greaterThanOrEqualTo: view.leadingAnchor,
                constant: 24
            ),

            containerView.trailingAnchor.constraint(
                lessThanOrEqualTo: view.trailingAnchor,
                constant: -24
            ),

            containerView.widthAnchor.constraint(
                lessThanOrEqualToConstant: 340
            ),

            stack.topAnchor.constraint(
                equalTo: containerView.topAnchor,
                constant: 24
            ),

            stack.leadingAnchor.constraint(
                equalTo: containerView.leadingAnchor,
                constant: 20
            ),

            stack.trailingAnchor.constraint(
                equalTo: containerView.trailingAnchor,
                constant: -20
            ),

            stack.bottomAnchor.constraint(
                equalTo: containerView.bottomAnchor,
                constant: -20
            ),

            buyButton.widthAnchor.constraint(
                equalToConstant: 220
            ),

            buyButton.heightAnchor.constraint(
                equalToConstant: 46
            )
        ])
    }

    @objc private func confirmPurchase() {
        guard
            let gift,
            let mod
        else {
            return
        }

        mod.performVisualPurchase(
            gift: gift
        ) { [weak self] result in

            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                switch result {
                case .success:
                    self.handleSuccessfulPurchase()

                case .failure(let error):
                    self.showPurchaseError(error)
                }
            }
        }
    }

    private func handleSuccessfulPurchase() {
        dismiss(animated: true) { [weak self] in
            guard let self else {
                return
            }

            guard let window = UIApplication.shared.phantomKeyWindow else {
                self.showSuccessAlert()
                return
            }

            GiftFireworksEffect.shared.showFireworks(
                in: window
            ) { [weak self] in
                self?.showSuccessAlert()
            }
        }
    }

    private func showSuccessAlert() {
        let name =
            mod?.targetUser?.displayName
            ?? "Пользователь"

        let alert = UIAlertController(
            title: "🎁 Подарок отправлен!",
            message:
                "\(name) получил(а) визуальное уведомление о подарке.",
            preferredStyle: .alert
        )

        alert.addAction(
            UIAlertAction(
                title: "Отлично!",
                style: .default
            )
        )

        UIApplication.shared
            .phantomTopViewController()?
            .present(
                alert,
                animated: true
            )
    }

    private func showPurchaseError(
        _ error: PhantomGiftPurchaseError
    ) {
        let message: String

        switch error {
        case .insufficientBalance:
            message = "Пополните визуальный баланс."

        case .userUnavailable:
            message = "Не удалось определить получателя."
        }

        let alert = UIAlertController(
            title: "❌ \(error.localizedDescription)",
            message: message,
            preferredStyle: .alert
        )

        alert.addAction(
            UIAlertAction(
                title: "OK",
                style: .default
            )
        )

        present(alert, animated: true)
    }

    @objc private func cancel() {
        dismiss(animated: true)
    }
}

// MARK: - Fireworks

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

        overlay.backgroundColor =
            UIColor.black.withAlphaComponent(0.3)

        overlay.autoresizingMask = [
            .flexibleWidth,
            .flexibleHeight
        ]

        view.addSubview(overlay)

        overlayView = overlay

        let container = UIView(frame: view.bounds)

        container.backgroundColor = .clear
        container.isUserInteractionEnabled = false

        container.autoresizingMask = [
            .flexibleWidth,
            .flexibleHeight
        ]

        view.addSubview(container)

        fireworksContainer = container

        let positions: [CGPoint] = [
            CGPoint(
                x: view.bounds.width * 0.20,
                y: view.bounds.height * 0.30
            ),
            CGPoint(
                x: view.bounds.width * 0.50,
                y: view.bounds.height * 0.20
            ),
            CGPoint(
                x: view.bounds.width * 0.80,
                y: view.bounds.height * 0.35
            ),
            CGPoint(
                x: view.bounds.width * 0.35,
                y: view.bounds.height * 0.15
            ),
            CGPoint(
                x: view.bounds.width * 0.65,
                y: view.bounds.height * 0.25
            )
        ]

        for (index, position) in positions.enumerated() {
            DispatchQueue.main.asyncAfter(
                deadline: .now() + Double(index) * 0.15
            ) { [weak self, weak container] in

                guard
                    let self,
                    let container,
                    self.isShowing
                else {
                    return
                }

                self.createFireworkBurst(
                    at: position,
                    in: container
                )
            }
        }

        DispatchQueue.main.asyncAfter(
            deadline: .now() + 1
        ) { [weak self, weak container] in

            guard
                let self,
                let container,
                self.isShowing
            else {
                return
            }

            self.createSecondaryBurst(
                in: container
            )
        }

        DispatchQueue.main.asyncAfter(
            deadline: .now() + 3
        ) { [weak self] in

            self?.dismissFireworks(
                completion: completion
            )
        }
    }

    private func createFireworkBurst(
        at position: CGPoint,
        in container: UIView
    ) {
        let emitter = CAEmitterLayer()

        emitter.emitterPosition = position
        emitter.emitterShape = .circle

        emitter.emitterSize = CGSize(
            width: 20,
            height: 20
        )

        emitter.renderMode = .unordered
        emitter.birthRate = 1

        let colors: [UIColor] = [
            .systemRed,
            .systemOrange,
            .systemYellow,
            .systemGreen,
            .systemBlue,
            .systemPurple,
            .systemPink,
            .white
        ]

        let cells = colors
            .shuffled()
            .prefix(Int.random(in: 3...5))
            .map(createParticleCell)

        emitter.emitterCells = Array(cells)

        container.layer.addSublayer(emitter)
        emitterLayers.append(emitter)

        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.15
        ) {
            emitter.birthRate = 0
        }

        DispatchQueue.main.asyncAfter(
            deadline: .now() + 2
        ) { [weak self, weak emitter] in

            emitter?.removeFromSuperlayer()

            self?.emitterLayers.removeAll {
                $0 === emitter
            }
        }
    }

    private func createParticleCell(
        color: UIColor
    ) -> CAEmitterCell {

        let cell = CAEmitterCell()

        cell.contents = createSparkImage(
            color: color
        )

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

    private func createSparkImage(
        color: UIColor
    ) -> CGImage? {

        let size = CGSize(
            width: 20,
            height: 20
        )

        let renderer = UIGraphicsImageRenderer(
            size: size
        )

        let image = renderer.image { context in
            let cgContext = context.cgContext

            let rect = CGRect(
                origin: .zero,
                size: size
            )

            cgContext.setFillColor(
                color.withAlphaComponent(0.35).cgColor
            )

            cgContext.fillEllipse(in: rect)

            let center = rect.insetBy(
                dx: 5,
                dy: 5
            )

            cgContext.setFillColor(
                color.cgColor
            )

            cgContext.fillEllipse(
                in: center
            )
        }

        return image.cgImage
    }

    private func createSecondaryBurst(
        in container: UIView
    ) {
        let positions: [CGPoint] = [
            CGPoint(
                x: container.bounds.width * 0.15,
                y: container.bounds.height * 0.50
            ),
            CGPoint(
                x: container.bounds.width * 0.45,
                y: container.bounds.height * 0.40
            ),
            CGPoint(
                x: container.bounds.width * 0.75,
                y: container.bounds.height * 0.55
            )
        ]

        for (index, position) in positions.enumerated() {
            DispatchQueue.main.asyncAfter(
                deadline: .now() + Double(index) * 0.2
            ) { [weak self, weak container] in

                guard
                    let self,
                    let container,
                    self.isShowing
                else {
                    return
                }

                self.createFireworkBurst(
                    at: position,
                    in: container
                )
            }
        }
    }

    private func dismissFireworks(
        completion: (() -> Void)?
    ) {
        emitterLayers.forEach {
            $0.birthRate = 0
            $0.removeFromSuperlayer()
        }

        emitterLayers.removeAll()

        let group = DispatchGroup()

        if let container = fireworksContainer {
            group.enter()

            UIView.animate(
                withDuration: 0.4,
                animations: {
                    container.alpha = 0
                },
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
                animations: {
                    overlay.alpha = 0
                },
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

// MARK: - UIApplication

extension UIApplication {

    var phantomKeyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter {
                $0.activationState == .foregroundActive
            }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    func phantomTopViewController(
        from controller: UIViewController? = nil
    ) -> UIViewController? {

        let controller =
            controller
            ?? phantomKeyWindow?.rootViewController

        if let navigation =
            controller as? UINavigationController {

            return phantomTopViewController(
                from: navigation.visibleViewController
            )
        }

        if let tab =
            controller as? UITabBarController {

            return phantomTopViewController(
                from: tab.selectedViewController
            )
        }

        if let presented =
            controller?.presentedViewController {

            return phantomTopViewController(
                from: presented
            )
        }

        return controller
    }
}
