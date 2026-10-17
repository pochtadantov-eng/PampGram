import Foundation
import UIKit
import Display

/// The withdrawal flow of the fake CryptoBot, from the recording of the real one: the form (coin,
/// network, address, amount, optional comment), "Подтверждение вывода", the four-digit code sheet
/// and "Вывод средств" with the transaction details. Nothing is sent anywhere; when the code is
/// entered the owner of this view writes the balance change and the history entry.

private let pampGramWithdrawGray = UIColor(rgb: 0x959595)
private let pampGramWithdrawBlue = UIColor(rgb: 0x3b9de3)
private let pampGramWithdrawCard = UIColor(rgb: 0x171717)
private let pampGramWithdrawBorder = UIColor(rgb: 0x3a3a3a)
private let pampGramWithdrawRed = UIColor(rgb: 0xff453a)

private func pampGramWithdrawLabel(_ size: CGFloat, _ weight: UIFont.Weight, _ color: UIColor, _ alignment: NSTextAlignment = .left) -> UILabel {
    let label = UILabel()
    label.font = PampGramFakeCryptoBotFonts.font(size, weight)
    label.textColor = color
    label.textAlignment = alignment
    return label
}

/// "≈ $0.1507": four decimals under a dollar, two from a dollar up, trailing zeros dropped.
private func pampGramWithdrawUSD(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = value >= 1.0 ? 2 : 4
    formatter.usesGroupingSeparator = false
    return formatter.string(from: NSNumber(value: value)) ?? "0"
}

private func pampGramWithdrawAmount(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 9
    formatter.usesGroupingSeparator = false
    return formatter.string(from: NSNumber(value: value)) ?? "0"
}

/// Network fee, in the coin being sent.
private func pampGramWithdrawFee(code: String, network: PampGramFakeCryptoBotNetwork) -> Double {
    switch network.name {
    case "TON":
        return code == "GRAM" ? 0.1 : 0.1
    case "Tron":
        return code == "TRX" ? 1.0 : 2.0
    case "Solana":
        return code == "SOL" ? 0.001 : 0.2
    case "Ethereum":
        return code == "ETH" ? 0.002 : 3.0
    case "BNB Smart Chain":
        return code == "BNB" ? 0.0005 : 0.3
    case "Bitcoin":
        return 0.0001
    case "Litecoin":
        return 0.001
    case "Dogecoin":
        return 4.0
    default:
        return 0.1
    }
}

private func pampGramWithdrawWeekText(count: Int, usd: Double) -> String {
    let remainder = count % 10
    let tens = count % 100
    var word = "выводов"
    if tens < 11 || tens > 14 {
        if remainder == 1 {
            word = "вывод"
        } else if remainder >= 2 && remainder <= 4 {
            word = "вывода"
        }
    }
    return "На этой неделе \(count) \(word) на сумму $" + pampGramWithdrawUSD(usd)
}

// MARK: - Pieces

/// The grey "$" disc that goes before a dollar value.
private final class PampGramWithdrawDollarView: UIView {
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = UIColor(rgb: 0x8e8e93)
        self.label.text = "$"
        self.label.font = PampGramFakeCryptoBotFonts.font(10.0, .bold)
        self.label.textColor = UIColor(rgb: 0x2b2b2b)
        self.label.textAlignment = .center
        self.addSubview(self.label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.layer.cornerRadius = self.bounds.width / 2.0
        self.label.frame = self.bounds
    }
}

/// A bordered input with a label that sits on its top border once the field has focus or text, and
/// lies inside it as a placeholder otherwise.
private final class PampGramWithdrawField: UIView, UITextViewDelegate {
    let textView = UITextView()
    private let borderView = UIView()
    private let floatingLabel = UILabel()
    var onChange: (() -> Void)?
    var onFocusChanged: (() -> Void)?
    var hasError = false {
        didSet {
            self.updateAppearance()
        }
    }
    private let title: String

    var text: String {
        get {
            return self.textView.text ?? ""
        }
        set {
            self.textView.text = newValue
            self.updateAppearance()
            self.setNeedsLayout()
        }
    }

    var isFloating: Bool {
        return self.textView.isFirstResponder || !self.text.isEmpty
    }

    init(title: String, keyboard: UIKeyboardType) {
        self.title = title
        super.init(frame: .zero)
        // The border is a view of its own so that the label can sit on it and cut it, like in the real page.
        self.borderView.layer.cornerRadius = 14.0
        self.borderView.layer.borderWidth = 1.0
        self.borderView.layer.borderColor = pampGramWithdrawBorder.cgColor
        self.borderView.isUserInteractionEnabled = false
        self.addSubview(self.borderView)

        self.textView.backgroundColor = .clear
        self.textView.font = PampGramFakeCryptoBotFonts.font(15.0, .regular)
        self.textView.textColor = .white
        self.textView.tintColor = pampGramWithdrawBlue
        self.textView.isScrollEnabled = false
        self.textView.textContainerInset = UIEdgeInsets(top: 13.0, left: 0.0, bottom: 13.0, right: 0.0)
        self.textView.textContainer.lineFragmentPadding = 0.0
        self.textView.keyboardType = keyboard
        self.textView.keyboardAppearance = .dark
        self.textView.autocorrectionType = .no
        self.textView.autocapitalizationType = .none
        self.textView.delegate = self
        self.addSubview(self.textView)

        self.floatingLabel.text = title
        self.floatingLabel.textAlignment = .left
        self.floatingLabel.isUserInteractionEnabled = false
        self.addSubview(self.floatingLabel)
        self.updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setTitle(_ title: String) {
        self.floatingLabel.text = title
        self.setNeedsLayout()
    }

    func height(forWidth width: CGFloat) -> CGFloat {
        let size = self.textView.sizeThatFits(CGSize(width: max(1.0, width - 32.0 - self.rightInset), height: CGFloat.greatestFiniteMagnitude))
        return max(47.0, ceil(size.height))
    }

    /// Room kept free on the right for icons.
    var rightInset: CGFloat = 0.0

    func updateAppearance() {
        var color = pampGramWithdrawBorder
        var width: CGFloat = 1.0
        if self.hasError {
            color = pampGramWithdrawRed
            width = 1.5
        } else if self.textView.isFirstResponder {
            color = pampGramWithdrawBlue
            width = 1.5
        }
        self.borderView.layer.borderColor = color.cgColor
        self.borderView.layer.borderWidth = width
        self.floatingLabel.textColor = self.hasError ? pampGramWithdrawRed : pampGramWithdrawGray
        self.setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = self.bounds.width
        self.borderView.frame = self.bounds
        self.textView.frame = CGRect(x: 16.0, y: 0.0, width: max(0.0, width - 32.0 - self.rightInset), height: self.bounds.height)
        if self.isFloating {
            self.floatingLabel.font = PampGramFakeCryptoBotFonts.font(13.0, .regular)
            self.floatingLabel.backgroundColor = pampGramWithdrawCard
            let size = self.floatingLabel.sizeThatFits(CGSize(width: 300.0, height: 20.0))
            self.floatingLabel.frame = CGRect(x: 12.0, y: -9.0, width: ceil(size.width) + 8.0, height: 18.0)
            self.floatingLabel.textAlignment = .center
        } else {
            self.floatingLabel.font = PampGramFakeCryptoBotFonts.font(15.0, .regular)
            self.floatingLabel.backgroundColor = .clear
            self.floatingLabel.textAlignment = .left
            self.floatingLabel.frame = CGRect(x: 16.0, y: 0.0, width: max(0.0, width - 32.0 - self.rightInset), height: self.bounds.height)
        }
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        self.updateAppearance()
        self.onFocusChanged?()
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        self.updateAppearance()
        self.onFocusChanged?()
    }

    func textViewDidChange(_ textView: UITextView) {
        self.hasError = false
        self.setNeedsLayout()
        self.onChange?()
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            textView.resignFirstResponder()
            return false
        }
        return true
    }
}

private struct PampGramWithdrawLine {
    enum Icon {
        case none
        case coin(String)
        case dollar
    }

    let icon: Icon
    let text: String
    let color: UIColor
    let isLink: Bool
}

private struct PampGramWithdrawRow {
    let title: String
    let lines: [PampGramWithdrawLine]
    let showsCopy: Bool
}

/// The two-column tables of the confirmation and the result.
private final class PampGramWithdrawTable: UIView {
    private var rows: [PampGramWithdrawRow] = []
    private var rowViews: [UIView] = []
    private var rowHeights: [CGFloat] = []
    private var leftWidth: CGFloat = 114.0
    var onCopy: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.layer.cornerRadius = 14.0
        self.layer.borderWidth = 1.0
        self.layer.borderColor = UIColor(rgb: 0x2d2d2d).cgColor
        self.layer.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setRows(_ rows: [PampGramWithdrawRow], leftWidth: CGFloat) {
        self.rows = rows
        self.leftWidth = leftWidth
        for view in self.rowViews {
            view.removeFromSuperview()
        }
        self.rowViews.removeAll()
        for row in rows {
            let container = UIView()
            container.tag = 1
            self.addSubview(container)
            self.rowViews.append(container)
            let title = pampGramWithdrawLabel(13.0, .regular, pampGramWithdrawGray)
            title.text = row.title
            container.addSubview(title)
            for line in row.lines {
                if case let .coin(asset) = line.icon {
                    let icon = UIImageView(image: PampGramFakeCryptoBotAssets.image(asset))
                    icon.contentMode = .scaleAspectFit
                    container.addSubview(icon)
                } else if case .dollar = line.icon {
                    container.addSubview(PampGramWithdrawDollarView())
                }
                let label = pampGramWithdrawLabel(13.0, .regular, line.color)
                label.text = line.text
                if line.isLink {
                    label.numberOfLines = 0
                    label.lineBreakMode = .byCharWrapping
                }
                container.addSubview(label)
            }
            if row.showsCopy {
                let copy = UIImageView(image: UIImage(systemName: "square.on.square", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13.0, weight: .regular)))
                copy.tintColor = pampGramWithdrawBlue
                copy.contentMode = .center
                container.addSubview(copy)
                let control = UIControl()
                control.addTarget(self, action: #selector(self.copyPressed), for: .touchUpInside)
                container.addSubview(control)
            }
        }
        self.setNeedsLayout()
    }

    @objc private func copyPressed() {
        self.onCopy?()
    }

    /// Fills the rows for `width` and returns the total height.
    func layoutRows(width: CGFloat) -> CGFloat {
        var y: CGFloat = 0.0
        let valueX = self.leftWidth + 12.0
        let valueWidth = max(0.0, width - valueX - 36.0)
        self.rowHeights.removeAll()
        for (index, row) in self.rows.enumerated() {
            let container = self.rowViews[index]
            let subviews = container.subviews
            var contentHeight: CGFloat = 0.0
            var cursor = 0
            let title = subviews[cursor] as? UILabel
            cursor += 1
            var lineY: CGFloat = 12.0
            for line in row.lines {
                var hasIcon = false
                var iconView: UIView?
                if case .none = line.icon {
                } else {
                    iconView = subviews[cursor]
                    cursor += 1
                    hasIcon = true
                }
                let label = subviews[cursor] as? UILabel
                cursor += 1
                let textX = valueX + (hasIcon ? 20.0 : 0.0)
                let size = label?.sizeThatFits(CGSize(width: max(1.0, valueWidth - (hasIcon ? 20.0 : 0.0)), height: CGFloat.greatestFiniteMagnitude)) ?? CGSize(width: 0.0, height: 18.0)
                let lineHeight = max(18.0, ceil(size.height))
                label?.frame = CGRect(x: textX, y: lineY, width: max(0.0, valueWidth - (hasIcon ? 20.0 : 0.0)), height: lineHeight)
                iconView?.frame = CGRect(x: valueX, y: lineY + 1.5, width: 15.0, height: 15.0)
                lineY += lineHeight
                contentHeight = lineY - 12.0
            }
            title?.frame = CGRect(x: 14.0, y: 12.0, width: max(0.0, self.leftWidth - 18.0), height: 18.0)
            let rowHeight = max(42.7, contentHeight + 24.0)
            if row.showsCopy {
                let copyIcon = subviews[cursor]
                let control = subviews[cursor + 1]
                copyIcon.frame = CGRect(x: width - 36.0, y: 0.0, width: 36.0, height: rowHeight)
                control.frame = CGRect(x: width - 56.0, y: 0.0, width: 56.0, height: rowHeight)
            }
            container.frame = CGRect(x: 0.0, y: y, width: width, height: rowHeight)
            self.rowHeights.append(rowHeight)
            y += rowHeight
        }
        return y
    }

    override func draw(_ rect: CGRect) {
        UIColor(rgb: 0x2d2d2d).setFill()
        let width = self.bounds.width
        var y: CGFloat = 0.0
        UIRectFill(CGRect(x: self.leftWidth, y: 0.0, width: 1.0, height: self.bounds.height))
        for height in self.rowHeights.dropLast() {
            y += height
            UIRectFill(CGRect(x: 0.0, y: y - 0.5, width: width, height: 1.0))
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        _ = self.layoutRows(width: self.bounds.width)
        self.setNeedsDisplay()
    }
}

// MARK: - The code sheet

private final class PampGramWithdrawCodeSheet: UIView {
    var onClose: (() -> Void)?
    var onCompleted: (() -> Void)?
    var onForgot: (() -> Void)?

    private let dim = UIView()
    private let sheet = UIView()
    private let closeControl = UIControl()
    private let closeIcon = UIImageView()
    private var boxes: [UIView] = []
    private var dots: [UILabel] = []
    private let promptLabel = pampGramWithdrawLabel(15.0, .regular, pampGramWithdrawGray, .center)
    private var keys: [UIButton] = []
    private let backspace = UIButton(type: .custom)
    private let forgot = UIButton(type: .custom)
    private let spinner = UIActivityIndicatorView(style: .large)
    private var entered = ""
    private var isBusy = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.dim.backgroundColor = UIColor(white: 0.0, alpha: 0.6)
        self.addSubview(self.dim)

        self.sheet.backgroundColor = pampGramWithdrawCard
        self.sheet.layer.cornerRadius = 30.0
        self.sheet.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        self.addSubview(self.sheet)

        self.closeControl.backgroundColor = UIColor(rgb: 0x2a2a2a)
        self.closeControl.layer.cornerRadius = 16.0
        self.closeControl.addTarget(self, action: #selector(self.closePressed), for: .touchUpInside)
        self.closeIcon.image = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13.0, weight: .semibold))
        self.closeIcon.tintColor = UIColor(rgb: 0x9a9a9a)
        self.closeIcon.contentMode = .center
        self.closeIcon.isUserInteractionEnabled = false
        self.closeControl.addSubview(self.closeIcon)
        self.sheet.addSubview(self.closeControl)

        for _ in 0 ..< 4 {
            let box = UIView()
            box.layer.cornerRadius = 12.0
            box.layer.borderWidth = 1.0
            box.layer.borderColor = UIColor(rgb: 0x333333).cgColor
            self.sheet.addSubview(box)
            self.boxes.append(box)
            let dot = UILabel()
            dot.text = "•"
            dot.font = PampGramFakeCryptoBotFonts.font(30.0, .bold)
            dot.textColor = .white
            dot.textAlignment = .center
            dot.isHidden = true
            box.addSubview(dot)
            self.dots.append(dot)
        }

        self.promptLabel.numberOfLines = 2
        self.promptLabel.text = "Введите код-пароль для\nподтверждения операции"
        self.sheet.addSubview(self.promptLabel)

        for digit in [1, 2, 3, 4, 5, 6, 7, 8, 9, 0] {
            let button = UIButton(type: .custom)
            button.setTitle(String(digit), for: .normal)
            button.titleLabel?.font = PampGramFakeCryptoBotFonts.font(28.0, .semibold)
            button.setTitleColor(.white, for: .normal)
            button.tag = digit
            button.addTarget(self, action: #selector(self.digitPressed(_:)), for: .touchUpInside)
            self.sheet.addSubview(button)
            self.keys.append(button)
        }
        self.backspace.setImage(UIImage(systemName: "delete.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 24.0, weight: .regular)), for: .normal)
        self.backspace.tintColor = .white
        self.backspace.addTarget(self, action: #selector(self.backspacePressed), for: .touchUpInside)
        self.sheet.addSubview(self.backspace)

        self.forgot.setTitle("Я забыл код-пароль", for: .normal)
        self.forgot.titleLabel?.font = PampGramFakeCryptoBotFonts.font(15.0, .medium)
        self.forgot.setTitleColor(pampGramWithdrawBlue, for: .normal)
        self.forgot.addTarget(self, action: #selector(self.forgotPressed), for: .touchUpInside)
        self.sheet.addSubview(self.forgot)

        self.spinner.color = pampGramWithdrawBlue
        self.spinner.hidesWhenStopped = true
        self.sheet.addSubview(self.spinner)
        self.refreshBoxes()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reset() {
        self.entered = ""
        self.isBusy = false
        self.spinner.stopAnimating()
        for key in self.keys {
            key.isHidden = false
        }
        self.backspace.isHidden = false
        self.promptLabel.isHidden = false
        self.refreshBoxes()
    }

    private func refreshBoxes() {
        for (index, box) in self.boxes.enumerated() {
            let isActive = index == self.entered.count && self.entered.count < 4
            box.layer.borderColor = (isActive ? pampGramWithdrawBlue : UIColor(rgb: 0x333333)).cgColor
            box.layer.borderWidth = isActive ? 2.0 : 1.0
            self.dots[index].isHidden = index >= self.entered.count
            box.isHidden = self.isBusy
        }
    }

    @objc private func closePressed() {
        if self.isBusy {
            return
        }
        self.onClose?()
    }

    @objc private func forgotPressed() {
        self.onForgot?()
    }

    @objc private func digitPressed(_ sender: UIButton) {
        if self.isBusy || self.entered.count >= 4 {
            return
        }
        self.entered += String(sender.tag)
        self.refreshBoxes()
        if self.entered.count == 4 {
            // Any code is taken: the screen is only a picture of the real one. A short spin, then done.
            self.isBusy = true
            self.refreshBoxes()
            self.spinner.startAnimating()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                guard let self = self, self.isBusy else {
                    return
                }
                self.onCompleted?()
            }
        }
    }

    @objc private func backspacePressed() {
        if self.isBusy || self.entered.isEmpty {
            return
        }
        self.entered.removeLast()
        self.refreshBoxes()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = self.bounds.width
        let height = self.bounds.height
        self.dim.frame = self.bounds
        let top: CGFloat = 226.0
        self.sheet.frame = CGRect(x: 0.0, y: top, width: width, height: max(0.0, height - top + 40.0))
        self.closeControl.frame = CGRect(x: width - 16.0 - 32.0, y: 16.0, width: 32.0, height: 32.0)
        self.closeIcon.frame = self.closeControl.bounds
        let boxWidth: CGFloat = 47.0
        let pitch: CGFloat = 56.0
        let startX = floor((width - (pitch * 3.0 + boxWidth)) / 2.0)
        for (index, box) in self.boxes.enumerated() {
            box.frame = CGRect(x: startX + CGFloat(index) * pitch, y: 56.7, width: boxWidth, height: 47.0)
            self.dots[index].frame = box.bounds
        }
        self.spinner.center = CGPoint(x: width / 2.0, y: 80.0)
        self.promptLabel.frame = CGRect(x: 16.0, y: 124.0, width: width - 32.0, height: 48.0)
        let columnPitch: CGFloat = 108.0
        let first = width / 2.0 - columnPitch
        var positions: [Int: CGPoint] = [:]
        for digit in 1 ... 9 {
            let column = (digit - 1) % 3
            let row = (digit - 1) / 3
            positions[digit] = CGPoint(x: first + CGFloat(column) * columnPitch, y: 224.3 + CGFloat(row) * 64.0)
        }
        positions[0] = CGPoint(x: width / 2.0, y: 224.3 + 3.0 * 64.0)
        for key in self.keys {
            if let center = positions[key.tag] {
                key.frame = CGRect(x: 0.0, y: 0.0, width: 80.0, height: 56.0)
                key.center = center
            }
        }
        self.backspace.frame = CGRect(x: 0.0, y: 0.0, width: 80.0, height: 56.0)
        self.backspace.center = CGPoint(x: first + 2.0 * columnPitch, y: 224.3 + 3.0 * 64.0)
        self.forgot.frame = CGRect(x: 0.0, y: 0.0, width: 220.0, height: 32.0)
        self.forgot.center = CGPoint(x: width / 2.0, y: 480.0)
    }
}

// MARK: - The flow

final class PampGramFakeCryptoBotWithdrawView: UIView {
    var onChangeCoin: (() -> Void)?
    var onUnavailable: (() -> Void)?
    var onToast: ((String) -> Void)?
    /// Called when the code was entered: coin code, what leaves the balance (amount and fee), and its
    /// dollar value.
    var onCompleted: ((String, Double, Double) -> Void)?
    var onOpenWallet: (() -> Void)?

    private var currency: PampGramFakeCryptoBotCurrency?
    private var network: PampGramFakeCryptoBotNetwork?
    private var balance = 0.0
    private var fee = 0.0
    private var weekCount = 0
    private var weekUSD = 0.0
    private var step = 0
    private var keyboardHeight: CGFloat = 0.0
    private var transactionId = ""
    private var transactionDate = ""
    private var sentAmount = 0.0
    private var commentVisible = false

    // Form.
    private let formView = UIView()
    private let coinIcon = UIImageView()
    private let coinTitle = pampGramWithdrawLabel(15.0, .regular, .white)
    private let changeCoinButton = UIButton(type: .custom)
    private let balanceLabel = pampGramWithdrawLabel(15.0, .regular, .white, .right)
    private let balanceUSD = pampGramWithdrawLabel(13.0, .regular, pampGramWithdrawGray, .right)
    private let networkIcon = UIImageView()
    private let networkTitle = pampGramWithdrawLabel(15.0, .regular, .white)
    private let networkSub = pampGramWithdrawLabel(13.0, .regular, pampGramWithdrawGray)
    private let feeLabel = pampGramWithdrawLabel(15.0, .regular, .white, .right)
    private let feeSub = pampGramWithdrawLabel(13.0, .regular, pampGramWithdrawGray, .right)
    private let addressField = PampGramWithdrawField(title: "Адрес", keyboard: .default)
    private let scanButton = UIButton(type: .custom)
    private let bookButton = UIButton(type: .custom)
    private let addressNote = pampGramWithdrawLabel(13.0, .regular, pampGramWithdrawGray)
    private let amountField = PampGramWithdrawField(title: "Сумма", keyboard: .decimalPad)
    private let maxButton = UIButton(type: .custom)
    private let amountNote = pampGramWithdrawLabel(13.0, .regular, pampGramWithdrawGray)
    private let commentButton = UIButton(type: .custom)
    private let commentField = PampGramWithdrawField(title: "Комментарий", keyboard: .default)
    private let noticeLabel = UILabel()
    private let bottomCover = UIView()
    private let continueButton = UIButton(type: .custom)

    // Confirmation.
    private let confirmView = UIView()
    private let confirmTitle = pampGramWithdrawLabel(15.0, .regular, pampGramWithdrawGray)
    private let confirmTable = PampGramWithdrawTable()

    // Result.
    private let resultScroll = UIScrollView()
    private let resultIcon = UIImageView()
    private let resultBadge = UIView()
    private let resultBadgeIcon = UIImageView()
    private let resultCaption = pampGramWithdrawLabel(15.0, .regular, pampGramWithdrawGray, .center)
    private let resultAmount = pampGramWithdrawLabel(32.0, .bold, .white, .center)
    private let resultUSD = pampGramWithdrawLabel(15.0, .regular, pampGramWithdrawGray, .center)
    private let resultDetailsTitle = pampGramWithdrawLabel(15.0, .regular, pampGramWithdrawGray)
    private let resultTable = PampGramWithdrawTable()
    private let openWalletButton = UIButton(type: .custom)
    private let cancelWithdrawButton = UIButton(type: .custom)

    private let codeSheet = PampGramWithdrawCodeSheet()

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = pampGramWithdrawCard
        self.setupForm()
        self.setupConfirm()
        self.setupResult()

        self.codeSheet.isHidden = true
        self.codeSheet.onClose = { [weak self] in
            self?.codeSheet.isHidden = true
        }
        self.codeSheet.onForgot = { [weak self] in
            self?.onUnavailable?()
        }
        self.codeSheet.onCompleted = { [weak self] in
            self?.finishWithdrawal()
        }
        self.addSubview(self.codeSheet)

        NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardChanged(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardHidden(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
        let tap = UITapGestureRecognizer(target: self, action: #selector(self.backgroundTapped))
        tap.cancelsTouchesInView = false
        self.formView.addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: Setup

    private func primaryButton(_ title: String, _ button: UIButton) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = PampGramFakeCryptoBotFonts.font(17.0, .bold)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor(rgb: 0x3b9ce0)
        button.layer.cornerRadius = 13.0
    }

    private func setupForm() {
        self.addSubview(self.formView)
        self.coinIcon.contentMode = .scaleAspectFit
        self.networkIcon.contentMode = .scaleAspectFit
        for view in [self.coinIcon, self.coinTitle, self.balanceLabel, self.balanceUSD, self.networkIcon, self.networkTitle, self.networkSub, self.feeLabel, self.feeSub] as [UIView] {
            self.formView.addSubview(view)
        }
        self.changeCoinButton.setTitle("Изменить монету ›", for: .normal)
        self.changeCoinButton.titleLabel?.font = PampGramFakeCryptoBotFonts.font(13.0, .regular)
        self.changeCoinButton.setTitleColor(pampGramWithdrawBlue, for: .normal)
        self.changeCoinButton.contentHorizontalAlignment = .left
        self.changeCoinButton.addTarget(self, action: #selector(self.changeCoinPressed), for: .touchUpInside)
        self.formView.addSubview(self.changeCoinButton)
        self.networkSub.text = "Сеть"
        self.feeSub.text = "Комиссия"

        self.addressField.rightInset = 70.0
        self.addressField.onChange = { [weak self] in
            self?.formChanged()
        }
        self.addressField.onFocusChanged = { [weak self] in
            self?.setNeedsLayout()
        }
        self.formView.addSubview(self.addressField)
        for (button, name) in [(self.scanButton, "form_scan"), (self.bookButton, "form_book")] {
            button.setImage(PampGramFakeCryptoBotAssets.image(name)?.withRenderingMode(.alwaysTemplate), for: .normal)
            button.tintColor = pampGramWithdrawBlue
            button.addTarget(self, action: #selector(self.unavailablePressed), for: .touchUpInside)
            self.formView.addSubview(button)
        }
        self.addressNote.numberOfLines = 1
        self.formView.addSubview(self.addressNote)

        self.amountField.rightInset = 56.0
        self.amountField.onChange = { [weak self] in
            self?.formChanged()
        }
        self.amountField.onFocusChanged = { [weak self] in
            self?.setNeedsLayout()
        }
        self.formView.addSubview(self.amountField)
        self.maxButton.setTitle("Макс", for: .normal)
        self.maxButton.titleLabel?.font = PampGramFakeCryptoBotFonts.font(16.0, .medium)
        self.maxButton.setTitleColor(pampGramWithdrawBlue, for: .normal)
        self.maxButton.addTarget(self, action: #selector(self.maxPressed), for: .touchUpInside)
        self.formView.addSubview(self.maxButton)
        self.formView.addSubview(self.amountNote)

        self.commentButton.setTitle("+ Добавить комментарий", for: .normal)
        self.commentButton.titleLabel?.font = PampGramFakeCryptoBotFonts.font(15.0, .regular)
        self.commentButton.setTitleColor(pampGramWithdrawBlue, for: .normal)
        self.commentButton.contentHorizontalAlignment = .left
        self.commentButton.addTarget(self, action: #selector(self.commentPressed), for: .touchUpInside)
        self.formView.addSubview(self.commentButton)
        self.commentField.isHidden = true
        self.commentField.onFocusChanged = { [weak self] in
            self?.setNeedsLayout()
        }
        self.formView.addSubview(self.commentField)

        self.noticeLabel.numberOfLines = 2
        self.noticeLabel.textAlignment = .center
        self.noticeLabel.attributedText = self.noticeText()
        self.formView.addSubview(self.noticeLabel)
        self.bottomCover.backgroundColor = pampGramWithdrawCard
        self.formView.addSubview(self.bottomCover)
        self.primaryButton("Продолжить", self.continueButton)
        self.continueButton.addTarget(self, action: #selector(self.continuePressed), for: .touchUpInside)
        self.formView.addSubview(self.continueButton)
    }

    private func noticeText() -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.minimumLineHeight = 17.7
        paragraph.maximumLineHeight = 17.7
        let attributes: [NSAttributedString.Key: Any] = [
            .font: PampGramFakeCryptoBotFonts.font(13.0, .regular),
            .foregroundColor: pampGramWithdrawGray,
            .paragraphStyle: paragraph
        ]
        let text = NSMutableAttributedString(string: "Перевод на санкционные и высокорисковые сервисы может быть отменён. ", attributes: attributes)
        text.append(NSAttributedString(string: "Подробнее ›", attributes: [
            .font: PampGramFakeCryptoBotFonts.font(13.0, .regular),
            .foregroundColor: pampGramWithdrawBlue,
            .paragraphStyle: paragraph
        ]))
        return text
    }

    private func setupConfirm() {
        self.confirmView.isHidden = true
        self.addSubview(self.confirmView)
        self.confirmTitle.text = "Подтверждение вывода"
        self.confirmView.addSubview(self.confirmTitle)
        self.confirmView.addSubview(self.confirmTable)
    }

    private func setupResult() {
        self.resultScroll.isHidden = true
        self.resultScroll.showsVerticalScrollIndicator = false
        self.resultScroll.alwaysBounceVertical = true
        self.addSubview(self.resultScroll)
        self.resultIcon.contentMode = .scaleAspectFit
        self.resultScroll.addSubview(self.resultIcon)
        self.resultBadge.backgroundColor = UIColor(rgb: 0x6b6b6e)
        self.resultBadge.layer.borderWidth = 3.0
        self.resultBadge.layer.borderColor = pampGramWithdrawCard.cgColor
        self.resultBadge.layer.cornerRadius = 15.0
        self.resultScroll.addSubview(self.resultBadge)
        self.resultBadgeIcon.image = UIImage(systemName: "clock", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14.0, weight: .semibold))
        self.resultBadgeIcon.tintColor = .white
        self.resultBadgeIcon.contentMode = .center
        self.resultBadge.addSubview(self.resultBadgeIcon)
        self.resultCaption.text = "Вывод средств"
        self.resultAmount.adjustsFontSizeToFitWidth = true
        self.resultAmount.minimumScaleFactor = 0.6
        self.resultDetailsTitle.text = "Детали транзакции"
        for view in [self.resultCaption, self.resultAmount, self.resultUSD, self.resultDetailsTitle, self.resultTable] as [UIView] {
            self.resultScroll.addSubview(view)
        }
        self.primaryButton("Открыть кошелёк", self.openWalletButton)
        self.openWalletButton.isHidden = true
        self.openWalletButton.addTarget(self, action: #selector(self.openWalletPressed), for: .touchUpInside)
        self.addSubview(self.openWalletButton)
        self.cancelWithdrawButton.setTitle("Отменить вывод", for: .normal)
        self.cancelWithdrawButton.titleLabel?.font = PampGramFakeCryptoBotFonts.font(17.0, .bold)
        self.cancelWithdrawButton.setTitleColor(UIColor(rgb: 0xff4b52), for: .normal)
        self.cancelWithdrawButton.isHidden = true
        self.cancelWithdrawButton.addTarget(self, action: #selector(self.unavailablePressed), for: .touchUpInside)
        self.addSubview(self.cancelWithdrawButton)
        self.resultTable.onCopy = { [weak self] in
            self?.onToast?("Скопировано")
        }
    }

    // MARK: Data

    func configure(currency: PampGramFakeCryptoBotCurrency, network: PampGramFakeCryptoBotNetwork, balance: Double, weekCount: Int, weekUSD: Double) {
        self.currency = currency
        self.network = network
        self.balance = balance
        self.fee = pampGramWithdrawFee(code: currency.code, network: network)
        self.weekCount = weekCount
        self.weekUSD = weekUSD
        self.step = 0
        self.commentVisible = false
        self.commentField.isHidden = true
        self.commentField.text = ""
        self.addressField.text = ""
        self.amountField.text = ""
        self.addressField.hasError = false
        self.amountField.hasError = false
        self.endEditing(true)

        self.coinIcon.image = PampGramFakeCryptoBotAssets.image(currency.assetName)
        self.coinTitle.text = currency.name
        self.balanceLabel.text = pampGramWithdrawAmount(balance) + " " + currency.code
        self.balanceUSD.text = "$" + pampGramWithdrawUSD(balance * currency.price)
        self.networkIcon.image = PampGramFakeCryptoBotAssets.image(network.assetName)
        self.networkTitle.text = network.short
        self.feeLabel.text = pampGramWithdrawAmount(self.fee) + " " + currency.code
        self.refreshAmountTitle()
        self.formChanged()
        self.showStep(0)
    }

    private func refreshAmountTitle() {
        // The floating label carries the coin: "Сумма GRAM".
        if let currency = self.currency {
            self.amountField.setTitle("Сумма " + currency.code)
        }
    }

    private func formChanged() {
        self.refreshNotes()
        self.setNeedsLayout()
    }

    private func refreshNotes() {
        self.addressNote.textColor = pampGramWithdrawGray
        self.amountNote.textColor = pampGramWithdrawGray
        let hasAddress = self.addressField.text.count >= 20
        if hasAddress && self.weekCount > 0 {
            self.addressNote.text = pampGramWithdrawWeekText(count: self.weekCount, usd: self.weekUSD)
        } else {
            self.addressNote.text = nil
        }
        if let currency = self.currency, let amount = self.parsedAmount(), amount > 0.0 {
            self.amountNote.text = "≈ $" + pampGramWithdrawUSD(amount * currency.price)
        } else {
            self.amountNote.text = nil
        }
        let showsIcons = self.addressField.text.isEmpty
        self.scanButton.isHidden = !showsIcons
        self.bookButton.isHidden = !showsIcons
        self.maxButton.isHidden = !self.amountField.text.isEmpty
    }

    private func parsedAmount() -> Double? {
        let cleaned = self.amountField.text.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")
        guard let value = Double(cleaned), value.isFinite else {
            return nil
        }
        return value
    }

    // MARK: Steps

    private func showStep(_ step: Int) {
        self.step = step
        self.formView.isHidden = step != 0
        self.confirmView.isHidden = step != 1
        self.resultScroll.isHidden = step != 2
        self.openWalletButton.isHidden = step != 2
        self.cancelWithdrawButton.isHidden = step != 2
        self.codeSheet.isHidden = true
        // The one blue button is "Продолжить" on the form and "Подтвердить" (asks for the code) next.
        self.continueButton.removeTarget(nil, action: nil, for: .touchUpInside)
        if step == 1 {
            self.continueButton.addTarget(self, action: #selector(self.confirmPressed), for: .touchUpInside)
            self.continueButton.setTitle("Подтвердить", for: .normal)
        } else {
            self.continueButton.addTarget(self, action: #selector(self.continuePressed), for: .touchUpInside)
            self.continueButton.setTitle("Продолжить", for: .normal)
        }
        self.setNeedsLayout()
    }

    /// The "Назад" of the window: inside the flow it steps back, at the form it asks the owner to leave.
    /// Returns true when it was handled here.
    func goBack() -> Bool {
        if !self.codeSheet.isHidden {
            self.codeSheet.isHidden = true
            return true
        }
        if self.step == 1 {
            self.showStep(0)
            return true
        }
        if self.step == 2 {
            self.onOpenWallet?()
            return true
        }
        return false
    }

    @objc private func changeCoinPressed() {
        self.endEditing(true)
        self.onChangeCoin?()
    }

    @objc private func unavailablePressed() {
        self.onUnavailable?()
    }

    @objc private func backgroundTapped() {
        self.endEditing(true)
    }

    @objc private func commentPressed() {
        self.commentVisible = true
        self.commentField.isHidden = false
        self.commentButton.isHidden = true
        self.commentField.textView.becomeFirstResponder()
        self.setNeedsLayout()
    }

    @objc private func maxPressed() {
        let value = max(0.0, self.balance - self.fee)
        self.amountField.text = value > 0.0 ? pampGramWithdrawAmount(value) : ""
        self.amountField.hasError = false
        self.formChanged()
    }

    @objc private func continuePressed() {
        guard let currency = self.currency, self.network != nil else {
            return
        }
        let address = self.addressField.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if address.count < 20 {
            self.addressField.hasError = true
            self.addressNote.text = address.isEmpty ? "Введите адрес" : "Некорректный адрес"
            self.addressNote.textColor = pampGramWithdrawRed
            self.setNeedsLayout()
            return
        }
        self.addressNote.textColor = pampGramWithdrawGray
        guard let amount = self.parsedAmount(), amount > 0.0 else {
            self.amountField.hasError = true
            self.amountNote.text = "Введите сумму"
            self.amountNote.textColor = pampGramWithdrawRed
            self.setNeedsLayout()
            return
        }
        if amount + self.fee > self.balance + 1e-12 {
            self.amountField.hasError = true
            self.amountNote.text = "Недостаточно средств"
            self.amountNote.textColor = pampGramWithdrawRed
            self.setNeedsLayout()
            return
        }
        self.amountNote.textColor = pampGramWithdrawGray
        self.endEditing(true)
        self.sentAmount = amount
        self.fillConfirmation(address: address, currency: currency, amount: amount)
        self.showStep(1)
    }

    private func fillConfirmation(address: String, currency: PampGramFakeCryptoBotCurrency, amount: Double) {
        guard let network = self.network else {
            return
        }
        let total = amount + self.fee
        var rows: [PampGramWithdrawRow] = [
            PampGramWithdrawRow(title: "Общая сумма", lines: [
                PampGramWithdrawLine(icon: .coin(currency.assetName), text: pampGramWithdrawAmount(total) + " " + currency.code, color: .white, isLink: false),
                PampGramWithdrawLine(icon: .dollar, text: pampGramWithdrawUSD(total * currency.price) + " USD", color: pampGramWithdrawGray, isLink: false)
            ], showsCopy: false),
            PampGramWithdrawRow(title: "Комиссия", lines: [
                PampGramWithdrawLine(icon: .coin(currency.assetName), text: pampGramWithdrawAmount(self.fee) + " " + currency.code, color: .white, isLink: false)
            ], showsCopy: false),
            PampGramWithdrawRow(title: "Отправка", lines: [
                PampGramWithdrawLine(icon: .coin(currency.assetName), text: pampGramWithdrawAmount(amount) + " " + currency.code, color: .white, isLink: false),
                PampGramWithdrawLine(icon: .dollar, text: pampGramWithdrawUSD(amount * currency.price) + " USD", color: pampGramWithdrawGray, isLink: false)
            ], showsCopy: false),
            PampGramWithdrawRow(title: "Сеть", lines: [
                PampGramWithdrawLine(icon: .coin(network.assetName), text: network.name + " (" + network.short + ")", color: .white, isLink: false)
            ], showsCopy: false),
            PampGramWithdrawRow(title: "Адрес", lines: [
                PampGramWithdrawLine(icon: .none, text: address + " \u{2197}\u{FE0E}", color: pampGramWithdrawBlue, isLink: true)
            ], showsCopy: false)
        ]
        if self.weekCount > 0 {
            rows.append(PampGramWithdrawRow(title: "Сводка", lines: [
                PampGramWithdrawLine(icon: .none, text: pampGramWithdrawWeekText(count: self.weekCount, usd: self.weekUSD), color: .white, isLink: true)
            ], showsCopy: false))
        }
        self.confirmTable.setRows(rows, leftWidth: 114.0)
    }

    @objc private func confirmPressed() {
        self.codeSheet.reset()
        self.codeSheet.isHidden = false
        self.setNeedsLayout()
    }

    private func finishWithdrawal() {
        guard let currency = self.currency, let network = self.network else {
            return
        }
        let amount = self.sentAmount
        let total = amount + self.fee
        let usd = total * currency.price
        self.transactionId = "#W" + String(Int.random(in: 10_000_000 ... 99_999_999))
        let parts = Calendar.current.dateComponents([.day, .month, .hour, .minute], from: Date())
        let months = ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"]
        let month = max(1, min(12, parts.month ?? 1))
        self.transactionDate = "\(parts.day ?? 1) \(months[month - 1]) в " + String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)

        self.resultIcon.image = PampGramFakeCryptoBotAssets.image(currency.assetName)
        self.resultAmount.text = "-" + pampGramWithdrawAmount(total) + " " + currency.code
        self.resultUSD.text = "$" + pampGramWithdrawUSD(usd)
        let address = self.addressField.text.trimmingCharacters(in: .whitespacesAndNewlines)
        var shortAddress = address
        if address.count > 14 {
            shortAddress = String(address.prefix(7)) + "..." + String(address.suffix(5))
        }
        let rows: [PampGramWithdrawRow] = [
            PampGramWithdrawRow(title: "ID", lines: [PampGramWithdrawLine(icon: .none, text: self.transactionId, color: .white, isLink: false)], showsCopy: true),
            PampGramWithdrawRow(title: "Статус", lines: [PampGramWithdrawLine(icon: .none, text: "В обработке", color: .white, isLink: false)], showsCopy: false),
            PampGramWithdrawRow(title: "Дата", lines: [PampGramWithdrawLine(icon: .none, text: self.transactionDate, color: .white, isLink: false)], showsCopy: false),
            PampGramWithdrawRow(title: "Адрес", lines: [PampGramWithdrawLine(icon: .none, text: shortAddress + " \u{2197}\u{FE0E}", color: pampGramWithdrawBlue, isLink: false)], showsCopy: true),
            PampGramWithdrawRow(title: "Сеть", lines: [PampGramWithdrawLine(icon: .coin(network.assetName), text: network.short, color: .white, isLink: false)], showsCopy: false),
            PampGramWithdrawRow(title: "Общая сумма", lines: [
                PampGramWithdrawLine(icon: .coin(currency.assetName), text: pampGramWithdrawAmount(total) + " " + currency.code, color: .white, isLink: false),
                PampGramWithdrawLine(icon: .dollar, text: pampGramWithdrawUSD(usd) + " USD", color: pampGramWithdrawGray, isLink: false)
            ], showsCopy: false),
            PampGramWithdrawRow(title: "Комиссия", lines: [
                PampGramWithdrawLine(icon: .coin(currency.assetName), text: pampGramWithdrawAmount(self.fee) + " " + currency.code, color: .white, isLink: false)
            ], showsCopy: false),
            PampGramWithdrawRow(title: "Вы отправили", lines: [
                PampGramWithdrawLine(icon: .coin(currency.assetName), text: pampGramWithdrawAmount(amount) + " " + currency.code, color: .white, isLink: false),
                PampGramWithdrawLine(icon: .dollar, text: pampGramWithdrawUSD(amount * currency.price) + " USD", color: pampGramWithdrawGray, isLink: false)
            ], showsCopy: false)
        ]
        self.resultTable.setRows(rows, leftWidth: 135.0)
        self.showStep(2)
        self.onCompleted?(currency.code, total, usd)
    }

    @objc private func openWalletPressed() {
        self.onOpenWallet?()
    }

    // MARK: Keyboard

    @objc private func keyboardChanged(_ notification: Notification) {
        guard let frameValue = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue, self.window != nil else {
            return
        }
        let converted = self.convert(frameValue.cgRectValue, from: nil)
        let overlap = max(0.0, self.bounds.height - converted.minY)
        self.keyboardHeight = overlap
        self.setNeedsLayout()
        UIView.animate(withDuration: 0.25) {
            self.layoutIfNeeded()
        }
    }

    @objc private func keyboardHidden(_ notification: Notification) {
        self.keyboardHeight = 0.0
        self.setNeedsLayout()
        UIView.animate(withDuration: 0.25) {
            self.layoutIfNeeded()
        }
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = self.bounds.width
        let height = self.bounds.height
        self.formView.frame = self.bounds
        self.confirmView.frame = self.bounds
        self.resultScroll.frame = self.bounds
        self.codeSheet.frame = self.bounds

        let bottomGap: CGFloat = self.keyboardHeight > 0.0 ? 10.0 : 21.0
        let buttonBottom = height - max(bottomGap, self.keyboardHeight + 10.0)
        let buttonFrame = CGRect(x: 16.0, y: buttonBottom - 49.0, width: width - 32.0, height: 49.0)

        // Form.
        self.coinIcon.frame = CGRect(x: 16.0, y: 11.7 + 12.0, width: 40.0, height: 40.0)
        self.coinTitle.frame = CGRect(x: 69.0, y: 11.7 + 13.0, width: width - 69.0 - 170.0, height: 20.0)
        self.changeCoinButton.frame = CGRect(x: 69.0, y: 11.7 + 33.0, width: 160.0, height: 20.0)
        self.balanceLabel.frame = CGRect(x: width - 16.0 - 190.0, y: 11.7 + 13.0, width: 190.0, height: 20.0)
        self.balanceUSD.frame = CGRect(x: width - 16.0 - 190.0, y: 11.7 + 34.0, width: 190.0, height: 18.0)
        self.networkIcon.frame = CGRect(x: 16.0, y: 75.7 + 12.0, width: 40.0, height: 40.0)
        self.networkTitle.frame = CGRect(x: 69.0, y: 75.7 + 13.0, width: width - 69.0 - 170.0, height: 20.0)
        self.networkSub.frame = CGRect(x: 69.0, y: 75.7 + 34.0, width: 120.0, height: 18.0)
        self.feeLabel.frame = CGRect(x: width - 16.0 - 190.0, y: 75.7 + 13.0, width: 190.0, height: 20.0)
        self.feeSub.frame = CGRect(x: width - 16.0 - 190.0, y: 75.7 + 34.0, width: 190.0, height: 18.0)

        let fieldWidth = width - 32.0
        let addressHeight = self.addressField.height(forWidth: fieldWidth)
        self.addressField.frame = CGRect(x: 16.0, y: 157.0, width: fieldWidth, height: addressHeight)
        // The scan icon's middle is 64 from the field's right edge, the book's 28.
        self.scanButton.frame = CGRect(x: 16.0 + fieldWidth - 64.0 - 20.0, y: 157.0 + (addressHeight - 40.0) / 2.0, width: 40.0, height: 40.0)
        self.bookButton.frame = CGRect(x: 16.0 + fieldWidth - 28.0 - 20.0, y: 157.0 + (addressHeight - 40.0) / 2.0, width: 40.0, height: 40.0)
        var y = self.addressField.frame.maxY
        let hasAddressNote = !(self.addressNote.text ?? "").isEmpty
        if hasAddressNote {
            self.addressNote.frame = CGRect(x: 32.0, y: y + 10.0, width: width - 48.0, height: 18.0)
            y = self.addressNote.frame.maxY + 24.0
        } else {
            self.addressNote.frame = .zero
            y += 25.0
        }
        let amountHeight = self.amountField.height(forWidth: fieldWidth)
        self.amountField.frame = CGRect(x: 16.0, y: y, width: fieldWidth, height: amountHeight)
        self.maxButton.frame = CGRect(x: 16.0 + fieldWidth - 66.0, y: y, width: 60.0, height: amountHeight)
        y = self.amountField.frame.maxY
        if !(self.amountNote.text ?? "").isEmpty {
            self.amountNote.frame = CGRect(x: 32.0, y: y + 8.0, width: width - 48.0, height: 18.0)
            y = self.amountNote.frame.maxY
        } else {
            self.amountNote.frame = .zero
        }
        if self.commentVisible {
            let commentHeight = self.commentField.height(forWidth: fieldWidth)
            self.commentField.frame = CGRect(x: 16.0, y: y + 26.0, width: fieldWidth, height: commentHeight)
            y = self.commentField.frame.maxY
        } else {
            self.commentButton.frame = CGRect(x: 32.0, y: y + 22.0, width: fieldWidth - 16.0, height: 24.0)
            y = self.commentButton.frame.maxY
        }
        let noticeSize = self.noticeLabel.sizeThatFits(CGSize(width: width - 48.0, height: CGFloat.greatestFiniteMagnitude))
        let noticeHeight = ceil(noticeSize.height)
        // The notice hangs at the bottom when there is room; with a keyboard it stays under the link and
        // the opaque strip behind the button covers whatever of it reaches that far (as in the real page).
        let noticeY = max(y + 14.5, buttonFrame.minY - 25.0 - noticeHeight)
        self.noticeLabel.frame = CGRect(x: 24.0, y: noticeY, width: width - 48.0, height: noticeHeight)
        self.bottomCover.frame = CGRect(x: 0.0, y: buttonFrame.minY - 7.0, width: width, height: max(0.0, height - buttonFrame.minY + 7.0))
        self.continueButton.frame = buttonFrame
        if self.step == 1 {
            self.confirmView.addSubview(self.continueButton)
        } else if self.step == 0 {
            self.formView.addSubview(self.continueButton)
        }

        // Confirmation.
        self.confirmTitle.frame = CGRect(x: 16.0, y: 24.0, width: width - 32.0, height: 22.0)
        let tableWidth = width - 32.0
        let tableHeight = self.confirmTable.layoutRows(width: tableWidth)
        self.confirmTable.frame = CGRect(x: 16.0, y: 58.3, width: tableWidth, height: tableHeight)

        // Result.
        let iconSize: CGFloat = 96.0
        self.resultIcon.frame = CGRect(x: (width - iconSize) / 2.0, y: 32.0, width: iconSize, height: iconSize)
        self.resultBadge.frame = CGRect(x: self.resultIcon.frame.maxX - 26.0, y: self.resultIcon.frame.maxY - 26.0, width: 30.0, height: 30.0)
        self.resultBadgeIcon.frame = self.resultBadge.bounds
        self.resultCaption.frame = CGRect(x: 16.0, y: 144.0, width: width - 32.0, height: 22.0)
        self.resultAmount.frame = CGRect(x: 16.0, y: 172.0, width: width - 32.0, height: 40.0)
        self.resultUSD.frame = CGRect(x: 16.0, y: 222.0, width: width - 32.0, height: 22.0)
        self.resultDetailsTitle.frame = CGRect(x: 16.0, y: 276.0, width: width - 32.0, height: 22.0)
        let resultHeight = self.resultTable.layoutRows(width: tableWidth)
        self.resultTable.frame = CGRect(x: 16.0, y: 310.0, width: tableWidth, height: resultHeight)
        self.resultScroll.contentSize = CGSize(width: width, height: self.resultTable.frame.maxY + 160.0)
        self.openWalletButton.frame = CGRect(x: 16.0, y: height - 21.0 - 49.0 - 32.0 - 28.0, width: width - 32.0, height: 49.0)
        self.cancelWithdrawButton.frame = CGRect(x: 16.0, y: self.openWalletButton.frame.maxY + 10.0, width: width - 32.0, height: 28.0)
        self.bringSubviewToFront(self.openWalletButton)
        self.bringSubviewToFront(self.cancelWithdrawButton)
        self.bringSubviewToFront(self.codeSheet)
    }
}
