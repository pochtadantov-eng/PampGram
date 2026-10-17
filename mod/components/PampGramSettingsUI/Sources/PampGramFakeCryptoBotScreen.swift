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

/// "$80,555.61" for `price`, with as many decimals as `template` ("$80,555.61") has.
private func pampGramFakeCryptoBotPriceText(_ price: Double, like template: String) -> String {
    var decimals = 2
    if let dot = template.firstIndex(of: ".") {
        decimals = template.distance(from: dot, to: template.endIndex) - 1
    }
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = decimals
    formatter.maximumFractionDigits = decimals
    formatter.groupingSeparator = ","
    formatter.usesGroupingSeparator = true
    return "$" + (formatter.string(from: NSNumber(value: price)) ?? "0")
}

func pampGramFakeCryptoBotFormat(_ amount: Double, fractionDigits: Int) -> String {
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
func pampGramFakeCryptoBotFormatUSD(_ value: Double) -> String {
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

/// Every colour of the page comes in a dark and a light variant; the page (and the standalone
/// screen) pins `overrideUserInterfaceStyle` to Telegram's own theme, so the variants follow it.
enum PampGramFakeCryptoBotColors {
    static func themed(dark: UInt32, light: UInt32, darkAlpha: CGFloat = 1.0, lightAlpha: CGFloat = 1.0) -> UIColor {
        return UIColor { traits in
            if traits.userInterfaceStyle == .light {
                return UIColor(rgb: light).withAlphaComponent(lightAlpha)
            }
            return UIColor(rgb: dark).withAlphaComponent(darkAlpha)
        }
    }

    static let card = themed(dark: 0x171717, light: 0xffffff)
    static let text = themed(dark: 0xffffff, light: 0x000000)
    static let secondary = themed(dark: 0x959595, light: 0x8a8a8e)
    static let subtitle = themed(dark: 0xacacac, light: 0x6d6d72)
    static let blue = themed(dark: 0x3b9de3, light: 0x5ea1d8)
    static let dotInactive = themed(dark: 0x233f53, light: 0xc4def1)
    static let dotFill = themed(dark: 0x3997d5, light: 0x5ea1d8)
    static let roundButton = themed(dark: 0x242424, light: 0xf2f2f2)
    static let roundGlyph = themed(dark: 0x8c8c8c, light: 0x999999)
    static let red = UIColor(rgb: 0xff4b52)
    static let green = themed(dark: 0x2e9f4f, light: 0x23984a)
    static let separator = themed(dark: 0x292929, light: 0xe5e5ea)
    static let border = themed(dark: 0x2d2d2d, light: 0xe0e0e6)
    static let borderStrong = themed(dark: 0x3a3a3a, light: 0xcfcfd5)
    static let surface = themed(dark: 0x1f1f1f, light: 0xf3f3f6)
    static let surfaceHigh = themed(dark: 0x2a2a2a, light: 0xebebef)
    static let tabBar = themed(dark: 0x20262c, light: 0xf5f6f8)
    static let tabActive = themed(dark: 0x2a2f35, light: 0xe2e5ea)
    static let tabBorder = themed(dark: 0xffffff, light: 0x000000, darkAlpha: 0.07, lightAlpha: 0.07)
    static let qrCard = themed(dark: 0xffffff, light: 0xf1f6fb)
    static let gemFill = themed(dark: 0x1b3a54, light: 0xd9eafa)
    static let gemStar = themed(dark: 0x0f2232, light: 0xbcd8ef)
    static let outer = themed(dark: 0x000000, light: 0xefeff4)
}

extension UIView {
    /// Layer colours are plain CGColors and do not follow the theme by themselves; the owners
    /// re-apply them through this when the theme or the window changes.
    func pampGramFakeCGColor(_ color: UIColor) -> CGColor {
        return color.resolvedColor(with: self.traitCollection).cgColor
    }
}

/// The blue fill of the pager pill: a capsule, so its end stays round while it grows.
private func pampGramFakeCryptoBotMakeDotFill() -> UIView {
    let fill = UIView()
    fill.isUserInteractionEnabled = false
    fill.backgroundColor = PampGramFakeCryptoBotColors.dotFill
    fill.layer.cornerRadius = 3.0
    return fill
}

/// Adds `delta` to the visual balance of `code`; an empty balance is removed.
private func pampGramFakeCryptoBotAdjust(_ balances: inout [String: Double], _ code: String, by delta: Double) {
    let updated = max(0.0, (balances[code] ?? 0.0) + delta)
    if updated < 1e-12 {
        balances.removeValue(forKey: code)
    } else {
        balances[code] = updated
    }
}

private func pampGramFakeCryptoBotLabel(size: CGFloat, weight: UIFont.Weight, color: UIColor, alignment: NSTextAlignment) -> UILabel {
    let label = UILabel()
    label.font = PampGramFakeCryptoBotFonts.font(size, weight)
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
    private let titleLabel = pampGramFakeCryptoBotLabel(size: 15.0, weight: .regular, color: PampGramFakeCryptoBotColors.text, alignment: .left)
    private let subtitleLabel = pampGramFakeCryptoBotLabel(size: 13.0, weight: .regular, color: PampGramFakeCryptoBotColors.secondary, alignment: .left)
    private let rightTopLabel = pampGramFakeCryptoBotLabel(size: 15.0, weight: .regular, color: PampGramFakeCryptoBotColors.text, alignment: .right)
    private let rightBottomLabel = pampGramFakeCryptoBotLabel(size: 13.0, weight: .regular, color: PampGramFakeCryptoBotColors.secondary, alignment: .right)
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
            self.setQuote(priceText: currency.priceText, change: currency.change)
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

    /// "$104.21 -1.00%": the price and the day's change under a coin's name in the wallet.
    func setQuote(priceText: String, change: Double) {
        let subtitle = NSMutableAttributedString(string: priceText + " ", attributes: [
            .font: PampGramFakeCryptoBotFonts.font(13.0, .regular),
            .foregroundColor: PampGramFakeCryptoBotColors.secondary
        ])
        var changeText = "0.00%"
        var changeColor = PampGramFakeCryptoBotColors.secondary
        let rounded = (change * 100.0).rounded() / 100.0
        if rounded > 0.0 {
            changeText = "+" + String(format: "%.2f", rounded) + "%"
            changeColor = PampGramFakeCryptoBotColors.green
        } else if rounded < 0.0 {
            changeText = "-" + String(format: "%.2f", abs(rounded)) + "%"
            changeColor = PampGramFakeCryptoBotColors.red
        }
        subtitle.append(NSAttributedString(string: changeText, attributes: [
            .font: PampGramFakeCryptoBotFonts.font(13.0, .regular),
            .foregroundColor: changeColor
        ]))
        self.subtitleLabel.attributedText = subtitle
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
        // The text block sits a hair below the icon's middle: title centre 7.9 above it, subtitle 10.9 below.
        let middle = height / 2.0
        self.titleLabel.frame = CGRect(x: textX, y: middle - 17.9, width: leftWidth, height: 20.0)
        self.subtitleLabel.frame = CGRect(x: textX, y: middle + 1.9, width: leftWidth, height: 18.0)
        self.rightTopLabel.frame = CGRect(x: width - 16.0 - rightWidth, y: middle - 17.9, width: rightWidth, height: 20.0)
        self.rightBottomLabel.frame = CGRect(x: width - 16.0 - rightWidth, y: middle + 1.9, width: rightWidth, height: 18.0)
        self.chevronView.frame = CGRect(x: width - 16.0 - 12.0, y: floor((height - 18.0) / 2.0), width: 12.0, height: 18.0)
        self.separator.frame = CGRect(x: textX, y: height - 1.0, width: max(0.0, width - textX - 16.0), height: 1.0)
    }

    override var isHighlighted: Bool {
        didSet {
            self.alpha = self.isHighlighted ? 0.6 : 1.0
        }
    }
}

/// A bottom-bar item: glyph over a label, with a lighter capsule behind the active one.
private final class PampGramFakeCryptoBotTabItem: UIControl {
    private let iconView = UIImageView()
    private let label = pampGramFakeCryptoBotLabel(size: 9.4, weight: .semibold, color: PampGramFakeCryptoBotColors.text, alignment: .center)

    init(assetName: String, title: String, active: Bool) {
        super.init(frame: .zero)
        self.iconView.image = PampGramFakeCryptoBotAssets.image(assetName)?.withRenderingMode(.alwaysTemplate)
        self.iconView.tintColor = active ? PampGramFakeCryptoBotColors.blue : PampGramFakeCryptoBotColors.text
        self.iconView.contentMode = .center
        self.iconView.isUserInteractionEnabled = false
        self.addSubview(self.iconView)

        self.label.text = title
        self.label.textColor = active ? PampGramFakeCryptoBotColors.blue : PampGramFakeCryptoBotColors.text
        self.addSubview(self.label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The blue highlight itself (the capsule) is drawn by the bar and slides between the items.
    func setActive(_ active: Bool, animated: Bool) {
        let update = {
            self.iconView.tintColor = active ? PampGramFakeCryptoBotColors.blue : PampGramFakeCryptoBotColors.text
            self.label.textColor = active ? PampGramFakeCryptoBotColors.blue : PampGramFakeCryptoBotColors.text
        }
        if animated {
            UIView.transition(with: self, duration: 0.25, options: [.transitionCrossDissolve, .allowUserInteraction], animations: update)
        } else {
            update()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = self.bounds.width
        let height = self.bounds.height
        // The bar is 66 high: the icon's centre sits 24.8 from the top, the label's 46.8.
        self.iconView.frame = CGRect(x: 0.0, y: 24.8 - 16.0, width: width, height: 32.0)
        self.label.frame = CGRect(x: 0.0, y: 46.8 - 7.0, width: width, height: 14.0)
        _ = height
    }
}

// MARK: - Rolling balance

/// The total balance, drawn digit by digit: every digit sits on a vertical strip of 0-9 and rolls
/// to its new value, the way the real mini app counts up when it opens or when the sum changes.
private final class PampGramFakeCryptoBotOdometerView: UIView {
    private static let font = PampGramFakeCryptoBotFonts.font(32.0, .bold, tabular: true)
    private static let lineHeight: CGFloat = 46.0

    private final class Cell {
        let character: Character
        private(set) var digit: Int?
        let width: CGFloat
        let container = UIView()
        private let strip = UIView()

        init(character: Character, color: UIColor, rolls: Bool) {
            let digit: Int? = rolls ? character.wholeNumberValue : nil
            let font = PampGramFakeCryptoBotOdometerView.font
            let lineHeight = PampGramFakeCryptoBotOdometerView.lineHeight
            let sample = digit == nil ? String(character) : "0"
            self.character = character
            self.digit = digit
            self.width = ceil((sample as NSString).size(withAttributes: [.font: font]).width)
            self.container.isUserInteractionEnabled = false
            self.container.clipsToBounds = true
            self.strip.isUserInteractionEnabled = false
            self.container.addSubview(self.strip)
            if let digit = digit {
                for value in 0 ..< 10 {
                    let label = UILabel(frame: CGRect(x: 0.0, y: CGFloat(value) * lineHeight, width: self.width, height: lineHeight))
                    label.font = font
                    label.textColor = color
                    label.textAlignment = .center
                    label.text = String(value)
                    self.strip.addSubview(label)
                }
                self.strip.frame = CGRect(x: 0.0, y: -CGFloat(digit) * lineHeight, width: self.width, height: lineHeight * 10.0)
            } else {
                let label = UILabel(frame: CGRect(x: 0.0, y: 0.0, width: self.width, height: lineHeight))
                label.font = font
                label.textColor = color
                label.textAlignment = .center
                label.text = String(character)
                self.strip.addSubview(label)
                self.strip.frame = label.frame
            }
        }

        func setDigit(_ digit: Int, animated: Bool, delay: Double = 0.0, duration: Double = 0.55) {
            self.digit = digit
            let frame = CGRect(x: 0.0, y: -CGFloat(digit) * PampGramFakeCryptoBotOdometerView.lineHeight, width: self.width, height: PampGramFakeCryptoBotOdometerView.lineHeight * 10.0)
            if animated {
                UIView.animate(withDuration: duration, delay: delay, options: [.curveEaseOut, .beginFromCurrentState], animations: {
                    self.strip.frame = frame
                })
            } else {
                self.strip.layer.removeAllAnimations()
                self.strip.frame = frame
            }
        }

        func rollFromZero(delay: Double) {
            guard let digit = self.digit, digit != 0 else {
                return
            }
            self.strip.layer.removeAllAnimations()
            self.strip.frame.origin.y = 0.0
            self.setDigit(digit, animated: true, delay: delay, duration: 0.7)
        }
    }

    private var cells: [Cell] = []
    private var text = ""
    private(set) var contentSize = CGSize(width: 0.0, height: PampGramFakeCryptoBotOdometerView.lineHeight)

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setText(prefix: String, value: String, animated: Bool) {
        let text = prefix + value
        if text == self.text {
            return
        }
        self.text = text
        let characters = Array(text)
        var reusable = characters.count == self.cells.count
        if reusable {
            for (index, character) in characters.enumerated() {
                let cell = self.cells[index]
                if (cell.digit == nil) != (character.wholeNumberValue == nil) || (cell.digit == nil && cell.character != character) {
                    reusable = false
                    break
                }
            }
        }
        if reusable {
            for (index, character) in characters.enumerated() {
                if let digit = character.wholeNumberValue, self.cells[index].digit != digit {
                    self.cells[index].setDigit(digit, animated: animated)
                }
            }
            return
        }

        for cell in self.cells {
            cell.container.removeFromSuperview()
        }
        self.cells.removeAll()
        var x: CGFloat = 0.0
        let prefixCount = prefix.count
        for (index, character) in characters.enumerated() {
            let isPrefix = index < prefixCount
            let cell = Cell(character: character, color: isPrefix ? PampGramFakeCryptoBotColors.secondary : PampGramFakeCryptoBotColors.text, rolls: !isPrefix)
            cell.container.frame = CGRect(x: x, y: 0.0, width: cell.width, height: PampGramFakeCryptoBotOdometerView.lineHeight)
            self.addSubview(cell.container)
            self.cells.append(cell)
            x += cell.width
        }
        self.contentSize = CGSize(width: x, height: PampGramFakeCryptoBotOdometerView.lineHeight)
    }

    /// The first appearance: every digit counts up from zero, left to right.
    func rollFromZero() {
        var order = 0
        for cell in self.cells where cell.digit != nil {
            cell.rollFromZero(delay: 0.05 * Double(order))
            order += 1
        }
    }
}

// MARK: - The page

/// What the real mini app shows inside Telegram's web-app window: everything below the window's own
/// header. Used both inside the real window (the window is Telegram's, only the page is ours)
/// and, wrapped with a drawn header, in the standalone screen opened from the settings.
private final class PampGramFakeCryptoBotContentView: UIView, UIScrollViewDelegate, UITextFieldDelegate, PampGramFakeMiniAppContent {
    enum Page {
        case wallet
        case deposit
        case withdraw
        /// "Выберите сеть": the networks of the coin picked in the deposit list.
        case network
        /// The address and the QR code.
        case address
        /// "История": the operations.
        case history
        /// The withdrawal form and the steps after it.
        case withdrawForm
        /// The "Биржа" tab.
        case exchange
        /// The "Обмен" tab.
        case swap
        /// The "Ещё" tab.
        case more
        /// The "P2P" tab: not drawn yet, only the bar works.
        case emptyTab
    }

    var onBackStateChanged: ((Bool) -> Void)?
    var onPageColorChanged: ((UIColor) -> Void)?
    private(set) var isDarkTheme = true
    private let themeDisposable = MetaDisposable()

    var pageColor: UIColor {
        return PampGramFakeCryptoBotColors.card.resolvedColor(with: UITraitCollection(userInterfaceStyle: self.isDarkTheme ? .dark : .light))
    }

    private let context: AccountContext
    private weak var presenter: ViewController?
    private let settingsDisposable = MetaDisposable()
    private var toastGeneration = 0

    private var balances: [String: Double] = [:]
    private var page: Page = .wallet
    private var selectedTab = 0
    private var selectedCoin: PampGramFakeCryptoBotCurrency?
    private var selectedNetworkIndex = 0
    private var addressSerials: [String: Int] = [:]
    private var balanceHidden = false
    private var smallBalancesHidden = false
    private var searchQuery = ""
    private var bannerPage = 0
    /// The blue fill that runs across the current page pill during the 4 s before the next banner.
    private var dotFill = pampGramFakeCryptoBotMakeDotFill()
    /// False while the four dots are still equal (just after the page appears); the first one then widens into the pill.
    private var pagerExpanded = false
    private var didReveal = false
    private var bannerTimer: Foundation.Timer?
    /// The live rates: `PampGramFakeCryptoBotMarket` polls the exchange while the page is on screen.
    private var marketObserver: Int?
    private var marketRefreshScheduled = false
    /// The page the sub-screens (deposit, withdrawal, history) go back to: the wallet, or "Ещё".
    private var returnPage: Page = .wallet
    private var orders: [PampGramFakeCryptoBotOrder] = []
    private var swaps: [PampGramFakeCryptoBotSwap] = []
    private var fillingOrderIds: Set<Int64> = []
    private let exchangeView = PampGramFakeCryptoBotExchangeView()
    private let swapView = PampGramFakeCryptoBotSwapView()
    private let moreView = PampGramFakeCryptoBotMoreView()
    private var bannerAnimationToken = 0

    private let toastView = UIView()
    private let toastLabel = pampGramFakeCryptoBotLabel(size: 15.0, weight: .medium, color: .white, alignment: .center)

    private let walletScroll = UIScrollView()
    private let scanControl = PampGramFakeCryptoBotRoundButton(glyph: "tg_scan")
    private let imageControl = PampGramFakeCryptoBotRoundButton(glyph: "tg_image")
    private let currencyControl = PampGramFakeCryptoBotRoundButton(glyph: "tg_currency")
    private let balanceView = PampGramFakeCryptoBotOdometerView()
    private let eyeControl = UIControl()
    private let eyeIcon = UIImageView()
    private let balanceCaption = UILabel()
    private let depositControl = PampGramFakeCryptoBotImageControl(image: PampGramFakeCryptoBotAssets.image("act_deposit"))
    private let withdrawControl = PampGramFakeCryptoBotImageControl(image: PampGramFakeCryptoBotAssets.image("act_withdraw"))
    private let historyControl = PampGramFakeCryptoBotImageControl(image: PampGramFakeCryptoBotAssets.image("act_history"))
    private let depositLabel = pampGramFakeCryptoBotLabel(size: 12.2, weight: .regular, color: PampGramFakeCryptoBotColors.blue, alignment: .center)
    private let withdrawLabel = pampGramFakeCryptoBotLabel(size: 12.2, weight: .regular, color: PampGramFakeCryptoBotColors.blue, alignment: .center)
    private let historyLabel = pampGramFakeCryptoBotLabel(size: 12.2, weight: .regular, color: PampGramFakeCryptoBotColors.blue, alignment: .center)
    private let bannerScroll = UIScrollView()
    private let bannerControls: [PampGramFakeCryptoBotBannerView] = [
        PampGramFakeCryptoBotBannerView(title: "Осенний фестиваль", lines: ["Криптовалютные подарки всем", "активным пользователям!"], accent: UIColor(rgb: 0xc44610), stripeAsset: "bs_autumn", textX: 84.3, titleCenter: 20.5, lineCenters: [40.3, 57.2]),
        PampGramFakeCryptoBotBannerView(title: "P2P Маркет", lines: ["Теперь доступен в приложении."], accent: PampGramFakeCryptoBotColors.dotFill, stripeAsset: "bs_p2p", textX: 80.7, titleCenter: 29.8, lineCenters: [49.3]),
        PampGramFakeCryptoBotBannerView(title: "Оплата по QR-коду", lines: ["Оплачивайте любые покупки с", "помощью криптовалюты."], accent: PampGramFakeCryptoBotColors.dotFill, stripeAsset: "bs_qr", textX: 80.7, titleCenter: 21.0, lineCenters: [40.2, 59.5]),
        PampGramFakeCryptoBotBannerView(title: "Быстрые обмены", lines: ["Обменивайте криптовалюту в", "несколько кликов."], accent: UIColor(rgb: 0xee8500), stripeAsset: "bs_exchange", textX: 84.7, titleCenter: 21.0, lineCenters: [40.2, 58.3])
    ]
    /// The icon of each banner, drawn over the still picture so it can play its own animation.
    private let bannerIcons: [UIImageView] = [UIImageView(), UIImageView(), UIImageView(), UIImageView()]
    private let bannerAnimations: [PampGramFakeCryptoBotIconAnimation?] = [
        PampGramFakeCryptoBotAnimations.animation(banner: "autumn"),
        PampGramFakeCryptoBotAnimations.animation(banner: "p2p"),
        PampGramFakeCryptoBotAnimations.animation(banner: "qr"),
        PampGramFakeCryptoBotAnimations.animation(banner: "exchange")
    ]
    private let dotViews: [UIView] = [UIView(), UIView(), UIView(), UIView()]
    private let assetsTitle = pampGramFakeCryptoBotLabel(size: 15.0, weight: .medium, color: PampGramFakeCryptoBotColors.blue, alignment: .left)
    private let assetsChevron = UIImageView()
    private let hideSmallButton = UIButton(type: .custom)
    private var assetRows: [PampGramFakeCryptoBotRowView] = []

    private let listScroll = UIScrollView()
    private let addressView = PampGramFakeCryptoBotAddressView()
    private let historyView = PampGramFakeCryptoBotHistoryView()
    private let withdrawView = PampGramFakeCryptoBotWithdrawView()
    private var operations: [PampGramFakeCryptoBotOperation] = []
    /// True while the coin/network pickers lead to the withdrawal form rather than to an address.
    private var isWithdrawFlow = false
    private let listTitle = pampGramFakeCryptoBotLabel(size: 15.0, weight: .regular, color: PampGramFakeCryptoBotColors.secondary, alignment: .left)
    private let searchBox = UIView()
    private let searchIcon = UIImageView()
    private let searchField = UITextField()
    private var listRows: [PampGramFakeCryptoBotRowView] = []

    private let tabBar = UIView()
    private let tabCapsule = UIView()
    private let tabBlur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let tabItems: [PampGramFakeCryptoBotTabItem] = [
        PampGramFakeCryptoBotTabItem(assetName: "tab_wallet", title: "Кошелёк", active: true),
        PampGramFakeCryptoBotTabItem(assetName: "tab_exchange", title: "Биржа", active: false),
        PampGramFakeCryptoBotTabItem(assetName: "tab_swap", title: "Обмен", active: false),
        PampGramFakeCryptoBotTabItem(assetName: "tab_p2p", title: "P2P", active: false),
        PampGramFakeCryptoBotTabItem(assetName: "tab_more", title: "Ещё", active: false)
    ]

    init(context: AccountContext, presenter: ViewController) {
        self.context = context
        self.presenter = presenter
        super.init(frame: .zero)
        // The page follows Telegram's own theme (dark or light), not the system's.
        self.isDarkTheme = context.sharedContext.currentPresentationData.with { $0 }.theme.overallDarkAppearance
        self.overrideUserInterfaceStyle = self.isDarkTheme ? .dark : .light
        self.backgroundColor = PampGramFakeCryptoBotColors.card
        // The real page shows nothing for a moment (Telegram's placeholder is under it) and then
        // fades in; see `didMoveToWindow`.
        self.alpha = 0.0

        self.setupWallet()
        self.setupList()
        self.setupMarketPages()
        self.setupTabBar()
        self.setupToast()

        self.reload()
        self.applyPage(animated: false)

        self.settingsDisposable.set((PampGramCore.rawSettingsSignal(postbox: context.account.postbox)
        |> deliverOnMainQueue).startStrict(next: { [weak self] settings in
            self?.setBalances(settings.fakeCryptoBotBalances)
            let operations = pampGramFakeCryptoBotParseOperations(settings.fakeCryptoBotHistoryRaw)
            self?.operations = operations
            self?.historyView.setOperations(operations)
            let orders = pampGramFakeCryptoBotParseOrders(settings.fakeCryptoBotOrdersRaw)
            self?.orders = orders
            self?.fillingOrderIds = (self?.fillingOrderIds ?? []).filter { id in orders.contains(where: { $0.id == id && $0.status == 0 }) }
            self?.exchangeView.setOrders(orders)
            let swaps = pampGramFakeCryptoBotParseSwaps(settings.fakeCryptoBotSwapsRaw)
            self?.swaps = swaps
            self?.swapView.setSwaps(swaps)
        }))

        self.themeDisposable.set((context.sharedContext.presentationData
        |> deliverOnMainQueue).startStrict(next: { [weak self] presentationData in
            self?.applyTheme(dark: presentationData.theme.overallDarkAppearance)
        }))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.settingsDisposable.dispose()
        self.themeDisposable.dispose()
        self.bannerTimer?.invalidate()
        if let id = self.marketObserver {
            PampGramFakeCryptoBotMarket.shared.removeObserver(id)
        }
    }

    // MARK: Appearance

    private func applyTheme(dark: Bool) {
        guard dark != self.isDarkTheme else {
            return
        }
        self.isDarkTheme = dark
        self.overrideUserInterfaceStyle = dark ? .dark : .light
        self.refreshThemeColors()
        self.onPageColorChanged?(self.pageColor)
    }

    /// Layer colours and the keyboard are not dynamic; they are set again when the theme changes.
    private func refreshThemeColors() {
        self.searchBox.layer.borderColor = self.pampGramFakeCGColor(PampGramFakeCryptoBotColors.separator)
        self.tabBar.layer.borderColor = self.pampGramFakeCGColor(PampGramFakeCryptoBotColors.tabBorder)
        self.searchField.keyboardAppearance = self.isDarkTheme ? .dark : .light
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        self.refreshThemeColors()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        self.refreshThemeColors()
        if self.window == nil {
            self.bannerTimer?.invalidate()
            self.bannerTimer = nil
            self.stopMarket()
            return
        }
        if self.didReveal {
            self.startBannerTimer()
            self.startMarket()
            return
        }
        self.didReveal = true
        // In the real app the window slides up with Telegram's placeholder in it, the page shows up
        // about 0.28 s after the slide starts (almost at once, no long fade), its balance starts
        // counting right away, and the leaf begins to play about 0.7 s later.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
            guard let self = self else {
                return
            }
            UIView.animate(withDuration: 0.06, animations: {
                self.alpha = 1.0
            })
            self.balanceView.rollFromZero()
            // The four dots are equal at first; a moment later the first one widens into the pill.
            self.pagerExpanded = true
            UIView.animate(withDuration: 0.3, delay: 0.13, options: [.curveEaseInOut], animations: {
                self.layoutDots(width: self.bounds.width)
            })
            self.startBannerTimer()
            self.startMarket()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                guard let self = self, self.bannerPage == 0 else {
                    return
                }
                self.playBannerAnimation(index: 0)
            }
        }
    }

    private func startBannerTimer() {
        self.bannerTimer?.invalidate()
        self.bannerTimer = nil
        guard self.window != nil, self.didReveal else {
            return
        }
        let timer = Foundation.Timer(timeInterval: 4.0, repeats: true) { [weak self] _ in
            self?.advanceBanner()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.bannerTimer = timer
        self.restartDotFill()
    }

    // MARK: Rates

    private func startMarket() {
        if self.marketObserver != nil {
            return
        }
        self.marketObserver = PampGramFakeCryptoBotMarket.shared.addObserver { [weak self] in
            self?.marketChanged()
        }
    }

    private func stopMarket() {
        if let id = self.marketObserver {
            PampGramFakeCryptoBotMarket.shared.removeObserver(id)
            self.marketObserver = nil
        }
    }

    /// New rates came in (up to ten answers within a moment): redraw once.
    private func marketChanged() {
        if self.marketRefreshScheduled {
            return
        }
        self.marketRefreshScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else {
                return
            }
            self.marketRefreshScheduled = false
            self.reload()
            if self.page == .exchange {
                self.exchangeView.marketUpdated()
            } else if self.page == .swap {
                self.swapView.marketUpdated()
            }
            self.checkOpenOrders()
        }
    }

    private func price(for currency: PampGramFakeCryptoBotCurrency) -> Double {
        return PampGramFakeCryptoBotMarket.shared.quote(currency.code).price
    }

    private func change(for currency: PampGramFakeCryptoBotCurrency) -> Double {
        return PampGramFakeCryptoBotMarket.shared.quote(currency.code).changePercent
    }

    private func advanceBanner() {
        let width = self.bannerScroll.bounds.width
        guard self.page == .wallet, width > 0.0, !self.bannerScroll.isTracking, !self.bannerScroll.isDragging, !self.bannerScroll.isDecelerating else {
            self.restartDotFill()
            return
        }
        let next = (self.bannerPage + 1) % self.bannerControls.count
        let offset = CGPoint(x: CGFloat(next) * width, y: 0.0)
        // After the last banner the real page runs back to the first one, a little faster.
        UIView.animate(withDuration: next == 0 ? 0.4 : 0.5, delay: 0.0, options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState], animations: {
            self.bannerScroll.contentOffset = offset
        })
    }

    private func playBannerAnimation(index: Int) {
        guard index >= 0, index < self.bannerIcons.count, let animation = self.bannerAnimations[index] else {
            return
        }
        let icon = self.bannerIcons[index]
        icon.stopAnimating()
        icon.animationImages = animation.frames
        icon.animationDuration = Double(animation.frames.count) / 20.0
        icon.animationRepeatCount = 1
        icon.startAnimating()
    }

    private func bannerPageChanged(to index: Int) {
        self.bannerAnimationToken += 1
        let token = self.bannerAnimationToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self, self.bannerAnimationToken == token, self.bannerPage == index else {
                return
            }
            self.playBannerAnimation(index: index)
        }
    }

    // MARK: Setup

    private func setupWallet() {
        self.walletScroll.alwaysBounceVertical = true
        self.walletScroll.showsVerticalScrollIndicator = false
        self.walletScroll.backgroundColor = .clear
        self.addSubview(self.walletScroll)

        for control in [self.scanControl, self.imageControl, self.currencyControl] {
            control.addTarget(self, action: #selector(self.unavailablePressed), for: .touchUpInside)
            self.walletScroll.addSubview(control)
        }

        self.balanceView.isUserInteractionEnabled = true
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(self.balanceLongPressed(_:)))
        longPress.minimumPressDuration = 1.0
        self.balanceView.addGestureRecognizer(longPress)
        self.walletScroll.addSubview(self.balanceView)

        self.eyeIcon.tintColor = PampGramFakeCryptoBotColors.secondary
        self.eyeIcon.contentMode = .center
        self.eyeIcon.isUserInteractionEnabled = false
        self.eyeControl.addSubview(self.eyeIcon)
        self.eyeControl.addTarget(self, action: #selector(self.eyePressed), for: .touchUpInside)
        self.walletScroll.addSubview(self.eyeControl)

        let caption = NSMutableAttributedString(string: "Общий баланс в ", attributes: [
            .font: PampGramFakeCryptoBotFonts.font(15.0, .regular),
            .foregroundColor: PampGramFakeCryptoBotColors.secondary
        ])
        caption.append(NSAttributedString(string: "USD", attributes: [
            .font: PampGramFakeCryptoBotFonts.font(15.0, .regular),
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
        self.historyControl.addTarget(self, action: #selector(self.historyPressed), for: .touchUpInside)
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
        for (index, icon) in self.bannerIcons.enumerated() {
            icon.isUserInteractionEnabled = false
            // The resting pose is the last frame; it is what shows before and after a play.
            icon.image = self.bannerAnimations[index]?.frames.last
            self.bannerScroll.addSubview(icon)
        }
        for dot in self.dotViews {
            dot.isUserInteractionEnabled = false
            dot.clipsToBounds = true
            self.walletScroll.addSubview(dot)
        }
        self.dotViews[0].addSubview(self.dotFill)

        self.assetsTitle.text = "Мои активы"
        self.walletScroll.addSubview(self.assetsTitle)
        self.assetsChevron.image = pampGramFakeCryptoBotSymbol("chevron.right", size: 13.0, weight: .semibold)
        self.assetsChevron.tintColor = PampGramFakeCryptoBotColors.blue
        self.assetsChevron.contentMode = .center
        self.walletScroll.addSubview(self.assetsChevron)

        self.hideSmallButton.setTitleColor(PampGramFakeCryptoBotColors.blue, for: .normal)
        self.hideSmallButton.titleLabel?.font = PampGramFakeCryptoBotFonts.font(15.0, .regular)
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
        self.addSubview(self.listScroll)

        self.addressView.isHidden = true
        self.addressView.onCopy = { [weak self] address in
            UIPasteboard.general.string = address
            self?.showToast("Адрес скопирован")
        }
        self.addressView.onUnavailable = { [weak self] in
            self?.showUnavailable()
        }
        self.addressView.onNewAddress = { [weak self] in
            self?.makeNewAddress()
        }
        self.addSubview(self.addressView)

        self.historyView.isHidden = true
        self.historyView.onFilterPressed = { [weak self] kind in
            self?.presentHistoryFilter(kind)
        }
        self.addSubview(self.historyView)

        self.withdrawView.isHidden = true
        self.withdrawView.onChangeCoin = { [weak self] in
            self?.setPage(.withdraw)
        }
        self.withdrawView.onUnavailable = { [weak self] in
            self?.showUnavailable()
        }
        self.withdrawView.onToast = { [weak self] text in
            self?.showToast(text)
        }
        self.withdrawView.onOpenWallet = { [weak self] in
            self?.setPage(.wallet)
        }
        self.withdrawView.onCompleted = { [weak self] code, total, usd in
            self?.withdrawalCompleted(code: code, total: total, usd: usd)
        }
        self.addSubview(self.withdrawView)

        self.listScroll.addSubview(self.listTitle)

        self.searchBox.layer.cornerRadius = 12.0
        self.searchBox.layer.borderWidth = 1.0
        self.searchBox.layer.borderColor = self.pampGramFakeCGColor(PampGramFakeCryptoBotColors.separator)
        self.listScroll.addSubview(self.searchBox)

        self.searchIcon.image = pampGramFakeCryptoBotSymbol("magnifyingglass", size: 19.0, weight: .regular)
        self.searchIcon.tintColor = PampGramFakeCryptoBotColors.secondary
        self.searchIcon.contentMode = .center
        self.searchBox.addSubview(self.searchIcon)

        self.searchField.attributedPlaceholder = NSAttributedString(string: "Поиск монеты", attributes: [
            .font: PampGramFakeCryptoBotFonts.font(15.0, .regular),
            .foregroundColor: PampGramFakeCryptoBotColors.secondary
        ])
        self.searchField.font = PampGramFakeCryptoBotFonts.font(15.0, .regular)
        self.searchField.textColor = PampGramFakeCryptoBotColors.text
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
        // The real bar is frosted glass: a blur with a dark tint over it.
        self.tabBar.backgroundColor = PampGramFakeCryptoBotColors.tabBar.withAlphaComponent(0.84)
        self.tabBar.layer.cornerRadius = 33.0
        self.tabBar.layer.masksToBounds = true
        self.tabBar.layer.borderWidth = 1.0
        self.tabBar.layer.borderColor = self.pampGramFakeCGColor(PampGramFakeCryptoBotColors.tabBorder)
        self.addSubview(self.tabBar)
        self.tabBlur.isUserInteractionEnabled = false
        self.tabBar.addSubview(self.tabBlur)
        self.tabCapsule.backgroundColor = PampGramFakeCryptoBotColors.tabActive
        self.tabCapsule.isUserInteractionEnabled = false
        self.tabBar.addSubview(self.tabCapsule)
        for item in self.tabItems {
            item.addTarget(self, action: #selector(self.tabPressed(_:)), for: .touchUpInside)
            self.tabBar.addSubview(item)
        }
    }

    private func setupToast() {
        self.toastView.backgroundColor = UIColor(white: 0.0, alpha: 0.82)
        self.toastView.layer.cornerRadius = 18.0
        self.toastView.alpha = 0.0
        self.toastView.isUserInteractionEnabled = false
        self.toastLabel.text = "Функция недоступна"
        self.toastView.addSubview(self.toastLabel)
        self.addSubview(self.toastView)
    }

    func showUnavailable() {
        self.showToast("Функция недоступна")
    }

    func showToast(_ text: String) {
        self.toastLabel.text = text
        self.setNeedsLayout()
        self.toastGeneration += 1
        let generation = self.toastGeneration
        UIView.animate(withDuration: 0.2, animations: {
            self.toastView.alpha = 1.0
        })
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let self = self, self.toastGeneration == generation else {
                return
            }
            UIView.animate(withDuration: 0.25, animations: {
                self.toastView.alpha = 0.0
            })
        }
    }

    func goBack() {
        switch self.page {
        case .address:
            if let coin = self.selectedCoin, pampGramFakeCryptoBotNetworks(for: coin.code).count > 1 {
                self.setPage(.network)
            } else {
                self.setPage(.deposit)
            }
        case .withdrawForm:
            if !self.withdrawView.goBack() {
                if let coin = self.selectedCoin, pampGramFakeCryptoBotNetworks(for: coin.code).count > 1 {
                    self.setPage(.network)
                } else {
                    self.setPage(.withdraw)
                }
            }
        case .network:
            self.setPage(self.isWithdrawFlow ? .withdraw : .deposit)
        case .deposit, .withdraw, .history:
            // Back to where the screen was opened from: the wallet or "Ещё".
            let target = self.returnPage
            self.returnPage = .wallet
            self.setPage(target)
        default:
            break
        }
    }

    // MARK: Data

    func setBalances(_ balances: [String: Double]) {
        self.balances = balances
        self.reload()
        self.exchangeView.balancesChanged()
        self.swapView.balancesChanged()
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
            total += self.amount(for: currency) * self.price(for: currency)
        }
        let totalText = self.balanceHidden ? "•••" : pampGramFakeCryptoBotFormatUSD(total)
        self.balanceView.setText(prefix: "$ ", value: totalText, animated: self.alpha > 0.0)
        self.eyeIcon.image = pampGramFakeCryptoBotSymbol(self.balanceHidden ? "eye.slash.fill" : "eye.fill", size: 15.0, weight: .regular)
        self.hideSmallButton.setTitle(self.smallBalancesHidden ? "Показать мелкие балансы" : "Скрыть мелкие балансы", for: .normal)

        for row in self.assetRows {
            let amount = self.amount(for: row.currency)
            let livePrice = self.price(for: row.currency)
            let usd = amount * livePrice
            row.setQuote(priceText: pampGramFakeCryptoBotPriceText(livePrice, like: row.currency.priceText), change: self.change(for: row.currency))
            row.update(amountText: self.balanceHidden ? "•••" : pampGramFakeCryptoBotFormat(amount, fractionDigits: row.currency.fractionDigits) + " " + row.currency.code, usdText: self.balanceHidden ? "•••" : "$" + pampGramFakeCryptoBotFormatUSD(usd))
            row.isHidden = self.smallBalancesHidden && usd < 1.0
        }
        for row in self.listRows {
            let amount = self.amount(for: row.currency)
            row.update(amountText: pampGramFakeCryptoBotFormat(amount, fractionDigits: row.currency.fractionDigits) + " " + row.currency.code, usdText: "$" + pampGramFakeCryptoBotFormatUSD(amount * self.price(for: row.currency)))
        }
        self.setNeedsLayout()
    }

    private func rebuildListRows() {
        for row in self.listRows {
            row.removeFromSuperview()
        }
        self.listRows.removeAll()
        if self.page == .network, let coin = self.selectedCoin {
            // The networks of the picked coin, drawn with the same rows as the coins.
            for (index, network) in pampGramFakeCryptoBotNetworks(for: coin.code).enumerated() {
                let pseudo = PampGramFakeCryptoBotCurrency(code: network.name, name: network.standard, assetName: network.assetName, price: 0.0, priceText: "", change: 0.0, fractionDigits: 2)
                let row = PampGramFakeCryptoBotRowView(currency: pseudo, kind: .deposit)
                row.tag = index
                row.addTarget(self, action: #selector(self.listRowPressed(_:)), for: .touchUpInside)
                self.listScroll.addSubview(row)
                self.listRows.append(row)
            }
            return
        }
        let kind: PampGramFakeCryptoBotRowView.Kind = self.page == .withdraw ? .withdraw : .deposit
        let query = self.searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        for currency in pampGramFakeCryptoBotCurrencies {
            if !query.isEmpty && !currency.code.lowercased().contains(query) && !currency.name.lowercased().contains(query) {
                continue
            }
            let row = PampGramFakeCryptoBotRowView(currency: currency, kind: kind)
            row.addTarget(self, action: #selector(self.listRowPressed(_:)), for: .touchUpInside)
            self.listScroll.addSubview(row)
            self.listRows.append(row)
        }
        self.reload()
    }

    private func applyPage(animated: Bool) {
        let isWallet = self.page == .wallet
        let isList = self.page == .deposit || self.page == .withdraw || self.page == .network
        let isAddress = self.page == .address
        let isHistory = self.page == .history
        let isWithdrawForm = self.page == .withdrawForm
        let isExchange = self.page == .exchange
        let isSwap = self.page == .swap
        let isMore = self.page == .more
        self.walletScroll.isHidden = !isWallet
        self.tabBar.isHidden = isList || isAddress || isHistory || isWithdrawForm
        self.historyView.isHidden = !isHistory
        self.withdrawView.isHidden = !isWithdrawForm
        self.listScroll.isHidden = !isList
        self.addressView.isHidden = !isAddress
        self.exchangeView.isHidden = !isExchange
        self.swapView.isHidden = !isSwap
        self.moreView.isHidden = !isMore
        self.exchangeView.setActive(isExchange)
        self.searchBox.isHidden = self.page == .network
        switch self.page {
        case .withdraw:
            self.listTitle.text = "Вывод криптовалюты"
        case .network:
            self.listTitle.text = "Выберите сеть"
        default:
            self.listTitle.text = "Пополнение криптовалюты"
        }
        if animated && (isWallet || isList || isAddress || isHistory || isWithdrawForm || isExchange || isSwap || isMore) {
            let target: UIView
            if isWallet {
                target = self.walletScroll
            } else if isAddress {
                target = self.addressView
            } else if isHistory {
                target = self.historyView
            } else if isWithdrawForm {
                target = self.withdrawView
            } else if isExchange {
                target = self.exchangeView
            } else if isSwap {
                target = self.swapView
            } else if isMore {
                target = self.moreView
            } else {
                target = self.listScroll
            }
            target.alpha = 0.0
            UIView.animate(withDuration: 0.2, animations: {
                target.alpha = 1.0
            })
        }
        self.onBackStateChanged?(isList || isAddress || isHistory || isWithdrawForm)
        self.setNeedsLayout()
    }

    private func setPage(_ page: Page) {
        self.endEditing(true)
        if page == .wallet {
            self.returnPage = .wallet
            self.syncTab(0, animated: false)
        }
        self.page = page
        self.searchField.text = ""
        self.searchQuery = ""
        self.listScroll.contentOffset = .zero
        if page == .deposit || page == .withdraw || page == .network {
            self.rebuildListRows()
        }
        self.applyPage(animated: true)
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = self.bounds.width
        let height = self.bounds.height

        self.walletScroll.frame = self.bounds
        self.listScroll.frame = self.bounds
        self.addressView.frame = self.bounds
        self.historyView.frame = self.bounds
        self.withdrawView.frame = self.bounds
        self.exchangeView.frame = self.bounds
        self.swapView.frame = self.bounds
        self.moreView.frame = self.bounds
        self.layoutWallet(width: width)
        self.layoutList(width: width)

        // Tab bar.
        let barWidth: CGFloat = width - 60.0
        self.tabBar.frame = CGRect(x: 30.0, y: height - 66.0 - 19.5, width: barWidth, height: 66.0)
        self.tabBlur.frame = self.tabBar.bounds
        let itemWidth = (barWidth - 9.0) / CGFloat(self.tabItems.count)
        for (index, item) in self.tabItems.enumerated() {
            item.frame = CGRect(x: 4.5 + CGFloat(index) * itemWidth, y: 0.0, width: itemWidth, height: 66.0)
        }
        self.layoutTabCapsule()

        // The "unavailable" toast, just above the tab bar.
        let toastTextSize = self.toastLabel.sizeThatFits(CGSize(width: max(0.0, width - 64.0), height: 40.0))
        let toastWidth = min(width - 32.0, toastTextSize.width + 32.0)
        self.toastView.frame = CGRect(x: floor((width - toastWidth) / 2.0), y: height - 66.0 - 19.5 - 16.0 - 36.0, width: toastWidth, height: 36.0)
        self.toastLabel.frame = self.toastView.bounds
    }

    private func layoutTabCapsule() {
        let itemWidth = (self.tabBar.bounds.width - 9.0) / CGFloat(self.tabItems.count)
        self.tabCapsule.frame = CGRect(x: 4.5 + CGFloat(self.selectedTab) * itemWidth, y: 5.0, width: itemWidth, height: 56.0).insetBy(dx: 0.3, dy: 0.0)
        self.tabCapsule.layer.cornerRadius = self.tabCapsule.bounds.height / 2.0
    }

    private func layoutWallet(width: CGFloat) {
        self.scanControl.frame = CGRect(x: 16.0, y: 8.0, width: 34.0, height: 34.0)
        self.imageControl.frame = CGRect(x: width - 96.0, y: 8.0, width: 34.0, height: 34.0)
        self.currencyControl.frame = CGRect(x: width - 50.0, y: 8.0, width: 34.0, height: 34.0)

        let balanceSize = self.balanceView.contentSize
        let eyeWidth: CGFloat = 26.0
        let groupWidth = balanceSize.width + 12.0 + eyeWidth
        let groupX = floor((width - groupWidth) / 2.0)
        self.balanceView.frame = CGRect(x: groupX, y: 59.0, width: balanceSize.width, height: 46.0)
        self.eyeControl.frame = CGRect(x: groupX + balanceSize.width + 4.0, y: 59.0, width: eyeWidth + 8.0, height: 46.0)
        self.eyeIcon.frame = self.eyeControl.bounds
        self.balanceCaption.frame = CGRect(x: 0.0, y: 108.0, width: width, height: 22.0)

        let contentWidth = width - 32.0
        let columnWidth = contentWidth / 3.0
        let controls: [UIView] = [self.depositControl, self.withdrawControl, self.historyControl]
        let labels: [UILabel] = [self.depositLabel, self.withdrawLabel, self.historyLabel]
        for index in 0 ..< 3 {
            let centerX = 16.0 + columnWidth * (CGFloat(index) + 0.5)
            controls[index].frame = CGRect(x: floor(centerX - 20.5), y: 149.0, width: 41.0, height: 41.0)
            labels[index].frame = CGRect(x: floor(centerX - columnWidth / 2.0), y: 196.0, width: columnWidth, height: 20.0)
        }

        let bannerWidth = contentWidth
        let bannerHeight: CGFloat = 74.0
        self.bannerScroll.frame = CGRect(x: 16.0, y: 234.0, width: bannerWidth, height: bannerHeight)
        self.bannerScroll.contentSize = CGSize(width: bannerWidth * CGFloat(self.bannerControls.count), height: bannerHeight)
        for (index, control) in self.bannerControls.enumerated() {
            control.frame = CGRect(x: CGFloat(index) * bannerWidth, y: 0.0, width: bannerWidth, height: bannerHeight)
        }
        // Each icon sits over its banner picture exactly where the picture has the icon; the
        // picture is shown aspect-fit, so follow the same scale and offset.
        let pictureWidth: CGFloat = 1110.0 / 3.0
        let pictureHeight: CGFloat = 223.0 / 3.0
        let pictureScale = min(bannerWidth / pictureWidth, bannerHeight / pictureHeight)
        let pictureOffsetX = (bannerWidth - pictureWidth * pictureScale) / 2.0
        let pictureOffsetY = (bannerHeight - pictureHeight * pictureScale) / 2.0
        for (index, icon) in self.bannerIcons.enumerated() {
            guard let box = self.bannerAnimations[index]?.box else {
                continue
            }
            icon.frame = CGRect(
                x: CGFloat(index) * bannerWidth + pictureOffsetX + box.minX / 3.0 * pictureScale,
                y: pictureOffsetY + box.minY / 3.0 * pictureScale,
                width: box.width / 3.0 * pictureScale,
                height: box.height / 3.0 * pictureScale
            )
        }
        self.layoutDots(width: width)

        let titleSize = self.assetsTitle.sizeThatFits(CGSize(width: width, height: 22.0))
        self.assetsTitle.frame = CGRect(x: 16.0, y: 346.0, width: titleSize.width, height: 22.0)
        self.assetsChevron.frame = CGRect(x: 16.0 + titleSize.width + 4.0, y: 346.0, width: 14.0, height: 22.0)
        self.hideSmallButton.frame = CGRect(x: width / 2.0 - 20.0, y: 337.0, width: width / 2.0 + 4.0, height: 40.0)

        var y: CGFloat = 379.5
        for row in self.assetRows where !row.isHidden {
            row.frame = CGRect(x: 0.0, y: y, width: width, height: 65.0)
            y += 65.0
        }
        self.walletScroll.contentSize = CGSize(width: width, height: y + 130.0)
    }

    /// The page dots: the current one is a 24pt pill, the others 6pt circles, 6pt apart; the row stays
    /// centred, so the first pill widens to both sides when it appears.
    private func layoutDots(width: CGFloat) {
        let count = self.dotViews.count
        var widths: [CGFloat] = []
        for index in 0 ..< count {
            widths.append(index == self.bannerPage && self.pagerExpanded ? 24.0 : 6.0)
        }
        let total = widths.reduce(0.0, +) + 6.0 * CGFloat(count - 1)
        var dotX = floor((width - total) / 2.0)
        for (index, dot) in self.dotViews.enumerated() {
            dot.frame = CGRect(x: dotX, y: 316.0, width: widths[index], height: 6.0)
            dot.layer.cornerRadius = 3.0
            dot.backgroundColor = PampGramFakeCryptoBotColors.dotInactive
            dotX += widths[index] + 6.0
        }
    }

    /// Fills the current pill from the left, from nothing to full over the 4 s the banner stays; the
    /// next banner comes when it is full. When the page changes, the old fill stays in the old pill
    /// while it shrinks and goes out in the middle of that, as on the real page.
    private func restartDotFill(retiringOld: Bool = false) {
        let pill = self.dotViews[max(0, min(self.dotViews.count - 1, self.bannerPage))]
        // The scripted slide calls this from inside its own animation block; the reset must not animate.
        if retiringOld {
            let old = self.dotFill
            UIView.performWithoutAnimation {
                let current = old.layer.presentation()?.frame ?? old.frame
                old.layer.removeAllAnimations()
                old.frame = current
            }
            UIView.animate(withDuration: 0.06, delay: 0.14, options: [], animations: {
                old.alpha = 0.0
            }, completion: { _ in
                old.removeFromSuperview()
            })
            self.dotFill = pampGramFakeCryptoBotMakeDotFill()
        }
        let fill = self.dotFill
        UIView.performWithoutAnimation {
            fill.layer.removeAllAnimations()
            if fill.superview !== pill {
                pill.addSubview(fill)
            }
            fill.alpha = 1.0
            fill.frame = CGRect(x: 0.0, y: 0.0, width: 0.0, height: 6.0)
        }
        guard self.bannerTimer != nil else {
            return
        }
        UIView.animate(withDuration: 4.0, delay: 0.0, options: [.curveLinear, .allowUserInteraction], animations: {
            fill.frame = CGRect(x: 0.0, y: 0.0, width: 24.0, height: 6.0)
        })
    }

    private func layoutList(width: CGFloat) {
        let isNetworks = self.page == .network
        self.listTitle.frame = CGRect(x: 16.0, y: isNetworks ? 25.0 : 29.0, width: max(0.0, width - 32.0), height: 22.0)
        self.searchBox.frame = CGRect(x: 16.0, y: 64.0, width: max(0.0, width - 32.0), height: 46.0)
        self.searchIcon.frame = CGRect(x: 12.0, y: 13.0, width: 24.0, height: 20.0)
        self.searchField.frame = CGRect(x: 48.0, y: 0.0, width: max(0.0, self.searchBox.bounds.width - 60.0), height: 46.0)
        var y: CGFloat = isNetworks ? 57.5 : 123.0
        for row in self.listRows {
            row.frame = CGRect(x: 0.0, y: y, width: width, height: 65.0)
            y += 65.0
        }
        self.listScroll.contentSize = CGSize(width: width, height: y + 40.0)
    }

    // MARK: Actions

    @objc private func historyPressed() {
        self.setPage(.history)
    }

    /// The three pills over the history: a sheet with the choices for that filter.
    private func presentHistoryFilter(_ kind: Int) {
        guard let presenter = self.presenter else {
            return
        }
        let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
        let sheet = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = []
        let history = self.historyView
        func choice(_ title: String, _ apply: @escaping () -> Void) {
            items.append(ActionSheetButtonItem(title: title, color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                apply()
            }))
        }
        switch kind {
        case 0:
            items.append(ActionSheetTextItem(title: "Тип операции"))
            choice("Все операции", { history.setTypeFilter(0) })
            choice("Пополнение", { history.setTypeFilter(1) })
            choice("Вывод", { history.setTypeFilter(2) })
        case 1:
            items.append(ActionSheetTextItem(title: "Монета"))
            choice("Все монеты", { history.setCoinFilter(nil) })
            for currency in pampGramFakeCryptoBotCurrencies {
                let code = currency.code
                choice(code, { history.setCoinFilter(code) })
            }
        default:
            items.append(ActionSheetTextItem(title: "Период"))
            choice("Всё время", { history.setPeriodFilter(0) })
            choice("Сегодня", { history.setPeriodFilter(1) })
            choice("7 дней", { history.setPeriodFilter(2) })
            choice("30 дней", { history.setPeriodFilter(3) })
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
    }

    @objc private func depositPressed() {
        self.setPage(.deposit)
    }

    @objc private func withdrawPressed() {
        self.setPage(.withdraw)
    }

    @objc private func listRowPressed(_ sender: PampGramFakeCryptoBotRowView) {
        switch self.page {
        case .deposit:
            let coin = sender.currency
            self.selectedCoin = coin
            self.isWithdrawFlow = false
            if pampGramFakeCryptoBotNetworks(for: coin.code).count > 1 {
                self.setPage(.network)
            } else {
                self.openAddress(networkIndex: 0)
            }
        case .withdraw:
            let coin = sender.currency
            self.selectedCoin = coin
            self.isWithdrawFlow = true
            if pampGramFakeCryptoBotNetworks(for: coin.code).count > 1 {
                self.setPage(.network)
            } else {
                self.openWithdraw(networkIndex: 0)
            }
        case .network:
            if self.isWithdrawFlow {
                self.openWithdraw(networkIndex: sender.tag)
            } else {
                self.openAddress(networkIndex: sender.tag)
            }
        default:
            self.showUnavailable()
        }
    }

    private func openWithdraw(networkIndex: Int) {
        guard let coin = self.selectedCoin else {
            return
        }
        let networks = pampGramFakeCryptoBotNetworks(for: coin.code)
        guard networkIndex >= 0 && networkIndex < networks.count else {
            return
        }
        self.selectedNetworkIndex = networkIndex
        // What was already withdrawn this week feeds the "На этой неделе …" line.
        let weekAgo = Int32(clamping: Int(Date().timeIntervalSince1970 - 7.0 * 86400.0))
        var count = 0
        var usd = 0.0
        for operation in self.operations where operation.kind == 1 && operation.date >= weekAgo {
            count += 1
            usd += operation.usd
        }
        let liveCoin = PampGramFakeCryptoBotCurrency(code: coin.code, name: coin.name, assetName: coin.assetName, price: self.price(for: coin), priceText: coin.priceText, change: coin.change, fractionDigits: coin.fractionDigits)
        self.withdrawView.configure(currency: liveCoin, network: networks[networkIndex], balance: self.balances[coin.code] ?? 0.0, weekCount: count, weekUSD: usd)
        self.setPage(.withdrawForm)
    }

    /// The code was entered: the balance goes down by what was sent and the fee, and the history gets a withdrawal.
    private func withdrawalCompleted(code: String, total: Double, usd: Double) {
        let context = self.context
        let price = pampGramFakeCryptoBotCurrencies.first(where: { $0.code == code }).map { self.price(for: $0) } ?? 0.0
        let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
            var settings = settings
            var balances = settings.fakeCryptoBotBalances
            let previous = balances[code] ?? 0.0
            let updated = max(0.0, previous - total)
            if updated <= 0.0 {
                balances.removeValue(forKey: code)
            } else {
                balances[code] = updated
            }
            settings.fakeCryptoBotBalances = balances
            settings.fakeCryptoBotHistoryRaw = pampGramFakeCryptoBotAppendingOperation(raw: settings.fakeCryptoBotHistoryRaw, code: code, old: previous, new: updated, price: price)
            return settings
        }).start()
        _ = usd
    }

    private func openAddress(networkIndex: Int) {
        guard let coin = self.selectedCoin else {
            return
        }
        let networks = pampGramFakeCryptoBotNetworks(for: coin.code)
        guard networkIndex >= 0 && networkIndex < networks.count else {
            return
        }
        self.selectedNetworkIndex = networkIndex
        self.configureAddressView()
        self.setPage(.address)
    }

    private func configureAddressView() {
        guard let coin = self.selectedCoin else {
            return
        }
        let networks = pampGramFakeCryptoBotNetworks(for: coin.code)
        guard self.selectedNetworkIndex >= 0 && self.selectedNetworkIndex < networks.count else {
            return
        }
        let network = networks[self.selectedNetworkIndex]
        let serial = self.addressSerials[coin.code + "|" + network.name] ?? 0
        self.addressView.configure(currency: coin, network: network, serial: serial)
    }

    /// "Получить новый адрес": another made-up address (and QR) for the same coin and network.
    private func makeNewAddress() {
        guard let coin = self.selectedCoin else {
            return
        }
        let networks = pampGramFakeCryptoBotNetworks(for: coin.code)
        guard self.selectedNetworkIndex >= 0 && self.selectedNetworkIndex < networks.count else {
            return
        }
        let key = coin.code + "|" + networks[self.selectedNetworkIndex].name
        self.addressSerials[key] = (self.addressSerials[key] ?? 0) + 1
        UIView.transition(with: self.addressView, duration: 0.2, options: [.transitionCrossDissolve], animations: {
            self.configureAddressView()
        })
    }

    @objc private func unavailablePressed() {
        self.showUnavailable()
    }

    @objc private func tabPressed(_ sender: PampGramFakeCryptoBotTabItem) {
        guard let index = self.tabItems.firstIndex(where: { $0 === sender }), index != self.selectedTab else {
            return
        }
        self.selectTab(index)
    }

    private func tabPage(_ index: Int) -> Page {
        switch index {
        case 0:
            return .wallet
        case 1:
            return .exchange
        case 2:
            return .swap
        case 4:
            return .more
        default:
            return .emptyTab
        }
    }

    /// Moves the highlight of the bar to `index` without touching the page.
    private func syncTab(_ index: Int, animated: Bool) {
        guard index != self.selectedTab else {
            return
        }
        self.selectedTab = index
        if animated {
            UIView.animate(withDuration: 0.4, delay: 0.0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0.4, options: [.allowUserInteraction, .beginFromCurrentState], animations: {
                self.layoutTabCapsule()
            })
        } else {
            self.layoutTabCapsule()
        }
        for (itemIndex, item) in self.tabItems.enumerated() {
            item.setActive(itemIndex == index, animated: animated)
        }
    }

    private func selectTab(_ index: Int) {
        self.endEditing(true)
        self.returnPage = .wallet
        self.syncTab(index, animated: true)
        self.page = self.tabPage(index)
        self.applyPage(animated: true)
    }

    /// A tile of "Ещё": the screens that exist open, the rest says it is not available.
    private func moreAction(_ id: String) {
        switch id {
        case "deposit":
            self.returnPage = .more
            self.setPage(.deposit)
        case "withdraw":
            self.returnPage = .more
            self.setPage(.withdraw)
        case "history":
            self.returnPage = .more
            self.setPage(.history)
        case "exchange":
            self.selectTab(1)
        case "swap":
            self.selectTab(2)
        case "p2p":
            self.selectTab(3)
        default:
            self.showUnavailable()
        }
    }

    /// A list of choices as a sheet, for the exchange's pair and step and the swap's coins.
    private func presentChoices(title: String, options: [String], selected: Int?, handler: @escaping (Int) -> Void) {
        guard let presenter = self.presenter else {
            return
        }
        let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
        let sheet = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = [ActionSheetTextItem(title: title)]
        for (index, option) in options.enumerated() {
            items.append(ActionSheetButtonItem(title: option, color: .accent, font: index == selected ? .bold : .default, action: { [weak sheet] in
                sheet?.dismissAnimated()
                handler(index)
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
    }

    private func balance(of code: String) -> Double {
        guard let currency = pampGramFakeCryptoBotCurrencies.first(where: { $0.code == code }) else {
            return 0.0
        }
        return self.amount(for: currency)
    }

    private func setupMarketPages() {
        let provider: (String) -> Double = { [weak self] code in
            return self?.balance(of: code) ?? 0.0
        }
        let choices: (String, [String], Int?, @escaping (Int) -> Void) -> Void = { [weak self] title, options, selected, handler in
            self?.presentChoices(title: title, options: options, selected: selected, handler: handler)
        }
        self.exchangeView.isHidden = true
        self.exchangeView.balanceProvider = provider
        self.exchangeView.presentChoices = choices
        self.exchangeView.onToast = { [weak self] text in
            self?.showToast(text)
        }
        self.exchangeView.onPlaceOrder = { [weak self] order in
            self?.placeOrder(order)
        }
        self.exchangeView.onCancelOrder = { [weak self] id in
            self?.cancelOrder(id)
        }
        self.addSubview(self.exchangeView)

        self.swapView.isHidden = true
        self.swapView.balanceProvider = provider
        self.swapView.presentChoices = choices
        self.swapView.onToast = { [weak self] text in
            self?.showToast(text)
        }
        self.swapView.onSwap = { [weak self] swap in
            self?.performSwap(swap)
        }
        self.addSubview(self.swapView)

        self.moreView.isHidden = true
        self.moreView.onAction = { [weak self] id in
            self?.moreAction(id)
        }
        self.addSubview(self.moreView)
    }

    // MARK: Orders and swaps

    /// Places an order: a market order, or a limit order the price has already reached, fills at once;
    /// any other limit order waits as open (its money is set aside) and fills when the price gets there.
    private func placeOrder(_ order: PampGramFakeCryptoBotOrder) {
        var order = order
        let market = PampGramFakeCryptoBotMarket.shared.quote(order.code).price
        var fillPrice = order.price
        var fills = order.kind == 1
        if order.kind == 1 {
            fillPrice = market
        } else if order.side == 0 && order.price >= market {
            fills = true
            fillPrice = market
        } else if order.side == 1 && order.price <= market {
            fills = true
            fillPrice = market
        }
        order.price = fillPrice
        order.status = fills ? 1 : 0
        let placed = order
        let _ = PampGramCore.updateSettingsInteractively(postbox: self.context.account.postbox, { settings in
            var settings = settings
            var balances = settings.fakeCryptoBotBalances
            if placed.side == 0 {
                pampGramFakeCryptoBotAdjust(&balances, "USDT", by: -placed.amount * placed.price)
                if placed.status == 1 {
                    pampGramFakeCryptoBotAdjust(&balances, placed.code, by: placed.amount)
                }
            } else {
                pampGramFakeCryptoBotAdjust(&balances, placed.code, by: -placed.amount)
                if placed.status == 1 {
                    pampGramFakeCryptoBotAdjust(&balances, "USDT", by: placed.amount * placed.price)
                }
            }
            settings.fakeCryptoBotBalances = balances
            var orders = pampGramFakeCryptoBotParseOrders(settings.fakeCryptoBotOrdersRaw)
            orders.append(placed)
            settings.fakeCryptoBotOrdersRaw = pampGramFakeCryptoBotSerializeOrders(orders)
            return settings
        }).start()
        self.showToast(fills ? "Ордер исполнен" : "Ордер создан")
    }

    private func cancelOrder(_ id: Int64) {
        let _ = PampGramCore.updateSettingsInteractively(postbox: self.context.account.postbox, { settings in
            var settings = settings
            var orders = pampGramFakeCryptoBotParseOrders(settings.fakeCryptoBotOrdersRaw)
            guard let index = orders.firstIndex(where: { $0.id == id && $0.status == 0 }) else {
                return settings
            }
            orders[index].status = 2
            let order = orders[index]
            var balances = settings.fakeCryptoBotBalances
            if order.side == 0 {
                pampGramFakeCryptoBotAdjust(&balances, "USDT", by: order.amount * order.price)
            } else {
                pampGramFakeCryptoBotAdjust(&balances, order.code, by: order.amount)
            }
            settings.fakeCryptoBotBalances = balances
            settings.fakeCryptoBotOrdersRaw = pampGramFakeCryptoBotSerializeOrders(orders)
            return settings
        }).start()
        self.showToast("Ордер отменён")
    }

    /// Fills the open orders the price has reached.
    private func checkOpenOrders() {
        for order in self.orders where order.status == 0 && !self.fillingOrderIds.contains(order.id) {
            let market = PampGramFakeCryptoBotMarket.shared.quote(order.code).price
            let reached = order.side == 0 ? market <= order.price : market >= order.price
            if reached {
                self.fillOrder(order.id)
            }
        }
    }

    private func fillOrder(_ id: Int64) {
        self.fillingOrderIds.insert(id)
        let _ = PampGramCore.updateSettingsInteractively(postbox: self.context.account.postbox, { settings in
            var settings = settings
            var orders = pampGramFakeCryptoBotParseOrders(settings.fakeCryptoBotOrdersRaw)
            guard let index = orders.firstIndex(where: { $0.id == id && $0.status == 0 }) else {
                return settings
            }
            orders[index].status = 1
            let order = orders[index]
            var balances = settings.fakeCryptoBotBalances
            if order.side == 0 {
                pampGramFakeCryptoBotAdjust(&balances, order.code, by: order.amount)
            } else {
                pampGramFakeCryptoBotAdjust(&balances, "USDT", by: order.amount * order.price)
            }
            settings.fakeCryptoBotBalances = balances
            settings.fakeCryptoBotOrdersRaw = pampGramFakeCryptoBotSerializeOrders(orders)
            return settings
        }).start()
    }

    private func performSwap(_ swap: PampGramFakeCryptoBotSwap) {
        let _ = PampGramCore.updateSettingsInteractively(postbox: self.context.account.postbox, { settings in
            var settings = settings
            var balances = settings.fakeCryptoBotBalances
            pampGramFakeCryptoBotAdjust(&balances, swap.from, by: -swap.fromAmount)
            pampGramFakeCryptoBotAdjust(&balances, swap.to, by: swap.toAmount)
            settings.fakeCryptoBotBalances = balances
            var swaps = pampGramFakeCryptoBotParseSwaps(settings.fakeCryptoBotSwapsRaw)
            swaps.append(swap)
            settings.fakeCryptoBotSwapsRaw = pampGramFakeCryptoBotSerializeSwaps(swaps)
            return settings
        }).start()
        self.showToast("Обмен выполнен")
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
        guard let presenter = self.presenter else {
            return
        }
        pampGramFakeCryptoBotPresentBalanceEditor(context: self.context, presenter: presenter)
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
            UIView.animate(withDuration: 0.3, delay: 0.0, options: [.curveEaseInOut, .beginFromCurrentState], animations: {
                self.layoutDots(width: self.bounds.width)
            })
            self.restartDotFill(retiringOld: true)
            self.bannerPageChanged(to: index)
        }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        if scrollView === self.bannerScroll {
            self.bannerTimer?.invalidate()
            self.bannerTimer = nil
            self.restartDotFill()
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if scrollView === self.bannerScroll && !decelerate {
            self.startBannerTimer()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        if scrollView === self.bannerScroll {
            self.startBannerTimer()
        }
    }
}

// MARK: - Standalone screen

/// The settings' "Открыть фейковый криптобот": the same page with a header drawn to look like
/// Telegram's web-app window, since there is no real window around it.
private final class PampGramFakeCryptoBotStandaloneView: UIView {
    var onClose: (() -> Void)?

    private var topInset: CGFloat = 59.0
    private let content: PampGramFakeCryptoBotContentView
    private let cardView = UIView()
    private let closeControl = UIControl()
    private let closeLabel = pampGramFakeCryptoBotLabel(size: 17.0, weight: .regular, color: PampGramFakeCryptoBotColors.text, alignment: .left)
    private let backControl = UIControl()
    private let backChevron = UIImageView()
    private let backLabel = pampGramFakeCryptoBotLabel(size: 17.0, weight: .regular, color: PampGramFakeCryptoBotColors.text, alignment: .left)
    private let titleLabel = pampGramFakeCryptoBotLabel(size: 17.0, weight: .semibold, color: PampGramFakeCryptoBotColors.text, alignment: .center)
    private let subtitleLabel = pampGramFakeCryptoBotLabel(size: 13.0, weight: .regular, color: PampGramFakeCryptoBotColors.subtitle, alignment: .center)
    private let moreControl = UIControl()
    private let moreIcon = UIImageView()

    init(content: PampGramFakeCryptoBotContentView, title: String) {
        self.content = content
        super.init(frame: .zero)
        self.overrideUserInterfaceStyle = content.isDarkTheme ? .dark : .light
        self.backgroundColor = PampGramFakeCryptoBotColors.outer

        self.cardView.backgroundColor = PampGramFakeCryptoBotColors.card
        self.cardView.layer.cornerRadius = 28.0
        self.cardView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        self.cardView.clipsToBounds = true
        self.addSubview(self.cardView)
        self.cardView.addSubview(content)

        self.closeLabel.text = "Закрыть"
        self.closeControl.addSubview(self.closeLabel)
        self.closeControl.addTarget(self, action: #selector(self.closePressed), for: .touchUpInside)
        self.cardView.addSubview(self.closeControl)

        self.backChevron.image = pampGramFakeCryptoBotSymbol("chevron.left", size: 20.0, weight: .semibold)
        self.backChevron.tintColor = PampGramFakeCryptoBotColors.text
        self.backChevron.contentMode = .center
        self.backChevron.isUserInteractionEnabled = false
        self.backLabel.text = "Назад"
        self.backControl.addSubview(self.backChevron)
        self.backControl.addSubview(self.backLabel)
        self.backControl.addTarget(self, action: #selector(self.backPressed), for: .touchUpInside)
        self.backControl.isHidden = true
        self.cardView.addSubview(self.backControl)

        self.titleLabel.text = title
        self.subtitleLabel.text = "мини-приложение"
        self.cardView.addSubview(self.titleLabel)
        self.cardView.addSubview(self.subtitleLabel)

        self.moreIcon.image = pampGramFakeCryptoBotSymbol("ellipsis.circle", size: 24.0, weight: .regular)
        self.moreIcon.tintColor = PampGramFakeCryptoBotColors.text
        self.moreIcon.contentMode = .center
        self.moreIcon.isUserInteractionEnabled = false
        self.moreControl.addSubview(self.moreIcon)
        self.moreControl.addTarget(self, action: #selector(self.morePressed), for: .touchUpInside)
        self.cardView.addSubview(self.moreControl)

        content.onBackStateChanged = { [weak self] hasBack in
            self?.closeControl.isHidden = hasBack
            self?.backControl.isHidden = !hasBack
        }
        content.onPageColorChanged = { [weak self] _ in
            self?.overrideUserInterfaceStyle = content.isDarkTheme ? .dark : .light
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

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

        self.closeControl.frame = CGRect(x: 0.0, y: 12.0, width: 110.0, height: 52.0)
        self.closeLabel.frame = CGRect(x: 16.0, y: 0.0, width: 94.0, height: 52.0)
        self.backControl.frame = CGRect(x: 0.0, y: 12.0, width: 120.0, height: 52.0)
        self.backChevron.frame = CGRect(x: 7.0, y: 14.0, width: 16.0, height: 24.0)
        self.backLabel.frame = CGRect(x: 28.0, y: 0.0, width: 90.0, height: 52.0)
        self.titleLabel.frame = CGRect(x: 70.0, y: 19.0, width: max(0.0, width - 140.0), height: 22.0)
        self.subtitleLabel.frame = CGRect(x: 70.0, y: 39.0, width: max(0.0, width - 140.0), height: 16.0)
        self.moreControl.frame = CGRect(x: width - 45.0, y: 18.0, width: 40.0, height: 40.0)
        self.moreIcon.frame = self.moreControl.bounds

        self.content.frame = CGRect(x: 0.0, y: 62.0, width: width, height: max(0.0, cardHeight - 62.0))
    }

    @objc private func closePressed() {
        self.onClose?()
    }

    @objc private func backPressed() {
        self.content.goBack()
    }

    @objc private func morePressed() {
        self.content.showUnavailable()
    }
}

private final class PampGramFakeCryptoBotScreen: ViewController {
    private let context: AccountContext
    private var standaloneView: PampGramFakeCryptoBotStandaloneView?
    private let title: String

    init(context: AccountContext, title: String) {
        self.context = context
        self.title = title
        super.init(navigationBarPresentationData: nil)
        self.displayNavigationBar = false
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadDisplayNode() {
        let node = ASDisplayNode()
        node.backgroundColor = .black
        self.displayNode = node
        self.displayNodeDidLoad()

        let content = PampGramFakeCryptoBotContentView(context: self.context, presenter: self)
        let standaloneView = PampGramFakeCryptoBotStandaloneView(content: content, title: self.title)
        standaloneView.onClose = { [weak self] in
            self?.dismiss()
        }
        node.view.addSubview(standaloneView)
        self.standaloneView = standaloneView
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        self.standaloneView?.frame = CGRect(origin: .zero, size: layout.size)
        self.standaloneView?.updateInsets(top: layout.insets(options: [.statusBar]).top)
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
                let previous = balances[currency.code] ?? 0.0
                if value <= 0 {
                    balances.removeValue(forKey: currency.code)
                } else {
                    balances[currency.code] = value
                }
                settings.fakeCryptoBotBalances = balances
                // A balance that went up reads as a deposit, one that went down as a withdrawal.
                settings.fakeCryptoBotHistoryRaw = pampGramFakeCryptoBotAppendingOperation(raw: settings.fakeCryptoBotHistoryRaw, code: currency.code, old: previous, new: max(value, 0.0), price: currency.price)
                return settings
            }).start()
        }
    ), in: .window(.root))
}

// MARK: - Публичные конструкторы

/// Открывает полноэкранный визуал «CryptoBot мини-апп» на этом устройстве (строка в
/// «Дополнительно»). Балансы подставляются из `PampGramSettings.fakeCryptoBotBalances`;
/// редактор открывается удержанием суммы общего баланса (около секунды).
public func pampGramFakeCryptoBotController(context: AccountContext, title: String = "Crypto Bot") -> ViewController {
    return PampGramFakeCryptoBotScreen(context: context, title: title)
}

/// Страница, которая вместо веб-страницы @CryptoBot показывается внутри родного окна
/// мини-аппа Telegram (шапка, «Закрыть/Назад», «⋯» и нижняя панель остаются родными).
/// `presenter` — само окно: через него показываются выбор монеты и ввод суммы.
public func pampGramFakeCryptoBotContentView(context: AccountContext, presenter: ViewController) -> PampGramFakeMiniAppContent {
    return PampGramFakeCryptoBotContentView(context: context, presenter: presenter)
}
