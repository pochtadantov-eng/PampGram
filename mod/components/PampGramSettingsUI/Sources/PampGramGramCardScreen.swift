import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import Postbox
import TelegramPresentationData
import AccountContext
import PampGramCore

/// "Карточка GRAM" (Подарки → Карточка GRAM): a cosmetic wallet-card editor modelled on the
/// card Telegram itself recently added to its Wallet tab — a big rounded card showing a GRAM
/// balance, with a background color and one emoji "sticker" the owner can drag into place.
///
/// Entirely local: the card only mirrors `PampGramSettings.fakeTonBalanceNanos`, the same
/// play-money counter "Дополнительно → TON" and the Portals/xRocket screens already show as
/// "TON/GRAM" — editing the balance here changes that one counter, nothing else. Visibility,
/// background and sticker placement live in their own `PampGramGramCardState`, entirely
/// separate from the balance itself.
private let pampGramGramCardPalette: [(UIColor, UIColor)] = [
    (UIColor(rgb: 0x3390ec), UIColor(rgb: 0x5ac8fa)),
    (UIColor(rgb: 0x8e44ec), UIColor(rgb: 0x6a3cd1)),
    (UIColor(rgb: 0x34c759), UIColor(rgb: 0x1f9e46)),
    (UIColor(rgb: 0xff9500), UIColor(rgb: 0xff6200)),
    (UIColor(rgb: 0xff2d55), UIColor(rgb: 0xd6174a)),
    (UIColor(rgb: 0x1c1c2e), UIColor(rgb: 0x0b0b16))
]

private let pampGramGramCardStickers = ["🔥", "💎", "⭐", "🚀", "🎁", "🐶"]

/// Formats nanotons as a plain GRAM amount with up to 9 decimals and no trailing zeroes —
/// same scale as the rest of the mod's "TON/GRAM" counter, kept local to this file like every
/// other screen's own formatter (`pampGramLedgerAmountText`, `formatFakeTon`, …).
private func pampGramGramCardFormatBalance(nanos: Int64) -> String {
    let sign = nanos < 0 ? "-" : ""
    let magnitude = nanos.magnitude
    let whole = magnitude / 1_000_000_000
    let fraction = magnitude % 1_000_000_000
    if fraction == 0 {
        return "\(sign)\(whole)"
    }
    var fractionString = String(fraction)
    while fractionString.count < 9 {
        fractionString = "0" + fractionString
    }
    while fractionString.hasSuffix("0") {
        fractionString.removeLast()
    }
    return "\(sign)\(whole).\(fractionString)"
}

private func pampGramGramCardParseBalance(_ text: String) -> Int64? {
    let normalized = text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ".")
    if normalized.isEmpty {
        return nil
    }
    let parts = normalized.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    guard let wholePart = parts.first else {
        return nil
    }
    let wholeString = wholePart.isEmpty ? "0" : String(wholePart)
    guard wholeString.allSatisfy({ $0.isNumber }), let whole = Int64(wholeString) else {
        return nil
    }
    var fraction: Int64 = 0
    if parts.count == 2 {
        var fractionString = String(parts[1])
        guard fractionString.allSatisfy({ $0.isNumber }) else {
            return nil
        }
        if fractionString.count > 9 {
            fractionString = String(fractionString.prefix(9))
        }
        while fractionString.count < 9 {
            fractionString.append("0")
        }
        guard let value = Int64(fractionString) else {
            return nil
        }
        fraction = value
    }
    guard whole <= (Int64.max - fraction) / 1_000_000_000 else {
        return nil
    }
    return whole * 1_000_000_000 + fraction
}

/// The card itself: gradient background, balance text, QR glyph, footer caption, and a
/// draggable emoji sticker. A plain `UIView` (not a node) so a `UIPanGestureRecognizer` can
/// drive the sticker directly — the same approach `PampGramMapPickerScreen` uses for its pin.
private final class PampGramGramCardPreviewView: UIView {
    private let gradientLayer = CAGradientLayer()
    private let balanceLabel = UILabel()
    private let diamondLabel = UILabel()
    private let qrImageView = UIImageView()
    private let footerLabel = UILabel()
    private let stickerLabel = UILabel()

    var stickerPositionChanged: ((CGPoint) -> Void)?

    private var stickerFraction = CGPoint(x: 0.5, y: 0.5)
    private var hasSticker = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.layer.cornerRadius = 22.0
        self.layer.cornerCurve = .continuous
        self.clipsToBounds = true

        self.gradientLayer.startPoint = CGPoint(x: 0.0, y: 0.0)
        self.gradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        self.layer.addSublayer(self.gradientLayer)

        self.diamondLabel.font = .systemFont(ofSize: 26.0, weight: .bold)
        self.diamondLabel.textColor = .white
        self.diamondLabel.text = "◆"
        self.addSubview(self.diamondLabel)

        self.balanceLabel.font = .systemFont(ofSize: 30.0, weight: .heavy)
        self.balanceLabel.textColor = .white
        self.balanceLabel.adjustsFontSizeToFitWidth = true
        self.balanceLabel.minimumScaleFactor = 0.5
        self.addSubview(self.balanceLabel)

        self.qrImageView.image = UIImage(systemName: "qrcode")?.withRenderingMode(.alwaysTemplate)
        self.qrImageView.tintColor = UIColor.white.withAlphaComponent(0.9)
        self.qrImageView.contentMode = .scaleAspectFit
        self.addSubview(self.qrImageView)

        self.footerLabel.font = .systemFont(ofSize: 13.0, weight: .semibold)
        self.footerLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        self.footerLabel.text = "GRAM · КАРТА"
        self.addSubview(self.footerLabel)

        self.stickerLabel.font = .systemFont(ofSize: 40.0)
        self.stickerLabel.textAlignment = .center
        self.stickerLabel.isHidden = true
        self.stickerLabel.isUserInteractionEnabled = true
        self.addSubview(self.stickerLabel)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(self.stickerPanned(_:)))
        self.stickerLabel.addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.gradientLayer.frame = self.bounds

        self.diamondLabel.frame = CGRect(x: 20.0, y: 22.0, width: 30.0, height: 32.0)
        self.balanceLabel.frame = CGRect(x: 20.0, y: 56.0, width: self.bounds.width - 40.0 - 36.0, height: 38.0)
        self.qrImageView.frame = CGRect(x: self.bounds.width - 52.0, y: 22.0, width: 32.0, height: 32.0)
        self.footerLabel.frame = CGRect(x: 20.0, y: self.bounds.height - 34.0, width: self.bounds.width - 40.0, height: 18.0)

        self.layoutSticker()
    }

    private func layoutSticker() {
        guard self.hasSticker else {
            return
        }
        let size = CGSize(width: 56.0, height: 56.0)
        let margin: CGFloat = size.width / 2.0 + 4.0
        let minX = margin, maxX = self.bounds.width - margin
        let minY = margin, maxY = self.bounds.height - margin
        let x = maxX > minX ? minX + self.stickerFraction.x * (maxX - minX) : self.bounds.midX
        let y = maxY > minY ? minY + self.stickerFraction.y * (maxY - minY) : self.bounds.midY
        self.stickerLabel.frame = CGRect(x: x - size.width / 2.0, y: y - size.height / 2.0, width: size.width, height: size.height)
    }

    func update(backgroundIndex: Int, balanceText: String) {
        let palette = pampGramGramCardPalette[max(0, min(pampGramGramCardPalette.count - 1, backgroundIndex))]
        self.gradientLayer.colors = [palette.0.cgColor, palette.1.cgColor]
        self.balanceLabel.text = "\(balanceText) GRAM"
    }

    func setSticker(emoji: String?, fraction: CGPoint) {
        self.hasSticker = emoji != nil
        self.stickerLabel.isHidden = !self.hasSticker
        self.stickerLabel.text = emoji
        self.stickerFraction = fraction
        self.setNeedsLayout()
    }

    @objc private func stickerPanned(_ gesture: UIPanGestureRecognizer) {
        guard self.hasSticker else {
            return
        }
        let translation = gesture.translation(in: self)
        let margin: CGFloat = 32.0
        let minX = margin, maxX = self.bounds.width - margin
        let minY = margin, maxY = self.bounds.height - margin
        var center = self.stickerLabel.center
        center.x = max(minX, min(maxX, center.x + translation.x))
        center.y = max(minY, min(maxY, center.y + translation.y))
        self.stickerLabel.center = center
        gesture.setTranslation(.zero, in: self)

        let fractionX = maxX > minX ? (center.x - minX) / (maxX - minX) : 0.5
        let fractionY = maxY > minY ? (center.y - minY) / (maxY - minY) : 0.5
        self.stickerFraction = CGPoint(x: fractionX, y: fractionY)
        if gesture.state == .ended || gesture.state == .cancelled {
            self.stickerPositionChanged?(self.stickerFraction)
        }
    }
}

private final class PampGramGramCardController: ViewController, UITextFieldDelegate {
    private let context: AccountContext
    private let presentationData: PresentationData
    private let stateDisposable = MetaDisposable()

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let stackView = UIStackView()
    private var headerTopConstraint: NSLayoutConstraint?

    private let cardPreview = PampGramGramCardPreviewView(frame: .zero)
    private let visibleSwitch = UISwitch()
    private let balanceField = UITextField()
    private var swatchButtons: [UIButton] = []
    private var stickerButtons: [UIButton] = []

    private var primaryColor: UIColor = .label
    private var secondaryColor: UIColor = .secondaryLabel

    private var cardState = PampGramGramCardState.default
    private var currentBalanceNanos: Int64 = 0
    private var didLoadInitialState = false

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
        self.stateDisposable.dispose()
        NotificationCenter.default.removeObserver(self)
    }

    override func loadDisplayNode() {
        let node = ASDisplayNode()
        node.backgroundColor = self.presentationData.theme.list.blocksBackgroundColor
        self.displayNode = node
        self.displayNodeDidLoad()
        self.configureView(node.view)

        NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardWillChangeFrame(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)

        self.stateDisposable.set((combineLatest(
            PampGramGramCardStore.signal(postbox: self.context.account.postbox),
            PampGramCore.rawSettingsSignal(postbox: self.context.account.postbox)
        )
        |> take(1)
        |> deliverOnMainQueue).startStrict(next: { [weak self] cardState, settings in
            self?.applyInitialState(cardState: cardState, balanceNanos: settings.fakeTonBalanceNanos)
        }))
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        self.headerTopConstraint?.constant = layout.insets(options: [.statusBar]).top
        let bottomInset = layout.intrinsicInsets.bottom
        if self.scrollView.contentInset.bottom < bottomInset + 24.0 {
            self.scrollView.contentInset.bottom = bottomInset + 24.0
        }
        self.scrollView.verticalScrollIndicatorInsets.bottom = bottomInset
    }

    private func configureView(_ rootView: UIView) {
        let theme = self.presentationData.theme
        self.primaryColor = theme.list.itemPrimaryTextColor
        self.secondaryColor = theme.list.itemSecondaryTextColor
        rootView.backgroundColor = theme.list.blocksBackgroundColor
        rootView.disablesInteractiveTransitionGestureRecognizer = true

        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(header)
        let headerTop = header.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 44.0)
        self.headerTopConstraint = headerTop
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            headerTop,
            header.heightAnchor.constraint(equalToConstant: 44.0)
        ])

        let backButton = self.makeGlyphButton(systemName: "chevron.left", action: #selector(self.closePressed))
        header.addSubview(backButton)
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Карточка GRAM"
        titleLabel.font = .systemFont(ofSize: 17.0, weight: .semibold)
        titleLabel.textColor = self.primaryColor
        titleLabel.textAlignment = .center
        header.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12.0),
            backButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 34.0),
            backButton.heightAnchor.constraint(equalToConstant: 34.0),
            titleLabel.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor)
        ])

        self.scrollView.translatesAutoresizingMaskIntoConstraints = false
        self.scrollView.alwaysBounceVertical = true
        self.scrollView.showsVerticalScrollIndicator = false
        self.scrollView.keyboardDismissMode = .interactive
        rootView.addSubview(self.scrollView)
        NSLayoutConstraint.activate([
            self.scrollView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            self.scrollView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            self.scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6.0),
            self.scrollView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        ])

        self.contentView.translatesAutoresizingMaskIntoConstraints = false
        self.scrollView.addSubview(self.contentView)
        NSLayoutConstraint.activate([
            self.contentView.leadingAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.leadingAnchor),
            self.contentView.trailingAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.trailingAnchor),
            self.contentView.topAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.topAnchor),
            self.contentView.bottomAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.bottomAnchor),
            self.contentView.widthAnchor.constraint(equalTo: self.scrollView.frameLayoutGuide.widthAnchor)
        ])

        self.stackView.translatesAutoresizingMaskIntoConstraints = false
        self.stackView.axis = .vertical
        self.stackView.alignment = .fill
        self.stackView.spacing = 18.0
        self.contentView.addSubview(self.stackView)
        NSLayoutConstraint.activate([
            self.stackView.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 16.0),
            self.stackView.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -16.0),
            self.stackView.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 12.0),
            self.stackView.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor, constant: -24.0)
        ])

        self.cardPreview.translatesAutoresizingMaskIntoConstraints = false
        self.cardPreview.heightAnchor.constraint(equalToConstant: 160.0).isActive = true
        self.cardPreview.stickerPositionChanged = { [weak self] fraction in
            self?.cardState.stickerX = Double(fraction.x)
            self?.cardState.stickerY = Double(fraction.y)
            self?.persist()
        }
        self.stackView.addArrangedSubview(self.cardPreview)

        self.stackView.addArrangedSubview(self.makeSectionLabel("Баланс"))
        self.stackView.addArrangedSubview(self.makeBalancePanel())

        self.stackView.addArrangedSubview(self.makeSectionLabel("Фон"))
        self.stackView.addArrangedSubview(self.makeSwatchPanel())

        self.stackView.addArrangedSubview(self.makeSectionLabel("Наклейка (тяните по карточке)"))
        self.stackView.addArrangedSubview(self.makeStickerPanel())
        self.stackView.addArrangedSubview(self.makeRemoveStickerButton())
    }

    private func makeGlyphButton(systemName: String, action: Selector) -> UIView {
        let panel = PampGramGlass.makeCircleButton(diameter: 34.0)
        panel.translatesAutoresizingMaskIntoConstraints = false
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = self.primaryColor
        button.setImage(UIImage(systemName: systemName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15.0, weight: .semibold)), for: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
        panel.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            button.topAnchor.constraint(equalTo: panel.topAnchor),
            button.bottomAnchor.constraint(equalTo: panel.bottomAnchor)
        ])
        return panel
    }

    private func makeSectionLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.font = .systemFont(ofSize: 13.0, weight: .semibold)
        label.textColor = self.secondaryColor
        return label
    }

    private func makeBalancePanel() -> UIView {
        let panel = PampGramGlass.makePanel(cornerRadius: 20.0)

        let visibleRow = UIView()
        visibleRow.translatesAutoresizingMaskIntoConstraints = false
        let visibleLabel = UILabel()
        visibleLabel.translatesAutoresizingMaskIntoConstraints = false
        visibleLabel.text = "Показывать карточку"
        visibleLabel.font = .systemFont(ofSize: 17.0, weight: .regular)
        visibleLabel.textColor = self.primaryColor
        visibleRow.addSubview(visibleLabel)
        self.visibleSwitch.translatesAutoresizingMaskIntoConstraints = false
        self.visibleSwitch.addTarget(self, action: #selector(self.visibleChanged), for: .valueChanged)
        visibleRow.addSubview(self.visibleSwitch)
        NSLayoutConstraint.activate([
            visibleRow.heightAnchor.constraint(equalToConstant: 50.0),
            visibleLabel.leadingAnchor.constraint(equalTo: visibleRow.leadingAnchor, constant: 18.0),
            visibleLabel.centerYAnchor.constraint(equalTo: visibleRow.centerYAnchor),
            self.visibleSwitch.trailingAnchor.constraint(equalTo: visibleRow.trailingAnchor, constant: -16.0),
            self.visibleSwitch.centerYAnchor.constraint(equalTo: visibleRow.centerYAnchor)
        ])

        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = self.secondaryColor.withAlphaComponent(0.2)
        divider.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale).isActive = true

        self.balanceField.translatesAutoresizingMaskIntoConstraints = false
        self.balanceField.font = .systemFont(ofSize: 18.0, weight: .regular)
        self.balanceField.textColor = self.primaryColor
        self.balanceField.keyboardType = .decimalPad
        self.balanceField.delegate = self
        self.balanceField.borderStyle = .none
        self.balanceField.backgroundColor = .clear
        self.balanceField.clearButtonMode = .whileEditing
        self.balanceField.returnKeyType = .done
        self.balanceField.addTarget(self, action: #selector(self.balanceFieldChanged), for: .editingChanged)
        let fieldRow = UIView()
        fieldRow.translatesAutoresizingMaskIntoConstraints = false
        fieldRow.heightAnchor.constraint(equalToConstant: 50.0).isActive = true
        fieldRow.addSubview(self.balanceField)
        NSLayoutConstraint.activate([
            self.balanceField.leadingAnchor.constraint(equalTo: fieldRow.leadingAnchor, constant: 18.0),
            self.balanceField.trailingAnchor.constraint(equalTo: fieldRow.trailingAnchor, constant: -18.0),
            self.balanceField.topAnchor.constraint(equalTo: fieldRow.topAnchor),
            self.balanceField.bottomAnchor.constraint(equalTo: fieldRow.bottomAnchor)
        ])

        let column = UIStackView(arrangedSubviews: [visibleRow, divider, fieldRow])
        column.translatesAutoresizingMaskIntoConstraints = false
        column.axis = .vertical
        panel.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            column.topAnchor.constraint(equalTo: panel.topAnchor),
            column.bottomAnchor.constraint(equalTo: panel.bottomAnchor)
        ])
        return panel
    }

    private func makeSwatchPanel() -> UIView {
        let panel = PampGramGlass.makePanel(cornerRadius: 20.0)
        panel.heightAnchor.constraint(equalToConstant: 76.0).isActive = true

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 10.0
        panel.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 18.0),
            stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -18.0),
            stack.centerYAnchor.constraint(equalTo: panel.centerYAnchor),
            stack.heightAnchor.constraint(equalToConstant: 44.0)
        ])

        for (index, colors) in pampGramGramCardPalette.enumerated() {
            let button = UIButton(type: .system)
            button.tag = index
            button.backgroundColor = colors.0
            button.layer.cornerRadius = 12.0
            button.addTarget(self, action: #selector(self.swatchTapped(_:)), for: .touchUpInside)
            stack.addArrangedSubview(button)
            self.swatchButtons.append(button)
        }
        return panel
    }

    private func makeStickerPanel() -> UIView {
        let panel = PampGramGlass.makePanel(cornerRadius: 20.0)
        panel.heightAnchor.constraint(equalToConstant: 76.0).isActive = true

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 8.0
        panel.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14.0),
            stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14.0),
            stack.centerYAnchor.constraint(equalTo: panel.centerYAnchor),
            stack.heightAnchor.constraint(equalToConstant: 48.0)
        ])

        for (index, emoji) in pampGramGramCardStickers.enumerated() {
            let button = UIButton(type: .system)
            button.tag = index
            button.setTitle(emoji, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 24.0)
            button.backgroundColor = self.secondaryColor.withAlphaComponent(0.12)
            button.layer.cornerRadius = 12.0
            button.addTarget(self, action: #selector(self.stickerTapped(_:)), for: .touchUpInside)
            stack.addArrangedSubview(button)
            self.stickerButtons.append(button)
        }
        return panel
    }

    private func makeRemoveStickerButton() -> UIView {
        let panel = PampGramGlass.makePanel(cornerRadius: 16.0)
        panel.heightAnchor.constraint(equalToConstant: 50.0).isActive = true
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Убрать наклейку", for: .normal)
        button.setTitleColor(.systemRed, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17.0, weight: .regular)
        button.addTarget(self, action: #selector(self.removeStickerTapped), for: .touchUpInside)
        panel.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            button.topAnchor.constraint(equalTo: panel.topAnchor),
            button.bottomAnchor.constraint(equalTo: panel.bottomAnchor)
        ])
        return panel
    }

    private func applyInitialState(cardState: PampGramGramCardState, balanceNanos: Int64) {
        guard !self.didLoadInitialState else {
            return
        }
        self.didLoadInitialState = true
        self.cardState = cardState
        self.currentBalanceNanos = balanceNanos
        self.visibleSwitch.isOn = cardState.visible
        self.balanceField.text = pampGramGramCardFormatBalance(nanos: balanceNanos)
        self.updateSwatchSelection()
        self.cardPreview.setSticker(emoji: cardState.stickerEmoji, fraction: CGPoint(x: CGFloat(cardState.stickerX), y: CGFloat(cardState.stickerY)))
        self.cardPreview.update(backgroundIndex: Int(cardState.backgroundIndex), balanceText: pampGramGramCardFormatBalance(nanos: balanceNanos))
    }

    private func updateSwatchSelection() {
        for (index, button) in self.swatchButtons.enumerated() {
            button.layer.borderWidth = index == Int(self.cardState.backgroundIndex) ? 3.0 : 0.0
            button.layer.borderColor = UIColor.white.cgColor
        }
    }

    private func persist() {
        let cardState = self.cardState
        let _ = self.context.account.postbox.transaction { transaction -> Void in
            PampGramGramCardStore.update(transaction: transaction, { _ in cardState })
        }.start()
    }

    private func popSelf() {
        if let navigationController = self.navigationController as? NavigationController {
            let _ = navigationController.popViewController(animated: true)
        } else {
            self.dismiss(animated: true, completion: nil)
        }
    }

    @objc private func closePressed() {
        self.view.endEditing(true)
        self.commitBalanceIfNeeded()
        self.popSelf()
    }

    @objc private func visibleChanged() {
        self.cardState.visible = self.visibleSwitch.isOn
        self.persist()
    }

    @objc private func balanceFieldChanged() {
        if let text = self.balanceField.text, let nanos = pampGramGramCardParseBalance(text) {
            self.cardPreview.update(backgroundIndex: Int(self.cardState.backgroundIndex), balanceText: pampGramGramCardFormatBalance(nanos: nanos))
        }
    }

    private func commitBalanceIfNeeded() {
        guard let text = self.balanceField.text, let nanos = pampGramGramCardParseBalance(text), nanos != self.currentBalanceNanos else {
            return
        }
        let delta = nanos - self.currentBalanceNanos
        self.currentBalanceNanos = nanos
        let _ = self.context.account.postbox.transaction { transaction -> Void in
            PampGramLocalLedgerStore.addAndApply(transaction: transaction, currency: .ton, kind: delta > 0 ? .credit : .debit, amount: delta, title: "Карточка GRAM", details: "Изменение баланса в редакторе карточки")
        }.start()
    }

    @objc private func swatchTapped(_ sender: UIButton) {
        self.cardState.backgroundIndex = Int32(sender.tag)
        self.updateSwatchSelection()
        self.cardPreview.update(backgroundIndex: sender.tag, balanceText: pampGramGramCardFormatBalance(nanos: pampGramGramCardParseBalance(self.balanceField.text ?? "") ?? self.currentBalanceNanos))
        self.persist()
    }

    @objc private func stickerTapped(_ sender: UIButton) {
        let emoji = pampGramGramCardStickers[sender.tag]
        if self.cardState.stickerEmoji == nil {
            self.cardState.stickerX = 0.5
            self.cardState.stickerY = 0.5
        }
        self.cardState.stickerEmoji = emoji
        self.cardPreview.setSticker(emoji: emoji, fraction: CGPoint(x: CGFloat(self.cardState.stickerX), y: CGFloat(self.cardState.stickerY)))
        self.persist()
    }

    @objc private func removeStickerTapped() {
        self.cardState.stickerEmoji = nil
        self.cardPreview.setSticker(emoji: nil, fraction: CGPoint(x: CGFloat(self.cardState.stickerX), y: CGFloat(self.cardState.stickerY)))
        self.persist()
    }

    // MARK: - Keyboard

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let endFrame = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else {
            return
        }
        let overlap = max(0.0, self.view.bounds.maxY - self.view.convert(endFrame, from: nil).minY)
        self.scrollView.contentInset.bottom = overlap + 24.0
        self.scrollView.verticalScrollIndicatorInsets.bottom = overlap
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        self.scrollView.contentInset.bottom = 24.0
        self.scrollView.verticalScrollIndicatorInsets.bottom = 0.0
    }

    // MARK: - UITextFieldDelegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        self.commitBalanceIfNeeded()
        return true
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        self.commitBalanceIfNeeded()
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard textField === self.balanceField else {
            return true
        }
        guard let currentText = textField.text, let textRange = Range(range, in: currentText) else {
            return true
        }
        let updatedText = currentText.replacingCharacters(in: textRange, with: string)
        if updatedText.isEmpty {
            return true
        }
        let separators = CharacterSet(charactersIn: ".,")
        var separatorCount = 0
        for scalar in updatedText.unicodeScalars {
            if CharacterSet.decimalDigits.contains(scalar) {
                continue
            } else if separators.contains(scalar) {
                separatorCount += 1
            } else {
                return false
            }
        }
        return separatorCount <= 1
    }
}

public func pampGramGramCardController(context: AccountContext) -> ViewController {
    return PampGramGramCardController(context: context)
}
