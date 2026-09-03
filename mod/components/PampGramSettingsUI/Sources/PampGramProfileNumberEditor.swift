import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import Postbox
import TelegramPresentationData
import AccountContext
import PampGramCore

private let pampGramNumberAccent = UIColor(red: 0.16, green: 0.55, blue: 0.98, alpha: 1.0)

/// Local-only editor for the visual anonymous "+888" number. It writes into PampGram's Postbox
/// preferences only after "Сохранить"; nothing here queries Fragment or changes Telegram's real
/// phone number on the server.
private final class PampGramProfileNumberEditorController: ViewController, UITextFieldDelegate {
    private let context: AccountContext
    private let presentationData: PresentationData
    private let stateDisposable = MetaDisposable()

    private let sheetView = UIView()
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let stackView = UIStackView()
    private var sheetHeightConstraint: NSLayoutConstraint?

    private let subtitleLabel = UILabel()
    private let previewNumberLabel = UILabel()
    private let previewDetailsLabel = UILabel()
    private let numberField = UITextField()
    private let datePicker = UIDatePicker()
    private let tonField = UITextField()
    private let usdField = UITextField()
    private let displayButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)

    private var showInProfile = false
    private var didLoadInitialState = false
    private weak var activeField: UITextField?

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
        node.backgroundColor = .clear
        self.displayNode = node
        self.displayNodeDidLoad()
        self.configureView(node.view)

        NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardWillChangeFrame(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)

        self.stateDisposable.set((PampGramProfileVisualStore.signal(postbox: self.context.account.postbox)
        |> take(1)
        |> deliverOnMainQueue).startStrict(next: { [weak self] state in
            self?.applyInitialState(state)
        }))
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        self.sheetHeightConstraint?.constant = min(640.0, max(430.0, layout.size.height - 12.0))
    }

    private func configureView(_ rootView: UIView) {
        let theme = self.presentationData.theme.list
        rootView.backgroundColor = .clear
        // Editing fields must not trigger the navigation's interactive back/dismiss gesture — the
        // editor closes only via its own X / Save buttons (or a tap outside the sheet).
        rootView.disablesInteractiveTransitionGestureRecognizer = true

        let dismissTap = UITapGestureRecognizer(target: self, action: #selector(self.backgroundTapped))
        dismissTap.cancelsTouchesInView = false
        rootView.addGestureRecognizer(dismissTap)

        self.sheetView.translatesAutoresizingMaskIntoConstraints = false
        self.sheetView.backgroundColor = theme.blocksBackgroundColor
        self.sheetView.layer.cornerRadius = 28.0
        self.sheetView.clipsToBounds = true
        if #available(iOS 11.0, *) {
            self.sheetView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        }
        rootView.addSubview(self.sheetView)
        let heightConstraint = self.sheetView.heightAnchor.constraint(equalToConstant: 600.0)
        self.sheetHeightConstraint = heightConstraint
        NSLayoutConstraint.activate([
            self.sheetView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            self.sheetView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            self.sheetView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            heightConstraint
        ])

        let grabber = UIView()
        grabber.translatesAutoresizingMaskIntoConstraints = false
        grabber.backgroundColor = theme.itemSecondaryTextColor.withAlphaComponent(0.35)
        grabber.layer.cornerRadius = 2.5
        self.sheetView.addSubview(grabber)
        NSLayoutConstraint.activate([
            grabber.topAnchor.constraint(equalTo: self.sheetView.topAnchor, constant: 9.0),
            grabber.centerXAnchor.constraint(equalTo: self.sheetView.centerXAnchor),
            grabber.widthAnchor.constraint(equalToConstant: 34.0),
            grabber.heightAnchor.constraint(equalToConstant: 5.0)
        ])

        self.scrollView.translatesAutoresizingMaskIntoConstraints = false
        self.scrollView.alwaysBounceVertical = true
        self.scrollView.showsVerticalScrollIndicator = false
        self.scrollView.keyboardDismissMode = .interactive
        self.sheetView.addSubview(self.scrollView)
        NSLayoutConstraint.activate([
            self.scrollView.leadingAnchor.constraint(equalTo: self.sheetView.leadingAnchor),
            self.scrollView.trailingAnchor.constraint(equalTo: self.sheetView.trailingAnchor),
            self.scrollView.topAnchor.constraint(equalTo: self.sheetView.topAnchor, constant: 18.0),
            self.scrollView.bottomAnchor.constraint(equalTo: self.sheetView.bottomAnchor)
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
        self.stackView.spacing = 12.0
        self.contentView.addSubview(self.stackView)
        NSLayoutConstraint.activate([
            self.stackView.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 20.0),
            self.stackView.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -20.0),
            self.stackView.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 6.0),
            self.stackView.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor, constant: -22.0)
        ])

        self.stackView.addArrangedSubview(self.makeHeader(primaryColor: theme.itemPrimaryTextColor, secondaryColor: theme.itemSecondaryTextColor))
        self.stackView.addArrangedSubview(self.makePreview(primaryColor: theme.itemPrimaryTextColor, secondaryColor: theme.itemSecondaryTextColor, cardColor: theme.itemBlocksBackgroundColor))

        self.stackView.setCustomSpacing(18.0, after: self.stackView.arrangedSubviews.last!)
        self.stackView.addArrangedSubview(self.makeFieldTitle("Номер", color: theme.itemPrimaryTextColor))
        self.configureField(self.numberField, placeholder: "+888 0000 0000", keyboard: .numbersAndPunctuation, theme: theme)
        self.stackView.addArrangedSubview(self.numberField)

        self.stackView.setCustomSpacing(16.0, after: self.numberField)
        self.stackView.addArrangedSubview(self.makeFieldTitle("Дата покупки", color: theme.itemPrimaryTextColor))
        self.datePicker.datePickerMode = .date
        self.datePicker.maximumDate = Date()
        self.datePicker.tintColor = pampGramNumberAccent
        if #available(iOS 13.4, *) {
            self.datePicker.preferredDatePickerStyle = .compact
        }
        self.datePicker.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let datePickerRow = UIView()
        datePickerRow.addSubview(self.datePicker)
        self.datePicker.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            self.datePicker.leadingAnchor.constraint(equalTo: datePickerRow.leadingAnchor),
            self.datePicker.topAnchor.constraint(equalTo: datePickerRow.topAnchor),
            self.datePicker.bottomAnchor.constraint(equalTo: datePickerRow.bottomAnchor),
            self.datePicker.trailingAnchor.constraint(lessThanOrEqualTo: datePickerRow.trailingAnchor)
        ])
        self.datePicker.addTarget(self, action: #selector(self.dateChanged), for: .valueChanged)
        self.stackView.addArrangedSubview(datePickerRow)

        self.stackView.setCustomSpacing(16.0, after: datePickerRow)
        self.stackView.addArrangedSubview(self.makeFieldTitle("Цена, 💎 TON", color: theme.itemPrimaryTextColor))
        self.configureField(self.tonField, placeholder: "например, 12,5", keyboard: .numbersAndPunctuation, theme: theme)
        self.stackView.addArrangedSubview(self.tonField)

        self.stackView.setCustomSpacing(16.0, after: self.tonField)
        self.stackView.addArrangedSubview(self.makeFieldTitle("Цена, $ USD", color: theme.itemPrimaryTextColor))
        self.configureField(self.usdField, placeholder: "например, 45,00", keyboard: .numbersAndPunctuation, theme: theme)
        self.stackView.addArrangedSubview(self.usdField)

        self.stackView.setCustomSpacing(18.0, after: self.usdField)
        self.configurePillButton(self.displayButton, title: "Показывать в профиле: выкл", primary: false)
        self.displayButton.addTarget(self, action: #selector(self.toggleDisplay), for: .touchUpInside)
        self.displayButton.heightAnchor.constraint(equalToConstant: 46.0).isActive = true
        self.stackView.addArrangedSubview(self.displayButton)

        self.configurePillButton(self.saveButton, title: "Сохранить", primary: true)
        self.saveButton.addTarget(self, action: #selector(self.savePressed), for: .touchUpInside)
        self.saveButton.heightAnchor.constraint(equalToConstant: 52.0).isActive = true
        self.stackView.addArrangedSubview(self.saveButton)

        self.updatePreview()
    }

    private func makeHeader(primaryColor: UIColor, secondaryColor: UIColor) -> UIView {
        let container = UIView()
        container.heightAnchor.constraint(equalToConstant: 53.0).isActive = true

        let titleLabel = self.makeLabel("Анонимный номер", font: .systemFont(ofSize: 27.0, weight: .bold), color: primaryColor)
        container.addSubview(titleLabel)
        self.subtitleLabel.font = .systemFont(ofSize: 15.0, weight: .regular)
        self.subtitleLabel.textColor = secondaryColor
        self.subtitleLabel.text = "коллекционный номер Fragment"
        self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(self.subtitleLabel)

        let closeButton = UIButton(type: .system)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.tintColor = secondaryColor
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.addTarget(self, action: #selector(self.closePressed), for: .touchUpInside)
        container.addSubview(closeButton)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor),
            self.subtitleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            self.subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 0.0),
            self.subtitleLabel.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),
            closeButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            closeButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 44.0),
            closeButton.heightAnchor.constraint(equalToConstant: 44.0),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -10.0)
        ])
        return container
    }

    private func makePreview(primaryColor: UIColor, secondaryColor: UIColor, cardColor: UIColor) -> UIView {
        let card = UIView()
        card.backgroundColor = cardColor
        card.layer.cornerRadius = 20.0
        card.heightAnchor.constraint(equalToConstant: 84.0).isActive = true

        let iconView = UIImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = pampGramNumberAccent
        iconView.image = UIImage(systemName: "phone.badge.checkmark")
        card.addSubview(iconView)

        self.previewNumberLabel.translatesAutoresizingMaskIntoConstraints = false
        self.previewNumberLabel.font = .systemFont(ofSize: 21.0, weight: .bold)
        self.previewNumberLabel.textColor = primaryColor
        card.addSubview(self.previewNumberLabel)

        self.previewDetailsLabel.translatesAutoresizingMaskIntoConstraints = false
        self.previewDetailsLabel.font = .systemFont(ofSize: 14.0, weight: .regular)
        self.previewDetailsLabel.textColor = secondaryColor
        self.previewDetailsLabel.numberOfLines = 2
        card.addSubview(self.previewDetailsLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18.0),
            iconView.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 40.0),
            iconView.heightAnchor.constraint(equalToConstant: 40.0),
            self.previewNumberLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 15.0),
            self.previewNumberLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 16.0),
            self.previewNumberLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16.0),
            self.previewDetailsLabel.leadingAnchor.constraint(equalTo: self.previewNumberLabel.leadingAnchor),
            self.previewDetailsLabel.topAnchor.constraint(equalTo: self.previewNumberLabel.bottomAnchor, constant: 3.0),
            self.previewDetailsLabel.trailingAnchor.constraint(equalTo: self.previewNumberLabel.trailingAnchor)
        ])
        return card
    }

    private func makeFieldTitle(_ text: String, color: UIColor) -> UILabel {
        return self.makeLabel(text, font: .systemFont(ofSize: 17.0, weight: .medium), color: color)
    }

    private func makeLabel(_ text: String, font: UIFont, color: UIColor) -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.font = font
        label.textColor = color
        return label
    }

    private func configureField(_ field: UITextField, placeholder: String, keyboard: UIKeyboardType, theme: PresentationThemeList) {
        field.translatesAutoresizingMaskIntoConstraints = false
        field.placeholder = placeholder
        field.font = .systemFont(ofSize: 18.0, weight: .regular)
        field.textColor = theme.itemPrimaryTextColor
        field.keyboardType = keyboard
        field.delegate = self
        field.borderStyle = .none
        field.backgroundColor = theme.itemBlocksBackgroundColor
        field.layer.cornerRadius = 12.0
        field.heightAnchor.constraint(equalToConstant: 46.0).isActive = true
        let padding = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 14.0, height: 46.0))
        field.leftView = padding
        field.leftViewMode = .always
        field.clearButtonMode = .whileEditing
        field.returnKeyType = .done
        field.addTarget(self, action: #selector(self.fieldEditingChanged), for: .editingChanged)
    }

    private func configurePillButton(_ button: UIButton, title: String, primary: Bool) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18.0, weight: .semibold)
        button.layer.cornerRadius = primary ? 26.0 : 23.0
        button.backgroundColor = primary ? pampGramNumberAccent : pampGramNumberAccent.withAlphaComponent(0.14)
        button.setTitleColor(primary ? .white : pampGramNumberAccent, for: .normal)
    }

    private func applyInitialState(_ state: PampGramProfileVisualState) {
        guard !self.didLoadInitialState else {
            return
        }
        self.didLoadInitialState = true
        self.numberField.text = state.anonymousNumber
        self.datePicker.date = Date(timeIntervalSince1970: TimeInterval(state.anonymousNumberPurchasedAt))
        if state.anonymousNumberPriceTonNanos > 0 {
            self.tonField.text = self.trimDecimal(Double(state.anonymousNumberPriceTonNanos) / 1_000_000_000.0)
        }
        if state.anonymousNumberPriceUsdCents > 0 {
            self.usdField.text = self.trimDecimal(Double(state.anonymousNumberPriceUsdCents) / 100.0)
        }
        self.showInProfile = state.anonymousNumberEnabled
        self.updatePreview()
    }

    @objc private func backgroundTapped(_ recognizer: UITapGestureRecognizer) {
        let location = recognizer.location(in: self.displayNode.view)
        if !self.sheetView.frame.contains(location) {
            self.dismiss(animated: true, completion: nil)
        } else {
            self.displayNode.view.endEditing(true)
        }
    }

    @objc private func closePressed() {
        self.dismiss(animated: true, completion: nil)
    }

    @objc private func dateChanged() {
        self.updatePreview()
    }

    @objc private func toggleDisplay() {
        self.showInProfile.toggle()
        self.updatePreview()
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        self.activeField = textField
        DispatchQueue.main.async { [weak self] in
            self?.scrollActiveFieldToVisible()
        }
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        if self.activeField === textField {
            self.activeField = nil
        }
        self.updatePreview()
    }

    @objc private func fieldEditingChanged() {
        self.updatePreview()
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        // The number field accepts free-form input ("+888 0000 0000"); only the two price fields
        // are constrained to a decimal amount: digits plus a single "." or "," separator, capped
        // at 10 digits total so the value stays a sensible visual price.
        guard textField === self.tonField || textField === self.usdField else {
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
        var digitCount = 0
        var separatorCount = 0
        for scalar in updatedText.unicodeScalars {
            if CharacterSet.decimalDigits.contains(scalar) {
                digitCount += 1
            } else if separators.contains(scalar) {
                separatorCount += 1
            } else {
                return false
            }
        }
        if digitCount > 10 || separatorCount > 1 {
            return false
        }
        return true
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        self.updatePreview()
        return true
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let endFrame = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else {
            return
        }
        let rootView = self.displayNode.view
        let keyboardFrameInView = rootView.convert(endFrame, from: nil)
        let overlap = max(0.0, rootView.bounds.maxY - keyboardFrameInView.minY)
        self.keyboardInset = overlap
        self.scrollView.contentInset.bottom = overlap
        self.scrollView.verticalScrollIndicatorInsets.bottom = overlap
        self.scrollActiveFieldToVisible()
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        self.keyboardInset = 0.0
        self.scrollView.contentInset.bottom = 0.0
        self.scrollView.verticalScrollIndicatorInsets.bottom = 0.0
    }

    private func scrollActiveFieldToVisible() {
        guard let field = self.activeField else {
            return
        }
        let fieldFrame = field.convert(field.bounds, to: self.contentView)
        let target = fieldFrame.insetBy(dx: 0.0, dy: -18.0)
        self.scrollView.scrollRectToVisible(target, animated: true)
    }

    @objc private func savePressed() {
        let number = (self.numberField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let finalNumber = number.isEmpty ? PampGramProfileVisualState.default.anonymousNumber : number
        let purchasedAt = Int32(self.datePicker.date.timeIntervalSince1970)
        let tonNanos = self.parseTonNanos(self.tonField.text)
        let usdCents = self.parseUsdCents(self.usdField.text)
        let shouldShow = self.showInProfile
        let _ = self.context.account.postbox.transaction { transaction -> Void in
            PampGramProfileVisualStore.update(transaction: transaction, { state in
                var state = state
                state.anonymousNumber = finalNumber
                state.anonymousNumberPurchasedAt = purchasedAt
                state.anonymousNumberPriceTonNanos = tonNanos
                state.anonymousNumberPriceUsdCents = usdCents
                state.anonymousNumberEnabled = shouldShow
                return state
            })
        }.start()
        self.dismiss(animated: true, completion: nil)
    }

    private func updatePreview() {
        let number = (self.numberField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.previewNumberLabel.text = number.isEmpty ? PampGramProfileVisualState.default.anonymousNumber : number

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateStyle = .long
        let dateText = formatter.string(from: self.datePicker.date)

        var priceParts: [String] = []
        let tonNanos = self.parseTonNanos(self.tonField.text)
        if tonNanos > 0 {
            priceParts.append("💎 \(self.trimDecimal(Double(tonNanos) / 1_000_000_000.0))")
        }
        let usdCents = self.parseUsdCents(self.usdField.text)
        if usdCents > 0 {
            priceParts.append(String(format: "$%.2f", Double(usdCents) / 100.0))
        }
        let priceText = priceParts.isEmpty ? "цена не указана" : priceParts.joined(separator: " · ")
        self.previewDetailsLabel.text = "Fragment · \(dateText)\n\(priceText)"

        let displayText = self.showInProfile ? "Показывать в профиле: вкл" : "Показывать в профиле: выкл"
        self.displayButton.setTitle(displayText, for: .normal)
        self.displayButton.backgroundColor = self.showInProfile ? pampGramNumberAccent : pampGramNumberAccent.withAlphaComponent(0.14)
        self.displayButton.setTitleColor(self.showInProfile ? .white : pampGramNumberAccent, for: .normal)
    }

    private func parseTonNanos(_ text: String?) -> Int64 {
        guard let value = self.parseDecimal(text), value > 0 else {
            return 0
        }
        return Int64((value * 1_000_000_000.0).rounded())
    }

    private func parseUsdCents(_ text: String?) -> Int64 {
        guard let value = self.parseDecimal(text), value > 0 else {
            return 0
        }
        return Int64((value * 100.0).rounded())
    }

    private func parseDecimal(_ text: String?) -> Double? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        return Double(text.replacingOccurrences(of: ",", with: "."))
    }

    private func trimDecimal(_ value: Double) -> String {
        if value == value.rounded() {
            return String(format: "%.0f", value)
        }
        return String(format: "%g", value)
    }
}

func pampGramProfileNumberEditorController(context: AccountContext) -> ViewController {
    return PampGramProfileNumberEditorController(context: context)
}
