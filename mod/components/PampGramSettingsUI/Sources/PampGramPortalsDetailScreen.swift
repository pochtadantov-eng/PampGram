import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramPresentationData
import AccountContext
import PampGramCore
import UndoUI

/// Portals item detail. Matches the portals-market mini-app's item sheet:
///   - centered square hero card with signature gradient and emoji
///     centerpiece, "Collection ›" title / "#number" subtitle, and a
///     green "Доступно для крафта" ribbon when the item has it;
///   - attributes table (Model / Symbol / Backdrop) with a blue rarity %
///     pill on each row and the item's GRAM price on the right, plus a
///     "Мин. Цена" summary row;
///   - reward row "Вознаграждение за покупку N ✦";
///   - two secondary buttons ("Сделать оффер" / "Lucky Buy 🍀") and the
///     primary "Купить подарок / N GRAM" button.
///
/// Only the two buy actions commit anything, and only to the local
/// `PampGramLocalLedgerStore`: a GRAM debit (Lucky Buy = half price)
/// and a stars credit sized to the reward.
public func pampGramPortalsDetailController(context: AccountContext, itemId: String) -> ViewController {
    return PampGramPortalsDetailControllerImpl(context: context, itemId: itemId)
}

private enum DetailPalette {
    static let surface         = UIColor(white: 0.043, alpha: 1.0)
    static let surfaceElevated = UIColor(white: 0.078, alpha: 1.0)
    static let surfaceInner    = UIColor(white: 0.063, alpha: 1.0)
    static let accentPrimary   = UIColor(red: 0.10, green: 0.79, blue: 1.00, alpha: 1.0)
    static let accentLucky     = UIColor(red: 0.16, green: 0.35, blue: 0.18, alpha: 1.0)
    static let accentStars     = UIColor(red: 1.00, green: 0.71, blue: 0.00, alpha: 1.0)
    static let accentCraft     = UIColor(red: 0.18, green: 0.82, blue: 0.48, alpha: 1.0)
    static let rarityPillBg    = UIColor(red: 0.12, green: 0.25, blue: 0.35, alpha: 1.0)
    static let rarityPillFg    = UIColor(red: 0.10, green: 0.79, blue: 1.00, alpha: 1.0)
}

private final class PampGramPortalsDetailControllerImpl: ViewController {
    private let context: AccountContext
    private let item: PampGramPortalsCatalog.Item
    private let presentationData: PresentationData
    private var detailNode: PampGramPortalsDetailNode?

    init(context: AccountContext, itemId: String) {
        self.context = context
        self.item = PampGramPortalsCatalog.item(id: itemId) ?? PampGramPortalsCatalog.items[0]
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }

        let navTheme = NavigationBarTheme(
            overallDarkAppearance: true,
            buttonColor: .white,
            disabledButtonColor: UIColor(white: 1.0, alpha: 0.5),
            primaryTextColor: .white,
            backgroundColor: DetailPalette.surface,
            enableBackgroundBlur: false,
            separatorColor: UIColor(white: 1.0, alpha: 0.08),
            badgeBackgroundColor: DetailPalette.accentPrimary,
            badgeStrokeColor: DetailPalette.accentPrimary,
            badgeTextColor: .black,
            accentButtonColor: DetailPalette.accentPrimary,
            accentDisabledButtonColor: UIColor(white: 1.0, alpha: 0.5),
            accentForegroundColor: .white
        )
        super.init(navigationBarPresentationData: NavigationBarPresentationData(
            theme: navTheme,
            strings: NavigationBarStrings(presentationStrings: self.presentationData.strings)
        ))

        self.statusBar.statusBarStyle = .White
        self.title = self.item.collection
        self.navigationItem.backBarButtonItem = UIBarButtonItem(
            title: self.presentationData.strings.Common_Back, style: .plain, target: nil, action: nil)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadDisplayNode() {
        self.displayNode = ViewControllerTracingNode()
        self.displayNode.backgroundColor = DetailPalette.surface
        let node = PampGramPortalsDetailNode(context: self.context, item: self.item, present: { [weak self] controller in
            self?.present(controller, in: .window(.root))
        }, dismiss: { [weak self] in
            self?.dismiss()
        })
        self.detailNode = node
        self.displayNode.view.addSubview(node)
        self.displayNodeDidLoad()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        self.detailNode?.frame = CGRect(origin: .zero, size: layout.size)
        let topInset = (layout.statusBarHeight ?? 0.0) + 44.0
        self.detailNode?.updateLayout(size: layout.size, topInset: topInset, bottomInset: layout.intrinsicInsets.bottom)
    }
}

// MARK: - Detail root view

private final class PampGramPortalsDetailNode: UIView {
    private let context: AccountContext
    private let item: PampGramPortalsCatalog.Item
    private let present: (ViewController) -> Void
    private let dismissAction: () -> Void

    private let scrollView = UIScrollView()
    private let contentView = UIStackView()

    init(context: AccountContext, item: PampGramPortalsCatalog.Item, present: @escaping (ViewController) -> Void, dismiss: @escaping () -> Void) {
        self.context = context
        self.item = item
        self.present = present
        self.dismissAction = dismiss
        super.init(frame: .zero)
        self.backgroundColor = DetailPalette.surface

        self.scrollView.showsVerticalScrollIndicator = false
        self.scrollView.contentInsetAdjustmentBehavior = .never
        self.addSubview(self.scrollView)

        self.contentView.axis = .vertical
        self.contentView.spacing = 16
        self.contentView.alignment = .fill
        self.contentView.isLayoutMarginsRelativeArrangement = true
        self.contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 24, trailing: 16)
        self.scrollView.addSubview(self.contentView)

        self.buildContent()
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateLayout(size: CGSize, topInset: CGFloat, bottomInset: CGFloat) {
        self.scrollView.frame = CGRect(origin: .zero, size: size)
        self.scrollView.contentInset = UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset + 24, right: 0)
        let width = size.width
        let fitHeight = self.contentView.systemLayoutSizeFitting(
            CGSize(width: width, height: .greatestFiniteMagnitude),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        self.contentView.frame = CGRect(origin: .zero, size: CGSize(width: width, height: fitHeight))
        self.scrollView.contentSize = CGSize(width: width, height: fitHeight)
    }

    // MARK: - Content

    private func buildContent() {
        self.contentView.addArrangedSubview(self.buildHero())
        self.contentView.addArrangedSubview(self.buildAttributesTable())
        self.contentView.addArrangedSubview(self.buildRewardRow())
        self.contentView.addArrangedSubview(self.buildSecondaryButtons())
        self.contentView.addArrangedSubview(self.buildPrimaryBuyButton())
    }

    private func buildHero() -> UIView {
        let hero = PortalsGradientView(colors: [self.item.gradientTop, self.item.gradientBottom], horizontal: false)
        hero.layer.cornerRadius = 24
        hero.layer.borderWidth = 1
        hero.layer.borderColor = UIColor(white: 1.0, alpha: 0.2).cgColor
        hero.clipsToBounds = true
        hero.translatesAutoresizingMaskIntoConstraints = false

        let glyph = UILabel()
        glyph.text = self.item.emoji
        glyph.font = .systemFont(ofSize: 120)
        glyph.textAlignment = .center
        glyph.translatesAutoresizingMaskIntoConstraints = false

        let title = UILabel()
        title.text = "\(self.item.collection)  ›"
        title.font = .systemFont(ofSize: 22, weight: .bold)
        title.textColor = .white
        title.textAlignment = .center

        let number = UILabel()
        number.text = "#\(self.item.number)"
        number.font = .systemFont(ofSize: 14)
        number.textColor = UIColor(white: 1.0, alpha: 0.6)
        number.textAlignment = .center

        let bottomStack = UIStackView(arrangedSubviews: [title, number])
        bottomStack.axis = .vertical
        bottomStack.spacing = 2
        bottomStack.alignment = .center

        if self.item.craftable {
            let craft = UILabel()
            craft.text = "⚒  Доступно для крафта"
            craft.font = .systemFont(ofSize: 12, weight: .bold)
            craft.textColor = DetailPalette.accentCraft
            craft.textAlignment = .center
            bottomStack.addArrangedSubview(craft)
        }
        bottomStack.translatesAutoresizingMaskIntoConstraints = false

        hero.addSubview(glyph)
        hero.addSubview(bottomStack)
        NSLayoutConstraint.activate([
            glyph.centerXAnchor.constraint(equalTo: hero.centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: hero.centerYAnchor, constant: -20),
            bottomStack.leadingAnchor.constraint(equalTo: hero.leadingAnchor, constant: 12),
            bottomStack.trailingAnchor.constraint(equalTo: hero.trailingAnchor, constant: -12),
            bottomStack.bottomAnchor.constraint(equalTo: hero.bottomAnchor, constant: -16)
        ])

        let wrap = UIView()
        wrap.addSubview(hero)
        NSLayoutConstraint.activate([
            hero.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 24),
            hero.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -24),
            hero.topAnchor.constraint(equalTo: wrap.topAnchor),
            hero.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
            hero.heightAnchor.constraint(equalToConstant: 320)
        ])
        return wrap
    }

    private func buildAttributesTable() -> UIView {
        let table = UIStackView()
        table.axis = .vertical
        table.spacing = 0
        table.isLayoutMarginsRelativeArrangement = true
        table.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14)
        table.backgroundColor = DetailPalette.surfaceElevated
        table.layer.cornerRadius = 18
        table.layer.borderWidth = 1
        table.layer.borderColor = UIColor(white: 1.0, alpha: 0.08).cgColor
        table.layer.masksToBounds = true

        table.addArrangedSubview(self.buildAttrRow(label: "Model",    value: self.item.model,    pct10: self.item.modelPct10))
        table.addArrangedSubview(self.buildThinDivider())
        table.addArrangedSubview(self.buildAttrRow(label: "Symbol",   value: self.item.symbol,   pct10: self.item.symbolPct10))
        table.addArrangedSubview(self.buildThinDivider())
        table.addArrangedSubview(self.buildAttrRow(label: "Backdrop", value: self.item.backdrop, pct10: self.item.backdropPct10))
        table.addArrangedSubview(self.buildThinDivider())
        table.addArrangedSubview(self.buildFloorRow())
        return table
    }

    private func buildAttrRow(label: String, value: String, pct10: Int) -> UIView {
        let row = UIView()
        let l = UILabel()
        l.text = label
        l.font = .systemFont(ofSize: 14)
        l.textColor = UIColor(white: 1.0, alpha: 0.6)

        let v = UILabel()
        v.text = value
        v.font = .systemFont(ofSize: 15, weight: .bold)
        v.textColor = DetailPalette.rarityPillFg

        let pct = PaddedLabel()
        pct.contentInsets = UIEdgeInsets(top: 2, left: 7, bottom: 2, right: 7)
        pct.text = String(format: "%.1f%%", Double(pct10) / 10.0)
        pct.font = .systemFont(ofSize: 11, weight: .bold)
        pct.textColor = DetailPalette.rarityPillFg
        pct.backgroundColor = DetailPalette.rarityPillBg
        pct.layer.cornerRadius = 10
        pct.clipsToBounds = true

        let right = UILabel()
        right.text = "\(PampGramPortalsCatalog.formatGram(self.item.priceNanoGram)) GRAM"
        right.font = .systemFont(ofSize: 14, weight: .bold)
        right.textColor = .white

        [l, v, pct, right].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview($0)
        }
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 48),
            l.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            l.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            l.widthAnchor.constraint(equalToConstant: 90),
            v.leadingAnchor.constraint(equalTo: l.trailingAnchor),
            v.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            pct.leadingAnchor.constraint(equalTo: v.trailingAnchor, constant: 8),
            pct.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            right.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            right.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        return row
    }

    private func buildThinDivider() -> UIView {
        let d = UIView()
        d.backgroundColor = UIColor(white: 1.0, alpha: 0.07)
        d.translatesAutoresizingMaskIntoConstraints = false
        d.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return d
    }

    private func buildFloorRow() -> UIView {
        let row = UIView()
        let l = UILabel()
        l.text = "Мин. Цена"
        l.font = .systemFont(ofSize: 14)
        l.textColor = UIColor(white: 1.0, alpha: 0.6)
        let v = UILabel()
        v.text = "\(PampGramPortalsCatalog.formatGram(self.item.priceNanoGram)) GRAM"
        v.font = .systemFont(ofSize: 15, weight: .bold)
        v.textColor = .white
        [l, v].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview($0)
        }
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 44),
            l.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            l.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            v.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            v.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        return row
    }

    private func buildRewardRow() -> UIView {
        let row = UIView()
        let l = UILabel()
        l.text = "Вознаграждение за покупку"
        l.font = .systemFont(ofSize: 14)
        l.textColor = UIColor(white: 1.0, alpha: 0.6)
        let r = UILabel()
        r.text = "\(PampGramPortalsCatalog.formatStars(self.item.rewardStars))  ✨"
        r.font = .systemFont(ofSize: 16, weight: .bold)
        r.textColor = DetailPalette.accentStars
        [l, r].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview($0)
        }
        NSLayoutConstraint.activate([
            l.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            l.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            r.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            r.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            row.heightAnchor.constraint(equalToConstant: 32)
        ])
        return row
    }

    private func buildSecondaryButtons() -> UIView {
        let offer = PortalsTwoLineButton(topText: "Сделать оффер", bottomText: "0.01 GRAM",
                                          bg: DetailPalette.surfaceInner, topColor: .white,
                                          bottomColor: UIColor(white: 1.0, alpha: 0.6), stroked: false)
        offer.action = { [weak self] in self?.showOfferComingSoon() }

        let luckyPrice = self.item.priceNanoGram / 2
        let lucky = PortalsTwoLineButton(topText: "Lucky Buy  🍀",
                                         bottomText: "За \(PampGramPortalsCatalog.formatGram(luckyPrice)) GRAM",
                                         bg: DetailPalette.accentLucky, topColor: .white,
                                         bottomColor: UIColor(white: 1.0, alpha: 0.8), stroked: true)
        lucky.action = { [weak self] in self?.onLuckyBuy() }

        let stack = UIStackView(arrangedSubviews: [offer, lucky])
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 10
        return stack
    }

    private func buildPrimaryBuyButton() -> UIView {
        let btn = UIControl()
        btn.backgroundColor = DetailPalette.accentPrimary
        btn.layer.cornerRadius = 22
        btn.heightAnchor.constraint(equalToConstant: 64).isActive = true

        let title = UILabel()
        title.text = "Купить подарок"
        title.font = .systemFont(ofSize: 16, weight: .bold)
        title.textColor = .black
        title.textAlignment = .center

        let price = UILabel()
        price.text = "\(PampGramPortalsCatalog.formatGram(self.item.priceNanoGram)) GRAM"
        price.font = .systemFont(ofSize: 13)
        price.textColor = UIColor(white: 0.0, alpha: 0.8)
        price.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [title, price])
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .center
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        btn.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: btn.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: btn.centerYAnchor)
        ])

        btn.addTarget(self, action: #selector(self.onPrimaryBuy), for: .touchUpInside)
        return btn
    }

    // MARK: - Actions

    @objc private func onPrimaryBuy() {
        self.confirmPurchase(priceNanoGram: self.item.priceNanoGram, rewardStars: self.item.rewardStars, kind: "Купить подарок")
    }

    private func onLuckyBuy() {
        let luckyPrice = self.item.priceNanoGram / 2
        let luckyReward = self.item.rewardStars / 2
        self.confirmPurchase(priceNanoGram: luckyPrice, rewardStars: luckyReward, kind: "Lucky Buy")
    }

    private func showOfferComingSoon() {
        let alert = UIAlertController(title: "Сделать оффер", message: "Оффер-флоу появится в следующих версиях PampGram.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        self.presentUIKitAlert(alert)
    }

    private func confirmPurchase(priceNanoGram: Int64, rewardStars: Int64, kind: String) {
        let _ = (PampGramCore.rawSettingsSignal(postbox: self.context.account.postbox)
        |> take(1)
        |> deliverOnMainQueue).start(next: { [weak self] settings in
            guard let self else { return }
            let priceText = "\(PampGramPortalsCatalog.formatGram(priceNanoGram)) GRAM"
            if settings.fakeTonBalanceNanos < priceNanoGram {
                let haveText = "\(PampGramPortalsCatalog.formatGram(settings.fakeTonBalanceNanos)) GRAM"
                let alert = UIAlertController(
                    title: "Недостаточно GRAM",
                    message: "Нужно \(priceText), у вас \(haveText).\n\nПополнить баланс можно, тапнув на пилюлю GRAM в правом верхнем углу Portals Market.",
                    preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self.presentUIKitAlert(alert)
                return
            }
            let rewardText = "\(PampGramPortalsCatalog.formatStars(rewardStars)) ✦"
            let alert = UIAlertController(
                title: "\(kind): \(self.item.collection) #\(self.item.number)",
                message: "Будет списано \(priceText). Вы получите \(rewardText) в баланс звёзд.",
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Купить", style: .default, handler: { [weak self] _ in
                self?.commitPurchase(priceNanoGram: priceNanoGram, rewardStars: rewardStars)
            }))
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            self.presentUIKitAlert(alert)
        })
    }

    private func commitPurchase(priceNanoGram: Int64, rewardStars: Int64) {
        let itemLabel = "\(self.item.collection) #\(self.item.number)"
        let _ = (self.context.account.postbox.transaction { tx in
            PampGramLocalLedgerStore.addAndApply(transaction: tx, currency: .ton,
                kind: .purchase, amount: -priceNanoGram,
                title: "Portals Market", details: itemLabel)
            if rewardStars > 0 {
                PampGramLocalLedgerStore.addAndApply(transaction: tx, currency: .stars,
                    kind: .credit, amount: rewardStars,
                    title: "Награда Portals", details: itemLabel)
            }
        } |> deliverOnMainQueue).start(completed: { [weak self] in
            guard let self else { return }
            let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
            let toast = UndoOverlayController(presentationData: presentationData,
                content: .info(title: nil, text: "\(itemLabel) куплен за \(PampGramPortalsCatalog.formatGram(priceNanoGram)) GRAM", timeout: nil, customUndoText: nil),
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

// MARK: - Shared subcomponents (file-private so they don't collide with the market screen)

private final class PortalsTwoLineButton: UIControl {
    var action: (() -> Void)?

    init(topText: String, bottomText: String, bg: UIColor, topColor: UIColor, bottomColor: UIColor, stroked: Bool) {
        super.init(frame: .zero)
        self.backgroundColor = bg
        self.layer.cornerRadius = 20
        if stroked {
            self.layer.borderWidth = 1
            self.layer.borderColor = UIColor(red: 0.21, green: 0.78, blue: 0.35, alpha: 0.3).cgColor
        }
        let top = UILabel()
        top.text = topText
        top.font = .systemFont(ofSize: 15, weight: .bold)
        top.textColor = topColor
        top.textAlignment = .center

        let bottom = UILabel()
        bottom.text = bottomText
        bottom.font = .systemFont(ofSize: 12)
        bottom.textColor = bottomColor
        bottom.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [top, bottom])
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .center
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            self.heightAnchor.constraint(equalToConstant: 56)
        ])
        self.addTarget(self, action: #selector(self.tapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError() }
    @objc private func tapped() { self.action?() }
}

/// A UILabel subclass that renders content insets — used for the rarity-% pills so a 1-decimal
/// value like "1.2%" sits inside a snug pill with 7pt horizontal / 2pt vertical padding, same as
/// the real portals-market cards.
private final class PaddedLabel: UILabel {
    var contentInsets: UIEdgeInsets = .zero {
        didSet {
            self.invalidateIntrinsicContentSize()
            self.setNeedsLayout()
        }
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: self.contentInsets))
    }

    override var intrinsicContentSize: CGSize {
        var size = super.intrinsicContentSize
        size.width += self.contentInsets.left + self.contentInsets.right
        size.height += self.contentInsets.top + self.contentInsets.bottom
        return size
    }
}
