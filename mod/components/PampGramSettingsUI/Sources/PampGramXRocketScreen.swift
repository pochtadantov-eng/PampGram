import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramPresentationData
import AccountContext
import PampGramCore
import UndoUI

/// Visual xRocket deposit flow. Pretends to send TON from an xRocket
/// wallet (balance stored locally in UserDefaults) into Portals' GRAM
/// balance (fakeTonBalanceNanos). The transfer debits the UserDefaults
/// balance and credits fakeTonBalanceNanos via
/// PampGramLocalLedgerStore.addAndApply so it also shows up in the local
/// "История и статистика" as a .topUp. Nothing touches the network and
/// nothing talks to the real xRocket; the screen is a visual mini-app
/// to pair with Portals Market.
public func pampGramXRocketController(context: AccountContext) -> ViewController {
    return PampGramXRocketControllerImpl(context: context)
}

// UserDefaults is used instead of adding another field to PampGramSettings
// because the xRocket balance is only interesting to the Portals screen —
// everything else in PampGram doesn't care about it.
private let XROCKET_BALANCE_KEY = "pampgram.xrocket.ton.nanos"
private let XROCKET_DEFAULT_NANOS: Int64 = 1_250_500_000_000  // 1250.5 TON

private enum XRocketPalette {
    static let surface   = UIColor(white: 0.043, alpha: 1.0)
    static let elevated  = UIColor(white: 0.078, alpha: 1.0)
    static let accent    = UIColor(red: 0.10, green: 0.79, blue: 1.00, alpha: 1.0)
    static let heroStart = UIColor(red: 0.29, green: 0.17, blue: 0.82, alpha: 1.0)
    static let heroMid   = UIColor(red: 0.08, green: 0.38, blue: 1.00, alpha: 1.0)
    static let heroEnd   = UIColor(red: 0.05, green: 0.25, blue: 0.65, alpha: 1.0)
    static let muted     = UIColor(white: 1.0, alpha: 0.6)
    static let dim       = UIColor(white: 1.0, alpha: 0.4)
    static let stroke    = UIColor(white: 1.0, alpha: 0.08)
}

private final class PampGramXRocketControllerImpl: ViewController {
    private let context: AccountContext
    private let presentationData: PresentationData
    private var contentNode: PampGramXRocketNode?

    init(context: AccountContext) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }

        let navTheme = NavigationBarTheme(
            buttonColor: .white,
            disabledButtonColor: UIColor(white: 1.0, alpha: 0.5),
            primaryTextColor: .white,
            backgroundColor: XRocketPalette.surface,
            enableBackgroundBlur: false,
            separatorColor: UIColor(white: 1.0, alpha: 0.08),
            badgeBackgroundColor: XRocketPalette.accent,
            badgeStrokeColor: XRocketPalette.accent,
            badgeTextColor: .black
        )
        super.init(navigationBarPresentationData: NavigationBarPresentationData(
            theme: navTheme,
            strings: NavigationBarStrings(presentationStrings: self.presentationData.strings)
        ))

        self.statusBar.statusBarStyle = .White
        self.title = "xRocket"
        self.navigationItem.backBarButtonItem = UIBarButtonItem(
            title: self.presentationData.strings.Common_Back, style: .plain, target: nil, action: nil)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadDisplayNode() {
        self.displayNode = ViewControllerTracingNode()
        self.displayNode.backgroundColor = XRocketPalette.surface

        let node = PampGramXRocketNode(context: self.context, present: { [weak self] controller in
            self?.present(controller, in: .window(.root))
        }, dismiss: { [weak self] in
            self?.dismiss()
        })
        self.contentNode = node
        self.displayNode.view.addSubview(node)
        self.displayNodeDidLoad()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let navHeight: CGFloat = 44.0
        let topInset = (layout.statusBarHeight ?? 20.0) + navHeight
        self.contentNode?.frame = CGRect(origin: .zero, size: layout.size)
        self.contentNode?.updateLayout(size: layout.size, topInset: topInset, bottomInset: layout.intrinsicInsets.bottom)
    }
}

private final class PampGramXRocketNode: UIView {
    private let context: AccountContext
    private let present: (ViewController) -> Void
    private let dismissAction: () -> Void

    private let scrollView = UIScrollView()
    private let contentView = UIStackView()

    private var rocketBalanceNanos: Int64 = 0
    private var pendingNanos: Int64 = 0

    // Views held as fields so refresh() can update them in place.
    private var tonValueLabel: UILabel!
    private var usdtValueLabel: UILabel!
    private var sendValueLabel: UILabel!
    private var receiveValueLabel: UILabel!
    private var sendButton: UIControl!
    private var sendButtonSubLabel: UILabel!
    private var chipButtons: [UIButton] = []
    private var customInput: UITextField!

    // 1 TON = 3.85 USDT, frozen for the mock. The real xRocket rate wobbles.
    private static let TON_USDT_RATE: Double = 3.85

    init(context: AccountContext, present: @escaping (ViewController) -> Void, dismiss: @escaping () -> Void) {
        self.context = context
        self.present = present
        self.dismissAction = dismiss
        self.rocketBalanceNanos = Self.readBalance()
        super.init(frame: .zero)
        self.backgroundColor = XRocketPalette.surface

        self.scrollView.showsVerticalScrollIndicator = false
        self.scrollView.contentInsetAdjustmentBehavior = .never
        self.scrollView.keyboardDismissMode = .interactive
        self.addSubview(self.scrollView)

        self.contentView.axis = .vertical
        self.contentView.spacing = 0
        self.contentView.alignment = .fill
        self.scrollView.addSubview(self.contentView)

        self.buildContent()
        self.refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - UserDefaults-backed balance

    static func readBalance() -> Int64 {
        let d = UserDefaults.standard
        if let number = d.object(forKey: XROCKET_BALANCE_KEY) as? NSNumber {
            return number.int64Value
        }
        d.set(NSNumber(value: XROCKET_DEFAULT_NANOS), forKey: XROCKET_BALANCE_KEY)
        return XROCKET_DEFAULT_NANOS
    }

    static func writeBalance(_ nanos: Int64) {
        UserDefaults.standard.set(NSNumber(value: nanos), forKey: XROCKET_BALANCE_KEY)
    }

    // MARK: - Layout

    func updateLayout(size: CGSize, topInset: CGFloat, bottomInset: CGFloat) {
        self.scrollView.frame = CGRect(origin: .zero, size: size)
        self.scrollView.contentInset = UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset + 24, right: 0)
        let width = size.width
        let h = self.contentView.systemLayoutSizeFitting(
            CGSize(width: width, height: .greatestFiniteMagnitude),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        self.contentView.frame = CGRect(origin: .zero, size: CGSize(width: width, height: h))
        self.scrollView.contentSize = CGSize(width: width, height: h)
    }

    // MARK: - Content tree

    private func buildContent() {
        self.contentView.addArrangedSubview(self.buildHero())

        let padded = UIView()
        padded.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 20, leading: 16, bottom: 16, trailing: 16)

        let column = UIStackView()
        column.axis = .vertical
        column.spacing = 14
        column.translatesAutoresizingMaskIntoConstraints = false

        column.addArrangedSubview(self.sectionLabel("Сумма перевода (TON → GRAM)"))
        column.addArrangedSubview(self.buildChipsRow())
        column.addArrangedSubview(self.buildCustomInputRow())
        column.addArrangedSubview(self.buildReceipt())
        column.addArrangedSubview(self.buildSendButton())
        column.addArrangedSubview(self.buildFooter())

        padded.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: padded.layoutMarginsGuide.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: padded.layoutMarginsGuide.trailingAnchor),
            column.topAnchor.constraint(equalTo: padded.layoutMarginsGuide.topAnchor),
            column.bottomAnchor.constraint(equalTo: padded.layoutMarginsGuide.bottomAnchor)
        ])
        self.contentView.addArrangedSubview(padded)
    }

    private func buildHero() -> UIView {
        // Reuses the gradient view declared in PampGramPortalsScreen.swift (same module).
        let hero = PortalsGradientView(colors: [XRocketPalette.heroStart, XRocketPalette.heroMid, XRocketPalette.heroEnd], horizontal: true)

        let logo = UILabel()
        logo.text = "💎"
        logo.font = .systemFont(ofSize: 24)
        logo.textAlignment = .center
        logo.backgroundColor = UIColor(white: 1.0, alpha: 0.18)
        logo.layer.cornerRadius = 14
        logo.clipsToBounds = true
        logo.translatesAutoresizingMaskIntoConstraints = false
        logo.widthAnchor.constraint(equalToConstant: 48).isActive = true
        logo.heightAnchor.constraint(equalToConstant: 48).isActive = true

        let title = UILabel()
        title.text = "Rocket · Pay"
        title.font = .systemFont(ofSize: 18, weight: .bold)
        title.textColor = .white
        let subtitle = UILabel()
        subtitle.text = "Отправить TON в Portals Market"
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = UIColor(white: 1.0, alpha: 0.85)
        let brandLabels = UIStackView(arrangedSubviews: [title, subtitle])
        brandLabels.axis = .vertical
        brandLabels.spacing = 2
        brandLabels.alignment = .leading

        let brandStack = UIStackView(arrangedSubviews: [logo, brandLabels])
        brandStack.axis = .horizontal
        brandStack.spacing = 14
        brandStack.alignment = .center
        brandStack.translatesAutoresizingMaskIntoConstraints = false

        let balanceCap = UILabel()
        balanceCap.text = "БАЛАНС КОШЕЛЬКА"
        balanceCap.font = .systemFont(ofSize: 11, weight: .bold)
        balanceCap.textColor = UIColor(white: 1.0, alpha: 0.75)

        self.tonValueLabel = UILabel()
        self.tonValueLabel.font = .systemFont(ofSize: 34, weight: .bold)
        self.tonValueLabel.textColor = .white

        self.usdtValueLabel = UILabel()
        self.usdtValueLabel.font = .systemFont(ofSize: 13)
        self.usdtValueLabel.textColor = UIColor(white: 1.0, alpha: 0.75)

        let balanceStack = UIStackView(arrangedSubviews: [balanceCap, self.tonValueLabel, self.usdtValueLabel])
        balanceStack.axis = .vertical
        balanceStack.spacing = 2
        balanceStack.setCustomSpacing(4, after: balanceCap)
        balanceStack.alignment = .leading
        balanceStack.translatesAutoresizingMaskIntoConstraints = false

        hero.addSubview(brandStack)
        hero.addSubview(balanceStack)
        NSLayoutConstraint.activate([
            brandStack.leadingAnchor.constraint(equalTo: hero.leadingAnchor, constant: 20),
            brandStack.topAnchor.constraint(equalTo: hero.topAnchor, constant: 22),
            brandStack.trailingAnchor.constraint(lessThanOrEqualTo: hero.trailingAnchor, constant: -20),
            balanceStack.leadingAnchor.constraint(equalTo: hero.leadingAnchor, constant: 20),
            balanceStack.topAnchor.constraint(equalTo: brandStack.bottomAnchor, constant: 22),
            balanceStack.bottomAnchor.constraint(equalTo: hero.bottomAnchor, constant: -26)
        ])
        return hero
    }

    private func sectionLabel(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text.uppercased()
        l.font = .systemFont(ofSize: 11, weight: .bold)
        l.textColor = XRocketPalette.muted
        return l
    }

    private func buildChipsRow() -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.distribution = .fillEqually
        let specs: [(String, Int)] = [("10", 1), ("50", 2), ("100", 3), ("500", 4), ("Макс", 5)]
        for (label, tag) in specs {
            let b = UIButton(type: .custom)
            b.setTitle(label, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
            b.setTitleColor(.white, for: .normal)
            b.setTitleColor(.black, for: .selected)
            b.backgroundColor = XRocketPalette.elevated
            b.layer.cornerRadius = 14
            b.layer.borderWidth = 1
            b.layer.borderColor = XRocketPalette.stroke.cgColor
            b.tag = tag
            b.heightAnchor.constraint(equalToConstant: 42).isActive = true
            b.addTarget(self, action: #selector(self.chipTapped(_:)), for: .touchUpInside)
            row.addArrangedSubview(b)
            self.chipButtons.append(b)
        }
        return row
    }

    private func buildCustomInputRow() -> UIView {
        let wrap = UIView()
        wrap.backgroundColor = XRocketPalette.elevated
        wrap.layer.cornerRadius = 14
        wrap.layer.borderWidth = 1
        wrap.layer.borderColor = XRocketPalette.stroke.cgColor
        wrap.heightAnchor.constraint(equalToConstant: 50).isActive = true

        self.customInput = UITextField()
        self.customInput.keyboardType = .decimalPad
        self.customInput.font = .systemFont(ofSize: 16)
        self.customInput.textColor = .white
        self.customInput.backgroundColor = .clear
        self.customInput.attributedPlaceholder = NSAttributedString(
            string: "Своя сумма",
            attributes: [.foregroundColor: XRocketPalette.muted])
        self.customInput.addTarget(self, action: #selector(self.customInputChanged), for: .editingChanged)
        self.customInput.translatesAutoresizingMaskIntoConstraints = false

        let unit = UILabel()
        unit.text = "TON"
        unit.font = .systemFont(ofSize: 15, weight: .bold)
        unit.textColor = XRocketPalette.muted
        unit.translatesAutoresizingMaskIntoConstraints = false

        wrap.addSubview(self.customInput)
        wrap.addSubview(unit)
        NSLayoutConstraint.activate([
            self.customInput.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 14),
            self.customInput.topAnchor.constraint(equalTo: wrap.topAnchor),
            self.customInput.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
            self.customInput.trailingAnchor.constraint(equalTo: unit.leadingAnchor, constant: -8),
            unit.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -14),
            unit.centerYAnchor.constraint(equalTo: wrap.centerYAnchor)
        ])
        return wrap
    }

    private func buildReceipt() -> UIView {
        let box = UIView()
        box.backgroundColor = XRocketPalette.elevated
        box.layer.cornerRadius = 16
        box.layer.borderWidth = 1
        box.layer.borderColor = XRocketPalette.stroke.cgColor

        self.sendValueLabel = self.makeValueLabel()
        self.receiveValueLabel = self.makeValueLabel()
        let feeValue = self.makeValueLabel()
        feeValue.text = "0 TON"

        let col = UIStackView()
        col.axis = .vertical
        col.spacing = 2
        col.isLayoutMarginsRelativeArrangement = true
        col.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
        col.translatesAutoresizingMaskIntoConstraints = false

        col.addArrangedSubview(self.receiptRow(key: "Вы отправляете", valueView: self.sendValueLabel))
        col.addArrangedSubview(self.receiptRow(key: "Комиссия сети",  valueView: feeValue))
        col.addArrangedSubview(self.receiptRow(key: "Portals получит", valueView: self.receiveValueLabel))

        box.addSubview(col)
        NSLayoutConstraint.activate([
            col.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            col.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            col.topAnchor.constraint(equalTo: box.topAnchor),
            col.bottomAnchor.constraint(equalTo: box.bottomAnchor)
        ])
        return box
    }

    private func makeValueLabel() -> UILabel {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14, weight: .bold)
        l.textColor = .white
        l.textAlignment = .right
        return l
    }

    private func receiptRow(key: String, valueView: UILabel) -> UIView {
        let k = UILabel()
        k.text = key
        k.font = .systemFont(ofSize: 13)
        k.textColor = XRocketPalette.muted

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [k, spacer, valueView])
        row.axis = .horizontal
        row.distribution = .fill
        row.alignment = .center
        row.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return row
    }

    private func buildSendButton() -> UIView {
        let btn = UIControl()
        btn.backgroundColor = XRocketPalette.accent
        btn.layer.cornerRadius = 22
        btn.heightAnchor.constraint(equalToConstant: 64).isActive = true

        let top = UILabel()
        top.text = "Отправить в Portals"
        top.font = .systemFont(ofSize: 16, weight: .bold)
        top.textColor = .black
        top.textAlignment = .center

        self.sendButtonSubLabel = UILabel()
        self.sendButtonSubLabel.text = "выберите сумму"
        self.sendButtonSubLabel.font = .systemFont(ofSize: 13)
        self.sendButtonSubLabel.textColor = UIColor(white: 0.0, alpha: 0.75)
        self.sendButtonSubLabel.textAlignment = .center

        let col = UIStackView(arrangedSubviews: [top, self.sendButtonSubLabel])
        col.axis = .vertical
        col.spacing = 2
        col.alignment = .center
        col.isUserInteractionEnabled = false
        col.translatesAutoresizingMaskIntoConstraints = false

        btn.addSubview(col)
        NSLayoutConstraint.activate([
            col.centerXAnchor.constraint(equalTo: btn.centerXAnchor),
            col.centerYAnchor.constraint(equalTo: btn.centerYAnchor)
        ])
        btn.addTarget(self, action: #selector(self.sendTapped), for: .touchUpInside)
        self.sendButton = btn
        return btn
    }

    private func buildFooter() -> UIView {
        let l = UILabel()
        l.text = "1 TON ≈ 1 GRAM (визуально). xRocket тоже локальный — ничего не уходит на сервер."
        l.font = .systemFont(ofSize: 11)
        l.textColor = XRocketPalette.dim
        l.textAlignment = .center
        l.numberOfLines = 0
        return l
    }

    // MARK: - Formatting

    private static func formatGram(_ nanos: Int64) -> String {
        let v = Double(nanos) / 1_000_000_000.0
        if abs(v - v.rounded()) < 0.005 {
            return String(format: "%.0f", v)
        }
        if abs(v * 10 - (v * 10).rounded()) < 0.005 {
            return String(format: "%.1f", v)
        }
        return String(format: "%.2f", v)
    }

    private static func formatUsdt(_ ton: Double) -> String {
        return String(format: "%.2f", ton * TON_USDT_RATE)
    }

    // MARK: - State

    private func refresh() {
        let ton = Double(self.rocketBalanceNanos) / 1_000_000_000.0
        self.tonValueLabel.text = "\(Self.formatGram(self.rocketBalanceNanos)) TON"
        self.usdtValueLabel.text = "≈ \(Self.formatUsdt(ton)) USDT"
        self.updateReceipt()
    }

    private func setPending(nanos requested: Int64, chipTag: Int, keepInput: Bool) {
        self.pendingNanos = max(0, min(requested, self.rocketBalanceNanos))
        for b in self.chipButtons {
            let active = (b.tag == chipTag)
            b.isSelected = active
            b.backgroundColor = active ? XRocketPalette.accent : XRocketPalette.elevated
            b.layer.borderColor = active ? UIColor.clear.cgColor : XRocketPalette.stroke.cgColor
        }
        if !keepInput {
            self.customInput.text = self.pendingNanos > 0 ? Self.formatGram(self.pendingNanos) : ""
        }
        self.updateReceipt()
    }

    private func updateReceipt() {
        self.sendValueLabel.text = "\(Self.formatGram(self.pendingNanos)) TON"
        self.receiveValueLabel.text = "\(Self.formatGram(self.pendingNanos)) GRAM"
        let ok = self.pendingNanos > 0
        self.sendButton.isEnabled = ok
        self.sendButton.alpha = ok ? 1.0 : 0.5
        self.sendButtonSubLabel.text = ok
            ? "\(Self.formatGram(self.pendingNanos)) TON → +\(Self.formatGram(self.pendingNanos)) GRAM"
            : "выберите сумму"
    }

    // MARK: - Actions

    @objc private func chipTapped(_ sender: UIButton) {
        let presetByTag: [Int: Int64] = [
            1: 10_000_000_000,
            2: 50_000_000_000,
            3: 100_000_000_000,
            4: 500_000_000_000
        ]
        if sender.tag == 5 {
            self.setPending(nanos: self.rocketBalanceNanos, chipTag: 5, keepInput: false)
        } else if let nanos = presetByTag[sender.tag] {
            self.setPending(nanos: nanos, chipTag: sender.tag, keepInput: false)
        }
        self.customInput.resignFirstResponder()
    }

    @objc private func customInputChanged() {
        let raw = (self.customInput.text ?? "").replacingOccurrences(of: ",", with: ".")
        let value = Double(raw) ?? 0
        let nanos = Int64((value * 1_000_000_000.0).rounded())
        // Chip tag 6 = "custom input" — no chip highlighted while typing.
        self.setPending(nanos: nanos, chipTag: 6, keepInput: true)
    }

    @objc private func sendTapped() {
        guard self.pendingNanos > 0, self.pendingNanos <= self.rocketBalanceNanos else { return }
        let amount = self.pendingNanos
        self.customInput.resignFirstResponder()
        let amountText = "\(Self.formatGram(amount)) TON"
        let confirm = UIAlertController(
            title: "Отправить \(amountText)?",
            message: "С кошелька xRocket спишется \(amountText) и зачислится как \(Self.formatGram(amount)) GRAM в баланс Portals.",
            preferredStyle: .alert)
        confirm.addAction(UIAlertAction(title: "Отправить", style: .default, handler: { [weak self] _ in
            self?.commit(amount: amount)
        }))
        confirm.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        self.presentUIKitAlert(confirm)
    }

    private func commit(amount: Int64) {
        self.rocketBalanceNanos = max(0, self.rocketBalanceNanos - amount)
        Self.writeBalance(self.rocketBalanceNanos)
        let _ = (self.context.account.postbox.transaction { tx in
            PampGramLocalLedgerStore.addAndApply(transaction: tx, currency: .ton,
                kind: .topUp, amount: amount,
                title: "Пополнение из xRocket",
                details: "\(Self.formatGram(amount)) TON")
        } |> deliverOnMainQueue).start(completed: { [weak self] in
            guard let self else { return }
            self.refresh()
            self.setPending(nanos: 0, chipTag: 0, keepInput: false)
            let pd = self.context.sharedContext.currentPresentationData.with { $0 }
            let toast = UndoOverlayController(presentationData: pd,
                content: .info(title: nil, text: "+\(Self.formatGram(amount)) GRAM с xRocket", timeout: nil, customUndoText: nil),
                elevatedLayout: false, action: { _ in return false })
            self.present(toast)
            self.dismissAction()
        })
    }

    private func presentUIKitAlert(_ alert: UIAlertController) {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let vc = next as? UIViewController {
                vc.present(alert, animated: true)
                return
            }
            responder = next
        }
    }
}
