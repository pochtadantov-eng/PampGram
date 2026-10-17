import Foundation
import UIKit
import Display

/// The fake CryptoBot's third tab, "Обмен": "Вы отправляете" / "Вы получаете", the swap button between
/// them, "Продолжить" and "Последние обмены". The rate is the live one from
/// `PampGramFakeCryptoBotMarket`; a swap moves the visual balances and is kept in the list.

struct PampGramFakeCryptoBotSwap: Codable, Equatable {
    var id: Int64
    var from: String
    var to: String
    var fromAmount: Double
    var toAmount: Double
    var date: Int32
}

func pampGramFakeCryptoBotParseSwaps(_ raw: String) -> [PampGramFakeCryptoBotSwap] {
    guard !raw.isEmpty, let data = raw.data(using: .utf8), let swaps = try? JSONDecoder().decode([PampGramFakeCryptoBotSwap].self, from: data) else {
        return []
    }
    return swaps
}

func pampGramFakeCryptoBotSerializeSwaps(_ swaps: [PampGramFakeCryptoBotSwap]) -> String {
    guard let data = try? JSONEncoder().encode(Array(swaps.suffix(100))), let text = String(data: data, encoding: .utf8) else {
        return ""
    }
    return text
}

/// How many places a received amount of `code` is cut to.
func pampGramFakeCryptoBotSwapDecimals(_ code: String) -> Int {
    if pampGramFakeCryptoBotIsStableCoin(code) {
        return 6
    }
    let price = PampGramFakeCryptoBotMarket.shared.quote(code).price
    if price < 1.0 {
        return 2
    } else if price < 10.0 {
        return 3
    } else if price < 1000.0 {
        return 5
    }
    return 8
}

private enum PGSwap {
    static let accent = UIColor(rgb: 0x44a3dd)
    static let green = PampGramFakeCryptoBotColors.themed(dark: 0x31a357, light: 0x2a9a4f)
    static let gray = PampGramFakeCryptoBotColors.secondary
    static let value = PampGramFakeCryptoBotColors.themed(dark: 0x8e8e8e, light: 0xa2a2a7)
    static let text = PampGramFakeCryptoBotColors.text
    static let circle = PampGramFakeCryptoBotColors.themed(dark: 0x213440, light: 0xdcebf6)
    static let line = PampGramFakeCryptoBotColors.border
    static let page = PampGramFakeCryptoBotColors.card
}

private func pgSwapLabel(_ size: CGFloat, _ weight: UIFont.Weight, _ color: UIColor, _ alignment: NSTextAlignment = .left) -> UILabel {
    let label = UILabel()
    label.font = PampGramFakeCryptoBotFonts.font(size, weight)
    label.textColor = color
    label.textAlignment = alignment
    label.isUserInteractionEnabled = false
    return label
}

/// "Coin ❯" with its logo: the line that opens the coin choice.
private final class PGSwapCoinControl: UIControl {
    private let icon = UIImageView()
    private let codeLabel = pgSwapLabel(23.0, .bold, PGSwap.text)
    private let chevron = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.icon.contentMode = .scaleAspectFit
        self.icon.isUserInteractionEnabled = false
        self.addSubview(self.icon)
        self.addSubview(self.codeLabel)
        self.chevron.image = UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13.0, weight: .semibold))
        self.chevron.tintColor = PGSwap.text
        self.chevron.contentMode = .center
        self.chevron.isUserInteractionEnabled = false
        self.addSubview(self.chevron)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func set(code: String) {
        self.icon.image = PampGramFakeCryptoBotAssets.image("coin_" + code)
        self.codeLabel.text = code
        self.setNeedsLayout()
    }

    var contentWidth: CGFloat {
        let size = self.codeLabel.sizeThatFits(CGSize(width: 200.0, height: 32.0))
        return 33.0 + ceil(size.width) + 24.0
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let height = self.bounds.height
        self.icon.frame = CGRect(x: 0.0, y: floor((height - 24.0) / 2.0), width: 24.0, height: 24.0)
        let size = self.codeLabel.sizeThatFits(CGSize(width: 200.0, height: 32.0))
        self.codeLabel.frame = CGRect(x: 33.0, y: floor((height - 30.0) / 2.0), width: ceil(size.width), height: 30.0)
        self.chevron.frame = CGRect(x: 33.0 + ceil(size.width) + 2.0, y: floor((height - 20.0) / 2.0), width: 20.0, height: 20.0)
    }

    override var isHighlighted: Bool {
        didSet {
            self.alpha = self.isHighlighted ? 0.6 : 1.0
        }
    }
}

private final class PGSwapRow: UIView {
    private let backIcon = UIImageView()
    private let frontIcon = UIImageView()
    private let titleLabel = pgSwapLabel(15.0, .regular, PGSwap.text)
    private let dateLabel = pgSwapLabel(13.0, .regular, PGSwap.gray)
    private let receivedLabel = pgSwapLabel(15.0, .regular, PGSwap.green, .right)
    private let sentLabel = pgSwapLabel(13.0, .regular, PGSwap.gray, .right)
    private let separator = UIView()

    init(swap: PampGramFakeCryptoBotSwap, showsSeparator: Bool) {
        super.init(frame: .zero)
        self.backIcon.image = PampGramFakeCryptoBotAssets.image("coin_" + swap.from)
        self.frontIcon.image = PampGramFakeCryptoBotAssets.image("coin_" + swap.to)
        self.frontIcon.layer.cornerRadius = 15.0
        self.frontIcon.layer.borderWidth = 1.5
        self.addSubview(self.backIcon)
        self.addSubview(self.frontIcon)
        self.titleLabel.text = swap.from + " на " + swap.to
        self.dateLabel.text = pampGramFakeCryptoBotShortDate(swap.date)
        self.receivedLabel.text = "+" + pampGramFakeCryptoBotTrimmed(swap.toAmount, decimals: 8) + " " + swap.to
        self.sentLabel.text = "-" + pampGramFakeCryptoBotTrimmed(swap.fromAmount, decimals: 8) + " " + swap.from
        for label in [self.titleLabel, self.dateLabel, self.receivedLabel, self.sentLabel] {
            self.addSubview(label)
        }
        self.separator.backgroundColor = PGSwap.line
        self.separator.isHidden = !showsSeparator
        self.addSubview(self.separator)
        self.updateColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateColors() {
        self.frontIcon.layer.borderColor = self.pampGramFakeCGColor(PGSwap.page)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        self.updateColors()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        self.updateColors()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = self.bounds.width
        self.backIcon.frame = CGRect(x: 0.0, y: 13.3, width: 28.0, height: 28.0)
        self.frontIcon.frame = CGRect(x: 10.7, y: 24.3, width: 30.0, height: 30.0)
        self.titleLabel.frame = CGRect(x: 52.3, y: 14.0, width: width * 0.55, height: 20.0)
        self.dateLabel.frame = CGRect(x: 52.3, y: 35.0, width: width * 0.55, height: 18.0)
        self.receivedLabel.frame = CGRect(x: width * 0.4, y: 14.0, width: width * 0.6, height: 20.0)
        self.sentLabel.frame = CGRect(x: width * 0.35, y: 35.0, width: width * 0.65, height: 18.0)
        self.separator.frame = CGRect(x: 52.3, y: self.bounds.height - 1.0, width: max(0.0, width - 52.3), height: 1.0)
    }
}

final class PampGramFakeCryptoBotSwapView: UIScrollView, UITextFieldDelegate, UIGestureRecognizerDelegate {
    var onToast: ((String) -> Void)?
    var onSwap: ((PampGramFakeCryptoBotSwap) -> Void)?
    var presentChoices: ((String, [String], Int?, @escaping (Int) -> Void) -> Void)?
    var balanceProvider: ((String) -> Double)?

    private var fromCode = "GRAM"
    private var toCode = "USDT"
    private var swaps: [PampGramFakeCryptoBotSwap] = []
    private var rows: [PGSwapRow] = []
    private var rotation: CGFloat = 0.0

    private let sendTitle = pgSwapLabel(15.0, .regular, PGSwap.text)
    private let walletIcon = UIImageView()
    private let balanceLabel = pgSwapLabel(15.0, .regular, PGSwap.gray, .right)
    private let maxButton = UIButton(type: .custom)
    private let fromControl = PGSwapCoinControl()
    private let amountInput = UITextField()
    private let leftLine = UIView()
    private let rightLine = UIView()
    private let swapControl = UIControl()
    private let swapIcon = UIImageView()
    private let receiveTitle = pgSwapLabel(15.0, .regular, PGSwap.text)
    private let toControl = PGSwapCoinControl()
    private let receiveLabel = pgSwapLabel(29.0, .bold, PGSwap.value, .right)
    private let continueButton = UIButton(type: .custom)
    private let recentTitle = pgSwapLabel(15.0, .regular, PGSwap.gray)

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .clear
        self.showsVerticalScrollIndicator = false
        self.alwaysBounceVertical = true
        self.keyboardDismissMode = .onDrag
        self.setup()
        self.refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        self.sendTitle.text = "Вы отправляете"
        self.receiveTitle.text = "Вы получаете"
        self.addSubview(self.sendTitle)
        self.addSubview(self.receiveTitle)
        self.walletIcon.image = PampGramFakeCryptoBotAssets.image("s_wallet")?.withRenderingMode(.alwaysTemplate)
        self.walletIcon.tintColor = PGSwap.gray
        self.walletIcon.contentMode = .scaleAspectFit
        self.addSubview(self.walletIcon)
        self.addSubview(self.balanceLabel)
        self.maxButton.setTitle("МАКС", for: .normal)
        self.maxButton.setTitleColor(PGSwap.accent, for: .normal)
        self.maxButton.titleLabel?.font = PampGramFakeCryptoBotFonts.font(15.0, .semibold)
        self.maxButton.contentHorizontalAlignment = .right
        self.maxButton.addTarget(self, action: #selector(self.maxPressed), for: .touchUpInside)
        self.addSubview(self.maxButton)

        self.fromControl.addTarget(self, action: #selector(self.fromPressed), for: .touchUpInside)
        self.toControl.addTarget(self, action: #selector(self.toPressed), for: .touchUpInside)
        self.addSubview(self.fromControl)
        self.addSubview(self.toControl)

        self.amountInput.font = PampGramFakeCryptoBotFonts.font(29.0, .bold)
        self.amountInput.textColor = PGSwap.text
        self.amountInput.tintColor = PGSwap.accent
        self.amountInput.textAlignment = .right
        self.amountInput.keyboardType = .decimalPad
        self.amountInput.attributedPlaceholder = NSAttributedString(string: "0", attributes: [
            .font: PampGramFakeCryptoBotFonts.font(29.0, .bold),
            .foregroundColor: PGSwap.value
        ])
        self.amountInput.adjustsFontSizeToFitWidth = true
        self.amountInput.minimumFontSize = 14.0
        self.amountInput.delegate = self
        self.amountInput.addTarget(self, action: #selector(self.amountChanged), for: .editingChanged)
        self.addSubview(self.amountInput)
        self.addSubview(self.receiveLabel)
        self.receiveLabel.adjustsFontSizeToFitWidth = true
        self.receiveLabel.minimumScaleFactor = 0.5

        self.leftLine.backgroundColor = PGSwap.line
        self.rightLine.backgroundColor = PGSwap.line
        self.addSubview(self.leftLine)
        self.addSubview(self.rightLine)
        self.swapControl.backgroundColor = PGSwap.circle
        self.swapControl.layer.cornerRadius = 16.0
        self.swapControl.addTarget(self, action: #selector(self.swapPressed), for: .touchUpInside)
        self.swapIcon.image = PampGramFakeCryptoBotAssets.image("i_swap")?.withRenderingMode(.alwaysTemplate)
        self.swapIcon.tintColor = PGSwap.accent
        self.swapIcon.contentMode = .scaleAspectFit
        self.swapIcon.isUserInteractionEnabled = false
        self.swapControl.addSubview(self.swapIcon)
        self.addSubview(self.swapControl)

        self.continueButton.setTitle("Продолжить", for: .normal)
        self.continueButton.setTitleColor(.white, for: .normal)
        self.continueButton.titleLabel?.font = PampGramFakeCryptoBotFonts.font(15.0, .semibold)
        self.continueButton.backgroundColor = PGSwap.accent
        self.continueButton.layer.cornerRadius = 16.0
        self.continueButton.addTarget(self, action: #selector(self.continuePressed), for: .touchUpInside)
        self.addSubview(self.continueButton)

        self.recentTitle.text = "Последние обмены"
        self.addSubview(self.recentTitle)

        let tap = UITapGestureRecognizer(target: self, action: #selector(self.backgroundTapped))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        self.addGestureRecognizer(tap)
    }

    // MARK: Data from the owner

    func setSwaps(_ swaps: [PampGramFakeCryptoBotSwap]) {
        self.swaps = swaps
        self.rebuildRows()
    }

    func balancesChanged() {
        self.refresh()
    }

    func marketUpdated() {
        self.refresh()
    }

    // MARK: State

    private var amount: Double? {
        let text = (self.amountInput.text ?? "").replacingOccurrences(of: ",", with: ".")
        if text.isEmpty {
            return nil
        }
        return Double(text)
    }

    private func rate() -> Double {
        let from = PampGramFakeCryptoBotMarket.shared.quote(self.fromCode).price
        let to = PampGramFakeCryptoBotMarket.shared.quote(self.toCode).price
        return to > 0.0 ? from / to : 0.0
    }

    private func received(for amount: Double) -> Double {
        let factor = pow(10.0, Double(pampGramFakeCryptoBotSwapDecimals(self.toCode)))
        return floor(amount * self.rate() * factor) / factor
    }

    private func refresh() {
        self.fromControl.set(code: self.fromCode)
        self.toControl.set(code: self.toCode)
        let balance = self.balanceProvider?(self.fromCode) ?? 0.0
        self.balanceLabel.text = pampGramFakeCryptoBotFormat(balance, fractionDigits: 9).replacingOccurrences(of: " ", with: "")
        if let amount = self.amount, amount > 0.0 {
            self.receiveLabel.text = pampGramFakeCryptoBotTrimmed(self.received(for: amount), decimals: pampGramFakeCryptoBotSwapDecimals(self.toCode))
            self.receiveLabel.textColor = PGSwap.text
        } else {
            self.receiveLabel.text = "0"
            self.receiveLabel.textColor = PGSwap.value
        }
        self.setNeedsLayout()
    }

    private func rebuildRows() {
        for row in self.rows {
            row.removeFromSuperview()
        }
        self.rows.removeAll()
        let recent = Array(self.swaps.sorted { $0.id > $1.id }.prefix(10))
        for (index, swap) in recent.enumerated() {
            let row = PGSwapRow(swap: swap, showsSeparator: index + 1 < recent.count)
            self.addSubview(row)
            self.rows.append(row)
        }
        self.recentTitle.isHidden = recent.isEmpty
        self.setNeedsLayout()
    }

    // MARK: Actions

    @objc private func backgroundTapped() {
        self.endEditing(true)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view: UIView? = touch.view
        while let current = view {
            if current is UIControl {
                return false
            }
            view = current.superview
        }
        return true
    }

    @objc private func amountChanged() {
        self.refresh()
    }

    @objc private func maxPressed() {
        let balance = self.balanceProvider?(self.fromCode) ?? 0.0
        if balance <= 0.0 {
            self.onToast?("Недостаточно средств")
            return
        }
        self.amountInput.text = pampGramFakeCryptoBotTrimmed(floor(balance * 1e8) / 1e8, decimals: 8)
        self.refresh()
    }

    @objc private func fromPressed() {
        self.endEditing(true)
        self.choose(title: "Вы отправляете", current: self.fromCode, excluded: self.toCode) { [weak self] code in
            self?.fromCode = code
            self?.refresh()
        }
    }

    @objc private func toPressed() {
        self.endEditing(true)
        self.choose(title: "Вы получаете", current: self.toCode, excluded: self.fromCode) { [weak self] code in
            self?.toCode = code
            self?.refresh()
        }
    }

    private func choose(title: String, current: String, excluded: String, apply: @escaping (String) -> Void) {
        let codes = pampGramFakeCryptoBotCurrencies.map { $0.code }.filter { $0 != excluded }
        let options = codes.map { code -> String in
            let name = pampGramFakeCryptoBotCurrencies.first(where: { $0.code == code })?.name ?? ""
            return code + " · " + name
        }
        self.presentChoices?(title, options, codes.firstIndex(of: current), { index in
            if index >= 0 && index < codes.count {
                apply(codes[index])
            }
        })
    }

    @objc private func swapPressed() {
        self.endEditing(true)
        let previous = self.fromCode
        self.fromCode = self.toCode
        self.toCode = previous
        self.rotation += CGFloat.pi
        UIView.animate(withDuration: 0.25, animations: {
            self.swapControl.transform = CGAffineTransform(rotationAngle: self.rotation)
        })
        self.refresh()
    }

    @objc private func continuePressed() {
        self.endEditing(true)
        guard let amount = self.amount, amount > 0.0 else {
            self.onToast?("Введите сумму")
            return
        }
        let balance = self.balanceProvider?(self.fromCode) ?? 0.0
        if amount > balance + 1e-9 {
            self.onToast?("Недостаточно средств")
            return
        }
        let received = self.received(for: amount)
        if received <= 0.0 {
            self.onToast?("Слишком маленькая сумма")
            return
        }
        let swap = PampGramFakeCryptoBotSwap(
            id: Int64(Date().timeIntervalSince1970 * 1000.0),
            from: self.fromCode,
            to: self.toCode,
            fromAmount: amount,
            toAmount: received,
            date: Int32(clamping: Int(Date().timeIntervalSince1970))
        )
        self.amountInput.text = ""
        self.refresh()
        self.onSwap?(swap)
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

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = self.bounds.width
        self.sendTitle.frame = CGRect(x: 16.0, y: 27.3, width: 140.0, height: 18.0)
        self.receiveTitle.frame = CGRect(x: 16.0, y: 175.7, width: 200.0, height: 18.0)

        let maxSize = self.maxButton.sizeThatFits(CGSize(width: 100.0, height: 24.0))
        let maxWidth = ceil(maxSize.width)
        self.maxButton.frame = CGRect(x: width - 16.0 - maxWidth, y: 24.3, width: maxWidth, height: 24.0)
        let balanceSize = self.balanceLabel.sizeThatFits(CGSize(width: 200.0, height: 20.0))
        let balanceWidth = ceil(balanceSize.width)
        self.balanceLabel.frame = CGRect(x: width - 16.0 - maxWidth - 8.0 - balanceWidth, y: 26.3, width: balanceWidth, height: 20.0)
        self.walletIcon.frame = CGRect(x: self.balanceLabel.frame.minX - 5.0 - 14.7, y: 28.9, width: 14.7, height: 14.7)

        let fromWidth = self.fromControl.contentWidth
        self.fromControl.frame = CGRect(x: 16.0, y: 56.3, width: fromWidth, height: 40.0)
        self.amountInput.frame = CGRect(x: 16.0 + fromWidth + 8.0, y: 56.3, width: max(60.0, width - 32.0 - fromWidth - 8.0), height: 40.0)
        let toWidth = self.toControl.contentWidth
        self.toControl.frame = CGRect(x: 16.0, y: 204.0, width: toWidth, height: 40.0)
        self.receiveLabel.frame = CGRect(x: 16.0 + toWidth + 8.0, y: 204.0, width: max(60.0, width - 32.0 - toWidth - 8.0), height: 40.0)

        let centerX = width / 2.0
        self.swapControl.transform = .identity
        self.swapControl.frame = CGRect(x: centerX - 16.0, y: 132.3, width: 32.0, height: 32.0)
        self.swapControl.transform = CGAffineTransform(rotationAngle: self.rotation)
        self.swapIcon.frame = CGRect(x: 8.0, y: 8.0, width: 16.0, height: 16.0)
        self.leftLine.frame = CGRect(x: 16.0, y: 147.8, width: max(0.0, centerX - 16.0 - 16.0 - 8.0), height: 1.0)
        self.rightLine.frame = CGRect(x: centerX + 16.0 + 8.0, y: 147.8, width: max(0.0, width - 16.0 - (centerX + 24.0)), height: 1.0)

        self.continueButton.frame = CGRect(x: 16.0, y: 296.3, width: width - 32.0, height: 48.0)

        var bottom: CGFloat = 360.0
        if !self.rows.isEmpty {
            self.recentTitle.frame = CGRect(x: 16.0, y: 386.3, width: width - 32.0, height: 18.0)
            var rowY: CGFloat = 417.0
            for row in self.rows {
                row.frame = CGRect(x: 16.0, y: rowY, width: width - 32.0, height: 66.0)
                rowY += 66.0
            }
            bottom = rowY
        }
        self.contentSize = CGSize(width: width, height: bottom + 130.0)
    }
}
