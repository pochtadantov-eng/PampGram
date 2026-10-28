import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import Postbox
import TelegramPresentationData
import AccountContext
import UndoUI
import PampGramCore

/// "Визуальный портал": a cinematic, fully local money-transfer screen. Picks a visible
/// "source" (xRocket, CryptoBot, Wallet, Fragment, TON Space, Pay2Ton), a currency
/// (Stars/TON/рубли) and an amount, plays a portal activation animation, then credits the
/// chosen local balance via `PampGramLocalLedgerStore.addAndApply` with kind `.topUp`. The
/// row also lands in the regular PampGram history/статистика screen.
///
/// Nothing here contacts any of the named services — xRocket, Wallet, Fragment and the rest
/// are string labels and SF-Symbol glyphs the screen draws itself. The whole flow is one
/// Postbox transaction against this device's own PampGram ledger, same mechanism "Пополнение"
/// in `PampGramLedgerScreen` already uses.

public func pampGramVisualPortalController(context: AccountContext) -> ViewController {
    return PampGramVisualPortalControllerImpl(context: context)
}

private struct PampGramVisualPortalSource {
    let id: String
    let title: String
    let subtitle: String
    let systemName: String
    let primary: UIColor
    let secondary: UIColor

    static let all: [PampGramVisualPortalSource] = [
        PampGramVisualPortalSource(id: "xrocket", title: "xRocket", subtitle: "Крипта и Stars", systemName: "paperplane.fill", primary: UIColor(rgb: 0x3390ec), secondary: UIColor(rgb: 0x5ac8fa)),
        PampGramVisualPortalSource(id: "cryptobot", title: "CryptoBot", subtitle: "@CryptoBot", systemName: "bitcoinsign.circle.fill", primary: UIColor(rgb: 0xf7931a), secondary: UIColor(rgb: 0xffcc00)),
        PampGramVisualPortalSource(id: "wallet", title: "Wallet", subtitle: "@wallet", systemName: "wallet.pass.fill", primary: UIColor(rgb: 0x2aabee), secondary: UIColor(rgb: 0x8774e1)),
        PampGramVisualPortalSource(id: "fragment", title: "Fragment", subtitle: "fragment.com", systemName: "sparkles", primary: UIColor(rgb: 0x8e44ec), secondary: UIColor(rgb: 0xff2d55)),
        PampGramVisualPortalSource(id: "tonspace", title: "TON Space", subtitle: "TON-кошелёк", systemName: "diamond.fill", primary: UIColor(rgb: 0x0098ea), secondary: UIColor(rgb: 0x34c759)),
        PampGramVisualPortalSource(id: "pay2ton", title: "Pay2Ton", subtitle: "Обменник", systemName: "arrow.triangle.2.circlepath", primary: UIColor(rgb: 0xff9500), secondary: UIColor(rgb: 0xff3b30))
    ]
}

private enum PampGramPortalCurrency {
    case stars
    case ton
    case rubles

    var local: PampGramLocalCurrency {
        switch self {
        case .stars: return .stars
        case .ton: return .ton
        case .rubles: return .rubles
        }
    }

    var presets: [Double] {
        switch self {
        case .stars: return [100, 1_000, 5_000, 50_000]
        case .ton: return [0.5, 2.0, 10.0, 50.0]
        case .rubles: return [500, 2_500, 10_000, 50_000]
        }
    }

    var placeholder: String {
        switch self {
        case .stars: return "1000"
        case .ton: return "2.5"
        case .rubles: return "5000"
        }
    }

    func format(_ value: Double) -> String {
        switch self {
        case .stars:
            return "\(Int64(value.rounded())) ⭐"
        case .ton:
            return String(format: "%.4f TON", value)
        case .rubles:
            return String(format: "%.2f ₽", value)
        }
    }

    func formatBalance(storedUnits: Int64) -> String {
        switch self {
        case .stars:
            return "\(storedUnits) ⭐"
        case .ton:
            return String(format: "%.4f TON", Double(storedUnits) / 1_000_000_000.0)
        case .rubles:
            return String(format: "%.2f ₽", Double(storedUnits) / 100.0)
        }
    }

    /// Parse the user-typed amount into the smallest exact unit used by the ledger.
    func parse(_ text: String) -> Int64? {
        let normalized = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(normalized), value > 0 else {
            return nil
        }
        switch self {
        case .stars: return Int64(value.rounded())
        case .ton: return Int64((value * 1_000_000_000.0).rounded())
        case .rubles: return Int64((value * 100.0).rounded())
        }
    }
}

private final class PampGramPortalView: UIView {
    private let gradientLayer = CAGradientLayer()
    private let outerRing = CAShapeLayer()
    private let middleRing = CAShapeLayer()
    private let innerRing = CAShapeLayer()
    private let glowLayer = CAShapeLayer()
    private let coreLayer = CAShapeLayer()
    private let glyphView = UIImageView()
    private let amountLabel = UILabel()
    private let captionLabel = UILabel()

    private var currentSource: PampGramVisualPortalSource = PampGramVisualPortalSource.all[0]
    private var baseSpeed: Double = 1.0

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.gradientLayer.type = .radial
        self.gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        self.gradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        self.layer.addSublayer(self.gradientLayer)

        for ring in [self.outerRing, self.middleRing, self.innerRing] {
            ring.fillColor = UIColor.clear.cgColor
            ring.lineCap = .round
            ring.strokeStart = 0.0
            ring.strokeEnd = 0.75
            self.layer.addSublayer(ring)
        }

        self.glowLayer.fillColor = UIColor.white.withAlphaComponent(0.08).cgColor
        self.layer.addSublayer(self.glowLayer)

        self.coreLayer.fillColor = UIColor.white.withAlphaComponent(0.12).cgColor
        self.layer.addSublayer(self.coreLayer)

        self.glyphView.contentMode = .scaleAspectFit
        self.glyphView.tintColor = .white
        self.addSubview(self.glyphView)

        self.amountLabel.textAlignment = .center
        self.amountLabel.textColor = .white
        self.amountLabel.font = UIFont.systemFont(ofSize: 32.0, weight: .heavy)
        self.amountLabel.text = ""
        self.amountLabel.alpha = 0.0
        self.addSubview(self.amountLabel)

        self.captionLabel.textAlignment = .center
        self.captionLabel.textColor = UIColor.white.withAlphaComponent(0.75)
        self.captionLabel.font = UIFont.systemFont(ofSize: 13.0, weight: .medium)
        self.captionLabel.text = "Готов к переводу"
        self.addSubview(self.captionLabel)

        self.applySource(self.currentSource)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = self.bounds
        self.gradientLayer.frame = bounds

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let r1 = min(bounds.width, bounds.height) * 0.42
        let r2 = r1 * 0.78
        let r3 = r1 * 0.56
        let rCore = r1 * 0.34

        let outer = UIBezierPath(arcCenter: center, radius: r1, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        let middle = UIBezierPath(arcCenter: center, radius: r2, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        let inner = UIBezierPath(arcCenter: center, radius: r3, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        let core = UIBezierPath(arcCenter: center, radius: rCore, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        let glow = UIBezierPath(arcCenter: center, radius: r1 * 1.15, startAngle: 0, endAngle: .pi * 2, clockwise: true)

        self.outerRing.path = outer.cgPath
        self.outerRing.lineWidth = 6.0
        self.outerRing.frame = bounds
        self.middleRing.path = middle.cgPath
        self.middleRing.lineWidth = 4.0
        self.middleRing.frame = bounds
        self.innerRing.path = inner.cgPath
        self.innerRing.lineWidth = 2.5
        self.innerRing.frame = bounds
        self.coreLayer.path = core.cgPath
        self.coreLayer.frame = bounds
        self.glowLayer.path = glow.cgPath
        self.glowLayer.frame = bounds

        let glyphSize: CGFloat = 48.0
        self.glyphView.frame = CGRect(x: center.x - glyphSize / 2.0, y: center.y - glyphSize / 2.0 - 6.0, width: glyphSize, height: glyphSize)

        self.amountLabel.frame = CGRect(x: 16.0, y: bounds.maxY - 68.0, width: bounds.width - 32.0, height: 36.0)
        self.captionLabel.frame = CGRect(x: 16.0, y: bounds.maxY - 32.0, width: bounds.width - 32.0, height: 18.0)
    }

    func applySource(_ source: PampGramVisualPortalSource) {
        self.currentSource = source
        self.gradientLayer.colors = [
            source.secondary.withAlphaComponent(0.85).cgColor,
            source.primary.withAlphaComponent(0.95).cgColor,
            UIColor.black.withAlphaComponent(0.85).cgColor
        ]
        self.gradientLayer.locations = [0.0, 0.6, 1.0]
        self.outerRing.strokeColor = UIColor.white.withAlphaComponent(0.95).cgColor
        self.middleRing.strokeColor = source.secondary.withAlphaComponent(0.9).cgColor
        self.innerRing.strokeColor = UIColor.white.withAlphaComponent(0.6).cgColor

        if let image = UIImage(systemName: source.systemName) {
            self.glyphView.image = image.withTintColor(.white, renderingMode: .alwaysOriginal)
        } else {
            self.glyphView.image = nil
        }
    }

    func startIdleAnimation() {
        self.baseSpeed = 1.0
        self.addRotation(to: self.outerRing, duration: 24.0, clockwise: true, key: "pampgram.portal.outer")
        self.addRotation(to: self.middleRing, duration: 16.0, clockwise: false, key: "pampgram.portal.middle")
        self.addRotation(to: self.innerRing, duration: 10.0, clockwise: true, key: "pampgram.portal.inner")

        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.25
        pulse.toValue = 0.55
        pulse.duration = 2.4
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        self.glowLayer.add(pulse, forKey: "pampgram.portal.pulse")
    }

    func stopIdleAnimation() {
        for ring in [self.outerRing, self.middleRing, self.innerRing] {
            ring.removeAllAnimations()
        }
        self.glowLayer.removeAllAnimations()
    }

    private func addRotation(to layer: CAShapeLayer, duration: Double, clockwise: Bool, key: String) {
        layer.removeAnimation(forKey: key)
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = 0.0
        animation.toValue = (clockwise ? 1.0 : -1.0) * Double.pi * 2.0
        animation.duration = duration
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: key)
    }

    func playTransfer(currency: PampGramPortalCurrency, amountDisplay: Double, completion: @escaping () -> Void) {
        self.captionLabel.text = "Открываем портал…"

        let scaleUp = CABasicAnimation(keyPath: "transform.scale")
        scaleUp.fromValue = 1.0
        scaleUp.toValue = 1.08
        scaleUp.duration = 0.35
        scaleUp.autoreverses = true
        self.layer.add(scaleUp, forKey: "pampgram.portal.scale")

        let flash = CABasicAnimation(keyPath: "opacity")
        flash.fromValue = 0.1
        flash.toValue = 0.9
        flash.duration = 0.6
        flash.autoreverses = true
        self.glowLayer.add(flash, forKey: "pampgram.portal.flash")

        self.animateAmountLabel(currency: currency, target: amountDisplay)

        if #available(iOS 10.0, *) {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
            guard let self else {
                completion()
                return
            }
            self.captionLabel.text = "Перевод зачислен"
            if #available(iOS 10.0, *) {
                let notif = UINotificationFeedbackGenerator()
                notif.notificationOccurred(.success)
            }
            completion()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
                guard let self else { return }
                UIView.animate(withDuration: 0.35, animations: {
                    self.amountLabel.alpha = 0.0
                }, completion: { _ in
                    self.amountLabel.text = ""
                    self.captionLabel.text = "Готов к переводу"
                })
            }
        }
    }

    private func animateAmountLabel(currency: PampGramPortalCurrency, target: Double) {
        self.amountLabel.alpha = 1.0
        let steps = 24
        for step in 0 ... steps {
            let fraction = Double(step) / Double(steps)
            let eased = 1.0 - pow(1.0 - fraction, 2.5)
            let value = target * eased
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9 * fraction) { [weak self] in
                self?.amountLabel.text = "+" + currency.format(value)
            }
        }
    }
}

private final class PampGramVisualPortalControllerImpl: ViewController, UITextFieldDelegate {
    private let context: AccountContext
    private let presentationData: PresentationData
    private let settingsDisposable = MetaDisposable()

    private let scrollView = UIScrollView()
    private let portalView = PampGramPortalView(frame: .zero)
    private let sourceScroll = UIScrollView()
    private var sourceChips: [UIButton] = []

    private let currencyControl = UISegmentedControl(items: ["⭐ Stars", "💎 TON", "₽ Рубли"])
    private let amountField = UITextField()
    private let presetStack = UIStackView()
    private let balanceLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private let footerLabel = UILabel()
    private let lastTransfersLabel = UILabel()

    private var selectedSource: PampGramVisualPortalSource = PampGramVisualPortalSource.all[0]
    private var selectedCurrency: PampGramPortalCurrency = .stars
    private var currentBalance: Int64 = 0
    private var isTransferring: Bool = false
    private var cachedLayoutWidth: CGFloat = 0.0

    init(context: AccountContext) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let navigationBarPresentationData = NavigationBarPresentationData(theme: NavigationBarTheme(rootControllerTheme: self.presentationData.theme), strings: NavigationBarStrings(presentationStrings: self.presentationData.strings))
        super.init(navigationBarPresentationData: navigationBarPresentationData)

        self.title = "Визуальный портал"
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "История", style: .plain, target: self, action: #selector(self.openHistory))
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.settingsDisposable.dispose()
        NotificationCenter.default.removeObserver(self)
    }

    override func loadDisplayNode() {
        let node = ASDisplayNode()
        node.backgroundColor = self.presentationData.theme.list.blocksBackgroundColor
        self.displayNode = node
        self.displayNodeDidLoad()
        self.configure(rootView: node.view)

        NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardWillChangeFrame(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)

        self.settingsDisposable.set((combineLatest(
            PampGramCore.rawSettingsSignal(postbox: self.context.account.postbox),
            PampGramLocalLedgerStore.signal(postbox: self.context.account.postbox)
        )
        |> deliverOnMainQueue).startStrict(next: { [weak self] settings, operations in
            self?.applyState(settings: settings, operations: operations)
        }))
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let bottomInset = layout.intrinsicInsets.bottom
        let topInset = layout.insets(options: [.statusBar]).top + 44.0
        self.scrollView.frame = CGRect(origin: CGPoint(x: 0.0, y: topInset), size: CGSize(width: layout.size.width, height: max(0.0, layout.size.height - topInset)))
        self.scrollView.contentInset.bottom = bottomInset + 32.0
        self.scrollView.verticalScrollIndicatorInsets.bottom = bottomInset
        self.cachedLayoutWidth = layout.size.width
        self.layoutContent(width: layout.size.width)
    }

    private func configure(rootView: UIView) {
        let theme = self.presentationData.theme
        rootView.backgroundColor = theme.list.blocksBackgroundColor

        self.scrollView.alwaysBounceVertical = true
        self.scrollView.keyboardDismissMode = .onDrag
        rootView.addSubview(self.scrollView)

        self.portalView.layer.cornerRadius = 24.0
        self.portalView.layer.masksToBounds = true
        self.scrollView.addSubview(self.portalView)
        self.portalView.applySource(self.selectedSource)
        self.portalView.startIdleAnimation()

        self.sourceScroll.showsHorizontalScrollIndicator = false
        self.sourceScroll.alwaysBounceHorizontal = true
        self.scrollView.addSubview(self.sourceScroll)
        self.buildSourceChips()

        self.currencyControl.selectedSegmentIndex = 0
        self.currencyControl.addTarget(self, action: #selector(self.currencyChanged), for: .valueChanged)
        self.scrollView.addSubview(self.currencyControl)

        self.amountField.borderStyle = .roundedRect
        self.amountField.keyboardType = .decimalPad
        self.amountField.placeholder = self.selectedCurrency.placeholder
        self.amountField.font = UIFont.monospacedDigitSystemFont(ofSize: 24.0, weight: .semibold)
        self.amountField.textAlignment = .center
        self.amountField.delegate = self
        self.amountField.returnKeyType = .done
        self.scrollView.addSubview(self.amountField)

        self.presetStack.axis = .horizontal
        self.presetStack.distribution = .fillEqually
        self.presetStack.spacing = 8.0
        self.scrollView.addSubview(self.presetStack)
        self.rebuildPresetButtons()

        self.balanceLabel.textAlignment = .center
        self.balanceLabel.font = UIFont.systemFont(ofSize: 14.0, weight: .medium)
        self.balanceLabel.textColor = theme.list.itemSecondaryTextColor
        self.scrollView.addSubview(self.balanceLabel)

        self.actionButton.backgroundColor = theme.list.itemAccentColor
        self.actionButton.layer.cornerRadius = 18.0
        self.actionButton.titleLabel?.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        self.actionButton.setTitleColor(.white, for: .normal)
        self.actionButton.setTitle("Открыть портал", for: .normal)
        self.actionButton.addTarget(self, action: #selector(self.openPortal), for: .touchUpInside)
        self.scrollView.addSubview(self.actionButton)

        self.footerLabel.numberOfLines = 0
        self.footerLabel.font = UIFont.systemFont(ofSize: 13.0, weight: .regular)
        self.footerLabel.textColor = theme.list.itemSecondaryTextColor
        self.footerLabel.text = "Портал меняет только локальный баланс PampGram на этом устройстве. Переводы в xRocket, Wallet, CryptoBot, Fragment и других сервисах при этом не происходят — ни одна внешняя система не вызывается. Каждый перевод записывается в историю PampGram и статистику."
        self.scrollView.addSubview(self.footerLabel)

        self.lastTransfersLabel.numberOfLines = 0
        self.lastTransfersLabel.font = UIFont.systemFont(ofSize: 13.0, weight: .regular)
        self.lastTransfersLabel.textColor = theme.list.itemPrimaryTextColor
        self.scrollView.addSubview(self.lastTransfersLabel)
    }

    private func buildSourceChips() {
        for chip in self.sourceChips {
            chip.removeFromSuperview()
        }
        self.sourceChips.removeAll()
        for (index, source) in PampGramVisualPortalSource.all.enumerated() {
            let chip = UIButton(type: .system)
            chip.tag = index
            chip.layer.cornerRadius = 16.0
            chip.layer.masksToBounds = true
            chip.titleLabel?.font = UIFont.systemFont(ofSize: 14.0, weight: .semibold)
            chip.setTitle(source.title, for: .normal)
            chip.contentEdgeInsets = UIEdgeInsets(top: 8.0, left: 14.0, bottom: 8.0, right: 14.0)
            chip.addTarget(self, action: #selector(self.sourceChipTapped(_:)), for: .touchUpInside)
            self.sourceScroll.addSubview(chip)
            self.sourceChips.append(chip)
        }
        self.updateSourceChipAppearance()
    }

    private func rebuildPresetButtons() {
        for subview in self.presetStack.arrangedSubviews {
            self.presetStack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
        for (index, value) in self.selectedCurrency.presets.enumerated() {
            let button = UIButton(type: .system)
            button.tag = index
            button.layer.cornerRadius = 14.0
            button.layer.masksToBounds = true
            button.backgroundColor = self.presentationData.theme.list.itemBlocksBackgroundColor
            button.setTitleColor(self.presentationData.theme.list.itemAccentColor, for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 15.0, weight: .semibold)
            let title: String
            switch self.selectedCurrency {
            case .stars:
                title = "+\(Int64(value.rounded())) ⭐"
            case .ton:
                title = String(format: "+%g TON", value)
            case .rubles:
                title = String(format: "+%g ₽", value)
            }
            button.setTitle(title, for: .normal)
            button.addTarget(self, action: #selector(self.presetTapped(_:)), for: .touchUpInside)
            self.presetStack.addArrangedSubview(button)
        }
    }

    private func updateSourceChipAppearance() {
        let theme = self.presentationData.theme
        for (index, chip) in self.sourceChips.enumerated() {
            let source = PampGramVisualPortalSource.all[index]
            let selected = source.id == self.selectedSource.id
            chip.backgroundColor = selected ? source.primary : theme.list.itemBlocksBackgroundColor
            chip.setTitleColor(selected ? .white : theme.list.itemPrimaryTextColor, for: .normal)
        }
    }

    private func layoutContent(width: CGFloat) {
        let sidePadding: CGFloat = 16.0
        let contentWidth = width - sidePadding * 2.0

        var y: CGFloat = 16.0

        let portalHeight: CGFloat = 260.0
        self.portalView.frame = CGRect(x: sidePadding, y: y, width: contentWidth, height: portalHeight)
        y = self.portalView.frame.maxY + 16.0

        let chipRowHeight: CGFloat = 44.0
        self.sourceScroll.frame = CGRect(x: 0.0, y: y, width: width, height: chipRowHeight)
        var chipX: CGFloat = sidePadding
        for chip in self.sourceChips {
            chip.sizeToFit()
            var frame = chip.frame
            frame.origin.x = chipX
            frame.origin.y = (chipRowHeight - frame.height) / 2.0
            chip.frame = frame
            chipX += frame.width + 8.0
        }
        self.sourceScroll.contentSize = CGSize(width: chipX + sidePadding - 8.0, height: chipRowHeight)
        y = self.sourceScroll.frame.maxY + 12.0

        self.currencyControl.frame = CGRect(x: sidePadding, y: y, width: contentWidth, height: 32.0)
        y = self.currencyControl.frame.maxY + 16.0

        self.amountField.frame = CGRect(x: sidePadding, y: y, width: contentWidth, height: 52.0)
        y = self.amountField.frame.maxY + 12.0

        self.presetStack.frame = CGRect(x: sidePadding, y: y, width: contentWidth, height: 40.0)
        y = self.presetStack.frame.maxY + 10.0

        self.balanceLabel.frame = CGRect(x: sidePadding, y: y, width: contentWidth, height: 20.0)
        y = self.balanceLabel.frame.maxY + 16.0

        self.actionButton.frame = CGRect(x: sidePadding, y: y, width: contentWidth, height: 54.0)
        y = self.actionButton.frame.maxY + 16.0

        let footerSize = self.footerLabel.sizeThatFits(CGSize(width: contentWidth, height: .greatestFiniteMagnitude))
        self.footerLabel.frame = CGRect(x: sidePadding, y: y, width: contentWidth, height: footerSize.height)
        y = self.footerLabel.frame.maxY + 16.0

        let historySize = self.lastTransfersLabel.sizeThatFits(CGSize(width: contentWidth, height: .greatestFiniteMagnitude))
        self.lastTransfersLabel.frame = CGRect(x: sidePadding, y: y, width: contentWidth, height: historySize.height)
        y = self.lastTransfersLabel.frame.maxY + 24.0

        self.scrollView.contentSize = CGSize(width: width, height: y)
    }

    private func applyState(settings: PampGramSettings, operations: [PampGramLocalOperation]) {
        switch self.selectedCurrency {
        case .stars: self.currentBalance = settings.fakeStarsBalance
        case .ton: self.currentBalance = settings.fakeTonBalanceNanos
        case .rubles: self.currentBalance = settings.localRublesBalanceKopecks
        }
        self.balanceLabel.text = "Текущий баланс: \(self.selectedCurrency.formatBalance(storedUnits: self.currentBalance))"

        let portalOps = operations.filter { operation in
            return operation.currency == self.selectedCurrency.local && operation.title.hasPrefix("Визуальный портал")
        }
        if portalOps.isEmpty {
            self.lastTransfersLabel.text = ""
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            let lines = portalOps.prefix(5).map { operation -> String in
                let date = formatter.string(from: Date(timeIntervalSince1970: Double(operation.date)))
                return "• \(operation.title) · \(self.selectedCurrency.formatBalance(storedUnits: operation.amount)) · \(date)"
            }
            self.lastTransfersLabel.text = "ПОСЛЕДНИЕ ПЕРЕВОДЫ\n" + lines.joined(separator: "\n")
        }
        if self.cachedLayoutWidth > 0.0 {
            self.layoutContent(width: self.cachedLayoutWidth)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.portalView.startIdleAnimation()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        self.portalView.stopIdleAnimation()
    }

    @objc private func currencyChanged() {
        switch self.currencyControl.selectedSegmentIndex {
        case 0: self.selectedCurrency = .stars
        case 1: self.selectedCurrency = .ton
        case 2: self.selectedCurrency = .rubles
        default: self.selectedCurrency = .stars
        }
        self.amountField.placeholder = self.selectedCurrency.placeholder
        self.amountField.text = ""
        self.rebuildPresetButtons()
        self.refreshBalanceAndLayout()
    }

    @objc private func sourceChipTapped(_ sender: UIButton) {
        let index = sender.tag
        guard index >= 0 && index < PampGramVisualPortalSource.all.count else { return }
        self.selectedSource = PampGramVisualPortalSource.all[index]
        self.portalView.applySource(self.selectedSource)
        self.updateSourceChipAppearance()
    }

    @objc private func presetTapped(_ sender: UIButton) {
        let index = sender.tag
        let presets = self.selectedCurrency.presets
        guard index >= 0 && index < presets.count else { return }
        let value = presets[index]
        switch self.selectedCurrency {
        case .stars:
            self.amountField.text = "\(Int64(value.rounded()))"
        case .ton:
            self.amountField.text = String(format: "%g", value)
        case .rubles:
            self.amountField.text = String(format: "%g", value)
        }
    }

    @objc private func openPortal() {
        guard !self.isTransferring else { return }
        self.view.endEditing(true)
        let text = self.amountField.text ?? ""
        guard let storedUnits = self.selectedCurrency.parse(text), storedUnits > 0 else {
            self.presentTooltip("Введите сумму больше нуля.")
            return
        }

        let displayValue: Double
        switch self.selectedCurrency {
        case .stars: displayValue = Double(storedUnits)
        case .ton: displayValue = Double(storedUnits) / 1_000_000_000.0
        case .rubles: displayValue = Double(storedUnits) / 100.0
        }

        self.isTransferring = true
        self.actionButton.isEnabled = false
        self.actionButton.alpha = 0.6

        let source = self.selectedSource
        let currency = self.selectedCurrency

        self.portalView.playTransfer(currency: currency, amountDisplay: displayValue, completion: { [weak self] in
            guard let self else { return }
            let title = "Визуальный портал · \(source.title)"
            let details = "Локальный перевод из \(source.title) (\(source.subtitle))"
            let _ = (self.context.account.postbox.transaction { transaction -> Void in
                PampGramLocalLedgerStore.addAndApply(
                    transaction: transaction,
                    currency: currency.local,
                    kind: .topUp,
                    amount: storedUnits,
                    title: title,
                    details: details
                )
            }
            |> deliverOnMainQueue).start(completed: { [weak self] in
                guard let self else { return }
                self.isTransferring = false
                self.actionButton.isEnabled = true
                self.actionButton.alpha = 1.0
                self.amountField.text = ""
                self.presentTooltip("Перевод из \(source.title) зачислен.")
            })
        })
    }

    @objc private func openHistory() {
        let historyController = pampGramLedgerController(context: self.context, currency: self.selectedCurrency.local)
        if let navigationController = self.navigationController as? NavigationController {
            navigationController.pushViewController(historyController)
        }
    }

    private func refreshBalanceAndLayout() {
        let _ = (PampGramCore.rawSettingsSignal(postbox: self.context.account.postbox)
        |> take(1)
        |> deliverOnMainQueue).start(next: { [weak self] settings in
            guard let self else { return }
            switch self.selectedCurrency {
            case .stars: self.currentBalance = settings.fakeStarsBalance
            case .ton: self.currentBalance = settings.fakeTonBalanceNanos
            case .rubles: self.currentBalance = settings.localRublesBalanceKopecks
            }
            self.balanceLabel.text = "Текущий баланс: \(self.selectedCurrency.formatBalance(storedUnits: self.currentBalance))"
        })
    }

    private func presentTooltip(_ text: String) {
        let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
        self.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), in: .current)
    }

    // MARK: - Keyboard

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let endFrame = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else {
            return
        }
        let overlap = max(0.0, self.view.bounds.height - endFrame.origin.y)
        self.scrollView.contentInset.bottom = overlap + 32.0
        self.scrollView.verticalScrollIndicatorInsets.bottom = overlap
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        self.scrollView.contentInset.bottom = 32.0
        self.scrollView.verticalScrollIndicatorInsets.bottom = 0.0
    }

    // MARK: - UITextFieldDelegate

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
