import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import PampGramCore
import PhantomGiftKit

// New visual sections that sit in the gifts settings next to the rating and +888:
// verification badges (Major / Hold), the GRAM card, visual usernames and visual crafting.
// Everything here is local: it only writes PampGram's own preferences.

// MARK: - Shared page

/// Full-screen page with a glass header (back button + title) and a vertical stack of panels.
/// Subclasses fill the stack in `buildContent()`.
class PampGramVisualPageController: ViewController {
    let context: AccountContext
    let presentationData: PresentationData
    let pageTitle: String
    let stack = UIStackView()
    var primaryColor: UIColor = .label
    var secondaryColor: UIColor = .secondaryLabel

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private var headerTopConstraint: NSLayoutConstraint?

    init(context: AccountContext, title: String) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        self.pageTitle = title
        super.init(navigationBarPresentationData: nil)
        self.displayNavigationBar = false
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadDisplayNode() {
        let node = ASDisplayNode()
        node.backgroundColor = self.presentationData.theme.list.blocksBackgroundColor
        self.displayNode = node
        self.displayNodeDidLoad()
        self.configureRoot(node.view)
        self.buildContent()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        self.headerTopConstraint?.constant = layout.insets(options: [.statusBar]).top
        let bottomInset = layout.intrinsicInsets.bottom
        self.scrollView.contentInset.bottom = bottomInset + 24.0
        self.scrollView.verticalScrollIndicatorInsets.bottom = bottomInset
    }

    /// Override to add panels with `self.stack.addArrangedSubview`.
    func buildContent() {
    }

    private func configureRoot(_ rootView: UIView) {
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

        let backPanel = PampGramGlass.makeCircleButton(diameter: 34.0)
        backPanel.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(backPanel)
        let backButton = UIButton(type: .system)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.tintColor = self.primaryColor
        backButton.setImage(UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15.0, weight: .semibold)), for: .normal)
        backButton.addTarget(self, action: #selector(self.backPressed), for: .touchUpInside)
        backPanel.addSubview(backButton)
        let titleLabel = self.makeLabel(self.pageTitle, size: 17.0, weight: .semibold, color: self.primaryColor)
        titleLabel.textAlignment = .center
        header.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            backPanel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12.0),
            backPanel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            backPanel.widthAnchor.constraint(equalToConstant: 34.0),
            backPanel.heightAnchor.constraint(equalToConstant: 34.0),
            backButton.leadingAnchor.constraint(equalTo: backPanel.leadingAnchor),
            backButton.trailingAnchor.constraint(equalTo: backPanel.trailingAnchor),
            backButton.topAnchor.constraint(equalTo: backPanel.topAnchor),
            backButton.bottomAnchor.constraint(equalTo: backPanel.bottomAnchor),
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

        self.stack.translatesAutoresizingMaskIntoConstraints = false
        self.stack.axis = .vertical
        self.stack.alignment = .fill
        self.stack.spacing = 14.0
        self.contentView.addSubview(self.stack)
        NSLayoutConstraint.activate([
            self.stack.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 16.0),
            self.stack.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -16.0),
            self.stack.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 12.0),
            self.stack.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor, constant: -24.0)
        ])
    }

    @objc func backPressed() {
        if let navigationController = self.navigationController as? NavigationController {
            let _ = navigationController.popViewController(animated: true)
        } else {
            self.dismiss(animated: true, completion: nil)
        }
    }

    // MARK: Helpers for subclasses

    func makeLabel(_ text: String, size: CGFloat, weight: UIFont.Weight, color: UIColor) -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.font = UIFont.systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.numberOfLines = 0
        return label
    }

    /// A glass panel with an optional title and `content` stacked inside with padding.
    func makePanel(title: String?, content: [UIView]) -> UIView {
        let panel = PampGramGlass.makePanel(cornerRadius: 20.0)
        let inner = UIStackView()
        inner.translatesAutoresizingMaskIntoConstraints = false
        inner.axis = .vertical
        inner.alignment = .fill
        inner.spacing = 12.0
        panel.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16.0),
            inner.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16.0),
            inner.topAnchor.constraint(equalTo: panel.topAnchor, constant: 16.0),
            inner.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -16.0)
        ])
        if let title = title {
            inner.addArrangedSubview(self.makeLabel(title, size: 17.0, weight: .semibold, color: self.primaryColor))
        }
        for view in content {
            inner.addArrangedSubview(view)
        }
        return panel
    }

    func makeButton(_ title: String, filled: Bool, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16.0, weight: .semibold)
        button.setTitleColor(filled ? UIColor.white : self.primaryColor, for: .normal)
        button.backgroundColor = filled ? UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0) : UIColor(white: 0.5, alpha: 0.18)
        button.layer.cornerRadius = 12.0
        button.heightAnchor.constraint(equalToConstant: 46.0).isActive = true
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    func makeField(placeholder: String, keyboard: UIKeyboardType) -> UITextField {
        let field = UITextField()
        field.borderStyle = .roundedRect
        field.placeholder = placeholder
        field.keyboardType = keyboard
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.heightAnchor.constraint(equalToConstant: 44.0).isActive = true
        return field
    }

    func loadExtras(_ completion: @escaping (PampGramVisualExtras) -> Void) {
        let _ = (PampGramProfileVisualStore.signal(postbox: self.context.account.postbox)
        |> take(1)
        |> deliverOnMainQueue).start(next: { state in
            completion(state.visualExtras)
        })
    }

    func updateExtras(_ f: @escaping (inout PampGramVisualExtras) -> Void) {
        let _ = self.context.account.postbox.transaction { transaction -> Void in
            PampGramProfileVisualStore.update(transaction: transaction, { state in
                var state = state
                var extras = state.visualExtras
                f(&extras)
                state.visualExtras = extras
                return state
            })
        }.start()
    }
}

// MARK: - Verification badges (Major / Hold)

private func pampGramBadgeImage(kind: Int, side: CGFloat) -> UIImage {
    let size = CGSize(width: side, height: side)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { _ in
        let rect = CGRect(origin: .zero, size: size)
        let color: UIColor
        if kind == 1 {
            color = UIColor(red: 0.56, green: 0.27, blue: 0.93, alpha: 1.0)
        } else {
            color = UIColor(red: 0.19, green: 0.78, blue: 0.35, alpha: 1.0)
        }
        color.setFill()
        UIBezierPath(ovalIn: rect).fill()
        let config = UIImage.SymbolConfiguration(pointSize: side * 0.55, weight: .bold)
        if let symbol = UIImage(systemName: "checkmark", withConfiguration: config)?.withTintColor(.white, renderingMode: .alwaysOriginal) {
            let symbolSize = symbol.size
            symbol.draw(in: CGRect(x: (side - symbolSize.width) / 2.0, y: (side - symbolSize.height) / 2.0, width: symbolSize.width, height: symbolSize.height))
        }
    }
}

private final class PampGramBadgeScreenController: PampGramVisualPageController {
    private let previewName = UILabel()
    private let previewBadge = UIImageView()
    private var rowButtons: [UIButton] = []
    private var selectedKind = 0

    override func buildContent() {
        self.previewName.translatesAutoresizingMaskIntoConstraints = false
        self.previewName.text = "Ваш профиль"
        self.previewName.font = UIFont.systemFont(ofSize: 22.0, weight: .bold)
        self.previewName.textColor = self.primaryColor
        self.previewBadge.translatesAutoresizingMaskIntoConstraints = false
        self.previewBadge.contentMode = .scaleAspectFit
        let previewRow = UIStackView(arrangedSubviews: [self.previewName, self.previewBadge, UIView()])
        previewRow.axis = .horizontal
        previewRow.alignment = .center
        previewRow.spacing = 8.0
        self.previewBadge.widthAnchor.constraint(equalToConstant: 22.0).isActive = true
        self.previewBadge.heightAnchor.constraint(equalToConstant: 22.0).isActive = true
        self.stack.addArrangedSubview(self.makePanel(title: "Предпросмотр", content: [previewRow]))

        var buttons: [UIView] = []
        for kind in 0 ... 2 {
            let button = self.makeButton(kind > 0 ? "  " + PampGramVisualExtras.badgeNames[kind] : PampGramVisualExtras.badgeNames[kind], filled: false, action: #selector(self.badgePressed(_:)))
            button.tag = kind
            if kind > 0 {
                button.setImage(pampGramBadgeImage(kind: kind, side: 22.0).withRenderingMode(.alwaysOriginal), for: .normal)
            }
            self.rowButtons.append(button)
            buttons.append(button)
        }
        self.stack.addArrangedSubview(self.makePanel(title: "Галочка рядом с именем", content: buttons))
        let note = self.makeLabel("Локальная метка Major или Hold рядом с вашим именем. Видна только на этом устройстве.", size: 13.0, weight: .regular, color: self.secondaryColor)
        self.stack.addArrangedSubview(note)

        self.loadExtras { [weak self] extras in
            self?.selectedKind = min(2, max(0, extras.badge))
            self?.refresh()
        }
        self.refresh()
    }

    private func refresh() {
        if self.selectedKind == 0 {
            self.previewBadge.image = nil
            self.previewBadge.isHidden = true
        } else {
            self.previewBadge.image = pampGramBadgeImage(kind: self.selectedKind, side: 22.0)
            self.previewBadge.isHidden = false
        }
        for button in self.rowButtons {
            button.alpha = button.tag == self.selectedKind ? 1.0 : 0.55
        }
    }

    @objc private func badgePressed(_ sender: UIButton) {
        let kind = sender.tag
        self.selectedKind = kind
        self.updateExtras { extras in
            extras.badge = kind
        }
        self.refresh()
    }
}

// MARK: - GRAM card

private final class PampGramGramCardView: UIView {
    static let backgrounds: [(UIColor, UIColor)] = [
        (UIColor(red: 0.20, green: 0.45, blue: 0.98, alpha: 1.0), UIColor(red: 0.30, green: 0.65, blue: 1.0, alpha: 1.0)),
        (UIColor(red: 0.45, green: 0.22, blue: 0.85, alpha: 1.0), UIColor(red: 0.75, green: 0.35, blue: 0.95, alpha: 1.0)),
        (UIColor(red: 0.10, green: 0.62, blue: 0.45, alpha: 1.0), UIColor(red: 0.30, green: 0.82, blue: 0.55, alpha: 1.0)),
        (UIColor(red: 0.92, green: 0.38, blue: 0.20, alpha: 1.0), UIColor(red: 1.00, green: 0.65, blue: 0.25, alpha: 1.0)),
        (UIColor(red: 0.85, green: 0.20, blue: 0.40, alpha: 1.0), UIColor(red: 1.00, green: 0.45, blue: 0.55, alpha: 1.0)),
        (UIColor(red: 0.10, green: 0.12, blue: 0.20, alpha: 1.0), UIColor(red: 0.28, green: 0.32, blue: 0.45, alpha: 1.0))
    ]

    private let gradient = CAGradientLayer()
    private let sheen = CAGradientLayer()
    private let balanceLabel = UILabel()
    private let captionLabel = UILabel()
    private let stickerLabel = UILabel()
    private let qrView = UIImageView()
    private var stickerX: Double = 0.82
    private var stickerY: Double = 0.28
    var onStickerMoved: ((Double, Double) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.layer.cornerRadius = 22.0
        self.layer.masksToBounds = true

        self.gradient.startPoint = CGPoint(x: 0.0, y: 0.0)
        self.gradient.endPoint = CGPoint(x: 1.0, y: 1.0)
        self.layer.addSublayer(self.gradient)

        self.sheen.colors = [UIColor.white.withAlphaComponent(0.0).cgColor, UIColor.white.withAlphaComponent(0.28).cgColor, UIColor.white.withAlphaComponent(0.0).cgColor]
        self.sheen.startPoint = CGPoint(x: 0.0, y: 0.5)
        self.sheen.endPoint = CGPoint(x: 1.0, y: 0.5)
        self.layer.addSublayer(self.sheen)

        self.balanceLabel.font = UIFont.systemFont(ofSize: 30.0, weight: .heavy)
        self.balanceLabel.textColor = .white
        self.balanceLabel.adjustsFontSizeToFitWidth = true
        self.balanceLabel.minimumScaleFactor = 0.5
        self.addSubview(self.balanceLabel)

        self.captionLabel.font = UIFont.systemFont(ofSize: 13.0, weight: .semibold)
        self.captionLabel.textColor = UIColor.white.withAlphaComponent(0.75)
        self.captionLabel.text = "GRAM · КАРТА"
        self.addSubview(self.captionLabel)

        self.qrView.image = UIImage(systemName: "qrcode")
        self.qrView.tintColor = UIColor.white.withAlphaComponent(0.9)
        self.qrView.contentMode = .scaleAspectFit
        self.addSubview(self.qrView)

        self.stickerLabel.font = UIFont.systemFont(ofSize: 44.0)
        self.stickerLabel.isUserInteractionEnabled = true
        self.stickerLabel.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(self.stickerPanned(_:))))
        self.addSubview(self.stickerLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(_ extras: PampGramVisualExtras) {
        let index = min(PampGramGramCardView.backgrounds.count - 1, max(0, extras.cardBackground))
        let pair = PampGramGramCardView.backgrounds[index]
        self.gradient.colors = [pair.0.cgColor, pair.1.cgColor]
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        let amount = formatter.string(from: NSNumber(value: extras.cardBalance)) ?? "\(extras.cardBalance)"
        self.balanceLabel.text = "◆ \(amount) GRAM"
        self.stickerLabel.text = extras.cardSticker
        self.stickerLabel.isHidden = extras.cardSticker.isEmpty
        self.stickerX = extras.cardStickerX
        self.stickerY = extras.cardStickerY
        self.setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = self.bounds.width
        let height = self.bounds.height
        self.gradient.frame = self.bounds
        self.balanceLabel.frame = CGRect(x: 22.0, y: height * 0.36, width: width - 110.0, height: 40.0)
        self.captionLabel.frame = CGRect(x: 22.0, y: height - 42.0, width: width - 44.0, height: 20.0)
        self.qrView.frame = CGRect(x: width - 70.0, y: height * 0.34, width: 46.0, height: 46.0)
        self.stickerLabel.sizeToFit()
        let centerX = CGFloat(self.stickerX) * width
        let centerY = CGFloat(self.stickerY) * height
        self.stickerLabel.center = CGPoint(x: centerX, y: centerY)
        let sheenWidth = width * 0.55
        self.sheen.frame = CGRect(x: 0.0, y: 0.0, width: sheenWidth, height: height)
        if self.sheen.animation(forKey: "sheen") == nil && width > 0.0 {
            let animation = CABasicAnimation(keyPath: "transform.translation.x")
            animation.fromValue = -sheenWidth
            animation.toValue = width + sheenWidth
            animation.duration = 2.8
            animation.repeatCount = Float.infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.sheen.add(animation, forKey: "sheen")
        }
    }

    @objc private func stickerPanned(_ gesture: UIPanGestureRecognizer) {
        guard self.bounds.width > 0.0, self.bounds.height > 0.0 else {
            return
        }
        let point = gesture.location(in: self)
        self.stickerX = min(0.95, max(0.05, Double(point.x / self.bounds.width)))
        self.stickerY = min(0.9, max(0.1, Double(point.y / self.bounds.height)))
        self.setNeedsLayout()
        if gesture.state == .ended {
            self.onStickerMoved?(self.stickerX, self.stickerY)
        }
    }
}

private final class PampGramCardScreenController: PampGramVisualPageController {
    private let card = PampGramGramCardView()
    private let enableSwitch = UISwitch()
    private var balanceField = UITextField()
    private var current = PampGramVisualExtras.default

    override func buildContent() {
        self.card.translatesAutoresizingMaskIntoConstraints = false
        self.card.heightAnchor.constraint(equalToConstant: 190.0).isActive = true
        self.card.onStickerMoved = { [weak self] x, y in
            self?.current.cardStickerX = x
            self?.current.cardStickerY = y
            self?.updateExtras { extras in
                extras.cardStickerX = x
                extras.cardStickerY = y
            }
        }
        self.stack.addArrangedSubview(self.card)

        let switchRow = UIStackView(arrangedSubviews: [self.makeLabel("Показывать карточку", size: 16.0, weight: .regular, color: self.primaryColor), self.enableSwitch])
        switchRow.axis = .horizontal
        switchRow.alignment = .center
        self.enableSwitch.addTarget(self, action: #selector(self.switchChanged), for: .valueChanged)
        self.balanceField = self.makeField(placeholder: "Баланс GRAM", keyboard: .numberPad)
        self.balanceField.addTarget(self, action: #selector(self.balanceChanged(_:)), for: .editingChanged)
        self.stack.addArrangedSubview(self.makePanel(title: "Баланс", content: [switchRow, self.balanceField]))

        var swatches: [UIView] = []
        let swatchRow = UIStackView()
        swatchRow.axis = .horizontal
        swatchRow.distribution = .fillEqually
        swatchRow.spacing = 8.0
        for index in 0 ..< PampGramGramCardView.backgrounds.count {
            let button = UIButton(type: .system)
            button.tag = index
            button.backgroundColor = PampGramGramCardView.backgrounds[index].0
            button.layer.cornerRadius = 12.0
            button.heightAnchor.constraint(equalToConstant: 40.0).isActive = true
            button.addTarget(self, action: #selector(self.backgroundPressed(_:)), for: .touchUpInside)
            swatchRow.addArrangedSubview(button)
        }
        swatches.append(swatchRow)
        self.stack.addArrangedSubview(self.makePanel(title: "Фон", content: swatches))

        let stickerRow = UIStackView()
        stickerRow.axis = .horizontal
        stickerRow.distribution = .fillEqually
        stickerRow.spacing = 6.0
        for symbol in ["🔥", "💎", "⭐️", "🚀", "🎁", "🐶"] {
            let button = UIButton(type: .system)
            button.setTitle(symbol, for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 28.0)
            button.backgroundColor = UIColor(white: 0.5, alpha: 0.18)
            button.layer.cornerRadius = 10.0
            button.heightAnchor.constraint(equalToConstant: 46.0).isActive = true
            button.addTarget(self, action: #selector(self.stickerPressed(_:)), for: .touchUpInside)
            stickerRow.addArrangedSubview(button)
        }
        let removeButton = self.makeButton("Убрать наклейку", filled: false, action: #selector(self.removeStickerPressed))
        self.stack.addArrangedSubview(self.makePanel(title: "Наклейка (тяните по карточке)", content: [stickerRow, removeButton]))

        self.loadExtras { [weak self] extras in
            self?.current = extras
            self?.enableSwitch.isOn = extras.cardEnabled
            self?.balanceField.text = extras.cardBalance > 0 ? "\(extras.cardBalance)" : ""
            self?.card.apply(extras)
        }
        self.card.apply(self.current)
    }

    @objc private func switchChanged() {
        let value = self.enableSwitch.isOn
        self.current.cardEnabled = value
        self.updateExtras { extras in
            extras.cardEnabled = value
        }
    }

    @objc private func balanceChanged(_ field: UITextField) {
        let digits = String((field.text ?? "").filter { $0.isNumber }.prefix(12))
        let value = Int64(digits) ?? 0
        self.current.cardBalance = value
        self.card.apply(self.current)
        self.updateExtras { extras in
            extras.cardBalance = value
        }
    }

    @objc private func backgroundPressed(_ sender: UIButton) {
        let index = sender.tag
        self.current.cardBackground = index
        self.card.apply(self.current)
        self.updateExtras { extras in
            extras.cardBackground = index
        }
    }

    @objc private func stickerPressed(_ sender: UIButton) {
        let symbol = sender.title(for: .normal) ?? ""
        self.current.cardSticker = symbol
        self.card.apply(self.current)
        self.updateExtras { extras in
            extras.cardSticker = symbol
        }
    }

    @objc private func removeStickerPressed() {
        self.current.cardSticker = ""
        self.card.apply(self.current)
        self.updateExtras { extras in
            extras.cardSticker = ""
        }
    }
}

// MARK: - Visual usernames

private final class PampGramUsernamesScreenController: PampGramVisualPageController {
    private var nameField = UITextField()
    private var priceField = UITextField()
    private let datePicker = UIDatePicker()
    private let errorLabel = UILabel()
    private let listStack = UIStackView()
    private var items: [PampGramVisualUsername] = []

    override func buildContent() {
        self.nameField = self.makeField(placeholder: "Юзернейм без @", keyboard: .asciiCapable)
        self.priceField = self.makeField(placeholder: "Цена TON", keyboard: .decimalPad)
        self.datePicker.datePickerMode = .date
        self.datePicker.preferredDatePickerStyle = .wheels
        self.errorLabel.translatesAutoresizingMaskIntoConstraints = false
        self.errorLabel.font = UIFont.systemFont(ofSize: 13.0)
        self.errorLabel.textColor = .systemRed
        self.errorLabel.numberOfLines = 0
        let addButton = self.makeButton("Добавить NFT-юзернейм", filled: true, action: #selector(self.addPressed))
        self.stack.addArrangedSubview(self.makePanel(title: "Новый юзернейм", content: [self.nameField, self.priceField, self.datePicker, self.errorLabel, addButton]))

        self.listStack.axis = .vertical
        self.listStack.spacing = 8.0
        self.stack.addArrangedSubview(self.makePanel(title: "Ваши юзернеймы", content: [self.listStack]))
        self.loadExtras { [weak self] extras in
            self?.items = extras.usernames
            self?.reloadList()
        }
        self.reloadList()
    }

    private func reloadList() {
        for view in self.listStack.arrangedSubviews {
            self.listStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        if self.items.isEmpty {
            self.listStack.addArrangedSubview(self.makeLabel("Пока пусто", size: 14.0, weight: .regular, color: self.secondaryColor))
            return
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        for (index, item) in self.items.enumerated() {
            let date = Date(timeIntervalSince1970: TimeInterval(item.boughtAt))
            let text = "@\(item.name) · \(item.priceTon) TON · \(formatter.string(from: date))"
            let label = self.makeLabel(text, size: 15.0, weight: .regular, color: self.primaryColor)
            let delete = UIButton(type: .system)
            delete.setTitle("Удалить", for: .normal)
            delete.tag = index
            delete.addTarget(self, action: #selector(self.deletePressed(_:)), for: .touchUpInside)
            let row = UIStackView(arrangedSubviews: [label, delete])
            row.axis = .horizontal
            row.alignment = .center
            row.spacing = 8.0
            self.listStack.addArrangedSubview(row)
        }
    }

    @objc private func addPressed() {
        var name = (self.nameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if name.hasPrefix("@") {
            name.removeFirst()
        }
        guard name.count >= 4 else {
            self.errorLabel.text = "Юзернейм должен быть не короче 4 символов."
            return
        }
        self.errorLabel.text = nil
        let priceText = (self.priceField.text ?? "").replacingOccurrences(of: ",", with: ".")
        let price = Double(priceText) ?? 0.0
        let item = PampGramVisualUsername(name: name, priceTon: price, boughtAt: Int32(self.datePicker.date.timeIntervalSince1970))
        self.items.append(item)
        self.updateExtras { extras in
            extras.usernames.append(item)
        }
        self.nameField.text = nil
        self.priceField.text = nil
        self.reloadList()
    }

    @objc private func deletePressed(_ sender: UIButton) {
        let index = sender.tag
        guard index >= 0 && index < self.items.count else {
            return
        }
        self.items.remove(at: index)
        self.updateExtras { extras in
            if index < extras.usernames.count {
                extras.usernames.remove(at: index)
            }
        }
        self.reloadList()
    }
}

// MARK: - Visual crafting

private final class PampGramCraftScreenController: PampGramVisualPageController {
    private let listStack = UIStackView()
    private let chanceLabel = UILabel()
    private let resultLabel = UILabel()
    private var craftButton = UIButton(type: .system)
    private var gifts: [PampGramPhantomGift] = []
    private var selectedIds: [Int64] = []

    /// Success chance by how many gifts are put on the table.
    private static func chance(for count: Int) -> Int {
        switch count {
        case 1:
            return 22
        case 2:
            return 41
        case 3:
            return 58
        case 4:
            return 72
        default:
            return 0
        }
    }

    override func buildContent() {
        self.listStack.axis = .vertical
        self.listStack.spacing = 8.0
        self.stack.addArrangedSubview(self.makePanel(title: "Выберите до 4 подарков", content: [self.listStack]))

        self.chanceLabel.translatesAutoresizingMaskIntoConstraints = false
        self.chanceLabel.font = UIFont.systemFont(ofSize: 15.0, weight: .semibold)
        self.chanceLabel.textColor = self.primaryColor
        self.chanceLabel.numberOfLines = 0
        self.resultLabel.translatesAutoresizingMaskIntoConstraints = false
        self.resultLabel.font = UIFont.systemFont(ofSize: 15.0, weight: .semibold)
        self.resultLabel.numberOfLines = 0
        self.craftButton = self.makeButton("Крафт", filled: true, action: #selector(self.craftPressed))
        self.stack.addArrangedSubview(self.makePanel(title: "Стол крафта", content: [self.chanceLabel, self.craftButton, self.resultLabel]))
        self.stack.addArrangedSubview(self.makeLabel("Если крафт не удался, выбранные подарки сгорают. Всё происходит локально.", size: 13.0, weight: .regular, color: self.secondaryColor))

        self.reloadGifts()
    }

    private func reloadGifts() {
        let peerId = self.context.account.peerId
        let _ = (self.context.account.postbox.transaction { transaction -> [PampGramPhantomGift] in
            return PampGramPhantomGiftStore.allGifts(transaction: transaction)
        }
        |> deliverOnMainQueue).start(next: { [weak self] all in
            guard let self = self else {
                return
            }
            self.gifts = all.filter { $0.peerId == peerId }
            self.selectedIds = self.selectedIds.filter { id in self.gifts.contains(where: { $0.id == id }) }
            self.rebuildList()
        })
    }

    private func rebuildList() {
        for view in self.listStack.arrangedSubviews {
            self.listStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        if self.gifts.isEmpty {
            self.listStack.addArrangedSubview(self.makeLabel("У вас нет локальных подарков. Добавьте их в «Коллекции и маркете».", size: 14.0, weight: .regular, color: self.secondaryColor))
        }
        for (index, gift) in self.gifts.enumerated() {
            let selected = self.selectedIds.contains(gift.id)
            let button = self.makeButton((selected ? "✓ " : "") + gift.title, filled: selected, action: #selector(self.giftPressed(_:)))
            button.tag = index
            self.listStack.addArrangedSubview(button)
        }
        let count = self.selectedIds.count
        let chance = PampGramCraftScreenController.chance(for: count)
        if count == 0 {
            self.chanceLabel.text = "Добавьте подарки на стол."
        } else {
            self.chanceLabel.text = "Подарков на столе: \(count). Шанс успеха: \(chance)%"
        }
        self.craftButton.isEnabled = count > 0
        self.craftButton.alpha = count > 0 ? 1.0 : 0.5
    }

    @objc private func giftPressed(_ sender: UIButton) {
        let index = sender.tag
        guard index >= 0 && index < self.gifts.count else {
            return
        }
        let id = self.gifts[index].id
        if let position = self.selectedIds.firstIndex(of: id) {
            self.selectedIds.remove(at: position)
        } else if self.selectedIds.count < 4 {
            self.selectedIds.append(id)
        }
        self.resultLabel.text = nil
        self.rebuildList()
    }

    @objc private func craftPressed() {
        let ids = self.selectedIds
        guard !ids.isEmpty else {
            return
        }
        let chance = PampGramCraftScreenController.chance(for: ids.count)
        let success = Int.random(in: 1 ... 100) <= chance
        let _ = (self.context.account.postbox.transaction { transaction -> String in
            let all = PampGramPhantomGiftStore.allGifts(transaction: transaction)
            guard let primary = all.first(where: { $0.id == ids[0] }) else {
                return ""
            }
            for id in ids {
                PampGramPhantomGiftStore.remove(transaction: transaction, id: id)
            }
            if success {
                let crafted = PampGramPhantomGift(id: Int64.random(in: 1 ... (Int64.max / 4)), peerId: primary.peerId, gift: primary.gift, price: primary.price, date: Int32(Date().timeIntervalSince1970), localMessageId: nil)
                PampGramPhantomGiftStore.add(transaction: transaction, gift: crafted)
            }
            return primary.title
        }
        |> deliverOnMainQueue).start(next: { [weak self] title in
            guard let self = self else {
                return
            }
            if success {
                self.resultLabel.textColor = .systemGreen
                self.resultLabel.text = "Крафт удался! Новый подарок: \(title)"
            } else {
                self.resultLabel.textColor = .systemRed
                self.resultLabel.text = "Крафт не удался. Подарков потеряно: \(ids.count)"
            }
            self.selectedIds = []
            self.reloadGifts()
        })
    }
}

// MARK: - Entry points

/// 0 = badges, 1 = GRAM card, 2 = usernames, 3 = crafting.
func pampGramVisualExtraController(context: AccountContext, kind: Int) -> ViewController {
    switch kind {
    case 0:
        return PampGramBadgeScreenController(context: context, title: "Галочки")
    case 1:
        return PampGramCardScreenController(context: context, title: "Карточка GRAM")
    case 2:
        return PampGramUsernamesScreenController(context: context, title: "Юзернеймы")
    default:
        return PampGramCraftScreenController(context: context, title: "Крафт подарков")
    }
}
