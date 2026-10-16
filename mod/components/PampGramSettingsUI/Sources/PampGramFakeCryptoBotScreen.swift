import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import PromptUI
import UndoUI
import PampGramCore

/// Визуальный «CryptoBot мини-апп». Открывается вместо настоящего мини-аппа @CryptoBot, пока
/// включён `fakeCryptoBotEnabled` (подмена в `standaloneWebAppController`, см. патч), либо
/// напрямую из «Дополнительно» → «Открыть фейковый криптобот».
///
/// Экран полностью локальный — ни одна цифра, ни одна кнопка никуда не отправляется.
/// Балансы хранятся в `PampGramSettings.fakeCryptoBotBalances` и редактируются скрытым
/// длинным нажатием (1,2 с) на круглый логотип в шапке — секретная кнопка, о которой
/// знает только владелец устройства.

/// Поддерживаемая валюта. `usdRate` — фиксированный ориентир для подсчёта «итого в USD»
/// в шапке; настоящий курс никто не запрашивает, это чисто визуальный расчёт.
struct PampGramFakeCryptoBotCurrency {
    let code: String
    let name: String
    let glyph: String
    let color: UIColor
    let usdRate: Double
    let fractionDigits: Int
}

let pampGramFakeCryptoBotCurrencies: [PampGramFakeCryptoBotCurrency] = [
    .init(code: "USDT", name: "Tether",   glyph: "₮", color: UIColor(rgb: 0x26a17b), usdRate: 1.00,       fractionDigits: 2),
    .init(code: "USDC", name: "USD Coin", glyph: "⊜", color: UIColor(rgb: 0x2775ca), usdRate: 1.00,       fractionDigits: 2),
    .init(code: "TON",  name: "Toncoin",  glyph: "◇", color: UIColor(rgb: 0x0098ea), usdRate: 5.20,       fractionDigits: 4),
    .init(code: "BTC",  name: "Bitcoin",  glyph: "₿", color: UIColor(rgb: 0xf7931a), usdRate: 68000.0,    fractionDigits: 8),
    .init(code: "ETH",  name: "Ethereum", glyph: "Ξ", color: UIColor(rgb: 0x627eea), usdRate: 3200.0,     fractionDigits: 6),
    .init(code: "LTC",  name: "Litecoin", glyph: "Ł", color: UIColor(rgb: 0x345d9d), usdRate: 85.0,       fractionDigits: 6),
    .init(code: "TRX",  name: "Tron",     glyph: "T", color: UIColor(rgb: 0xeb0029), usdRate: 0.12,       fractionDigits: 4),
    .init(code: "BNB",  name: "BNB",      glyph: "B", color: UIColor(rgb: 0xf3ba2f), usdRate: 580.0,      fractionDigits: 6),
    .init(code: "SOL",  name: "Solana",   glyph: "S", color: UIColor(rgb: 0x9945ff), usdRate: 150.0,      fractionDigits: 4),
    .init(code: "DOGE", name: "Dogecoin", glyph: "Ð", color: UIColor(rgb: 0xc2a633), usdRate: 0.15,       fractionDigits: 2),
    .init(code: "GRAM", name: "Gram",     glyph: "ɡ", color: UIColor(rgb: 0x0088cc), usdRate: 0.0040,     fractionDigits: 4),
    .init(code: "PEPE", name: "Pepe",     glyph: "P", color: UIColor(rgb: 0x4caf50), usdRate: 0.00001,    fractionDigits: 0)
]

private func pampGramFakeCryptoBotFormat(_ amount: Double, fractionDigits: Int) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = fractionDigits
    formatter.groupingSeparator = " "
    formatter.decimalSeparator = "."
    return formatter.string(from: NSNumber(value: amount)) ?? "0"
}

private func pampGramFakeCryptoBotFormatUSD(_ amount: Double) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    formatter.groupingSeparator = ","
    formatter.decimalSeparator = "."
    return formatter.string(from: NSNumber(value: amount)) ?? "0.00"
}

private final class PampGramFakeCryptoBotScreen: ViewController {
    private let context: AccountContext
    private let presentationData: PresentationData
    private let settingsDisposable = MetaDisposable()

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let logoView = UIView()
    private let logoLabel = UILabel()
    private let totalLabel = UILabel()
    private let totalCaptionLabel = UILabel()
    private let coinsStack = UIStackView()
    private var coinRows: [String: PampGramFakeCryptoBotCoinRow] = [:]

    init(context: AccountContext) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: nil)
        self.displayNavigationBar = false
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.settingsDisposable.dispose()
    }

    override func loadDisplayNode() {
        let node = ASDisplayNode()
        node.backgroundColor = UIColor(rgb: 0xf2f5f8)
        self.displayNode = node
        self.displayNodeDidLoad()
        self.configureView(node.view)

        self.settingsDisposable.set((PampGramCore.rawSettingsSignal(postbox: self.context.account.postbox)
        |> deliverOnMainQueue).startStrict(next: { [weak self] settings in
            self?.applyBalances(settings.fakeCryptoBotBalances)
        }))
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let topInset = layout.insets(options: [.statusBar]).top
        let bottomInset = layout.intrinsicInsets.bottom
        self.scrollView.contentInset = UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset + 24, right: 0)
        self.scrollView.verticalScrollIndicatorInsets = UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
    }

    private func configureView(_ rootView: UIView) {
        rootView.backgroundColor = UIColor(rgb: 0xf2f5f8)

        // Шапка под логотипом — ровный тёмно-голубой фон, как в оригинальном
        // CryptoBot. Градиент выпилен специально: его frame пришлось бы вручную
        // пересчитывать после layout, что некрасиво; одноцветной подкладки хватает.
        let headerBg = UIView()
        headerBg.translatesAutoresizingMaskIntoConstraints = false
        headerBg.backgroundColor = UIColor(rgb: 0x1687c7)
        rootView.addSubview(headerBg)
        NSLayoutConstraint.activate([
            headerBg.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            headerBg.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            headerBg.topAnchor.constraint(equalTo: rootView.topAnchor),
            headerBg.heightAnchor.constraint(equalToConstant: 300)
        ])

        // Кнопка «закрыть» в правом верхнем углу.
        let closeButton = UIButton(type: .system)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setTitle("✕", for: .normal)
        closeButton.titleLabel?.font = UIFont.systemFont(ofSize: 28, weight: .regular)
        closeButton.tintColor = .white
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.addTarget(self, action: #selector(self.closePressed), for: .touchUpInside)
        rootView.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -16),
            closeButton.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 52),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44)
        ])

        // Scroll + content.
        self.scrollView.translatesAutoresizingMaskIntoConstraints = false
        self.scrollView.alwaysBounceVertical = true
        self.scrollView.backgroundColor = .clear
        rootView.addSubview(self.scrollView)
        NSLayoutConstraint.activate([
            self.scrollView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            self.scrollView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            self.scrollView.topAnchor.constraint(equalTo: rootView.topAnchor),
            self.scrollView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        ])

        self.contentView.translatesAutoresizingMaskIntoConstraints = false
        self.scrollView.addSubview(self.contentView)
        NSLayoutConstraint.activate([
            self.contentView.leadingAnchor.constraint(equalTo: self.scrollView.leadingAnchor),
            self.contentView.trailingAnchor.constraint(equalTo: self.scrollView.trailingAnchor),
            self.contentView.topAnchor.constraint(equalTo: self.scrollView.topAnchor),
            self.contentView.bottomAnchor.constraint(equalTo: self.scrollView.bottomAnchor),
            self.contentView.widthAnchor.constraint(equalTo: self.scrollView.widthAnchor)
        ])

        // Логотип (секретная долго-нажимаемая кнопка!).
        self.logoView.translatesAutoresizingMaskIntoConstraints = false
        self.logoView.backgroundColor = .white
        self.logoView.layer.cornerRadius = 44
        self.logoView.layer.shadowColor = UIColor.black.cgColor
        self.logoView.layer.shadowOpacity = 0.18
        self.logoView.layer.shadowRadius = 12
        self.logoView.layer.shadowOffset = CGSize(width: 0, height: 6)
        self.contentView.addSubview(self.logoView)
        NSLayoutConstraint.activate([
            self.logoView.centerXAnchor.constraint(equalTo: self.contentView.centerXAnchor),
            self.logoView.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 44),
            self.logoView.widthAnchor.constraint(equalToConstant: 88),
            self.logoView.heightAnchor.constraint(equalToConstant: 88)
        ])

        self.logoLabel.translatesAutoresizingMaskIntoConstraints = false
        self.logoLabel.font = UIFont.systemFont(ofSize: 46, weight: .heavy)
        self.logoLabel.textColor = UIColor(rgb: 0x1f8ed6)
        self.logoLabel.text = "₿"
        self.logoLabel.textAlignment = .center
        self.logoView.addSubview(self.logoLabel)
        NSLayoutConstraint.activate([
            self.logoLabel.centerXAnchor.constraint(equalTo: self.logoView.centerXAnchor),
            self.logoLabel.centerYAnchor.constraint(equalTo: self.logoView.centerYAnchor, constant: -2)
        ])

        // Долгое нажатие (1,2 с) на логотип открывает редактор балансов — это и есть
        // «секретная» кнопка, никакого видимого хинта на экране нет.
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(self.logoLongPressed(_:)))
        longPress.minimumPressDuration = 1.2
        self.logoView.addGestureRecognizer(longPress)
        self.logoView.isUserInteractionEnabled = true

        // Крупный баланс в USD.
        self.totalCaptionLabel.translatesAutoresizingMaskIntoConstraints = false
        self.totalCaptionLabel.text = "Ваш баланс"
        self.totalCaptionLabel.font = UIFont.systemFont(ofSize: 15, weight: .regular)
        self.totalCaptionLabel.textColor = UIColor.white.withAlphaComponent(0.75)
        self.totalCaptionLabel.textAlignment = .center
        self.contentView.addSubview(self.totalCaptionLabel)
        NSLayoutConstraint.activate([
            self.totalCaptionLabel.centerXAnchor.constraint(equalTo: self.contentView.centerXAnchor),
            self.totalCaptionLabel.topAnchor.constraint(equalTo: self.logoView.bottomAnchor, constant: 14)
        ])

        self.totalLabel.translatesAutoresizingMaskIntoConstraints = false
        self.totalLabel.font = UIFont.systemFont(ofSize: 40, weight: .heavy)
        self.totalLabel.textColor = .white
        self.totalLabel.textAlignment = .center
        self.totalLabel.text = "≈ $0.00"
        self.contentView.addSubview(self.totalLabel)
        NSLayoutConstraint.activate([
            self.totalLabel.centerXAnchor.constraint(equalTo: self.contentView.centerXAnchor),
            self.totalLabel.topAnchor.constraint(equalTo: self.totalCaptionLabel.bottomAnchor, constant: 4)
        ])

        // Карточка с кнопками действий (Пополнить / Отправить / Чек / Обмен).
        let actionsCard = UIView()
        actionsCard.translatesAutoresizingMaskIntoConstraints = false
        actionsCard.backgroundColor = .white
        actionsCard.layer.cornerRadius = 20
        actionsCard.layer.shadowColor = UIColor.black.cgColor
        actionsCard.layer.shadowOpacity = 0.06
        actionsCard.layer.shadowRadius = 10
        actionsCard.layer.shadowOffset = CGSize(width: 0, height: 2)
        self.contentView.addSubview(actionsCard)
        NSLayoutConstraint.activate([
            actionsCard.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 16),
            actionsCard.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -16),
            actionsCard.topAnchor.constraint(equalTo: self.totalLabel.bottomAnchor, constant: 32),
            actionsCard.heightAnchor.constraint(equalToConstant: 104)
        ])

        let actions: [(String, String)] = [
            ("arrow.down.circle.fill", "Пополнить"),
            ("arrow.up.circle.fill",   "Отправить"),
            ("doc.text.fill",          "Чек"),
            ("arrow.triangle.swap",    "Обмен")
        ]
        let actionStack = UIStackView()
        actionStack.translatesAutoresizingMaskIntoConstraints = false
        actionStack.axis = .horizontal
        actionStack.distribution = .fillEqually
        actionsCard.addSubview(actionStack)
        NSLayoutConstraint.activate([
            actionStack.leadingAnchor.constraint(equalTo: actionsCard.leadingAnchor),
            actionStack.trailingAnchor.constraint(equalTo: actionsCard.trailingAnchor),
            actionStack.topAnchor.constraint(equalTo: actionsCard.topAnchor),
            actionStack.bottomAnchor.constraint(equalTo: actionsCard.bottomAnchor)
        ])
        for (systemName, title) in actions {
            let button = PampGramFakeCryptoBotActionButton(systemName: systemName, title: title)
            button.addTarget(self, action: #selector(self.actionButtonPressed), for: .touchUpInside)
            actionStack.addArrangedSubview(button)
        }

        // Заголовок «Монеты».
        let coinsHeader = UILabel()
        coinsHeader.translatesAutoresizingMaskIntoConstraints = false
        coinsHeader.text = "Монеты"
        coinsHeader.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        coinsHeader.textColor = UIColor(rgb: 0x8e8e93)
        self.contentView.addSubview(coinsHeader)
        NSLayoutConstraint.activate([
            coinsHeader.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 32),
            coinsHeader.topAnchor.constraint(equalTo: actionsCard.bottomAnchor, constant: 24)
        ])

        // Карточка списка валют.
        let coinsCard = UIView()
        coinsCard.translatesAutoresizingMaskIntoConstraints = false
        coinsCard.backgroundColor = .white
        coinsCard.layer.cornerRadius = 16
        coinsCard.clipsToBounds = true
        self.contentView.addSubview(coinsCard)
        NSLayoutConstraint.activate([
            coinsCard.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 16),
            coinsCard.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -16),
            coinsCard.topAnchor.constraint(equalTo: coinsHeader.bottomAnchor, constant: 8),
            coinsCard.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor, constant: -40)
        ])

        self.coinsStack.translatesAutoresizingMaskIntoConstraints = false
        self.coinsStack.axis = .vertical
        self.coinsStack.spacing = 0
        coinsCard.addSubview(self.coinsStack)
        NSLayoutConstraint.activate([
            self.coinsStack.leadingAnchor.constraint(equalTo: coinsCard.leadingAnchor),
            self.coinsStack.trailingAnchor.constraint(equalTo: coinsCard.trailingAnchor),
            self.coinsStack.topAnchor.constraint(equalTo: coinsCard.topAnchor),
            self.coinsStack.bottomAnchor.constraint(equalTo: coinsCard.bottomAnchor)
        ])

        for (index, currency) in pampGramFakeCryptoBotCurrencies.enumerated() {
            let row = PampGramFakeCryptoBotCoinRow(currency: currency, isLast: index == pampGramFakeCryptoBotCurrencies.count - 1)
            self.coinsStack.addArrangedSubview(row)
            self.coinRows[currency.code] = row
        }
    }

    private func applyBalances(_ balances: [String: Double]) {
        var totalUsd: Double = 0
        for currency in pampGramFakeCryptoBotCurrencies {
            let amount = balances[currency.code] ?? 0
            self.coinRows[currency.code]?.update(amount: amount)
            totalUsd += amount * currency.usdRate
        }
        self.totalLabel.text = "≈ $\(pampGramFakeCryptoBotFormatUSD(totalUsd))"
    }

    @objc private func closePressed() {
        self.dismiss()
    }

    @objc private func actionButtonPressed() {
        let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
        self.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: "Функция недоступна", timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), in: .current)
    }

    @objc private func logoLongPressed(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        pampGramFakeCryptoBotPresentBalanceEditor(context: self.context, presenter: self)
    }
}

/// Кнопка действия в карточке «Пополнить/Отправить/Чек/Обмен»: SF Symbol сверху,
/// подпись снизу. Собственная вёрстка через subviews (а не `imageEdgeInsets`), чтобы
/// избежать депрекейтед-предупреждений под `-warnings-as-errors`.
private final class PampGramFakeCryptoBotActionButton: UIControl {
    init(systemName: String, title: String) {
        super.init(frame: .zero)
        let iconView = UIImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = UIColor(rgb: 0x1f8ed6)
        iconView.image = UIImage(systemName: systemName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .semibold))
        iconView.isUserInteractionEnabled = false
        self.addSubview(iconView)

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = UIColor(rgb: 0x3c3c43)
        label.text = title
        label.textAlignment = .center
        label.isUserInteractionEnabled = false
        self.addSubview(label)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            iconView.topAnchor.constraint(equalTo: self.topAnchor, constant: 22),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),
            label.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            label.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 8)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            self.alpha = self.isHighlighted ? 0.5 : 1.0
        }
    }
}

/// Строка валюты: кружок с глифом + название + баланс + равное-в-USD. Используется в
/// списке «Монеты» на главном экране.
private final class PampGramFakeCryptoBotCoinRow: UIView {
    private let currency: PampGramFakeCryptoBotCurrency
    private let iconView = UIView()
    private let glyphLabel = UILabel()
    private let nameLabel = UILabel()
    private let amountLabel = UILabel()
    private let usdLabel = UILabel()
    private let separator = UIView()

    init(currency: PampGramFakeCryptoBotCurrency, isLast: Bool) {
        self.currency = currency
        super.init(frame: .zero)
        self.translatesAutoresizingMaskIntoConstraints = false
        self.heightAnchor.constraint(equalToConstant: 60).isActive = true

        self.iconView.translatesAutoresizingMaskIntoConstraints = false
        self.iconView.backgroundColor = currency.color
        self.iconView.layer.cornerRadius = 18
        self.addSubview(self.iconView)
        NSLayoutConstraint.activate([
            self.iconView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 16),
            self.iconView.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            self.iconView.widthAnchor.constraint(equalToConstant: 36),
            self.iconView.heightAnchor.constraint(equalToConstant: 36)
        ])

        self.glyphLabel.translatesAutoresizingMaskIntoConstraints = false
        self.glyphLabel.text = currency.glyph
        self.glyphLabel.textColor = .white
        self.glyphLabel.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        self.iconView.addSubview(self.glyphLabel)
        NSLayoutConstraint.activate([
            self.glyphLabel.centerXAnchor.constraint(equalTo: self.iconView.centerXAnchor),
            self.glyphLabel.centerYAnchor.constraint(equalTo: self.iconView.centerYAnchor, constant: -1)
        ])

        self.nameLabel.translatesAutoresizingMaskIntoConstraints = false
        self.nameLabel.text = currency.name
        self.nameLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        self.nameLabel.textColor = UIColor(rgb: 0x1c1c1e)
        self.addSubview(self.nameLabel)
        NSLayoutConstraint.activate([
            self.nameLabel.leadingAnchor.constraint(equalTo: self.iconView.trailingAnchor, constant: 12),
            self.nameLabel.topAnchor.constraint(equalTo: self.centerYAnchor, constant: -17)
        ])

        let codeLabel = UILabel()
        codeLabel.translatesAutoresizingMaskIntoConstraints = false
        codeLabel.text = currency.code
        codeLabel.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        codeLabel.textColor = UIColor(rgb: 0x8e8e93)
        self.addSubview(codeLabel)
        NSLayoutConstraint.activate([
            codeLabel.leadingAnchor.constraint(equalTo: self.iconView.trailingAnchor, constant: 12),
            codeLabel.topAnchor.constraint(equalTo: self.nameLabel.bottomAnchor, constant: 1)
        ])

        self.amountLabel.translatesAutoresizingMaskIntoConstraints = false
        self.amountLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        self.amountLabel.textColor = UIColor(rgb: 0x1c1c1e)
        self.amountLabel.textAlignment = .right
        self.addSubview(self.amountLabel)
        NSLayoutConstraint.activate([
            self.amountLabel.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -16),
            self.amountLabel.topAnchor.constraint(equalTo: self.centerYAnchor, constant: -17)
        ])

        self.usdLabel.translatesAutoresizingMaskIntoConstraints = false
        self.usdLabel.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        self.usdLabel.textColor = UIColor(rgb: 0x8e8e93)
        self.usdLabel.textAlignment = .right
        self.addSubview(self.usdLabel)
        NSLayoutConstraint.activate([
            self.usdLabel.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -16),
            self.usdLabel.topAnchor.constraint(equalTo: self.amountLabel.bottomAnchor, constant: 1)
        ])

        if !isLast {
            self.separator.translatesAutoresizingMaskIntoConstraints = false
            self.separator.backgroundColor = UIColor(rgb: 0xe5e5ea)
            self.addSubview(self.separator)
            NSLayoutConstraint.activate([
                self.separator.leadingAnchor.constraint(equalTo: self.iconView.trailingAnchor, constant: 12),
                self.separator.trailingAnchor.constraint(equalTo: self.trailingAnchor),
                self.separator.bottomAnchor.constraint(equalTo: self.bottomAnchor),
                self.separator.heightAnchor.constraint(equalToConstant: 0.5)
            ])
        }

        self.update(amount: 0)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(amount: Double) {
        self.amountLabel.text = pampGramFakeCryptoBotFormat(amount, fractionDigits: self.currency.fractionDigits)
        let usd = amount * self.currency.usdRate
        self.usdLabel.text = "≈ $\(pampGramFakeCryptoBotFormatUSD(usd))"
    }
}

// MARK: - Балансы: редактор

private func pampGramFakeCryptoBotPlain(_ amount: Double) -> String {
    if amount == amount.rounded(), abs(amount) < 1e15 {
        return String(Int64(amount))
    }
    return String(amount)
}

/// Выбор монеты (ActionSheet), затем ввод суммы (promptController). Оба показываются через
/// `present(_, in: .window(.root))`, поэтому работают и когда экран открыт модально
/// мини-аппом, и когда он запушен из настроек.
private func pampGramFakeCryptoBotPresentBalanceEditor(context: AccountContext, presenter: ViewController) {
    let _ = (PampGramCore.rawSettingsSignal(postbox: context.account.postbox)
    |> take(1)
    |> deliverOnMainQueue).start(next: { [weak presenter] settings in
        guard let presenter = presenter else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let balances = settings.fakeCryptoBotBalances
        let sheet = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = [ActionSheetTextItem(title: "Баланс какой монеты изменить?")]
        for currency in pampGramFakeCryptoBotCurrencies {
            let amount = balances[currency.code] ?? 0
            let title = "\(currency.code) — \(pampGramFakeCryptoBotFormat(amount, fractionDigits: currency.fractionDigits))"
            items.append(ActionSheetButtonItem(title: title, color: .accent, action: { [weak sheet, weak presenter] in
                sheet?.dismissAnimated()
                guard let presenter = presenter else {
                    return
                }
                pampGramFakeCryptoBotPromptBalance(context: context, presenter: presenter, currency: currency, current: amount)
            }))
        }
        sheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                })
            ])
        ])
        presenter.present(sheet, in: .window(.root))
    })
}

private func pampGramFakeCryptoBotPromptBalance(context: AccountContext, presenter: ViewController, currency: PampGramFakeCryptoBotCurrency, current: Double) {
    presenter.present(promptController(
        context: context,
        text: "Баланс \(currency.code)",
        subtitle: "Любое число. Хранится только на этом устройстве. 0 — убрать.",
        value: current > 0 ? pampGramFakeCryptoBotPlain(current) : "",
        placeholder: "0",
        characterLimit: 24,
        apply: { entered in
            guard let entered = entered else {
                return
            }
            let cleaned = entered.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")
            var value = Double(cleaned) ?? 0
            if !value.isFinite || value < 0 {
                value = 0
            }
            value = min(value, 1e15)
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                var balances = settings.fakeCryptoBotBalances
                if value <= 0 {
                    balances.removeValue(forKey: currency.code)
                } else {
                    balances[currency.code] = value
                }
                settings.fakeCryptoBotBalances = balances
                return settings
            }).start()
        }
    ), in: .window(.root))
}

// MARK: - Публичный конструктор

/// Открывает полноэкранный визуал «CryptoBot мини-апп» на этом устройстве. Балансы
/// подставляются из `PampGramSettings.fakeCryptoBotBalances`; редактор открывается
/// длинным нажатием на круглый логотип в шапке (1,2 с).
public func pampGramFakeCryptoBotController(context: AccountContext) -> ViewController {
    return PampGramFakeCryptoBotScreen(context: context)
}
