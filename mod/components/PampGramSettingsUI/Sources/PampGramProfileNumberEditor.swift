import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import Postbox
import TelegramPresentationData
import AccountContext
import PampGramCore

/// Local-only editor for the visual anonymous "+888" number — full-screen, "liquid glass" style.
/// Writes into PampGram's Postbox preferences only on save; nothing here queries Fragment or changes
/// Telegram's real phone number on the server.
private final class PampGramProfileNumberEditorController: ViewController, UITextFieldDelegate {
    private let context: AccountContext
    private let presentationData: PresentationData
    private let stateDisposable = MetaDisposable()

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let stackView = UIStackView()
    private var headerTopConstraint: NSLayoutConstraint?

    private let previewNumberLabel = UILabel()
    private let previewDetailsLabel = UILabel()
    private let numberField = UITextField()
    private let datePicker = UIDatePicker()
    private let tonField = UITextField()
    private let usdField = UITextField()
    private let displaySwitch = UISwitch()

    private var primaryColor: UIColor = .label
    private var secondaryColor: UIColor = .secondaryLabel
    private weak var activeField: UITextField?

    private var showInProfile = false
    private var didLoadInitialState = false

    /// Fixed, non-editable prefix for the visual "+888" number -- the field always starts with
    /// this and typing can never remove or move past it.
    private let numberPrefix = "+888 "
    /// 3 + 4 + 4 digits, grouped by groupedDigits(_:) below. Once this many digits are entered,
    /// further digits are rejected outright -- only deleting and retyping changes the number.
    private let maxAnonymousNumberDigits = 11

    /// Which price field the user actually typed into last -- that one stays the source of
    /// truth and the other gets recomputed from it whenever the TON/USD rate arrives or the
    /// purchase date changes. Debounced via `rateSyncTimer` so a live CoinGecko request doesn't
    /// fire on every keystroke.
    private weak var lastEditedPriceField: UITextField?
    private var rateSyncTimer: Foundation.Timer?
    private var isSyncingPriceFields = false
    private var rateSyncRequestId = 0

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
        self.rateSyncTimer?.invalidate()
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

        self.stateDisposable.set((PampGramProfileVisualStore.signal(postbox: self.context.account.postbox)
        |> take(1)
        |> deliverOnMainQueue).startStrict(next: { [weak self] state in
            self?.applyInitialState(state)
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

        // Header bar.
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
        let doneButton = self.makeGlyphButton(systemName: "checkmark", action: #selector(self.savePressed))
        header.addSubview(doneButton)
        let titleLabel = self.makeLabel("Анонимный номер", font: .systemFont(ofSize: 17.0, weight: .semibold), color: self.primaryColor)
        titleLabel.textAlignment = .center
        header.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12.0),
            backButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 34.0),
            backButton.heightAnchor.constraint(equalToConstant: 34.0),
            doneButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -12.0),
            doneButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            doneButton.widthAnchor.constraint(equalToConstant: 34.0),
            doneButton.heightAnchor.constraint(equalToConstant: 34.0),
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
        self.stackView.spacing = 8.0
        self.contentView.addSubview(self.stackView)
        NSLayoutConstraint.activate([
            self.stackView.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 16.0),
            self.stackView.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -16.0),
            self.stackView.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 12.0),
            self.stackView.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor, constant: -24.0)
        ])

        self.stackView.addArrangedSubview(self.makePreviewPanel())
        self.stackView.setCustomSpacing(18.0, after: self.stackView.arrangedSubviews.last!)

        self.stackView.addArrangedSubview(self.makeSectionLabel("Номер"))
        self.configureField(self.numberField, placeholder: "+888 000 0000 0000", keyboard: .numberPad)
        self.stackView.addArrangedSubview(self.makeFieldPanel(self.numberField))
        self.stackView.setCustomSpacing(18.0, after: self.stackView.arrangedSubviews.last!)

        self.stackView.addArrangedSubview(self.makeSectionLabel("Дата покупки"))
        self.stackView.addArrangedSubview(self.makeDatePanel())
        self.stackView.setCustomSpacing(18.0, after: self.stackView.arrangedSubviews.last!)

        self.stackView.addArrangedSubview(self.makeSectionLabel("Цена, 💎 TON"))
        self.configureField(self.tonField, placeholder: "например, 12,5", keyboard: .numbersAndPunctuation)
        self.stackView.addArrangedSubview(self.makeFieldPanel(self.tonField))
        self.stackView.setCustomSpacing(18.0, after: self.stackView.arrangedSubviews.last!)

        self.stackView.addArrangedSubview(self.makeSectionLabel("Цена, $ USD"))
        self.configureField(self.usdField, placeholder: "например, 45,00", keyboard: .numbersAndPunctuation)
        self.stackView.addArrangedSubview(self.makeFieldPanel(self.usdField))
        self.stackView.setCustomSpacing(18.0, after: self.stackView.arrangedSubviews.last!)

        self.stackView.addArrangedSubview(self.makeDisplayPanel())

        self.updatePreview()
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

    private func makePreviewPanel() -> UIView {
        let panel = PampGramGlass.makePanel(cornerRadius: 20.0)
        panel.heightAnchor.constraint(equalToConstant: 84.0).isActive = true

        let iconView = UIImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = self.primaryColor
        iconView.image = UIImage(systemName: "phone.badge.checkmark")
        panel.addSubview(iconView)

        self.previewNumberLabel.translatesAutoresizingMaskIntoConstraints = false
        self.previewNumberLabel.font = .systemFont(ofSize: 21.0, weight: .bold)
        self.previewNumberLabel.textColor = self.primaryColor
        panel.addSubview(self.previewNumberLabel)

        self.previewDetailsLabel.translatesAutoresizingMaskIntoConstraints = false
        self.previewDetailsLabel.font = .systemFont(ofSize: 14.0, weight: .regular)
        self.previewDetailsLabel.textColor = self.secondaryColor
        self.previewDetailsLabel.numberOfLines = 2
        panel.addSubview(self.previewDetailsLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 18.0),
            iconView.centerYAnchor.constraint(equalTo: panel.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 38.0),
            iconView.heightAnchor.constraint(equalToConstant: 38.0),
            self.previewNumberLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 15.0),
            self.previewNumberLabel.topAnchor.constraint(equalTo: panel.topAnchor, constant: 16.0),
            self.previewNumberLabel.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16.0),
            self.previewDetailsLabel.leadingAnchor.constraint(equalTo: self.previewNumberLabel.leadingAnchor),
            self.previewDetailsLabel.topAnchor.constraint(equalTo: self.previewNumberLabel.bottomAnchor, constant: 3.0),
            self.previewDetailsLabel.trailingAnchor.constraint(equalTo: self.previewNumberLabel.trailingAnchor)
        ])
        return panel
    }

    private func makeSectionLabel(_ text: String) -> UILabel {
        let label = self.makeLabel(text, font: .systemFont(ofSize: 13.0, weight: .regular), color: self.secondaryColor)
        return label
    }

    private func makeFieldPanel(_ field: UITextField) -> UIView {
        let panel = PampGramGlass.makePanel(cornerRadius: 14.0)
        panel.heightAnchor.constraint(equalToConstant: 50.0).isActive = true
        panel.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14.0),
            field.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14.0),
            field.topAnchor.constraint(equalTo: panel.topAnchor),
            field.bottomAnchor.constraint(equalTo: panel.bottomAnchor)
        ])
        return panel
    }

    private func makeDatePanel() -> UIView {
        let panel = PampGramGlass.makePanel(cornerRadius: 14.0)
        panel.heightAnchor.constraint(equalToConstant: 50.0).isActive = true
        self.datePicker.datePickerMode = .date
        self.datePicker.maximumDate = Date()
        if #available(iOS 13.4, *) {
            self.datePicker.preferredDatePickerStyle = .compact
        }
        self.datePicker.translatesAutoresizingMaskIntoConstraints = false
        self.datePicker.addTarget(self, action: #selector(self.dateChanged), for: .valueChanged)
        panel.addSubview(self.datePicker)
        NSLayoutConstraint.activate([
            self.datePicker.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 12.0),
            self.datePicker.centerYAnchor.constraint(equalTo: panel.centerYAnchor),
            self.datePicker.trailingAnchor.constraint(lessThanOrEqualTo: panel.trailingAnchor, constant: -12.0)
        ])
        return panel
    }

    private func makeDisplayPanel() -> UIView {
        let panel = PampGramGlass.makePanel(cornerRadius: 20.0)
        panel.heightAnchor.constraint(equalToConstant: 56.0).isActive = true
        let title = self.makeLabel("Показывать в профиле", font: .systemFont(ofSize: 17.0, weight: .regular), color: self.primaryColor)
        panel.addSubview(title)
        self.displaySwitch.translatesAutoresizingMaskIntoConstraints = false
        self.displaySwitch.addTarget(self, action: #selector(self.toggleDisplay), for: .valueChanged)
        panel.addSubview(self.displaySwitch)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 18.0),
            title.centerYAnchor.constraint(equalTo: panel.centerYAnchor),
            self.displaySwitch.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16.0),
            self.displaySwitch.centerYAnchor.constraint(equalTo: panel.centerYAnchor)
        ])
        return panel
    }

    private func makeLabel(_ text: String, font: UIFont, color: UIColor) -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.font = font
        label.textColor = color
        return label
    }

    private func configureField(_ field: UITextField, placeholder: String, keyboard: UIKeyboardType) {
        field.translatesAutoresizingMaskIntoConstraints = false
        field.placeholder = placeholder
        field.font = .systemFont(ofSize: 18.0, weight: .regular)
        field.textColor = self.primaryColor
        field.keyboardType = keyboard
        field.delegate = self
        field.borderStyle = .none
        field.backgroundColor = .clear
        field.clearButtonMode = .whileEditing
        field.returnKeyType = .done
        field.addTarget(self, action: #selector(self.fieldEditingChanged(_:)), for: .editingChanged)
    }

    private func applyInitialState(_ state: PampGramProfileVisualState) {
        guard !self.didLoadInitialState else {
            return
        }
        self.didLoadInitialState = true
        self.numberField.text = self.normalizedNumberText(state.anonymousNumber)
        self.datePicker.date = Date(timeIntervalSince1970: TimeInterval(state.anonymousNumberPurchasedAt))
        if state.anonymousNumberPriceTonNanos > 0 {
            self.tonField.text = self.trimDecimal(Double(state.anonymousNumberPriceTonNanos) / 1_000_000_000.0)
        }
        if state.anonymousNumberPriceUsdCents > 0 {
            self.usdField.text = self.trimDecimal(Double(state.anonymousNumberPriceUsdCents) / 100.0)
        }
        self.showInProfile = state.anonymousNumberEnabled
        self.displaySwitch.isOn = self.showInProfile
        self.updatePreview()
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
        self.popSelf()
    }

    @objc private func dateChanged() {
        self.updatePreview()
        self.scheduleRateSync()
    }

    @objc private func toggleDisplay() {
        self.showInProfile = self.displaySwitch.isOn
    }

    @objc private func fieldEditingChanged(_ sender: UITextField) {
        self.updatePreview()
        guard !self.isSyncingPriceFields, sender === self.tonField || sender === self.usdField else {
            return
        }
        self.lastEditedPriceField = sender
        self.scheduleRateSync()
    }

    /// Debounces the actual network request: a burst of keystrokes (or a fast date-picker drag)
    /// collapses into a single CoinGecko fetch 0.6s after the user stops.
    private func scheduleRateSync() {
        self.rateSyncTimer?.invalidate()
        self.rateSyncTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            self?.performRateSync()
        }
    }

    /// Fills in the price field the user *didn't* just type into, from the other one and the
    /// TON/USD rate for the selected purchase date -- today's live rate for today, CoinGecko's
    /// historical daily rate for any other date. If neither field has a value yet, there's
    /// nothing to convert and this is a no-op.
    private func performRateSync() {
        let sourceField: UITextField
        if let lastEdited = self.lastEditedPriceField, self.parseDecimal(lastEdited.text) != nil {
            sourceField = lastEdited
        } else if self.parseDecimal(self.tonField.text) != nil {
            sourceField = self.tonField
        } else if self.parseDecimal(self.usdField.text) != nil {
            sourceField = self.usdField
        } else {
            return
        }
        guard let sourceValue = self.parseDecimal(sourceField.text), sourceValue > 0 else {
            return
        }

        self.rateSyncRequestId += 1
        let requestId = self.rateSyncRequestId
        let purchaseDate = self.datePicker.date
        let isToday = Calendar.current.isDateInToday(purchaseDate)

        let applyRate: (Double?) -> Void = { [weak self] rate in
            guard let self, self.rateSyncRequestId == requestId, let rate, rate > 0 else {
                return
            }
            self.isSyncingPriceFields = true
            if sourceField === self.tonField {
                self.usdField.text = self.trimDecimal(((sourceValue * rate) * 100.0).rounded() / 100.0)
            } else {
                self.tonField.text = self.trimDecimal(((sourceValue / rate) * 1_000_000_000.0).rounded() / 1_000_000_000.0)
            }
            self.isSyncingPriceFields = false
            self.updatePreview()
        }
        if isToday {
            PampGramTonRateService.currentRate(completion: applyRate)
        } else {
            PampGramTonRateService.historicalRate(date: purchaseDate, completion: applyRate)
        }
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        self.activeField = textField
        if textField === self.numberField, textField.text?.hasPrefix(self.numberPrefix) != true {
            textField.text = self.numberPrefix
        }
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

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if textField === self.numberField {
            return self.handleNumberFieldChange(range: range, replacementString: string)
        }
        // The two price fields accept digits plus a single "." or "," separator, up to 10 digits.
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

    /// Enforces the "+888" editor's whole contract: the "+888 " prefix can never be edited or
    /// removed, only digits 0-9 may be typed after it, and once `maxAnonymousNumberDigits` digits
    /// have been entered no more can be added -- deleting and retyping is the only way to change
    /// the number. Spaces are inserted automatically (groupedDigits(_:)), so the field's `text`
    /// is always either the bare prefix or the prefix plus a "XXX XXXX XXXX"-grouped number.
    private func handleNumberFieldChange(range: NSRange, replacementString string: String) -> Bool {
        let field = self.numberField
        let text = field.text?.hasPrefix(self.numberPrefix) == true ? field.text! : self.numberPrefix
        let prefixLength = self.numberPrefix.count

        // Never allow an edit that reaches into the fixed prefix.
        if range.location < prefixLength {
            return false
        }
        // Only digits may be typed; deletions (empty replacement) are always fine.
        if string.contains(where: { !$0.isNumber }) {
            return false
        }

        let nsText = text as NSString
        let suffix = nsText.substring(from: prefixLength)
        var rangeInSuffix = NSRange(location: range.location - prefixLength, length: range.length)
        // A single backspace landing on a formatting space we inserted would otherwise be a
        // no-op (removing the space just makes groupedDigits(_:) put it right back, since the
        // digit count didn't change) -- extend it one character back so it deletes the digit
        // before the space instead, matching how a plain (unformatted) field would behave.
        if string.isEmpty, range.length == 1, rangeInSuffix.location > 0,
           let spaceRange = Range(rangeInSuffix, in: suffix), suffix[spaceRange] == " " {
            rangeInSuffix.location -= 1
            rangeInSuffix.length += 1
        }
        guard let suffixTextRange = Range(rangeInSuffix, in: suffix) else {
            return false
        }

        // How many digits precede the edit point in the OLD suffix -- used to relocate the caret
        // after reformatting, since inserted spaces shift everything after them.
        let digitsBeforeEdit = suffix[suffix.startIndex..<suffixTextRange.lowerBound].filter { $0.isNumber }.count

        let candidateSuffix = suffix.replacingCharacters(in: suffixTextRange, with: string)
        let newDigits = String(candidateSuffix.filter { $0.isNumber })
        if newDigits.count > self.maxAnonymousNumberDigits {
            return false
        }

        let grouped = self.groupedDigits(newDigits)
        field.text = self.numberPrefix + grouped

        let caretDigitTarget = digitsBeforeEdit + string.count
        var seenDigits = 0
        var caretOffset = prefixLength
        for ch in grouped {
            if seenDigits >= caretDigitTarget {
                break
            }
            caretOffset += 1
            if ch.isNumber {
                seenDigits += 1
            }
        }
        if let caretPosition = field.position(from: field.beginningOfDocument, offset: caretOffset) {
            field.selectedTextRange = field.textRange(from: caretPosition, to: caretPosition)
        }

        self.updatePreview()
        return false
    }

    /// "XXXXXXXXXXX" -> "XXX XXXX XXXX" (3 + 4 + 4 digits); any shorter prefix of that digit
    /// count is grouped the same way, so partial input formats correctly as it's typed.
    private func groupedDigits(_ digits: String) -> String {
        var result = ""
        for (index, ch) in digits.enumerated() {
            if index == 3 || index == 7 {
                result.append(" ")
            }
            result.append(ch)
        }
        return result
    }

    /// Reformats an arbitrary stored number (older "+888 0000 0000" 4+4 layout, or anything else)
    /// into the current "+888 " + "XXX XXXX XXXX" shape, so the editor's own input rules always
    /// see text in the shape they expect once the user starts typing.
    private func normalizedNumberText(_ stored: String) -> String {
        let digits = String(stored.filter { $0.isNumber }.dropFirst(stored.hasPrefix("+888") ? 3 : 0))
        let clamped = String(digits.prefix(self.maxAnonymousNumberDigits))
        return self.numberPrefix + self.groupedDigits(clamped)
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
        self.scrollView.contentInset.bottom = overlap + 24.0
        self.scrollView.verticalScrollIndicatorInsets.bottom = overlap
        self.scrollActiveFieldToVisible()
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        self.scrollView.contentInset.bottom = 24.0
        self.scrollView.verticalScrollIndicatorInsets.bottom = 0.0
    }

    private func scrollActiveFieldToVisible() {
        guard let field = self.activeField else {
            return
        }
        let fieldFrame = field.convert(field.bounds, to: self.contentView)
        self.scrollView.scrollRectToVisible(fieldFrame.insetBy(dx: 0.0, dy: -24.0), animated: true)
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
        self.view.endEditing(true)
        self.popSelf()
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
        // Never use "%g" here: it flips to scientific notation ("1.5e+06") and clamps to 6
        // significant digits, which mangles large TON/USD prices when the editor re-opens.
        if value == value.rounded() {
            return String(format: "%.0f", value)
        }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 9
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
    }
}

func pampGramProfileNumberEditorController(context: AccountContext) -> ViewController {
    return PampGramProfileNumberEditorController(context: context)
}
