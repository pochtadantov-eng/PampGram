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

/// Визуальная копия мини-аппа @CryptoBot (тёмная тема), снятая с записи экрана настоящего:
/// шапка «Закрыть / Crypto Bot / мини-приложение», общий баланс, «Пополнить / Вывести / История»,
/// баннеры, список активов, экраны «Пополнение» и «Вывод» с поиском и нижний таб-бар. Открывается
/// вместо настоящего мини-аппа, пока включён `fakeCryptoBotEnabled` (подмена в
/// `standaloneWebAppController`, см. патч), либо напрямую из «Дополнительно».
///
/// Экран полностью локальный — ничего никуда не отправляется. Балансы хранятся в
/// `PampGramSettings.fakeCryptoBotBalances`; редактор открывается удержанием суммы общего
/// баланса (около секунды) — никаких видимых подсказок об этом на экране нет.

struct PampGramFakeCryptoBotCurrency {
    let code: String
    let name: String
    let assetName: String
    let price: Double
    let priceText: String
    let change: Double
    let fractionDigits: Int
}

let pampGramFakeCryptoBotCurrencies: [PampGramFakeCryptoBotCurrency] = [
    PampGramFakeCryptoBotCurrency(code: "USDT", name: "Tether", assetName: "coin_USDT", price: 0.9988, priceText: "$0.9988", change: 0.0, fractionDigits: 2),
    PampGramFakeCryptoBotCurrency(code: "GRAM", name: "Gram", assetName: "coin_GRAM", price: 1.33, priceText: "$1.33", change: -3.44, fractionDigits: 4),
    PampGramFakeCryptoBotCurrency(code: "SOL", name: "Solana", assetName: "coin_SOL", price: 104.21, priceText: "$104.21", change: -1.0, fractionDigits: 4),
    PampGramFakeCryptoBotCurrency(code: "TRX", name: "TRON", assetName: "coin_TRX", price: 0.3348, priceText: "$0.3348", change: 0.84, fractionDigits: 4),
    PampGramFakeCryptoBotCurrency(code: "BTC", name: "Bitcoin", assetName: "coin_BTC", price: 80555.61, priceText: "$80,555.61", change: -2.09, fractionDigits: 8),
    PampGramFakeCryptoBotCurrency(code: "ETH", name: "Ethereum", assetName: "coin_ETH", price: 2388.13, priceText: "$2,388.13", change: -2.29, fractionDigits: 6),
    PampGramFakeCryptoBotCurrency(code: "DOGE", name: "Dogecoin", assetName: "coin_DOGE", price: 0.08075, priceText: "$0.08075", change: -0.28, fractionDigits: 2),
    PampGramFakeCryptoBotCurrency(code: "LTC", name: "Litecoin", assetName: "coin_LTC", price: 59.65, priceText: "$59.65", change: -1.65, fractionDigits: 6),
    PampGramFakeCryptoBotCurrency(code: "BNB", name: "Binance Coin", assetName: "coin_BNB", price: 721.21, priceText: "$721.21", change: -0.81, fractionDigits: 6),
    PampGramFakeCryptoBotCurrency(code: "USDC", name: "USD Coin", assetName: "coin_USDC", price: 0.9998, priceText: "$0.9998", change: 0.0, fractionDigits: 2),
    PampGramFakeCryptoBotCurrency(code: "XAUT", name: "Tether Gold", assetName: "coin_XAUT", price: 4152.71, priceText: "$4,152.71", change: 0.0, fractionDigits: 4)
]

private func pampGramFakeCryptoBotFormat(_ amount: Double, fractionDigits: Int) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = fractionDigits
    formatter.groupingSeparator = " "
    formatter.usesGroupingSeparator = true
    formatter.decimalSeparator = "."
    return formatter.string(from: NSNumber(value: amount)) ?? "0"
}

/// "0" for nothing, two decimals from a cent up, and up to eight decimals for dust — which is
/// how the real app shows its tiny leftover Tether balance ("$0.00000001").
private func pampGramFakeCryptoBotFormatUSD(_ value: Double) -> String {
    if value <= 0.0 {
        return "0"
    }
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = ","
    formatter.usesGroupingSeparator = true
    formatter.decimalSeparator = "."
    if value >= 0.01 {
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
    } else {
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 8
    }
    return formatter.string(from: NSNumber(value: value)) ?? "0"
}

private enum PampGramFakeCryptoBotColors {
    static let card = UIColor(rgb: 0x171717)
    static let secondary = UIColor(rgb: 0x959595)
    static let subtitle = UIColor(rgb: 0xacacac)
    static let blue = UIColor(rgb: 0x3b9de3)
    static let dotInactive = UIColor(rgb: 0x264252)
    static let red = UIColor(rgb: 0xff4b52)
    static let green = UIColor(rgb: 0x2e9f4f)
    static let separator = UIColor(rgb: 0x292929)
    static let tabBar = UIColor(rgb: 0x1d2026)
    static let tabActive = UIColor(rgb: 0x272a30)
}

private func pampGramFakeCryptoBotLabel(size: CGFloat, weight: UIFont.Weight, color: UIColor, alignment: NSTextAlignment) -> UILabel {
    let label = UILabel()
    label.font = UIFont.systemFont(ofSize: size, weight: weight)
    label.textColor = color
    label.textAlignment = alignment
    label.isUserInteractionEnabled = false
    return label
}

private func pampGramFakeCryptoBotSymbol(_ name: String, size: CGFloat, weight: UIImage.SymbolWeight) -> UIImage? {
    return UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: weight))
}

// MARK: - Small controls

private final class PampGramFakeCryptoBotImageControl: UIControl {
    let imageView = UIImageView()

    init(image: UIImage?) {
        super.init(frame: .zero)
        self.imageView.image = image
        self.imageView.contentMode = .scaleAspectFit
        self.imageView.isUserInteractionEnabled = false
        self.addSubview(self.imageView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.imageView.frame = self.bounds
    }

    override var isHighlighted: Bool {
        didSet {
            self.alpha = self.isHighlighted ? 0.6 : 1.0
        }
    }
}

/// One coin line: a logo, a title/subtitle pair and, depending on the screen, either an amount
/// column ("0 USDT" over "$0") or a chevron. `.asset` is the wallet list (name + price and daily
/// change), `.deposit`/`.withdraw` are the coin pickers (ticker + name).
private final class PampGramFakeCryptoBotRowView: UIControl {
    enum Kind {
        case asset
        case deposit
        case withdraw
    }

    let currency: PampGramFakeCryptoBotCurrency
    private let kind: Kind
    private let iconView = UIImageView()
    private let titleLabel = pampGramFakeCryptoBotLabel(size: 17.0, weight: .regular, color: .white, alignment: .left)
    private let subtitleLabel = pampGramFakeCryptoBotLabel(size: 15.0, weight: .regular, color: PampGramFakeCryptoBotColors.secondary, alignment: .left)
    private let rightTopLabel = pampGramFakeCryptoBotLabel(size: 17.0, weight: .regular, color: .white, alignment: .right)
    private let rightBottomLabel = pampGramFakeCryptoBotLabel(size: 15.0, weight: .regular, color: PampGramFakeCryptoBotColors.secondary, alignment: .right)
    private let chevronView = UIImageView()
    private let separator = UIView()

    init(currency: PampGramFakeCryptoBotCurrency, kind: Kind) {
        self.currency = currency
        self.kind = kind
        super.init(frame: .zero)

        self.iconView.image = PampGramFakeCryptoBotAssets.image(currency.assetName)
        self.iconView.contentMode = .scaleAspectFit
        self.iconView.isUserInteractionEnabled = false
        self.addSubview(self.iconView)
        self.addSubview(self.titleLabel)
        self.addSubview(self.subtitleLabel)
        self.addSubview(self.rightTopLabel)
        self.addSubview(self.rightBottomLabel)

        self.chevronView.image = pampGramFakeCryptoBotSymbol("chevron.right", size: 13.0, weight: .semibold)
        self.chevronView.tintColor = PampGramFakeCryptoBotColors.secondary
        self.chevronView.contentMode = .center
        self.chevronView.isUserInteractionEnabled = false
        self.addSubview(self.chevronView)

        self.separator.backgroundColor = PampGramFakeCryptoBotColors.separator
        self.separator.isUserInteractionEnabled = false
        self.addSubview(self.separator)

        switch kind {
        case .asset:
            self.titleLabel.text = currency.name
            let subtitle = NSMutableAttributedString(string: currency.priceText + " ", attributes: [
                .font: UIFont.systemFont(ofSize: 15.0, weight: .regular),
                .foregroundColor: PampGramFakeCryptoBotColors.secondary
            ])
            var changeText = "0.00%"
            var changeColor = PampGramFakeCryptoBotColors.secondary
            if currency.change > 0.0 {
                changeText = "+" + String(format: "%.2f", currency.change) + "%"
                changeColor = PampGramFakeCryptoBotColors.green
            } else if currency.change < 0.0 {
                changeText = "-" + String(format: "%.2f", abs(currency.change)) + "%"
                changeColor = PampGramFakeCryptoBotColors.red
            }
            subtitle.append(NSAttributedString(string: changeText, attributes: [
                .font: UIFont.systemFont(ofSize: 15.0, weight: .regular),
                .foregroundColor: changeColor
            ]))
            self.subtitleLabel.attributedText = subtitle
            self.chevronView.isHidden = true
        case .deposit:
            self.titleLabel.text = currency.code
            self.subtitleLabel.text = currency.name
            self.rightTopLabel.isHidden = true
            self.rightBottomLabel.isHidden = true
        case .withdraw:
            self.titleLabel.text = currency.code
            self.subtitleLabel.text = currency.name
            self.chevronView.isHidden = true
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(amountText: String, usdText: String) {
        self.rightTopLabel.text = amountText
        self.rightBottomLabel.text = usdText
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = self.bounds.width
        let height = self.bounds.height
        let textX: CGFloat = 69.0
        let rightWidth: CGFloat = 150.0
        let leftWidth = max(0.0, width - textX - (self.kind == .deposit ? 40.0 : rightWidth + 20.0))
        self.iconView.frame = CGRect(x: 16.0, y: floor((height - 40.0) / 2.0), width: 40.0, height: 40.0)
        self.titleLabel.frame = CGRect(x: textX, y: floor(height / 2.0) - 20.0, width: leftWidth, height: 20.0)
        self.subtitleLabel.frame = CGRect(x: textX, y: floor(height / 2.0) + 1.0, width: leftWidth, height: 19.0)
        self.rightTopLabel.frame = CGRect(x: width - 16.0 - rightWidth, y: floor(height / 2.0) - 20.0, width: rightWidth, height: 20.0)
        self.rightBottomLabel.frame = CGRect(x: width - 16.0 - rightWidth, y: floor(height / 2.0) + 1.0, width: rightWidth, height: 19.0)
        self.chevronView.frame = CGRect(x: width - 16.0 - 12.0, y: floor((height - 18.0) / 2.0), width: 12.0, height: 18.0)
        self.separator.frame = CGRect(x: textX, y: height - 1.0, width: max(0.0, width - textX), height: 1.0)
    }

    override var isHighlighted: Bool {
        didSet {
            self.alpha = self.isHighlighted ? 0.6 : 1.0
        }
    }
}

/// A bottom-bar item: glyph over a label, with a lighter capsule behind the active one.
private final class PampGramFakeCryptoBotTabItem: UIControl {
    private let capsule = UIView()
    private let iconView = UIImageView()
    private let label = pampGramFakeCryptoBotLabel(size: 11.0, weight: .medium, color: .white, alignment: .center)

    init(assetName: String, title: String, active: Bool) {
        super.init(frame: .zero)
        self.capsule.backgroundColor = PampGramFakeCryptoBotColors.tabActive
        self.capsule.isHidden = !active
        self.capsule.isUserInteractionEnabled = false
        self.addSubview(self.capsule)

        self.iconView.image = PampGramFakeCryptoBotAssets.image(assetName)?.withRenderingMode(.alwaysTemplate)
        self.iconView.tintColor = active ? PampGramFakeCryptoBotColors.blue : UIColor.white
        self.iconView.contentMode = .center
        self.iconView.isUserInteractionEnabled = false
        self.addSubview(self.iconView)

        self.label.text = title
        self.label.textColor = active ? PampGramFakeCryptoBotColors.blue : UIColor.white
        self.addSubview(self.label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = self.bounds.width
        let height = self.bounds.height
        self.capsule.frame = self.bounds.insetBy(dx: 1.0, dy: 5.0)
        self.capsule.layer.cornerRadius = self.capsule.bounds.height / 2.0
        self.iconView.frame = CGRect(x: 0.0, y: 8.0, width: width, height: 24.0)
        self.label.frame = CGRect(x: 0.0, y: height - 22.0, width: width, height: 14.0)
    }
}

// MARK: - The mini app

private final class PampGramFakeCryptoBotAppView: UIView, UIScrollViewDelegate, UITextFieldDelegate {
    enum Page {
        case wallet
        case deposit
        case withdraw
    }

    var onClose: (() -> Void)?
    var onUnavailable: (() -> Void)?
    var onEditBalances: (() -> Void)?

    private var balances: [String: Double] = [:]
    private var page: Page = .wallet
    private var topInset: CGFloat = 59.0
    private var balanceHidden = false
    private var smallBalancesHidden = false
    private var searchQuery = ""
    private var bannerPage = 0

    private let cardView = UIView()

    private let closeControl = UIControl()
    private let closeLabel = pampGramFakeCryptoBotLabel(size: 17.0, weight: .regular, color: .white, alignment: .left)
    private let backControl = UIControl()
    private let backChevron = UIImageView()
    private let backLabel = pampGramFakeCryptoBotLabel(size: 17.0, weight: .regular, color: .white, alignment: .left)
    private let titleLabel = pampGramFakeCryptoBotLabel(size: 17.0, weight: .semibold, color: .white, alignment: .center)
    private let subtitleLabel = pampGramFakeCryptoBotLabel(size: 13.0, weight: .regular, color: PampGramFakeCryptoBotColors.subtitle, alignment: .center)
    private let moreControl = UIControl()
    private let moreIcon = UIImageView()

    private let walletScroll = UIScrollView()
    private let scanControl = PampGramFakeCryptoBotImageControl(image: PampGramFakeCryptoBotAssets.image("top_scan"))
    private let imageControl = PampGramFakeCryptoBotImageControl(image: PampGramFakeCryptoBotAssets.image("top_image"))
    private let currencyControl = PampGramFakeCryptoBotImageControl(image: PampGramFakeCryptoBotAssets.image("top_currency"))
    private let balanceLabel = UILabel()
    private let eyeControl = UIControl()
    private let eyeIcon = UIImageView()
    private let balanceCaption = UILabel()
    private let depositControl = PampGramFakeCryptoBotImageControl(image: PampGramFakeCryptoBotAssets.image("act_deposit"))
    private let withdrawControl = PampGramFakeCryptoBotImageControl(image: PampGramFakeCryptoBotAssets.image("act_withdraw"))
    private let historyControl = PampGramFakeCryptoBotImageControl(image: PampGramFakeCryptoBotAssets.image("act_history"))
    private let depositLabel = pampGramFakeCryptoBotLabel(size: 15.0, weight: .regular, color: PampGramFakeCryptoBotColors.blue, alignment: .center)
    private let withdrawLabel = pampGramFakeCryptoBotLabel(size: 15.0, weight: .regular, color: PampGramFakeCryptoBotColors.blue, alignment: .center)
    private let historyLabel = pampGramFakeCryptoBotLabel(size: 15.0, weight: .regular, color: PampGramFakeCryptoBotColors.blue, alignment: .center)
    private let bannerScroll = UIScrollView()
    private let bannerControls: [PampGramFakeCryptoBotImageControl] = [
        PampGramFakeCryptoBotImageControl(image: PampGramFakeCryptoBotAssets.image("banner_autumn")),
        PampGramFakeCryptoBotImageControl(image: PampGramFakeCryptoBotAssets.image("banner_p2p"))
    ]
    private let dotViews: [UIView] = [UIView(), UIView()]
    private let assetsTitle = pampGramFakeCryptoBotLabel(size: 17.0, weight: .medium, color: PampGramFakeCryptoBotColors.blue, alignment: .left)
    private let assetsChevron = UIImageView()
    private let hideSmallButton = UIButton(type: .custom)
    private var assetRows: [PampGramFakeCryptoBotRowView] = []

    private let listScroll = UIScrollView()
    private let listTitle = pampGramFakeCryptoBotLabel(size: 17.0, weight: .regular, color: PampGramFakeCryptoBotColors.secondary, alignment: .left)
    private let searchBox = UIView()
    private let searchIcon = UIImageView()
    private let searchField = UITextField()
    private var listRows: [PampGramFakeCryptoBotRowView] = []

    private let tabBar = UIView()
    private let tabItems: [PampGramFakeCryptoBotTabItem] = [
        PampGramFakeCryptoBotTabItem(assetName: "tab_wallet", title: "Кошелёк", active: true),
        PampGramFakeCryptoBotTabItem(assetName: "tab_exchange", title: "Биржа", active: false),
        PampGramFakeCryptoBotTabItem(assetName: "tab_swap", title: "Обмен", active: false),
        PampGramFakeCryptoBotTabItem(assetName: "tab_p2p", title: "P2P", active: false),
        PampGramFakeCryptoBotTabItem(assetName: "tab_more", title: "Ещё", active: false)
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .black

        self.cardView.backgroundColor = PampGramFakeCryptoBotColors.card
        self.cardView.layer.cornerRadius = 28.0
        self.cardView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        self.cardView.clipsToBounds = true
        self.addSubview(self.cardView)

        // Wallet and list scrolls sit under the header, so they go in first.
        self.setupWallet()
        self.setupList()
        self.setupHeader()
        self.setupTabBar()

        self.reload()
        self.applyPage(animated: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Setup

    private func setupHeader() {
        self.closeLabel.text = "Закрыть"
        self.closeControl.addSubview(self.closeLabel)
        self.closeControl.addTarget(self, action: #selector(self.closePressed), for: .touchUpInside)
        self.cardView.addSubview(self.closeControl)

        self.backChevron.image = pampGramFakeCryptoBotSymbol("chevron.left", size: 20.0, weight: .semibold)
        self.backChevron.tintColor = .white
        self.backChevron.contentMode = .center
        self.backChevron.isUserInteractionEnabled = false
        self.backLabel.text = "Назад"
        self.backControl.addSubview(self.backChevron)
        self.backControl.addSubview(self.backLabel)
        self.backControl.addTarget(self, action: #selector(self.backPressed), for: .touchUpInside)
        self.cardView.addSubview(self.backControl)

        self.titleLabel.text = "Crypto Bot"
        self.subtitleLabel.text = "мини-приложение"
        self.cardView.addSubview(self.titleLabel)
        self.cardView.addSubview(self.subtitleLabel)

        self.moreIcon.image = pampGramFakeCryptoBotSymbol("ellipsis.circle", size: 24.0, weight: .regular)
        self.moreIcon.tintColor = .white
        self.moreIcon.contentMode = .center
        self.moreIcon.isUserInteractionEnabled = false
        self.moreControl.addSubview(self.moreIcon)
        self.moreControl.addTarget(self, action: #selector(self.unavailablePressed), for: .touchUpInside)
        self.cardView.addSubview(self.moreControl)
    }

    private func setupWallet() {
        self.walletScroll.alwaysBounceVertical = true
        self.walletScroll.showsVerticalScrollIndicator = false
        self.walletScroll.backgroundColor = .clear
        self.cardView.addSubview(self.walletScroll)

        for control in [self.scanControl, self.imageControl, self.currencyControl] {
            control.addTarget(self, action: #selector(self.unavailablePressed), for: .touchUpInside)
            self.walletScroll.addSubview(control)
        }

        self.balanceLabel.textAlignment = .center
        self.balanceLabel.isUserInteractionEnabled = true
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(self.balanceLongPressed(_:)))
        longPress.minimumPressDuration = 1.0
        self.balanceLabel.addGestureRecognizer(longPress)
        self.walletScroll.addSubview(self.balanceLabel)

        self.eyeIcon.tintColor = PampGramFakeCryptoBotColors.secondary
        self.eyeIcon.contentMode = .center
        self.eyeIcon.isUserInteractionEnabled = false
        self.eyeControl.addSubview(self.eyeIcon)
        self.eyeControl.addTarget(self, action: #selector(self.eyePressed), for: .touchUpInside)
        self.walletScroll.addSubview(self.eyeControl)

        let caption = NSMutableAttributedString(string: "Общий баланс в ", attributes: [
            .font: UIFont.systemFont(ofSize: 17.0, weight: .regular),
            .foregroundColor: PampGramFakeCryptoBotColors.secondary
        ])
        caption.append(NSAttributedString(string: "USD", attributes: [
            .font: UIFont.systemFont(ofSize: 17.0, weight: .regular),
            .foregroundColor: PampGramFakeCryptoBotColors.blue
        ]))
        self.balanceCaption.attributedText = caption
        self.balanceCaption.textAlignment = .center
        self.walletScroll.addSubview(self.balanceCaption)

        self.depositLabel.text = "Пополнить"
        self.withdrawLabel.text = "Вывести"
        self.historyLabel.text = "История"
        self.depositControl.addTarget(self, action: #selector(self.depositPressed), for: .touchUpInside)
        self.withdrawControl.addTarget(self, action: #selector(self.withdrawPressed), for: .touchUpInside)
        self.historyControl.addTarget(self, action: #selector(self.unavailablePressed), for: .touchUpInside)
        for view in [self.depositControl, self.withdrawControl, self.historyControl] as [UIView] {
            self.walletScroll.addSubview(view)
        }
        for label in [self.depositLabel, self.withdrawLabel, self.historyLabel] {
            self.walletScroll.addSubview(label)
        }

        self.bannerScroll.isPagingEnabled = true
        self.bannerScroll.showsHorizontalScrollIndicator = false
        self.bannerScroll.bounces = false
        self.bannerScroll.layer.cornerRadius = 12.0
        self.bannerScroll.clipsToBounds = true
        self.bannerScroll.delegate = self
        self.walletScroll.addSubview(self.bannerScroll)
        for control in self.bannerControls {
            control.addTarget(self, action: #selector(self.unavailablePressed), for: .touchUpInside)
            self.bannerScroll.addSubview(control)
        }
        for dot in self.dotViews {
            dot.isUserInteractionEnabled = false
            self.walletScroll.addSubview(dot)
        }

        self.assetsTitle.text = "Мои активы"
        self.walletScroll.addSubview(self.assetsTitle)
        self.assetsChevron.image = pampGramFakeCryptoBotSymbol("chevron.right", size: 13.0, weight: .semibold)
        self.assetsChevron.tintColor = PampGramFakeCryptoBotColors.blue
        self.assetsChevron.contentMode = .center
        self.walletScroll.addSubview(self.assetsChevron)

        self.hideSmallButton.setTitleColor(PampGramFakeCryptoBotColors.blue, for: .normal)
        self.hideSmallButton.titleLabel?.font = UIFont.systemFont(ofSize: 17.0, weight: .regular)
        self.hideSmallButton.contentHorizontalAlignment = .right
        self.hideSmallButton.addTarget(self, action: #selector(self.hideSmallPressed), for: .touchUpInside)
        self.walletScroll.addSubview(self.hideSmallButton)

        for currency in pampGramFakeCryptoBotCurrencies {
            let row = PampGramFakeCryptoBotRowView(currency: currency, kind: .asset)
            row.addTarget(self, action: #selector(self.unavailablePressed), for: .touchUpInside)
            self.walletScroll.addSubview(row)
            self.assetRows.append(row)
        }
    }

    private func setupList() {
        self.listScroll.alwaysBounceVertical = true
        self.listScroll.showsVerticalScrollIndicator = false
        self.listScroll.keyboardDismissMode = .onDrag
        self.listScroll.backgroundColor = .clear
        self.cardView.addSubview(self.listScroll)

        self.listScroll.addSubview(self.listTitle)

        self.searchBox.layer.cornerRadius = 12.0
        self.searchBox.layer.borderWidth = 1.0
        self.searchBox.layer.borderColor = PampGramFakeCryptoBotColors.separator.cgColor
        self.listScroll.addSubview(self.searchBox)

        self.searchIcon.image = pampGramFakeCryptoBotSymbol("magnifyingglass", size: 19.0, weight: .regular)
        self.searchIcon.tintColor = PampGramFakeCryptoBotColors.secondary
        self.searchIcon.contentMode = .center
        self.searchBox.addSubview(self.searchIcon)

        self.searchField.attributedPlaceholder = NSAttributedString(string: "Поиск монеты", attributes: [
            .font: UIFont.systemFont(ofSize: 17.0, weight: .regular),
            .foregroundColor: PampGramFakeCryptoBotColors.secondary
        ])
        self.searchField.font = UIFont.systemFont(ofSize: 17.0, weight: .regular)
        self.searchField.textColor = .white
        self.searchField.tintColor = PampGramFakeCryptoBotColors.blue
        self.searchField.autocorrectionType = .no
        self.searchField.autocapitalizationType = .none
        self.searchField.returnKeyType = .done
        self.searchField.keyboardAppearance = .dark
        self.searchField.delegate = self
        self.searchField.addTarget(self, action: #selector(self.searchChanged), for: .editingChanged)
        self.searchBox.addSubview(self.searchField)
    }

    private func setupTabBar() {
        self.tabBar.backgroundColor = PampGramFakeCryptoBotColors.tabBar
        self.tabBar.layer.cornerRadius = 26.5
        self.tabBar.layer.borderWidth = 1.0
        self.tabBar.layer.borderColor = UIColor(white: 1.0, alpha: 0.05).cgColor
        self.cardView.addSubview(self.tabBar)
        for item in self.tabItems {
            item.addTarget(self, action: #selector(self.tabPressed(_:)), for: .touchUpInside)
            self.tabBar.addSubview(item)
        }
    }

    // MARK: Data

    func setBalances(_ balances: [String: Double]) {
        self.balances = balances
        self.reload()
    }

    /// The real app keeps a speck of Tether in a fresh wallet ("0 USDT", "$0.00000001"), so an
    /// untouched wallet looks the same here until a USDT balance is set.
    private func amount(for currency: PampGramFakeCryptoBotCurrency) -> Double {
        if let value = self.balances[currency.code] {
            return value
        }
        return currency.code == "USDT" ? 0.00000001 : 0.0
    }

    private func reload() {
        var total = 0.0
        for currency in pampGramFakeCryptoBotCurrencies {
            total += self.amount(for: currency) * currency.price
        }
        let totalText = self.balanceHidden ? "•••••" : pampGramFakeCryptoBotFormatUSD(total)
        let balance = NSMutableAttributedString(string: "$ ", attributes: [
            .font: UIFont.systemFont(ofSize: 36.0, weight: .bold),
            .foregroundColor: PampGramFakeCryptoBotColors.secondary
        ])
        balance.append(NSAttributedString(string: totalText, attributes: [
            .font: UIFont.systemFont(ofSize: 36.0, weight: .bold),
            .foregroundColor: UIColor.white
        ]))
        self.balanceLabel.attributedText = balance
        self.eyeIcon.image = pampGramFakeCryptoBotSymbol(self.balanceHidden ? "eye.slash.fill" : "eye.fill", size: 20.0, weight: .regular)
        self.hideSmallButton.setTitle(self.smallBalancesHidden ? "Показать мелкие балансы" : "Скрыть мелкие балансы", for: .normal)

        for row in self.assetRows {
            let amount = self.amount(for: row.currency)
            let usd = amount * row.currency.price
            row.update(amountText: pampGramFakeCryptoBotFormat(amount, fractionDigits: row.currency.fractionDigits) + " " + row.currency.code, usdText: "$" + pampGramFakeCryptoBotFormatUSD(usd))
            row.isHidden = self.smallBalancesHidden && usd < 1.0
        }
        for row in self.listRows {
            let amount = self.amount(for: row.currency)
            row.update(amountText: pampGramFakeCryptoBotFormat(amount, fractionDigits: row.currency.fractionDigits) + " " + row.currency.code, usdText: "$" + pampGramFakeCryptoBotFormatUSD(amount * row.currency.price))
        }
        self.setNeedsLayout()
    }

    private func rebuildListRows() {
        for row in self.listRows {
            row.removeFromSuperview()
        }
        self.listRows.removeAll()
        let kind: PampGramFakeCryptoBotRowView.Kind = self.page == .withdraw ? .withdraw : .deposit
        let query = self.searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        for currency in pampGramFakeCryptoBotCurrencies {
            if !query.isEmpty && !currency.code.lowercased().contains(query) && !currency.name.lowercased().contains(query) {
                continue
            }
            let row = PampGramFakeCryptoBotRowView(currency: currency, kind: kind)
            row.addTarget(self, action: #selector(self.unavailablePressed), for: .touchUpInside)
            self.listScroll.addSubview(row)
            self.listRows.append(row)
        }
        self.reload()
    }

    private func applyPage(animated: Bool) {
        let isWallet = self.page == .wallet
        self.closeControl.isHidden = !isWallet
        self.backControl.isHidden = isWallet
        self.walletScroll.isHidden = !isWallet
        self.tabBar.isHidden = !isWallet
        self.listScroll.isHidden = isWallet
        self.listTitle.text = self.page == .withdraw ? "Вывод криптовалюты" : "Пополнение криптовалюты"
        if animated {
            let target = isWallet ? self.walletScroll : self.listScroll
            target.alpha = 0.0
            UIView.animate(withDuration: 0.2, animations: {
                target.alpha = 1.0
            })
        }
        self.setNeedsLayout()
    }

    private func setPage(_ page: Page) {
        self.endEditing(true)
        self.page = page
        self.searchField.text = ""
        self.searchQuery = ""
        self.listScroll.contentOffset = .zero
        if page != .wallet {
            self.rebuildListRows()
        }
        self.applyPage(animated: true)
    }

    // MARK: Layout

    func updateInsets(top: CGFloat) {
        self.topInset = top
        self.setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = self.bounds.width
        let cardTop = self.topInset + 6.0
        self.cardView.frame = CGRect(x: 0.0, y: cardTop, width: width, height: max(0.0, self.bounds.height - cardTop))
        let cardHeight = self.cardView.bounds.height

        // Header.
        self.closeControl.frame = CGRect(x: 0.0, y: 12.0, width: 110.0, height: 52.0)
        self.closeLabel.frame = CGRect(x: 16.0, y: 0.0, width: 94.0, height: 52.0)
        self.backControl.frame = CGRect(x: 0.0, y: 12.0, width: 120.0, height: 52.0)
        self.backChevron.frame = CGRect(x: 7.0, y: 14.0, width: 16.0, height: 24.0)
        self.backLabel.frame = CGRect(x: 28.0, y: 0.0, width: 90.0, height: 52.0)
        self.titleLabel.frame = CGRect(x: 70.0, y: 19.0, width: max(0.0, width - 140.0), height: 22.0)
        self.subtitleLabel.frame = CGRect(x: 70.0, y: 39.0, width: max(0.0, width - 140.0), height: 16.0)
        self.moreControl.frame = CGRect(x: width - 45.0, y: 18.0, width: 40.0, height: 40.0)
        self.moreIcon.frame = self.moreControl.bounds

        let scrollFrame = CGRect(x: 0.0, y: 62.0, width: width, height: max(0.0, cardHeight - 62.0))
        self.walletScroll.frame = scrollFrame
        self.listScroll.frame = scrollFrame
        self.layoutWallet(width: width)
        self.layoutList(width: width)

        // Tab bar.
        let barWidth: CGFloat = min(291.0, width - 32.0)
        self.tabBar.frame = CGRect(x: floor((width - barWidth) / 2.0), y: cardHeight - 53.0 - 19.0, width: barWidth, height: 53.0)
        let itemWidth = barWidth / CGFloat(self.tabItems.count)
        for (index, item) in self.tabItems.enumerated() {
            item.frame = CGRect(x: CGFloat(index) * itemWidth, y: 0.0, width: itemWidth, height: 53.0)
        }
    }

    private func layoutWallet(width: CGFloat) {
        self.scanControl.frame = CGRect(x: 16.0, y: 13.0, width: 34.0, height: 34.0)
        self.imageControl.frame = CGRect(x: width - 96.0, y: 13.0, width: 34.0, height: 34.0)
        self.currencyControl.frame = CGRect(x: width - 50.0, y: 13.0, width: 34.0, height: 34.0)

        let balanceSize = self.balanceLabel.sizeThatFits(CGSize(width: width, height: 60.0))
        let eyeWidth: CGFloat = 26.0
        let groupWidth = balanceSize.width + 12.0 + eyeWidth
        let groupX = floor((width - groupWidth) / 2.0)
        self.balanceLabel.frame = CGRect(x: groupX, y: 65.0, width: balanceSize.width, height: 46.0)
        self.eyeControl.frame = CGRect(x: groupX + balanceSize.width + 4.0, y: 65.0, width: eyeWidth + 8.0, height: 46.0)
        self.eyeIcon.frame = self.eyeControl.bounds
        self.balanceCaption.frame = CGRect(x: 0.0, y: 114.0, width: width, height: 22.0)

        let contentWidth = width - 32.0
        let columnWidth = contentWidth / 3.0
        let controls: [UIView] = [self.depositControl, self.withdrawControl, self.historyControl]
        let labels: [UILabel] = [self.depositLabel, self.withdrawLabel, self.historyLabel]
        for index in 0 ..< 3 {
            let centerX = 16.0 + columnWidth * (CGFloat(index) + 0.5)
            controls[index].frame = CGRect(x: floor(centerX - 20.5), y: 154.0, width: 41.0, height: 41.0)
            labels[index].frame = CGRect(x: floor(centerX - columnWidth / 2.0), y: 202.0, width: columnWidth, height: 20.0)
        }

        let bannerWidth = contentWidth
        let bannerHeight: CGFloat = 74.0
        self.bannerScroll.frame = CGRect(x: 16.0, y: 239.0, width: bannerWidth, height: bannerHeight)
        self.bannerScroll.contentSize = CGSize(width: bannerWidth * CGFloat(self.bannerControls.count), height: bannerHeight)
        for (index, control) in self.bannerControls.enumerated() {
            control.frame = CGRect(x: CGFloat(index) * bannerWidth, y: 0.0, width: bannerWidth, height: bannerHeight)
        }
        var dotX = floor((width - (12.0 + 10.0 + 6.0)) / 2.0)
        for (index, dot) in self.dotViews.enumerated() {
            let isActive = index == self.bannerPage
            let dotWidth: CGFloat = isActive ? 12.0 : 6.0
            dot.frame = CGRect(x: dotX, y: 321.0, width: dotWidth, height: 6.0)
            dot.layer.cornerRadius = 3.0
            dot.backgroundColor = isActive ? PampGramFakeCryptoBotColors.blue : PampGramFakeCryptoBotColors.dotInactive
            dotX += dotWidth + 10.0
        }

        let titleSize = self.assetsTitle.sizeThatFits(CGSize(width: width, height: 22.0))
        self.assetsTitle.frame = CGRect(x: 16.0, y: 351.0, width: titleSize.width, height: 22.0)
        self.assetsChevron.frame = CGRect(x: 16.0 + titleSize.width + 4.0, y: 351.0, width: 14.0, height: 22.0)
        self.hideSmallButton.frame = CGRect(x: width / 2.0 - 20.0, y: 342.0, width: width / 2.0 + 4.0, height: 40.0)

        var y: CGFloat = 386.0
        for row in self.assetRows where !row.isHidden {
            row.frame = CGRect(x: 0.0, y: y, width: width, height: 65.0)
            y += 65.0
        }
        self.walletScroll.contentSize = CGSize(width: width, height: y + 130.0)
    }

    private func layoutList(width: CGFloat) {
        self.listTitle.frame = CGRect(x: 16.0, y: 29.0, width: max(0.0, width - 32.0), height: 22.0)
        self.searchBox.frame = CGRect(x: 16.0, y: 64.0, width: max(0.0, width - 32.0), height: 46.0)
        self.searchIcon.frame = CGRect(x: 12.0, y: 13.0, width: 24.0, height: 20.0)
        self.searchField.frame = CGRect(x: 48.0, y: 0.0, width: max(0.0, self.searchBox.bounds.width - 60.0), height: 46.0)
        var y: CGFloat = 123.0
        for row in self.listRows {
            row.frame = CGRect(x: 0.0, y: y, width: width, height: 65.0)
            y += 65.0
        }
        self.listScroll.contentSize = CGSize(width: width, height: y + 40.0)
    }

    // MARK: Actions

    @objc private func closePressed() {
        self.onClose?()
    }

    @objc private func backPressed() {
        self.setPage(.wallet)
    }

    @objc private func depositPressed() {
        self.setPage(.deposit)
    }

    @objc private func withdrawPressed() {
        self.setPage(.withdraw)
    }

    @objc private func unavailablePressed() {
        self.onUnavailable?()
    }

    @objc private func tabPressed(_ sender: PampGramFakeCryptoBotTabItem) {
        if sender !== self.tabItems[0] {
            self.onUnavailable?()
        }
    }

    @objc private func eyePressed() {
        self.balanceHidden = !self.balanceHidden
        self.reload()
    }

    @objc private func hideSmallPressed() {
        self.smallBalancesHidden = !self.smallBalancesHidden
        self.reload()
    }

    @objc private func balanceLongPressed(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else {
            return
        }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        self.onEditBalances?()
    }

    @objc private func searchChanged() {
        self.searchQuery = self.searchField.text ?? ""
        self.rebuildListRows()
        self.setNeedsLayout()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === self.bannerScroll, scrollView.bounds.width > 0.0 else {
            return
        }
        let index = max(0, min(self.dotViews.count - 1, Int(round(scrollView.contentOffset.x / scrollView.bounds.width))))
        if index != self.bannerPage {
            self.bannerPage = index
            self.setNeedsLayout()
        }
    }
}

// MARK: - Screen

private final class PampGramFakeCryptoBotScreen: ViewController {
    private let context: AccountContext
    private let settingsDisposable = MetaDisposable()
    private var appView: PampGramFakeCryptoBotAppView?

    init(context: AccountContext) {
        self.context = context
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
        node.backgroundColor = .black
        self.displayNode = node
        self.displayNodeDidLoad()

        let appView = PampGramFakeCryptoBotAppView(frame: .zero)
        appView.onClose = { [weak self] in
            self?.dismiss()
        }
        appView.onUnavailable = { [weak self] in
            self?.presentUnavailable()
        }
        appView.onEditBalances = { [weak self] in
            guard let self = self else {
                return
            }
            pampGramFakeCryptoBotPresentBalanceEditor(context: self.context, presenter: self)
        }
        node.view.addSubview(appView)
        self.appView = appView

        self.settingsDisposable.set((PampGramCore.rawSettingsSignal(postbox: self.context.account.postbox)
        |> deliverOnMainQueue).startStrict(next: { [weak self] settings in
            self?.appView?.setBalances(settings.fakeCryptoBotBalances)
        }))
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        self.appView?.frame = CGRect(origin: .zero, size: layout.size)
        self.appView?.updateInsets(top: layout.insets(options: [.statusBar]).top)
    }

    private func presentUnavailable() {
        let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
        self.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: "Функция недоступна", timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), in: .current)
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
/// удержанием суммы общего баланса (около секунды).
public func pampGramFakeCryptoBotController(context: AccountContext) -> ViewController {
    return PampGramFakeCryptoBotScreen(context: context)
}
