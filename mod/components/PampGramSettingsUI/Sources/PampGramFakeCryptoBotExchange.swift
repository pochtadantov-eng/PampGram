import Foundation
import UIKit
import Display

/// The fake CryptoBot's second tab, "Биржа": the pair header with the 24 h change and volume, the
/// order form (buy/sell, limit/market, price, amount, percent slider, total), the order book with
/// the live price in the middle, and the tabs with the orders. Drawn from screenshots of the real
/// page; the rates and the book come from `PampGramFakeCryptoBotMarket`. Orders are local: placing
/// one moves the visual balances, a limit order that the market has not reached waits as open and
/// fills when the price gets there.

// MARK: - Orders

struct PampGramFakeCryptoBotOrder: Codable, Equatable {
    var id: Int64
    /// 0 — buy, 1 — sell.
    var side: Int
    /// 0 — limit, 1 — market.
    var kind: Int
    /// The base coin; the quote is always USDT.
    var code: String
    var price: Double
    var amount: Double
    /// 0 — open, 1 — filled, 2 — cancelled.
    var status: Int
    var date: Int32
}

func pampGramFakeCryptoBotParseOrders(_ raw: String) -> [PampGramFakeCryptoBotOrder] {
    guard !raw.isEmpty, let data = raw.data(using: .utf8), let orders = try? JSONDecoder().decode([PampGramFakeCryptoBotOrder].self, from: data) else {
        return []
    }
    return orders
}

func pampGramFakeCryptoBotSerializeOrders(_ orders: [PampGramFakeCryptoBotOrder]) -> String {
    guard let data = try? JSONEncoder().encode(Array(orders.suffix(300))), let text = String(data: data, encoding: .utf8) else {
        return ""
    }
    return text
}

/// The coins the exchange has pairs for (all against USDT); the first one is what the real page opened with.
let pampGramFakeCryptoBotExchangePairs: [String] = ["USDC", "GRAM", "BTC", "ETH", "SOL", "TRX", "BNB", "DOGE", "LTC", "XAUT"]

private enum PGTrade {
    static let green = PampGramFakeCryptoBotColors.themed(dark: 0x31a357, light: 0x2a9a4f)
    static let red = PampGramFakeCryptoBotColors.themed(dark: 0xff5252, light: 0xf04545)
    static let inactive = PampGramFakeCryptoBotColors.themed(dark: 0x323232, light: 0xe6e6eb)
    static let askBar = PampGramFakeCryptoBotColors.themed(dark: 0x2f1e1e, light: 0xfcebeb)
    static let bidBar = PampGramFakeCryptoBotColors.themed(dark: 0x1a261e, light: 0xe6f4eb)
    static let chip = PampGramFakeCryptoBotColors.themed(dark: 0x272727, light: 0xefeff3)
    static let accent = UIColor(rgb: 0x44a3dd)
    static let accentDim = PampGramFakeCryptoBotColors.themed(dark: 0x2b678d, light: 0x8cc4ea)
    static let gray = PampGramFakeCryptoBotColors.secondary
    static let grayDim = PampGramFakeCryptoBotColors.themed(dark: 0x6b6b6b, light: 0xb4b4b9)
    static let text = PampGramFakeCryptoBotColors.text
    static let border = PampGramFakeCryptoBotColors.border
    static let page = PampGramFakeCryptoBotColors.card
}

private func pgLabel(_ size: CGFloat, _ weight: UIFont.Weight, _ color: UIColor, _ alignment: NSTextAlignment = .left) -> UILabel {
    let label = UILabel()
    label.font = PampGramFakeCryptoBotFonts.font(size, weight)
    label.textColor = color
    label.textAlignment = alignment
    label.isUserInteractionEnabled = false
    return label
}

private func pgDecimals(ofTick tick: Double) -> Int {
    var decimals = 0
    var value = tick
    while decimals < 8 && abs(value - value.rounded()) > 1e-9 {
        value *= 10.0
        decimals += 1
    }
    return decimals
}

private func pgBaseTick(_ price: Double) -> Double {
    if price < 0.1 {
        return 0.00001
    } else if price < 2.0 {
        return 0.0001
    } else if price < 20.0 {
        return 0.001
    } else if price < 200.0 {
        return 0.01
    } else if price < 2000.0 {
        return 0.1
    }
    return 1.0
}

// MARK: - Small controls

/// One of the two halves of "Купить | Продать": a pill whose inner corners are almost square.
private final class PGSegmentButton: UIControl {
    private let titleLabel = pgLabel(15.0, .semibold, PGTrade.gray, .center)
    private let isLeft: Bool

    init(title: String, isLeft: Bool) {
        self.isLeft = isLeft
        super.init(frame: .zero)
        self.titleLabel.text = title
        self.addSubview(self.titleLabel)
        self.layer.masksToBounds = true
        self.layer.cornerRadius = 15.0
        self.layer.maskedCorners = isLeft ? [.layerMinXMinYCorner, .layerMinXMaxYCorner] : [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        self.setSelected(false, color: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSelected(_ selected: Bool, color: UIColor?) {
        self.backgroundColor = selected ? color : PGTrade.inactive
        self.titleLabel.textColor = selected ? UIColor.white : PGTrade.gray
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.titleLabel.frame = self.bounds
        self.layer.cornerRadius = self.bounds.height / 2.0
    }
}

/// A field with a title that sits on the top border once the field has a value or the focus.
private final class PGTradeField: UIView, UITextFieldDelegate {
    let input = UITextField()
    var onChange: (() -> Void)?
    var onFocusChanged: (() -> Void)?
    var rightInset: CGFloat = 0.0
    private let borderView = UIView()
    private let floatingLabel = pgLabel(15.0, .regular, PGTrade.gray)
    private let title: String

    init(title: String) {
        self.title = title
        super.init(frame: .zero)
        self.borderView.layer.cornerRadius = 14.0
        self.borderView.layer.borderWidth = 1.0
        self.borderView.isUserInteractionEnabled = false
        self.addSubview(self.borderView)
        self.input.font = PampGramFakeCryptoBotFonts.font(14.6, .regular)
        self.input.textColor = PGTrade.text
        self.input.tintColor = PGTrade.accent
        self.input.keyboardType = .decimalPad
        self.input.autocorrectionType = .no
        self.input.delegate = self
        self.input.addTarget(self, action: #selector(self.textChanged), for: .editingChanged)
        self.addSubview(self.input)
        self.floatingLabel.text = title
        self.addSubview(self.floatingLabel)
        self.updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var text: String {
        get {
            return self.input.text ?? ""
        }
        set {
            self.input.text = newValue
            self.setNeedsLayout()
        }
    }

    var isReadOnlyText: Bool = false {
        didSet {
            self.input.isUserInteractionEnabled = !self.isReadOnlyText
        }
    }

    private var isFloating: Bool {
        return self.input.isFirstResponder || !self.text.isEmpty
    }

    func updateAppearance() {
        let focused = self.input.isFirstResponder
        self.borderView.layer.borderColor = self.pampGramFakeCGColor(focused ? PGTrade.accent : PGTrade.border)
        self.borderView.layer.borderWidth = focused ? 1.5 : 1.0
        self.input.keyboardAppearance = self.traitCollection.userInterfaceStyle == .light ? .light : .dark
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        self.updateAppearance()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        self.updateAppearance()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = self.bounds.width
        let height = self.bounds.height
        self.borderView.frame = self.bounds
        self.input.frame = CGRect(x: 16.7, y: 0.0, width: max(0.0, width - 33.4 - self.rightInset), height: height)
        if self.isFloating {
            self.floatingLabel.font = PampGramFakeCryptoBotFonts.font(12.0, .regular)
            self.floatingLabel.backgroundColor = PGTrade.page
            self.floatingLabel.textAlignment = .center
            let size = self.floatingLabel.sizeThatFits(CGSize(width: 300.0, height: 20.0))
            self.floatingLabel.frame = CGRect(x: 13.3, y: -8.0, width: ceil(size.width) + 7.0, height: 16.0)
        } else {
            self.floatingLabel.font = PampGramFakeCryptoBotFonts.font(15.0, .regular)
            self.floatingLabel.backgroundColor = .clear
            self.floatingLabel.textAlignment = .left
            self.floatingLabel.frame = CGRect(x: 16.7, y: 0.0, width: max(0.0, width - 33.4 - self.rightInset), height: height)
        }
    }

    @objc private func textChanged() {
        self.setNeedsLayout()
        self.onChange?()
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        self.updateAppearance()
        self.setNeedsLayout()
        self.onFocusChanged?()
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        self.updateAppearance()
        self.setNeedsLayout()
        self.onFocusChanged?()
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let current = (textField.text ?? "") as NSString
        let updated = current.replacingCharacters(in: range, with: string)
        let allowed = Set("0123456789.,")
        if updated.contains(where: { !allowed.contains($0) }) {
            return false
        }
        let separators = updated.filter { $0 == "." || $0 == "," }.count
        return separators <= 1 && updated.count <= 24
    }
}

/// The 0 / 25 / 50 / 75 / 100 % slider under the amount.
private final class PGPercentSlider: UIControl {
    var value: CGFloat = 0.0 {
        didSet {
            self.setNeedsLayout()
        }
    }
    var onChange: ((CGFloat) -> Void)?
    private let track = UIView()
    private let nodes: [UIView] = [UIView(), UIView(), UIView(), UIView(), UIView()]
    private let knob = UIView()
    private let labels: [UILabel] = ["0%", "25%", "50%", "75%", "100%"].map { (title: String) -> UILabel in
        let label = pgLabel(12.0, .regular, PGTrade.gray, .center)
        label.text = title
        return label
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.track.isUserInteractionEnabled = false
        self.track.backgroundColor = PGTrade.border
        self.track.layer.cornerRadius = 1.4
        self.addSubview(self.track)
        for node in self.nodes {
            node.isUserInteractionEnabled = false
            node.backgroundColor = PGTrade.page
            node.layer.cornerRadius = 6.0
            self.addSubview(node)
        }
        self.knob.isUserInteractionEnabled = false
        self.knob.backgroundColor = PGTrade.page
        self.knob.layer.cornerRadius = 8.0
        self.addSubview(self.knob)
        for label in self.labels {
            self.addSubview(label)
        }
        self.updateColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateColors() {
        for node in self.nodes {
            node.layer.borderWidth = 1.6
            node.layer.borderColor = self.pampGramFakeCGColor(PGTrade.border)
        }
        self.knob.layer.borderWidth = 1.6
        self.knob.layer.borderColor = self.pampGramFakeCGColor(PGTrade.gray)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        self.updateColors()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        self.updateColors()
    }

    private var trackStart: CGFloat {
        return 8.0
    }

    private var trackLength: CGFloat {
        return max(1.0, self.bounds.width - 16.0)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let centerY: CGFloat = 9.0
        self.track.frame = CGRect(x: self.trackStart, y: centerY - 1.4, width: self.trackLength, height: 2.8)
        for (index, node) in self.nodes.enumerated() {
            let x = self.trackStart + self.trackLength * CGFloat(index) / 4.0
            node.frame = CGRect(x: x - 6.0, y: centerY - 6.0, width: 12.0, height: 12.0)
        }
        let knobX = self.trackStart + self.trackLength * max(0.0, min(1.0, self.value))
        self.knob.frame = CGRect(x: knobX - 8.0, y: centerY - 8.0, width: 16.0, height: 16.0)
        for (index, label) in self.labels.enumerated() {
            let size = label.sizeThatFits(CGSize(width: 80.0, height: 16.0))
            let centerX = self.trackStart + self.trackLength * CGFloat(index) / 4.0
            var x = centerX - size.width / 2.0
            if index == 0 {
                x = 0.0
            } else if index == 4 {
                x = self.bounds.width - size.width
            }
            label.frame = CGRect(x: x, y: 17.7, width: ceil(size.width), height: 16.0)
        }
    }

    private func update(for touch: UITouch) {
        let x = touch.location(in: self).x
        var fraction = (x - self.trackStart) / self.trackLength
        fraction = max(0.0, min(1.0, fraction))
        // A little magnet at the marks.
        for mark in [0.0, 0.25, 0.5, 0.75, 1.0] {
            if abs(fraction - CGFloat(mark)) < 0.03 {
                fraction = CGFloat(mark)
            }
        }
        self.value = fraction
        self.onChange?(fraction)
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        self.update(for: touch)
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        self.update(for: touch)
        return true
    }
}

/// One line of the order book: a tinted bar behind the price and the amount.
private final class PGBookRow: UIView {
    private let bar = UIView()
    private let priceLabel = pgLabel(14.6, .regular, PGTrade.text)
    private let amountLabel = pgLabel(14.6, .regular, PGTrade.text, .right)
    private let isAsk: Bool
    private var ratio: CGFloat = 0.0

    init(isAsk: Bool) {
        self.isAsk = isAsk
        super.init(frame: .zero)
        self.bar.backgroundColor = isAsk ? PGTrade.askBar : PGTrade.bidBar
        self.bar.isUserInteractionEnabled = false
        self.addSubview(self.bar)
        self.priceLabel.textColor = isAsk ? PGTrade.red : PGTrade.green
        self.amountLabel.textColor = isAsk ? PGTrade.red : PGTrade.green
        self.addSubview(self.priceLabel)
        self.addSubview(self.amountLabel)
        self.isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func set(price: String, amount: String, ratio: CGFloat) {
        self.priceLabel.text = price
        self.amountLabel.text = amount
        self.ratio = max(0.0, min(1.0, ratio))
        self.setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = self.bounds.width
        let barWidth = ceil(width * self.ratio)
        self.bar.frame = CGRect(x: width - barWidth, y: 0.0, width: barWidth, height: self.bounds.height)
        self.priceLabel.frame = CGRect(x: 0.0, y: 0.0, width: width * 0.6, height: self.bounds.height)
        self.amountLabel.frame = CGRect(x: width * 0.3, y: 0.0, width: width * 0.7, height: self.bounds.height)
    }
}

/// A line of "Открытые ордера" / "История ордеров" / "Сделки".
private final class PGOrderRow: UIView {
    private let titleLabel = pgLabel(15.0, .regular, PGTrade.text)
    private let dateLabel = pgLabel(13.0, .regular, PGTrade.gray, .right)
    private let detailLabel = pgLabel(13.0, .regular, PGTrade.gray)
    private let statusButton = UIButton(type: .custom)
    private let separator = UIView()
    var onCancel: (() -> Void)?

    init(order: PampGramFakeCryptoBotOrder, priceDecimals: Int, showsCancel: Bool) {
        super.init(frame: .zero)
        let isBuy = order.side == 0
        let title = NSMutableAttributedString(string: isBuy ? "Покупка" : "Продажа", attributes: [
            .font: PampGramFakeCryptoBotFonts.font(15.0, .medium),
            .foregroundColor: isBuy ? PGTrade.green : PGTrade.red
        ])
        title.append(NSAttributedString(string: "  " + order.code + "/USDT", attributes: [
            .font: PampGramFakeCryptoBotFonts.font(15.0, .regular),
            .foregroundColor: PGTrade.text
        ]))
        self.titleLabel.attributedText = title
        self.addSubview(self.titleLabel)
        self.dateLabel.text = pampGramFakeCryptoBotShortDate(order.date)
        self.addSubview(self.dateLabel)
        let priceText = order.kind == 1 ? "По рынку" : pampGramFakeCryptoBotTrimmed(order.price, decimals: priceDecimals)
        self.detailLabel.text = priceText + " · " + pampGramFakeCryptoBotTrimmed(order.amount, decimals: 8) + " " + order.code
        self.addSubview(self.detailLabel)
        self.statusButton.titleLabel?.font = PampGramFakeCryptoBotFonts.font(13.0, .medium)
        if showsCancel {
            self.statusButton.setTitle("Отменить", for: .normal)
            self.statusButton.setTitleColor(PGTrade.accent, for: .normal)
            self.statusButton.addTarget(self, action: #selector(self.cancelPressed), for: .touchUpInside)
        } else {
            self.statusButton.setTitle(order.status == 1 ? "Исполнен" : "Отменён", for: .normal)
            self.statusButton.setTitleColor(order.status == 1 ? PGTrade.green : PGTrade.gray, for: .normal)
            self.statusButton.isUserInteractionEnabled = false
        }
        self.statusButton.contentHorizontalAlignment = .right
        self.addSubview(self.statusButton)
        self.separator.backgroundColor = PampGramFakeCryptoBotColors.separator
        self.addSubview(self.separator)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func cancelPressed() {
        self.onCancel?()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = self.bounds.width
        self.titleLabel.frame = CGRect(x: 0.0, y: 8.0, width: width * 0.62, height: 20.0)
        self.dateLabel.frame = CGRect(x: width * 0.55, y: 9.0, width: width * 0.45, height: 18.0)
        self.detailLabel.frame = CGRect(x: 0.0, y: 32.0, width: width * 0.68, height: 18.0)
        self.statusButton.frame = CGRect(x: width - 100.0, y: 28.0, width: 100.0, height: 26.0)
        self.separator.frame = CGRect(x: 0.0, y: self.bounds.height - 1.0, width: width, height: 1.0)
    }
}

// MARK: - The page

final class PampGramFakeCryptoBotExchangeView: UIScrollView, UIGestureRecognizerDelegate {
    var onToast: ((String) -> Void)?
    var onPlaceOrder: ((PampGramFakeCryptoBotOrder) -> Void)?
    var onCancelOrder: ((Int64) -> Void)?
    /// Title, options, the selected one; the owner shows them as a sheet and calls back with the pick.
    var presentChoices: ((String, [String], Int?, @escaping (Int) -> Void) -> Void)?
    var balanceProvider: ((String) -> Double)?

    private var pairIndex = 0
    private var isBuy = true
    private var isMarket = false
    private var bookMode = 0
    private var tick: Double = 0.0001
    private var userEditedPrice = false
    private var book: PampGramFakeCryptoBotBook?
    private var lastPrice: Double = 0.0
    private var previousPrice: Double = 0.0
    private var bookTimer: Foundation.Timer?
    private var orders: [PampGramFakeCryptoBotOrder] = []
    private var tabIndex = 0
    private var chipIndex = 0
    private var orderRows: [PGOrderRow] = []
    private var isActive = false
    private var isMenuOpen = false
    private var isUpdatingFields = false

    private let baseIcon = UIImageView()
    private let quoteIcon = UIImageView()
    private let pairLabel = pgLabel(15.0, .semibold, PGTrade.text)
    private let pairTriangle = UIImageView()
    private let pairControl = UIControl()
    private let candlesControl = UIControl()
    private let candlesIcon = UIImageView()
    private let headerSeparator = UIView()
    private let statsSeparator = UIView()
    private let changeTitle = pgLabel(13.0, .regular, PGTrade.gray)
    private let changeValue = pgLabel(14.0, .regular, PGTrade.green)
    private let volumeTitle = pgLabel(13.0, .regular, PGTrade.gray, .right)
    private let volumeValue = pgLabel(14.0, .regular, PGTrade.text, .right)

    private let buyButton = PGSegmentButton(title: "Купить", isLeft: true)
    private let sellButton = PGSegmentButton(title: "Продать", isLeft: false)
    private let typeBox = UIControl()
    private let typeLabel = pgLabel(15.0, .regular, PGTrade.text)
    private let typeChevron = UIImageView()
    private let priceField = PGTradeField(title: "Цена (USDT)")
    private let minusControl = UIControl()
    private let plusControl = UIControl()
    private let amountField = PGTradeField(title: "Сумма")
    private let slider = PGPercentSlider()
    private let totalField = PGTradeField(title: "Всего")
    private let availableLabel = pgLabel(13.0, .regular, PGTrade.gray)
    private let maxLabel = pgLabel(13.0, .regular, PGTrade.gray)
    private let actionButton = UIButton(type: .custom)

    private let modeControls: [UIControl] = [UIControl(), UIControl(), UIControl()]
    private let modeIcons: [UIImageView] = [UIImageView(), UIImageView(), UIImageView()]
    private let tickLabel = pgLabel(14.0, .regular, PGTrade.text, .right)
    private let tickTriangle = UIImageView()
    private let tickControl = UIControl()
    private let priceHeaderOne = pgLabel(12.0, .regular, PGTrade.gray)
    private let priceHeaderTwo = pgLabel(12.0, .regular, PGTrade.gray)
    private let amountHeaderOne = pgLabel(12.0, .regular, PGTrade.gray, .right)
    private let amountHeaderTwo = pgLabel(12.0, .regular, PGTrade.gray, .right)
    private let askRows: [PGBookRow] = (0 ..< 12).map { _ in PGBookRow(isAsk: true) }
    private let bidRows: [PGBookRow] = (0 ..< 12).map { _ in PGBookRow(isAsk: false) }
    private let midLabel = pgLabel(19.2, .bold, PGTrade.green)
    private let midUSDLabel = pgLabel(12.0, .regular, PGTrade.gray)

    private let baseline = UIView()
    private let tabsScroll = UIScrollView()
    private let tabUnderline = UIView()
    private var tabLabels: [UILabel] = []
    private var tabControls: [UIControl] = []
    private var chipControls: [UIControl] = []
    private var chipLabels: [UILabel] = []
    private let emptyImage = UIImageView()
    private let emptyLabel = pgLabel(13.0, .regular, PGTrade.gray, .center)

    private let typeMenu = UIView()
    private let limitOption = UIControl()
    private let limitOptionLabel = pgLabel(15.0, .regular, PGTrade.text)
    private let limitCheck = UIImageView()
    private let marketOption = UIControl()
    private let marketOptionLabel = pgLabel(15.0, .regular, PGTrade.text)
    private let menuDivider = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .clear
        self.showsVerticalScrollIndicator = false
        self.alwaysBounceVertical = true
        self.keyboardDismissMode = .onDrag
        self.setup()
        self.applyPair(resetPrice: true)
        NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardChanged(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.bookTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    /// The keyboard would cover the lower fields: the page makes room for it and brings the field that has the focus into view.
    @objc private func keyboardChanged(_ notification: Notification) {
        guard let window = self.window, let frame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else {
            return
        }
        let pageBottom = self.convert(CGPoint(x: 0.0, y: self.bounds.height), to: window).y
        let overlap = max(0.0, pageBottom - frame.minY)
        self.contentInset.bottom = overlap
        self.verticalScrollIndicatorInsets.bottom = overlap
        for field in [self.priceField, self.amountField, self.totalField] where field.input.isFirstResponder {
            let target = field.frame.insetBy(dx: 0.0, dy: -24.0)
            self.scrollRectToVisible(target, animated: true)
        }
    }

    // MARK: Setup

    private func setup() {
        self.addSubview(self.baseIcon)
        self.quoteIcon.layer.cornerRadius = 11.0
        self.quoteIcon.layer.borderWidth = 1.5
        self.addSubview(self.quoteIcon)
        self.quoteIcon.image = PampGramFakeCryptoBotAssets.image("coin_USDT")
        self.addSubview(self.pairLabel)
        self.pairTriangle.image = UIImage(systemName: "arrowtriangle.down.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 7.0, weight: .regular))
        self.pairTriangle.tintColor = PGTrade.gray
        self.pairTriangle.contentMode = .center
        self.addSubview(self.pairTriangle)
        self.pairControl.addTarget(self, action: #selector(self.pairPressed), for: .touchUpInside)
        self.addSubview(self.pairControl)
        self.candlesIcon.image = PampGramFakeCryptoBotAssets.image("i_candles")?.withRenderingMode(.alwaysTemplate)
        self.candlesIcon.tintColor = PGTrade.gray
        self.candlesIcon.contentMode = .scaleAspectFit
        self.candlesIcon.isUserInteractionEnabled = false
        self.candlesControl.addSubview(self.candlesIcon)
        self.candlesControl.addTarget(self, action: #selector(self.unavailablePressed), for: .touchUpInside)
        self.addSubview(self.candlesControl)
        self.headerSeparator.backgroundColor = PGTrade.border
        self.statsSeparator.backgroundColor = PGTrade.border
        self.addSubview(self.headerSeparator)
        self.addSubview(self.statsSeparator)
        self.changeTitle.text = "Изменение за 24ч"
        self.volumeTitle.text = "Объём за 24ч (USDT)"
        self.addSubview(self.changeTitle)
        self.addSubview(self.changeValue)
        self.addSubview(self.volumeTitle)
        self.addSubview(self.volumeValue)

        self.buyButton.addTarget(self, action: #selector(self.buyPressed), for: .touchUpInside)
        self.sellButton.addTarget(self, action: #selector(self.sellPressed), for: .touchUpInside)
        self.addSubview(self.buyButton)
        self.addSubview(self.sellButton)

        self.typeBox.layer.cornerRadius = 14.0
        self.typeBox.layer.borderWidth = 1.0
        self.typeBox.addTarget(self, action: #selector(self.typePressed), for: .touchUpInside)
        self.addSubview(self.typeBox)
        self.typeBox.addSubview(self.typeLabel)
        self.typeChevron.image = UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12.0, weight: .medium))
        self.typeChevron.tintColor = PGTrade.gray
        self.typeChevron.contentMode = .center
        self.typeChevron.isUserInteractionEnabled = false
        self.typeBox.addSubview(self.typeChevron)

        self.addSubview(self.priceField)
        self.priceField.rightInset = 82.0
        self.priceField.onChange = { [weak self] in
            self?.userEditedPrice = true
            self?.fieldsChanged(from: .price)
        }
        for (control, symbol) in [(self.minusControl, "minus"), (self.plusControl, "plus")] {
            let icon = UIImageView(image: UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15.0, weight: .semibold)))
            icon.tintColor = PGTrade.text
            icon.contentMode = .center
            icon.isUserInteractionEnabled = false
            icon.frame = CGRect(x: 0.0, y: 0.0, width: 36.0, height: 36.0)
            control.addSubview(icon)
            self.priceField.addSubview(control)
        }
        self.minusControl.addTarget(self, action: #selector(self.minusPressed), for: .touchUpInside)
        self.plusControl.addTarget(self, action: #selector(self.plusPressed), for: .touchUpInside)

        self.addSubview(self.amountField)
        self.amountField.onChange = { [weak self] in
            self?.fieldsChanged(from: .amount)
        }
        self.addSubview(self.slider)
        self.slider.onChange = { [weak self] fraction in
            self?.sliderChanged(fraction)
        }
        self.addSubview(self.totalField)
        self.totalField.onChange = { [weak self] in
            self?.fieldsChanged(from: .total)
        }
        self.addSubview(self.availableLabel)
        self.addSubview(self.maxLabel)
        self.actionButton.titleLabel?.font = PampGramFakeCryptoBotFonts.font(15.0, .semibold)
        self.actionButton.setTitleColor(.white, for: .normal)
        self.actionButton.layer.cornerRadius = 16.0
        self.actionButton.addTarget(self, action: #selector(self.actionPressed), for: .touchUpInside)
        self.addSubview(self.actionButton)

        let modeAssets = ["x_mode_all", "x_mode_bid", "x_mode_ask"]
        for index in 0 ..< 3 {
            self.modeIcons[index].image = PampGramFakeCryptoBotAssets.image(modeAssets[index])
            self.modeIcons[index].contentMode = .scaleAspectFit
            self.modeIcons[index].isUserInteractionEnabled = false
            self.modeControls[index].addSubview(self.modeIcons[index])
            self.modeControls[index].tag = index
            self.modeControls[index].addTarget(self, action: #selector(self.modePressed(_:)), for: .touchUpInside)
            self.addSubview(self.modeControls[index])
        }
        self.tickTriangle.image = UIImage(systemName: "arrowtriangle.down.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 6.0, weight: .regular))
        self.tickTriangle.tintColor = PGTrade.gray
        self.tickTriangle.contentMode = .center
        self.tickTriangle.isUserInteractionEnabled = false
        self.tickControl.addSubview(self.tickLabel)
        self.tickControl.addSubview(self.tickTriangle)
        self.tickControl.addTarget(self, action: #selector(self.tickPressed), for: .touchUpInside)
        self.addSubview(self.tickControl)
        self.priceHeaderOne.text = "Цена"
        self.amountHeaderOne.text = "Сумма"
        for label in [self.priceHeaderOne, self.priceHeaderTwo, self.amountHeaderOne, self.amountHeaderTwo] {
            self.addSubview(label)
        }
        for row in self.askRows + self.bidRows {
            self.addSubview(row)
        }
        self.midLabel.adjustsFontSizeToFitWidth = true
        self.midLabel.minimumScaleFactor = 0.6
        self.addSubview(self.midLabel)
        self.addSubview(self.midUSDLabel)

        self.baseline.backgroundColor = PGTrade.border
        self.addSubview(self.baseline)
        self.tabsScroll.showsHorizontalScrollIndicator = false
        self.tabsScroll.alwaysBounceHorizontal = false
        self.addSubview(self.tabsScroll)
        self.tabUnderline.backgroundColor = PGTrade.accent
        self.tabUnderline.layer.cornerRadius = 1.0
        self.tabsScroll.addSubview(self.tabUnderline)
        for (index, title) in ["Открытые ордера", "История ордеров", "Сделки"].enumerated() {
            let label = pgLabel(15.0, .medium, PGTrade.gray)
            label.text = title
            self.tabLabels.append(label)
            let control = UIControl()
            control.tag = index
            control.addTarget(self, action: #selector(self.tabPressed(_:)), for: .touchUpInside)
            control.addSubview(label)
            self.tabControls.append(control)
            self.tabsScroll.addSubview(control)
        }
        for index in 0 ..< 3 {
            let control = UIControl()
            control.tag = index
            control.layer.masksToBounds = true
            control.addTarget(self, action: #selector(self.chipPressed(_:)), for: .touchUpInside)
            let label = UILabel()
            label.isUserInteractionEnabled = false
            label.textAlignment = .center
            control.addSubview(label)
            self.chipLabels.append(label)
            self.chipControls.append(control)
            self.addSubview(control)
        }
        self.emptyImage.image = PampGramFakeCryptoBotAssets.image("x_empty")
        self.emptyImage.contentMode = .scaleAspectFit
        self.addSubview(self.emptyImage)
        self.addSubview(self.emptyLabel)

        self.typeMenu.isHidden = true
        self.typeMenu.backgroundColor = PGTrade.page
        self.typeMenu.layer.cornerRadius = 14.0
        self.typeMenu.layer.borderWidth = 1.0
        self.typeMenu.layer.masksToBounds = true
        self.limitOptionLabel.text = "Лимитный ордер"
        self.marketOptionLabel.text = "Маркет ордер"
        self.limitCheck.image = UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15.0, weight: .semibold))
        self.limitCheck.tintColor = PGTrade.accent
        self.limitCheck.contentMode = .center
        self.limitOption.addSubview(self.limitOptionLabel)
        self.limitOption.addSubview(self.limitCheck)
        self.limitOption.addTarget(self, action: #selector(self.limitPressed), for: .touchUpInside)
        self.marketOption.addSubview(self.marketOptionLabel)
        self.marketOption.addTarget(self, action: #selector(self.marketPressed), for: .touchUpInside)
        self.menuDivider.backgroundColor = PGTrade.border
        self.typeMenu.addSubview(self.limitOption)
        self.typeMenu.addSubview(self.marketOption)
        self.typeMenu.addSubview(self.menuDivider)
        self.addSubview(self.typeMenu)

        let tap = UITapGestureRecognizer(target: self, action: #selector(self.backgroundTapped))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        self.addGestureRecognizer(tap)
        self.updateColors()
    }

    private func updateColors() {
        self.quoteIcon.layer.borderColor = self.pampGramFakeCGColor(PGTrade.page)
        self.typeBox.layer.borderColor = self.pampGramFakeCGColor(PGTrade.border)
        self.typeMenu.layer.borderColor = self.pampGramFakeCGColor(PGTrade.border)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        self.updateColors()
        self.renderTabs()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        self.updateColors()
    }

    // MARK: Data from the owner

    func setOrders(_ orders: [PampGramFakeCryptoBotOrder]) {
        self.orders = orders
        self.renderTabs()
        self.updateAvailability()
    }

    /// Called when the page is shown (`true`) or left (`false`): the book polls only while it is on screen.
    func setActive(_ active: Bool) {
        if self.isActive == active {
            return
        }
        self.isActive = active
        self.bookTimer?.invalidate()
        self.bookTimer = nil
        if active {
            self.marketUpdated()
            self.fetchBook()
            let timer = Foundation.Timer(timeInterval: 3.0, repeats: true) { [weak self] _ in
                self?.fetchBook()
            }
            RunLoop.main.add(timer, forMode: .common)
            self.bookTimer = timer
        }
    }

    func balancesChanged() {
        self.updateAvailability()
    }

    /// New rates arrived: the ticker, the middle price and the order price follow.
    func marketUpdated() {
        let code = self.code
        let quote = PampGramFakeCryptoBotMarket.shared.quote(code)
        self.previousPrice = self.lastPrice
        self.lastPrice = quote.price
        self.renderTicker()
        if !self.userEditedPrice && !self.priceField.input.isFirstResponder {
            self.setFieldText(self.priceField, self.priceString(self.lastPrice))
        }
        self.renderBook()
        self.recompute(from: .price)
    }

    // MARK: Pair

    private var code: String {
        return pampGramFakeCryptoBotExchangePairs[self.pairIndex]
    }

    private var priceDecimals: Int {
        return pgDecimals(ofTick: self.tick)
    }

    private func priceString(_ price: Double) -> String {
        return pampGramFakeCryptoBotTrimmed(price, decimals: max(self.priceDecimals, 2))
    }

    private func applyPair(resetPrice: Bool) {
        let code = self.code
        let quote = PampGramFakeCryptoBotMarket.shared.quote(code)
        self.lastPrice = quote.price
        self.previousPrice = quote.price
        self.tick = pgBaseTick(quote.price)
        self.baseIcon.image = PampGramFakeCryptoBotAssets.image("coin_" + code)
        self.pairLabel.text = code + " / USDT"
        self.priceHeaderTwo.text = "(USDT)"
        self.amountHeaderTwo.text = "(" + code + ")"
        self.book = nil
        if resetPrice {
            self.userEditedPrice = false
            self.setFieldText(self.priceField, self.priceString(quote.price))
            self.setFieldText(self.amountField, "")
            self.setFieldText(self.totalField, "")
            self.slider.value = 0.0
        }
        self.renderTicker()
        self.renderForm()
        self.renderBook()
        self.renderTabs()
        self.setNeedsLayout()
    }

    private func renderTicker() {
        let quote = PampGramFakeCryptoBotMarket.shared.quote(self.code)
        let change = quote.change
        let percent = quote.changePercent
        let sign = percent >= 0.0 ? "+" : ""
        let text = pampGramFakeCryptoBotTrimmed(abs(change) < 1e-12 ? 0.0 : change, decimals: max(self.priceDecimals, 2)) + " " + sign + pampGramFakeCryptoBotGrouped(percent, decimals: 2).replacingOccurrences(of: " ", with: "") + "%"
        self.changeValue.text = text
        self.changeValue.textColor = percent >= 0.0 ? PGTrade.green : PGTrade.red
        self.volumeValue.text = pampGramFakeCryptoBotGrouped(quote.volume, decimals: 2)
    }

    // MARK: Order book

    private func fetchBook() {
        let code = self.code
        PampGramFakeCryptoBotMarket.shared.fetchBook(code: code) { [weak self] book in
            guard let self = self, self.code == code else {
                return
            }
            self.book = book ?? PampGramFakeCryptoBotMarket.shared.syntheticBook(code: code, price: self.lastPrice)
            self.renderBook()
        }
    }

    private func renderBook() {
        let decimals = self.priceDecimals
        let tick = self.tick
        var asks: [(Double, Double)] = []
        var bids: [(Double, Double)] = []
        if let book = self.book {
            var askMap: [Int64: Double] = [:]
            for level in book.asks {
                let key = Int64((level.price / tick - 1e-9).rounded(.up))
                askMap[key, default: 0.0] += level.amount
            }
            asks = askMap.keys.sorted().map { (Double($0) * tick, askMap[$0] ?? 0.0) }
            var bidMap: [Int64: Double] = [:]
            for level in book.bids {
                let key = Int64((level.price / tick + 1e-9).rounded(.down))
                bidMap[key, default: 0.0] += level.amount
            }
            bids = bidMap.keys.sorted(by: >).map { (Double($0) * tick, bidMap[$0] ?? 0.0) }
        }
        let askCount = self.bookMode == 1 ? 0 : (self.bookMode == 2 ? 12 : 6)
        let bidCount = self.bookMode == 2 ? 0 : (self.bookMode == 1 ? 12 : 6)
        let shownAsks = Array(asks.prefix(askCount))
        let shownBids = Array(bids.prefix(bidCount))
        let maxAsk = shownAsks.map { $0.1 }.max() ?? 1.0
        let maxBid = shownBids.map { $0.1 }.max() ?? 1.0
        for (index, row) in self.askRows.enumerated() {
            row.isHidden = index >= askCount
            if index < askCount {
                // The best ask sits next to the middle price, so the list runs from far to near.
                let source = askCount - 1 - index
                if source < shownAsks.count {
                    row.set(price: pampGramFakeCryptoBotTrimmed(shownAsks[source].0, decimals: decimals), amount: pampGramFakeCryptoBotCompact(shownAsks[source].1), ratio: CGFloat(shownAsks[source].1 / maxAsk))
                } else {
                    row.set(price: "", amount: "", ratio: 0.0)
                }
            }
        }
        for (index, row) in self.bidRows.enumerated() {
            row.isHidden = index >= bidCount
            if index < bidCount {
                if index < shownBids.count {
                    row.set(price: pampGramFakeCryptoBotTrimmed(shownBids[index].0, decimals: decimals), amount: pampGramFakeCryptoBotCompact(shownBids[index].1), ratio: CGFloat(shownBids[index].1 / maxBid))
                } else {
                    row.set(price: "", amount: "", ratio: 0.0)
                }
            }
        }
        self.midLabel.text = pampGramFakeCryptoBotTrimmed(self.lastPrice, decimals: max(decimals, 2))
        self.midLabel.textColor = self.lastPrice >= self.previousPrice ? PGTrade.green : PGTrade.red
        let usdPrice = self.lastPrice * PampGramFakeCryptoBotMarket.shared.quote("USDT").price
        self.midUSDLabel.text = "$" + pampGramFakeCryptoBotTrimmed(usdPrice, decimals: max(decimals, 2))
        self.tickLabel.text = pampGramFakeCryptoBotTrimmed(self.tick, decimals: decimals)
        for (index, control) in self.modeControls.enumerated() {
            control.alpha = index == self.bookMode ? 1.0 : 0.55
        }
        self.setNeedsLayout()
    }

    // MARK: Form

    private enum Source {
        case price
        case amount
        case total
    }

    private func parse(_ field: PGTradeField) -> Double? {
        let text = field.text.replacingOccurrences(of: ",", with: ".")
        if text.isEmpty {
            return nil
        }
        return Double(text)
    }

    private func setFieldText(_ field: PGTradeField, _ text: String) {
        self.isUpdatingFields = true
        field.text = text
        self.isUpdatingFields = false
    }

    /// What the form can spend: dollars when buying, the coin when selling.
    private var available: Double {
        let provider = self.balanceProvider
        if self.isBuy {
            return provider?("USDT") ?? 0.0
        }
        return provider?(self.code) ?? 0.0
    }

    private var effectivePrice: Double {
        if self.isMarket {
            return self.lastPrice
        }
        return self.parse(self.priceField) ?? self.lastPrice
    }

    private var maxAmount: Double {
        let price = self.effectivePrice
        if self.isBuy {
            return price > 0.0 ? self.available / price : 0.0
        }
        return self.available
    }

    private func fieldsChanged(from source: Source) {
        if self.isUpdatingFields {
            return
        }
        self.recompute(from: source)
    }

    private func recompute(from source: Source) {
        let price = self.effectivePrice
        switch source {
        case .price:
            if let amount = self.parse(self.amountField) {
                self.setFieldText(self.totalField, pampGramFakeCryptoBotTrimmed(price * amount, decimals: 8))
            }
        case .amount:
            if let amount = self.parse(self.amountField) {
                self.setFieldText(self.totalField, pampGramFakeCryptoBotTrimmed(price * amount, decimals: 8))
            } else {
                self.setFieldText(self.totalField, "")
            }
        case .total:
            if let total = self.parse(self.totalField), price > 0.0 {
                self.setFieldText(self.amountField, pampGramFakeCryptoBotTrimmed(total / price, decimals: 8))
            } else {
                self.setFieldText(self.amountField, "")
            }
        }
        let maximum = self.maxAmount
        if let amount = self.parse(self.amountField), maximum > 0.0 {
            self.slider.value = CGFloat(max(0.0, min(1.0, amount / maximum)))
        } else {
            self.slider.value = 0.0
        }
        self.updateAvailability()
    }

    private func sliderChanged(_ fraction: CGFloat) {
        self.endEditing(true)
        let amount = self.maxAmount * Double(fraction)
        if fraction <= 0.0 {
            self.setFieldText(self.amountField, "")
            self.setFieldText(self.totalField, "")
        } else {
            // Floor to eight places so 100 % never asks for more than there is.
            let floored = floor(amount * 1e8) / 1e8
            self.setFieldText(self.amountField, pampGramFakeCryptoBotTrimmed(floored, decimals: 8))
            self.setFieldText(self.totalField, pampGramFakeCryptoBotTrimmed(floored * self.effectivePrice, decimals: 8))
        }
    }

    private func updateAvailability() {
        let code = self.code
        let available = self.available
        let formattedAvailable = pampGramFakeCryptoBotFormat(available, fractionDigits: 8)
        let price = self.effectivePrice
        func line(_ title: String, _ value: String) -> NSAttributedString {
            let text = NSMutableAttributedString(string: title + " ", attributes: [
                .font: PampGramFakeCryptoBotFonts.font(13.0, .regular),
                .foregroundColor: PGTrade.gray
            ])
            text.append(NSAttributedString(string: value, attributes: [
                .font: PampGramFakeCryptoBotFonts.font(13.0, .regular),
                .foregroundColor: PGTrade.text
            ]))
            return text
        }
        if self.isBuy {
            self.availableLabel.attributedText = line("Доступно", formattedAvailable + " USDT")
            let maximum = price > 0.0 ? available / price : 0.0
            self.maxLabel.attributedText = line("Макс. покупка", pampGramFakeCryptoBotFormat(floor(maximum * 1e8) / 1e8, fractionDigits: 8) + " " + code)
        } else {
            self.availableLabel.attributedText = line("Доступно", formattedAvailable + " " + code)
            self.maxLabel.attributedText = line("Макс. продажа", pampGramFakeCryptoBotFormat(floor(available * price * 1e8) / 1e8, fractionDigits: 8) + " USDT")
        }
    }

    private func renderForm() {
        let color = self.isBuy ? PGTrade.green : PGTrade.red
        self.buyButton.setSelected(self.isBuy, color: PGTrade.green)
        self.sellButton.setSelected(!self.isBuy, color: PGTrade.red)
        self.actionButton.backgroundColor = color
        self.actionButton.setTitle((self.isBuy ? "Купить " : "Продать ") + self.code, for: .normal)
        self.typeLabel.text = self.isMarket ? "Маркет ордер" : "Лимитный ордер"
        self.typeLabel.textColor = PGTrade.text
        self.limitOptionLabel.textColor = self.isMarket ? PGTrade.text : PGTrade.accent
        self.limitCheck.isHidden = self.isMarket
        self.marketOptionLabel.textColor = self.isMarket ? PGTrade.accent : PGTrade.text
        self.priceField.isReadOnlyText = self.isMarket
        self.minusControl.isHidden = self.isMarket
        self.plusControl.isHidden = self.isMarket
        self.priceField.rightInset = self.isMarket ? 0.0 : 82.0
        if self.isMarket {
            self.setFieldText(self.priceField, "По рынку")
        } else if self.priceField.text == "По рынку" {
            self.userEditedPrice = false
            self.setFieldText(self.priceField, self.priceString(self.lastPrice))
        }
        self.updateAvailability()
        self.priceField.setNeedsLayout()
    }

    // MARK: Actions

    @objc private func backgroundTapped() {
        self.endEditing(true)
        if self.isMenuOpen {
            self.setMenuOpen(false)
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // A tap on the menu's own options is theirs.
        var view: UIView? = touch.view
        while let current = view {
            if current === self.typeMenu || current is UIControl {
                return false
            }
            view = current.superview
        }
        return true
    }

    @objc private func unavailablePressed() {
        self.onToast?("Функция недоступна")
    }

    @objc private func buyPressed() {
        self.setSide(buy: true)
    }

    @objc private func sellPressed() {
        self.setSide(buy: false)
    }

    private func setSide(buy: Bool) {
        if self.isBuy == buy {
            return
        }
        self.isBuy = buy
        self.slider.value = 0.0
        self.setFieldText(self.amountField, "")
        self.setFieldText(self.totalField, "")
        self.renderForm()
    }

    @objc private func typePressed() {
        self.endEditing(true)
        self.setMenuOpen(!self.isMenuOpen)
    }

    private func setMenuOpen(_ open: Bool) {
        self.isMenuOpen = open
        self.typeMenu.isHidden = !open
        self.typeMenu.alpha = open ? 0.0 : 1.0
        if open {
            UIView.animate(withDuration: 0.15, animations: {
                self.typeMenu.alpha = 1.0
            })
        }
        self.setNeedsLayout()
    }

    @objc private func limitPressed() {
        self.isMarket = false
        self.setMenuOpen(false)
        self.renderForm()
        self.recompute(from: .price)
    }

    @objc private func marketPressed() {
        self.isMarket = true
        self.setMenuOpen(false)
        self.renderForm()
        self.recompute(from: .price)
    }

    @objc private func minusPressed() {
        self.stepPrice(-1.0)
    }

    @objc private func plusPressed() {
        self.stepPrice(1.0)
    }

    private func stepPrice(_ direction: Double) {
        self.endEditing(true)
        let current = self.parse(self.priceField) ?? self.lastPrice
        let updated = max(self.tick, current + direction * self.tick)
        self.userEditedPrice = true
        self.setFieldText(self.priceField, self.priceString(updated))
        self.recompute(from: .price)
    }

    @objc private func pairPressed() {
        self.endEditing(true)
        let options = pampGramFakeCryptoBotExchangePairs.map { $0 + " / USDT" }
        self.presentChoices?("Торговая пара", options, self.pairIndex, { [weak self] index in
            guard let self = self, index >= 0, index < pampGramFakeCryptoBotExchangePairs.count, index != self.pairIndex else {
                return
            }
            self.pairIndex = index
            self.applyPair(resetPrice: true)
            self.fetchBook()
        })
    }

    @objc private func tickPressed() {
        self.endEditing(true)
        let base = pgBaseTick(self.lastPrice)
        let ticks = [base, base * 10.0, base * 100.0]
        let options = ticks.map { pampGramFakeCryptoBotTrimmed($0, decimals: pgDecimals(ofTick: $0)) }
        let selected = ticks.firstIndex(where: { abs($0 - self.tick) < base / 2.0 })
        self.presentChoices?("Шаг цены", options, selected, { [weak self] index in
            guard let self = self, index >= 0, index < ticks.count else {
                return
            }
            self.tick = ticks[index]
            self.renderBook()
        })
    }

    @objc private func modePressed(_ sender: UIControl) {
        self.bookMode = sender.tag
        self.renderBook()
    }

    @objc private func tabPressed(_ sender: UIControl) {
        self.tabIndex = sender.tag
        self.chipIndex = 0
        self.renderTabs()
    }

    @objc private func chipPressed(_ sender: UIControl) {
        self.chipIndex = sender.tag
        self.renderTabs()
    }

    @objc private func actionPressed() {
        self.endEditing(true)
        let price = self.effectivePrice
        guard let amount = self.parse(self.amountField), amount > 0.0, price > 0.0 else {
            self.onToast?("Введите сумму")
            return
        }
        let total = amount * price
        if self.isBuy {
            if total > self.available + 1e-9 {
                self.onToast?("Недостаточно средств")
                return
            }
        } else if amount > self.available + 1e-9 {
            self.onToast?("Недостаточно средств")
            return
        }
        let order = PampGramFakeCryptoBotOrder(
            id: Int64(Date().timeIntervalSince1970 * 1000.0),
            side: self.isBuy ? 0 : 1,
            kind: self.isMarket ? 1 : 0,
            code: self.code,
            price: price,
            amount: amount,
            status: 0,
            date: Int32(clamping: Int(Date().timeIntervalSince1970))
        )
        self.setFieldText(self.amountField, "")
        self.setFieldText(self.totalField, "")
        self.slider.value = 0.0
        self.onPlaceOrder?(order)
    }

    // MARK: Tabs and orders

    private func visibleOrders() -> [PampGramFakeCryptoBotOrder] {
        var result: [PampGramFakeCryptoBotOrder]
        switch self.tabIndex {
        case 0:
            result = self.orders.filter { $0.status == 0 }
        case 1:
            result = self.orders.filter { $0.status != 0 }
        default:
            result = self.orders.filter { $0.status == 1 }
        }
        result.sort { $0.id > $1.id }
        return result
    }

    private func renderTabs() {
        for (index, label) in self.tabLabels.enumerated() {
            label.textColor = index == self.tabIndex ? PGTrade.accent : PGTrade.gray
        }
        let tabOrders: [PampGramFakeCryptoBotOrder] = {
            switch self.tabIndex {
            case 0:
                return self.orders.filter { $0.status == 0 }
            case 1:
                return self.orders.filter { $0.status != 0 }
            default:
                return self.orders.filter { $0.status == 1 }
            }
        }()
        let counts = [tabOrders.count, tabOrders.filter { $0.side == 0 }.count, tabOrders.filter { $0.side == 1 }.count]
        let titles = ["Все", "Покупки", "Продажи"]
        for index in 0 ..< 3 {
            let selected = index == self.chipIndex
            let text = NSMutableAttributedString(string: titles[index], attributes: [
                .font: PampGramFakeCryptoBotFonts.font(13.0, .semibold),
                .foregroundColor: selected ? PGTrade.accent : PGTrade.gray
            ])
            text.append(NSAttributedString(string: " " + String(counts[index]), attributes: [
                .font: PampGramFakeCryptoBotFonts.font(13.0, .semibold),
                .foregroundColor: selected ? PGTrade.accentDim : PGTrade.grayDim
            ]))
            self.chipLabels[index].attributedText = text
            self.chipControls[index].backgroundColor = selected ? .clear : PGTrade.chip
            self.chipControls[index].layer.borderWidth = selected ? 2.0 : 0.0
            self.chipControls[index].layer.borderColor = self.pampGramFakeCGColor(PGTrade.accent)
        }
        for row in self.orderRows {
            row.removeFromSuperview()
        }
        self.orderRows.removeAll()
        var shown = self.visibleOrders()
        if self.chipIndex == 1 {
            shown = shown.filter { $0.side == 0 }
        } else if self.chipIndex == 2 {
            shown = shown.filter { $0.side == 1 }
        }
        for order in shown {
            let row = PGOrderRow(order: order, priceDecimals: max(self.priceDecimals, 2), showsCancel: order.status == 0)
            let id = order.id
            row.onCancel = { [weak self] in
                self?.onCancelOrder?(id)
            }
            self.addSubview(row)
            self.orderRows.append(row)
        }
        self.emptyImage.isHidden = !shown.isEmpty
        self.emptyLabel.isHidden = !shown.isEmpty
        switch self.tabIndex {
        case 0:
            self.emptyLabel.text = "Открытых ордеров пока нет."
        case 1:
            self.emptyLabel.text = "Истории ордеров пока нет."
        default:
            self.emptyLabel.text = "Сделок пока нет."
        }
        self.setNeedsLayout()
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = self.bounds.width
        let leftWidth = floor((width - 32.0 - 16.5) * 0.6054)
        let columnX = 16.0 + leftWidth + 16.5
        let columnWidth = width - 16.0 - columnX

        // Pair header and the 24 h numbers.
        self.baseIcon.frame = CGRect(x: 16.0, y: 8.7, width: 20.0, height: 20.0)
        self.quoteIcon.frame = CGRect(x: 28.3, y: 21.0, width: 22.0, height: 22.0)
        let pairSize = self.pairLabel.sizeThatFits(CGSize(width: 200.0, height: 22.0))
        self.pairLabel.frame = CGRect(x: 56.7, y: 9.7, width: ceil(pairSize.width), height: 22.0)
        self.pairTriangle.frame = CGRect(x: 56.7 + ceil(pairSize.width) + 5.0, y: 16.5, width: 10.0, height: 10.0)
        self.pairControl.frame = CGRect(x: 0.0, y: 0.0, width: width - 60.0, height: 48.0)
        self.candlesControl.frame = CGRect(x: width - 58.0, y: 0.0, width: 58.0, height: 48.0)
        self.candlesIcon.frame = CGRect(x: 58.0 - 17.0 - 18.0, y: 11.0, width: 18.0, height: 18.0)
        self.headerSeparator.frame = CGRect(x: 0.0, y: 48.2, width: width, height: 1.0)
        self.changeTitle.frame = CGRect(x: 16.0, y: 58.3, width: width * 0.5 - 16.0, height: 16.0)
        self.changeValue.frame = CGRect(x: 16.0, y: 77.3, width: width * 0.5 - 16.0, height: 18.0)
        self.volumeTitle.frame = CGRect(x: width * 0.4, y: 58.3, width: width * 0.6 - 16.0, height: 16.0)
        self.volumeValue.frame = CGRect(x: width * 0.4, y: 77.3, width: width * 0.6 - 16.0, height: 18.0)
        self.statsSeparator.frame = CGRect(x: 0.0, y: 105.2, width: width, height: 1.0)

        // The order form.
        let half = (leftWidth - 4.3) / 2.0
        self.buyButton.frame = CGRect(x: 16.0, y: 122.7, width: half, height: 31.3)
        self.sellButton.frame = CGRect(x: 16.0 + half + 4.3, y: 122.7, width: half, height: 31.3)
        self.typeBox.frame = CGRect(x: 16.0, y: 167.0, width: leftWidth, height: 38.7)
        self.typeLabel.frame = CGRect(x: 16.3, y: 0.0, width: leftWidth - 60.0, height: 38.7)
        self.typeChevron.frame = CGRect(x: leftWidth - 16.0 - 24.0, y: 7.0, width: 24.0, height: 24.0)
        self.priceField.frame = CGRect(x: 16.0, y: 227.3, width: leftWidth, height: 46.4)
        self.minusControl.frame = CGRect(x: leftWidth - 82.0 + 0.0, y: 5.0, width: 36.0, height: 36.0)
        self.plusControl.frame = CGRect(x: leftWidth - 46.0, y: 5.0, width: 36.0, height: 36.0)
        self.amountField.frame = CGRect(x: 16.0, y: 294.7, width: leftWidth, height: 47.0)
        self.slider.frame = CGRect(x: 16.0, y: 345.3, width: leftWidth, height: 36.0)
        self.totalField.frame = CGRect(x: 16.0, y: 395.0, width: leftWidth, height: 46.7)
        self.availableLabel.frame = CGRect(x: 16.0, y: 458.3, width: leftWidth, height: 18.0)
        self.maxLabel.frame = CGRect(x: 16.0, y: 484.7, width: leftWidth, height: 18.0)
        self.actionButton.frame = CGRect(x: 16.0, y: 518.7, width: leftWidth, height: 47.7)

        // The book column.
        for index in 0 ..< 3 {
            self.modeControls[index].frame = CGRect(x: columnX - 6.0 + CGFloat(index) * 24.0, y: 126.0, width: 26.0, height: 24.0)
            self.modeIcons[index].frame = CGRect(x: 6.6, y: 5.0, width: 14.3, height: 14.3)
        }
        self.tickControl.frame = CGRect(x: width - 16.0 - 96.0, y: 126.0, width: 96.0, height: 24.0)
        self.tickLabel.frame = CGRect(x: 0.0, y: 2.0, width: 80.0, height: 20.0)
        self.tickTriangle.frame = CGRect(x: 84.0, y: 7.0, width: 10.0, height: 10.0)
        self.priceHeaderOne.frame = CGRect(x: columnX, y: 167.7, width: columnWidth, height: 16.0)
        self.priceHeaderTwo.frame = CGRect(x: columnX, y: 183.3, width: columnWidth, height: 16.0)
        self.amountHeaderOne.frame = CGRect(x: columnX, y: 167.7, width: columnWidth, height: 16.0)
        self.amountHeaderTwo.frame = CGRect(x: columnX, y: 183.3, width: columnWidth, height: 16.0)
        let askCount = self.bookMode == 1 ? 0 : (self.bookMode == 2 ? 12 : 6)
        let bidCount = self.bookMode == 2 ? 0 : (self.bookMode == 1 ? 12 : 6)
        let firstCenter: CGFloat = 216.3
        for (index, row) in self.askRows.enumerated() where index < askCount {
            row.frame = CGRect(x: columnX, y: firstCenter + 26.0 * CGFloat(index) - 11.0, width: columnWidth, height: 22.0)
        }
        let midCenter = firstCenter + 26.0 * CGFloat(askCount) + 0.4
        self.midLabel.frame = CGRect(x: columnX, y: midCenter - 14.0, width: columnWidth, height: 28.0)
        self.midUSDLabel.frame = CGRect(x: columnX, y: midCenter + 12.6, width: columnWidth, height: 16.0)
        let firstBid = midCenter + 45.3
        for (index, row) in self.bidRows.enumerated() where index < bidCount {
            row.frame = CGRect(x: columnX, y: firstBid + 26.0 * CGFloat(index) - 11.0, width: columnWidth, height: 22.0)
        }

        // The tabs with the orders.
        self.baseline.frame = CGRect(x: 0.0, y: 638.0, width: width, height: 1.0)
        self.tabsScroll.frame = CGRect(x: 0.0, y: 599.7, width: width, height: 39.0)
        var tabX: CGFloat = 16.0
        var selectedFrame = CGRect.zero
        for (index, label) in self.tabLabels.enumerated() {
            let size = label.sizeThatFits(CGSize(width: 300.0, height: 24.0))
            let tabWidth = ceil(size.width) + 24.6
            self.tabControls[index].frame = CGRect(x: tabX, y: 0.0, width: tabWidth, height: 37.0)
            label.frame = CGRect(x: 12.3, y: 3.0, width: ceil(size.width), height: 24.0)
            if index == self.tabIndex {
                selectedFrame = CGRect(x: tabX, y: 37.0, width: tabWidth, height: 2.0)
            }
            tabX += tabWidth
        }
        self.tabsScroll.contentSize = CGSize(width: tabX + 16.0, height: 39.0)
        if self.tabUnderline.frame.isEmpty || self.tabUnderline.frame.height == 0.0 {
            self.tabUnderline.frame = selectedFrame
        } else if self.tabUnderline.frame != selectedFrame {
            UIView.animate(withDuration: 0.22, delay: 0.0, options: [.beginFromCurrentState, .curveEaseInOut], animations: {
                self.tabUnderline.frame = selectedFrame
            })
        }
        var chipX: CGFloat = 16.0
        for index in 0 ..< 3 {
            let size = self.chipLabels[index].attributedText?.size() ?? CGSize(width: 40.0, height: 16.0)
            let chipWidth = ceil(size.width) + 25.0
            self.chipControls[index].frame = CGRect(x: chipX, y: 651.0, width: chipWidth, height: 31.7)
            self.chipControls[index].layer.cornerRadius = 15.85
            self.chipLabels[index].frame = self.chipControls[index].bounds
            chipX += chipWidth + 8.3
        }
        let contentBottom: CGFloat
        if self.orderRows.isEmpty {
            let imageSize = CGSize(width: 63.0, height: 75.0)
            self.emptyImage.frame = CGRect(x: floor((width - imageSize.width) / 2.0), y: 739.0, width: imageSize.width, height: imageSize.height)
            self.emptyLabel.frame = CGRect(x: 16.0, y: 834.0, width: width - 32.0, height: 18.0)
            contentBottom = 870.0
        } else {
            var rowY: CGFloat = 696.0
            for row in self.orderRows {
                row.frame = CGRect(x: 16.0, y: rowY, width: width - 32.0, height: 62.0)
                rowY += 62.0
            }
            contentBottom = rowY
        }
        self.contentSize = CGSize(width: width, height: contentBottom + 130.0)

        // The order type menu covers the first field, as on the real page.
        self.typeMenu.frame = CGRect(x: 16.0, y: 167.0, width: leftWidth, height: 77.7)
        self.limitOption.frame = CGRect(x: 0.0, y: 0.0, width: leftWidth, height: 38.8)
        self.limitOptionLabel.frame = CGRect(x: 16.3, y: 0.0, width: leftWidth - 60.0, height: 38.8)
        self.limitCheck.frame = CGRect(x: leftWidth - 16.0 - 24.0, y: 7.0, width: 24.0, height: 24.0)
        self.marketOption.frame = CGRect(x: 0.0, y: 38.8, width: leftWidth, height: 38.9)
        self.marketOptionLabel.frame = CGRect(x: 16.3, y: 0.0, width: leftWidth - 60.0, height: 38.9)
        self.menuDivider.frame = CGRect(x: 0.0, y: 38.3, width: leftWidth, height: 1.0)
        self.bringSubviewToFront(self.typeMenu)
    }
}
