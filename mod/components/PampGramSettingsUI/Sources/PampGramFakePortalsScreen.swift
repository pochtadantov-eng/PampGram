import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import PromptUI
import UndoUI
import PampGramCore

/// Визуальная копия мини-аппа @portals — подарки, баланс TON/Stars, покупка с витрин.
///
/// Экран полностью локальный — ничего не отправляется. Балансы хранятся в
/// `PampGramSettings.fakePortalsBalanceTonNanos` и `.fakePortalsBalanceStars`.
/// Редактор балансов открывается удержанием карточки баланса (~1 с).

// MARK: - Data

struct PampGramFakePortalsGift {
    let id: String
    let name: String
    let emoji: String
    let priceTon: Double
    let priceStars: Int
    let rarity: String
}

private let pampGramFakePortalsGifts: [PampGramFakePortalsGift] = [
    PampGramFakePortalsGift(id: "plush_pepe", name: "Plush Pepe", emoji: "🐸", priceTon: 5.0, priceStars: 500, rarity: "Common"),
    PampGramFakePortalsGift(id: "crystal_ball", name: "Crystal Ball", emoji: "🔮", priceTon: 15.0, priceStars: 1500, rarity: "Rare"),
    PampGramFakePortalsGift(id: "golden_trophy", name: "Golden Trophy", emoji: "🏆", priceTon: 50.0, priceStars: 5000, rarity: "Epic"),
    PampGramFakePortalsGift(id: "diamond_ring", name: "Diamond Ring", emoji: "💍", priceTon: 100.0, priceStars: 10000, rarity: "Legendary"),
    PampGramFakePortalsGift(id: "rocket_ship", name: "Rocket Ship", emoji: "🚀", priceTon: 25.0, priceStars: 2500, rarity: "Rare"),
    PampGramFakePortalsGift(id: "fire_heart", name: "Fire Heart", emoji: "❤️‍🔥", priceTon: 10.0, priceStars: 1000, rarity: "Common"),
    PampGramFakePortalsGift(id: "star_dust", name: "Star Dust", emoji: "✨", priceTon: 75.0, priceStars: 7500, rarity: "Epic"),
    PampGramFakePortalsGift(id: "neon_cat", name: "Neon Cat", emoji: "🐱", priceTon: 200.0, priceStars: 20000, rarity: "Legendary"),
    PampGramFakePortalsGift(id: "magic_wand", name: "Magic Wand", emoji: "🪄", priceTon: 8.0, priceStars: 800, rarity: "Common"),
    PampGramFakePortalsGift(id: "crown_jewel", name: "Crown Jewel", emoji: "👑", priceTon: 150.0, priceStars: 15000, rarity: "Legendary"),
    PampGramFakePortalsGift(id: "lucky_clover", name: "Lucky Clover", emoji: "🍀", priceTon: 3.0, priceStars: 300, rarity: "Common"),
    PampGramFakePortalsGift(id: "phoenix_egg", name: "Phoenix Egg", emoji: "🥚", priceTon: 120.0, priceStars: 12000, rarity: "Epic"),
]

// MARK: - Colors

private enum PortalsColors {
    static func themed(dark: UInt32, light: UInt32, darkAlpha: CGFloat = 1.0, lightAlpha: CGFloat = 1.0) -> UIColor {
        return UIColor { traits in
            if traits.userInterfaceStyle == .light {
                return UIColor(rgb: light).withAlphaComponent(lightAlpha)
            }
            return UIColor(rgb: dark).withAlphaComponent(darkAlpha)
        }
    }

    static let background = themed(dark: 0x0f0f0f, light: 0xf2f2f7)
    static let card = themed(dark: 0x1c1c1e, light: 0xffffff)
    static let text = themed(dark: 0xffffff, light: 0x000000)
    static let secondary = themed(dark: 0x8e8e93, light: 0x8a8a8e)
    static let accent = themed(dark: 0x7b68ee, light: 0x6c5ce7)
    static let accentLight = themed(dark: 0x9b8afb, light: 0x8b7cf6)
    static let green = themed(dark: 0x34c759, light: 0x28a745)
    static let orange = themed(dark: 0xff9500, light: 0xe8850c)
    static let red = UIColor(rgb: 0xff3b30)
    static let separator = themed(dark: 0x38383a, light: 0xe5e5ea)
    static let tonBlue = UIColor(rgb: 0x0098ea)
    static let starYellow = UIColor(rgb: 0xffb800)
}

private func portalsRarityColor(_ rarity: String) -> UIColor {
    switch rarity {
    case "Common": return PortalsColors.secondary
    case "Rare": return PortalsColors.tonBlue
    case "Epic": return PortalsColors.accent
    case "Legendary": return PortalsColors.orange
    default: return PortalsColors.secondary
    }
}

// MARK: - Helpers

private func portalsLabel(size: CGFloat, weight: UIFont.Weight, color: UIColor, alignment: NSTextAlignment = .left) -> UILabel {
    let label = UILabel()
    label.font = .systemFont(ofSize: size, weight: weight)
    label.textColor = color
    label.textAlignment = alignment
    label.isUserInteractionEnabled = false
    return label
}

private func portalsFormatTon(_ nanos: Int64) -> String {
    let ton = Double(nanos) / 1_000_000_000.0
    if ton == 0 { return "0" }
    if ton == Double(Int64(ton)) { return "\(Int64(ton))" }
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 9
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = " "
    formatter.usesGroupingSeparator = true
    return formatter.string(from: NSNumber(value: ton)) ?? "0"
}

private func portalsFormatStars(_ stars: Int64) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = " "
    formatter.usesGroupingSeparator = true
    return formatter.string(from: NSNumber(value: stars)) ?? "0"
}

// MARK: - Balance Card

private final class PampGramFakePortalsBalanceCard: UIView {
    private let tonIcon = UILabel()
    private let tonLabel = portalsLabel(size: 28, weight: .bold, color: PortalsColors.text)
    private let tonCaption = portalsLabel(size: 13, weight: .regular, color: PortalsColors.secondary)
    private let starIcon = UILabel()
    private let starLabel = portalsLabel(size: 28, weight: .bold, color: PortalsColors.text)
    private let starCaption = portalsLabel(size: 13, weight: .regular, color: PortalsColors.secondary)
    private let divider = UIView()

    var onLongPress: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = PortalsColors.card
        self.layer.cornerRadius = 16
        self.clipsToBounds = true

        self.tonIcon.text = "💎"
        self.tonIcon.font = .systemFont(ofSize: 24)
        self.tonCaption.text = "TON"

        self.starIcon.text = "⭐"
        self.starIcon.font = .systemFont(ofSize: 24)
        self.starCaption.text = "Stars"

        self.divider.backgroundColor = PortalsColors.separator

        for v in [tonIcon, tonLabel, tonCaption, starIcon, starLabel, starCaption, divider] {
            v.isUserInteractionEnabled = false
            self.addSubview(v)
        }

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.8
        self.addGestureRecognizer(longPress)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            self.onLongPress?()
        }
    }

    func update(tonNanos: Int64, stars: Int64) {
        self.tonLabel.text = portalsFormatTon(tonNanos)
        self.starLabel.text = portalsFormatStars(stars)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = self.bounds.width
        let half = w / 2.0

        self.tonIcon.frame = CGRect(x: half / 2.0 - 14, y: 20, width: 28, height: 28)
        self.tonLabel.frame = CGRect(x: 16, y: 52, width: half - 32, height: 34)
        self.tonLabel.textAlignment = .center
        self.tonCaption.frame = CGRect(x: 16, y: 88, width: half - 32, height: 18)
        self.tonCaption.textAlignment = .center

        self.divider.frame = CGRect(x: half - 0.5, y: 24, width: 1, height: self.bounds.height - 48)

        self.starIcon.frame = CGRect(x: half + half / 2.0 - 14, y: 20, width: 28, height: 28)
        self.starLabel.frame = CGRect(x: half + 16, y: 52, width: half - 32, height: 34)
        self.starLabel.textAlignment = .center
        self.starCaption.frame = CGRect(x: half + 16, y: 88, width: half - 32, height: 18)
        self.starCaption.textAlignment = .center
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: 120)
    }
}

// MARK: - Gift Cell

private final class PampGramFakePortalsGiftCell: UIControl {
    private let emojiLabel = UILabel()
    private let nameLabel = portalsLabel(size: 13, weight: .semibold, color: PortalsColors.text)
    private let rarityLabel = portalsLabel(size: 11, weight: .medium, color: PortalsColors.secondary)
    private let priceLabel = portalsLabel(size: 12, weight: .bold, color: PortalsColors.accent)

    let gift: PampGramFakePortalsGift

    init(gift: PampGramFakePortalsGift) {
        self.gift = gift
        super.init(frame: .zero)
        self.backgroundColor = PortalsColors.card
        self.layer.cornerRadius = 12
        self.clipsToBounds = true

        self.emojiLabel.text = gift.emoji
        self.emojiLabel.font = .systemFont(ofSize: 36)
        self.emojiLabel.textAlignment = .center
        self.emojiLabel.isUserInteractionEnabled = false

        self.nameLabel.text = gift.name
        self.nameLabel.textAlignment = .center
        self.nameLabel.numberOfLines = 1

        self.rarityLabel.text = gift.rarity
        self.rarityLabel.textAlignment = .center
        self.rarityLabel.textColor = portalsRarityColor(gift.rarity)

        self.priceLabel.text = "💎 \(Int(gift.priceTon)) TON"
        self.priceLabel.textAlignment = .center

        for v in [emojiLabel, nameLabel, rarityLabel, priceLabel] {
            self.addSubview(v)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = self.bounds.width
        self.emojiLabel.frame = CGRect(x: 0, y: 12, width: w, height: 44)
        self.nameLabel.frame = CGRect(x: 4, y: 60, width: w - 8, height: 18)
        self.rarityLabel.frame = CGRect(x: 4, y: 78, width: w - 8, height: 16)
        self.priceLabel.frame = CGRect(x: 4, y: 98, width: w - 8, height: 16)
    }

    override var isHighlighted: Bool {
        didSet { self.alpha = self.isHighlighted ? 0.6 : 1.0 }
    }
}

// MARK: - Owned Gift Row

private final class PampGramFakePortalsOwnedRow: UIView {
    private let emojiLabel = UILabel()
    private let nameLabel = portalsLabel(size: 15, weight: .medium, color: PortalsColors.text)
    private let dateLabel = portalsLabel(size: 13, weight: .regular, color: PortalsColors.secondary)
    private let separator = UIView()

    init(giftName: String, emoji: String, date: String) {
        super.init(frame: .zero)
        self.emojiLabel.text = emoji
        self.emojiLabel.font = .systemFont(ofSize: 28)
        self.nameLabel.text = giftName
        self.dateLabel.text = date
        self.separator.backgroundColor = PortalsColors.separator
        for v in [emojiLabel, nameLabel, dateLabel, separator] {
            v.isUserInteractionEnabled = false
            self.addSubview(v)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = self.bounds.height
        self.emojiLabel.frame = CGRect(x: 16, y: (h - 34) / 2, width: 34, height: 34)
        self.nameLabel.frame = CGRect(x: 60, y: h / 2 - 18, width: self.bounds.width - 76, height: 20)
        self.dateLabel.frame = CGRect(x: 60, y: h / 2 + 2, width: self.bounds.width - 76, height: 16)
        self.separator.frame = CGRect(x: 60, y: h - 0.5, width: self.bounds.width - 60, height: 0.5)
    }
}

// MARK: - Purchase History Row

private final class PampGramFakePortalsHistoryRow: UIView {
    private let emojiLabel = UILabel()
    private let titleLabel = portalsLabel(size: 15, weight: .medium, color: PortalsColors.text)
    private let amountLabel = portalsLabel(size: 15, weight: .semibold, color: PortalsColors.red)
    private let dateLabel = portalsLabel(size: 13, weight: .regular, color: PortalsColors.secondary)
    private let separator = UIView()

    init(giftName: String, emoji: String, amount: String, date: String) {
        super.init(frame: .zero)
        self.emojiLabel.text = emoji
        self.emojiLabel.font = .systemFont(ofSize: 28)
        self.titleLabel.text = "Bought \(giftName)"
        self.amountLabel.text = "-\(amount)"
        self.dateLabel.text = date
        self.separator.backgroundColor = PortalsColors.separator
        for v in [emojiLabel, titleLabel, amountLabel, dateLabel, separator] {
            v.isUserInteractionEnabled = false
            self.addSubview(v)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = self.bounds.width
        let h = self.bounds.height
        self.emojiLabel.frame = CGRect(x: 16, y: (h - 34) / 2, width: 34, height: 34)
        self.titleLabel.frame = CGRect(x: 60, y: h / 2 - 18, width: w - 160, height: 20)
        self.amountLabel.frame = CGRect(x: w - 120, y: h / 2 - 18, width: 104, height: 20)
        self.amountLabel.textAlignment = .right
        self.dateLabel.frame = CGRect(x: 60, y: h / 2 + 2, width: w - 76, height: 16)
        self.separator.frame = CGRect(x: 60, y: h - 0.5, width: w - 60, height: 0.5)
    }
}

// MARK: - Main Content View

private final class PampGramFakePortalsContentView: UIView, PampGramFakeMiniAppContent {
    var onBackStateChanged: ((Bool) -> Void)?
    var pageColor: UIColor { return PortalsColors.background }
    var onPageColorChanged: ((UIColor) -> Void)?

    private let context: AccountContext
    private weak var presenter: ViewController?
    private let scrollView = UIScrollView()
    private let balanceCard = PampGramFakePortalsBalanceCard()
    private let sectionTitle = portalsLabel(size: 20, weight: .bold, color: PortalsColors.text)
    private let tabTon = UIButton(type: .system)
    private let tabStars = UIButton(type: .system)
    private var giftCells: [PampGramFakePortalsGiftCell] = []
    private let ownedHeader = portalsLabel(size: 17, weight: .bold, color: PortalsColors.text)
    private var ownedRows: [PampGramFakePortalsOwnedRow] = []
    private let historyHeader = portalsLabel(size: 17, weight: .bold, color: PortalsColors.text)
    private var historyRows: [PampGramFakePortalsHistoryRow] = []
    private let emptyOwnedLabel = portalsLabel(size: 15, weight: .regular, color: PortalsColors.secondary, alignment: .center)
    private let emptyHistoryLabel = portalsLabel(size: 15, weight: .regular, color: PortalsColors.secondary, alignment: .center)
    private var showingTon = true
    private var settingsDisposable: Disposable?
    private var tonNanos: Int64 = 0
    private var stars: Int64 = 0
    private var ownedGiftsRaw: String = ""
    private var purchaseHistoryRaw: String = ""

    init(context: AccountContext, presenter: ViewController?) {
        self.context = context
        self.presenter = presenter
        super.init(frame: .zero)
        self.backgroundColor = PortalsColors.background

        self.scrollView.alwaysBounceVertical = true
        self.scrollView.showsVerticalScrollIndicator = false
        self.addSubview(self.scrollView)

        self.balanceCard.onLongPress = { [weak self] in
            self?.showBalanceEditor()
        }
        self.scrollView.addSubview(self.balanceCard)

        self.sectionTitle.text = "🎁 Gift Showcase"
        self.scrollView.addSubview(self.sectionTitle)

        self.tabTon.setTitle("💎 TON", for: .normal)
        self.tabTon.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        self.tabTon.addTarget(self, action: #selector(switchToTon), for: .touchUpInside)
        self.scrollView.addSubview(self.tabTon)

        self.tabStars.setTitle("⭐ Stars", for: .normal)
        self.tabStars.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        self.tabStars.addTarget(self, action: #selector(switchToStars), for: .touchUpInside)
        self.scrollView.addSubview(self.tabStars)

        for gift in pampGramFakePortalsGifts {
            let cell = PampGramFakePortalsGiftCell(gift: gift)
            cell.addTarget(self, action: #selector(giftTapped(_:)), for: .touchUpInside)
            self.giftCells.append(cell)
            self.scrollView.addSubview(cell)
        }

        self.ownedHeader.text = "My Gifts"
        self.scrollView.addSubview(self.ownedHeader)

        self.historyHeader.text = "Purchase History"
        self.scrollView.addSubview(self.historyHeader)

        self.emptyOwnedLabel.text = "No gifts yet"
        self.emptyOwnedLabel.numberOfLines = 0
        self.scrollView.addSubview(self.emptyOwnedLabel)

        self.emptyHistoryLabel.text = "No purchases yet"
        self.emptyHistoryLabel.numberOfLines = 0
        self.scrollView.addSubview(self.emptyHistoryLabel)

        self.updateTabs()

        self.settingsDisposable = (PampGramCore.settingsSignal(postbox: context.account.postbox)
        |> deliverOnMainQueue).start(next: { [weak self] settings in
            guard let self else { return }
            self.tonNanos = settings.fakePortalsBalanceTonNanos
            self.stars = settings.fakePortalsBalanceStars
            self.ownedGiftsRaw = settings.fakePortalsOwnedGiftsRaw
            self.purchaseHistoryRaw = settings.fakePortalsPurchaseHistoryRaw
            self.balanceCard.update(tonNanos: self.tonNanos, stars: self.stars)
            self.rebuildOwnedAndHistory()
            self.setNeedsLayout()
        })
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        self.settingsDisposable?.dispose()
    }

    func goBack() {}

    @objc private func switchToTon() {
        self.showingTon = true
        self.updateTabs()
        self.updateGiftPrices()
    }

    @objc private func switchToStars() {
        self.showingTon = false
        self.updateTabs()
        self.updateGiftPrices()
    }

    private func updateTabs() {
        if self.showingTon {
            self.tabTon.backgroundColor = PortalsColors.accent
            self.tabTon.setTitleColor(.white, for: .normal)
            self.tabStars.backgroundColor = PortalsColors.card
            self.tabStars.setTitleColor(PortalsColors.secondary, for: .normal)
        } else {
            self.tabStars.backgroundColor = PortalsColors.accent
            self.tabStars.setTitleColor(.white, for: .normal)
            self.tabTon.backgroundColor = PortalsColors.card
            self.tabTon.setTitleColor(PortalsColors.secondary, for: .normal)
        }
        self.tabTon.layer.cornerRadius = 16
        self.tabStars.layer.cornerRadius = 16
    }

    private func updateGiftPrices() {
        for cell in self.giftCells {
            if self.showingTon {
                cell.accessibilityLabel = "💎 \(Int(cell.gift.priceTon)) TON"
            } else {
                cell.accessibilityLabel = "⭐ \(cell.gift.priceStars)"
            }
        }
    }

    private func rebuildOwnedAndHistory() {
        for row in self.ownedRows { row.removeFromSuperview() }
        self.ownedRows.removeAll()
        for row in self.historyRows { row.removeFromSuperview() }
        self.historyRows.removeAll()

        let ownedEntries = parseOwnedGifts(self.ownedGiftsRaw)
        for entry in ownedEntries {
            let gift = pampGramFakePortalsGifts.first(where: { $0.id == entry.giftId })
            let row = PampGramFakePortalsOwnedRow(
                giftName: gift?.name ?? entry.giftId,
                emoji: gift?.emoji ?? "🎁",
                date: entry.date
            )
            self.ownedRows.append(row)
            self.scrollView.addSubview(row)
        }

        let historyEntries = parsePurchaseHistory(self.purchaseHistoryRaw)
        for entry in historyEntries {
            let gift = pampGramFakePortalsGifts.first(where: { $0.id == entry.giftId })
            let row = PampGramFakePortalsHistoryRow(
                giftName: gift?.name ?? entry.giftId,
                emoji: gift?.emoji ?? "🎁",
                amount: entry.amount,
                date: entry.date
            )
            self.historyRows.append(row)
            self.scrollView.addSubview(row)
        }

        self.emptyOwnedLabel.isHidden = !self.ownedRows.isEmpty
        self.emptyHistoryLabel.isHidden = !self.historyRows.isEmpty
    }

    private struct OwnedEntry {
        let giftId: String
        let date: String
    }

    private struct HistoryEntry {
        let giftId: String
        let amount: String
        let date: String
    }

    private func parseOwnedGifts(_ raw: String) -> [OwnedEntry] {
        guard !raw.isEmpty else { return [] }
        return raw.split(separator: ";").compactMap { part in
            let components = part.split(separator: ",", maxSplits: 1)
            guard components.count == 2 else { return nil }
            return OwnedEntry(giftId: String(components[0]), date: String(components[1]))
        }
    }

    private func parsePurchaseHistory(_ raw: String) -> [HistoryEntry] {
        guard !raw.isEmpty else { return [] }
        return raw.split(separator: ";").compactMap { part in
            let components = part.split(separator: ",", maxSplits: 2)
            guard components.count == 3 else { return nil }
            return HistoryEntry(giftId: String(components[0]), amount: String(components[1]), date: String(components[2]))
        }
    }

    @objc private func giftTapped(_ sender: PampGramFakePortalsGiftCell) {
        let gift = sender.gift
        self.showPurchaseConfirmation(gift: gift)
    }

    private func showPurchaseConfirmation(gift: PampGramFakePortalsGift) {
        guard let presenter = self.presenter else { return }
        let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
        let sheet = ActionSheetController(presentationData: presentationData)

        let priceText = self.showingTon ? "💎 \(Int(gift.priceTon)) TON" : "⭐ \(gift.priceStars) Stars"
        var items: [ActionSheetItem] = [
            ActionSheetTextItem(title: "\(gift.emoji) \(gift.name)\n\(gift.rarity) • \(priceText)")
        ]

        items.append(ActionSheetButtonItem(title: "Купить за \(priceText)", color: .accent, action: { [weak self, weak sheet] in
            sheet?.dismissAnimated()
            self?.executePurchase(gift: gift)
        }))

        sheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                })
            ])
        ])
        presenter.present(sheet, in: .window(.root))
    }

    private func executePurchase(gift: PampGramFakePortalsGift) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy HH:mm"
        let dateStr = dateFormatter.string(from: Date())

        let _ = PampGramCore.updateSettingsInteractively(postbox: self.context.account.postbox, { [weak self] settings in
            var settings = settings
            guard let self else { return settings }

            if self.showingTon {
                let costNanos = Int64(gift.priceTon * 1_000_000_000)
                settings.fakePortalsBalanceTonNanos = max(0, settings.fakePortalsBalanceTonNanos - costNanos)

                let historyEntry = "\(gift.id),\(Int(gift.priceTon)) TON,\(dateStr)"
                if settings.fakePortalsPurchaseHistoryRaw.isEmpty {
                    settings.fakePortalsPurchaseHistoryRaw = historyEntry
                } else {
                    settings.fakePortalsPurchaseHistoryRaw = historyEntry + ";" + settings.fakePortalsPurchaseHistoryRaw
                }
            } else {
                settings.fakePortalsBalanceStars = max(0, settings.fakePortalsBalanceStars - Int64(gift.priceStars))

                let historyEntry = "\(gift.id),\(gift.priceStars) Stars,\(dateStr)"
                if settings.fakePortalsPurchaseHistoryRaw.isEmpty {
                    settings.fakePortalsPurchaseHistoryRaw = historyEntry
                } else {
                    settings.fakePortalsPurchaseHistoryRaw = historyEntry + ";" + settings.fakePortalsPurchaseHistoryRaw
                }
            }

            let ownedEntry = "\(gift.id),\(dateStr)"
            if settings.fakePortalsOwnedGiftsRaw.isEmpty {
                settings.fakePortalsOwnedGiftsRaw = ownedEntry
            } else {
                settings.fakePortalsOwnedGiftsRaw = ownedEntry + ";" + settings.fakePortalsOwnedGiftsRaw
            }

            return settings
        }).start()

        if let presenter = self.presenter {
            let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
            presenter.present(
                UndoOverlayController(
                    presentationData: presentationData,
                    content: .succeed(text: "\(gift.emoji) \(gift.name) куплен!", timeout: nil, customUndoText: nil),
                    elevatedLayout: false,
                    action: { _ in return false }
                ),
                in: .current
            )
        }
    }

    private func showBalanceEditor() {
        guard let presenter = self.presenter else { return }
        let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
        let sheet = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = [ActionSheetTextItem(title: "Какой баланс изменить?")]

        items.append(ActionSheetButtonItem(title: "💎 TON — \(portalsFormatTon(self.tonNanos))", color: .accent, action: { [weak self, weak sheet] in
            sheet?.dismissAnimated()
            self?.promptTonBalance()
        }))

        items.append(ActionSheetButtonItem(title: "⭐ Stars — \(portalsFormatStars(self.stars))", color: .accent, action: { [weak self, weak sheet] in
            sheet?.dismissAnimated()
            self?.promptStarsBalance()
        }))

        sheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                })
            ])
        ])
        presenter.present(sheet, in: .window(.root))
    }

    private func promptTonBalance() {
        guard let presenter = self.presenter else { return }
        let current = Double(self.tonNanos) / 1_000_000_000.0
        presenter.present(promptController(
            context: self.context,
            text: "Баланс TON",
            subtitle: "Введите сумму в TON. Хранится только на устройстве.",
            value: current > 0 ? "\(current)" : "",
            placeholder: "0",
            characterLimit: 24,
            apply: { [weak self] entered in
                guard let self, let entered else { return }
                let cleaned = entered.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")
                var value = Double(cleaned) ?? 0
                if !value.isFinite || value < 0 { value = 0 }
                value = min(value, 1e12)
                let nanos = Int64(value * 1_000_000_000)
                let _ = PampGramCore.updateSettingsInteractively(postbox: self.context.account.postbox, { settings in
                    var settings = settings
                    settings.fakePortalsBalanceTonNanos = nanos
                    return settings
                }).start()
            }
        ), in: .window(.root))
    }

    private func promptStarsBalance() {
        guard let presenter = self.presenter else { return }
        presenter.present(promptController(
            context: self.context,
            text: "Баланс Stars",
            subtitle: "Введите количество Stars. Хранится только на устройстве.",
            value: self.stars > 0 ? "\(self.stars)" : "",
            placeholder: "0",
            characterLimit: 15,
            apply: { [weak self] entered in
                guard let self, let entered else { return }
                let cleaned = entered.replacingOccurrences(of: " ", with: "")
                var value = Int64(cleaned) ?? 0
                if value < 0 { value = 0 }
                value = min(value, 999_999_999_999)
                let _ = PampGramCore.updateSettingsInteractively(postbox: self.context.account.postbox, { settings in
                    var settings = settings
                    settings.fakePortalsBalanceStars = value
                    return settings
                }).start()
            }
        ), in: .window(.root))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = self.bounds.width
        let pad: CGFloat = 16.0
        let contentWidth = w - pad * 2

        self.scrollView.frame = self.bounds

        var y: CGFloat = 16.0
        self.balanceCard.frame = CGRect(x: pad, y: y, width: contentWidth, height: 120)
        y += 136

        self.sectionTitle.frame = CGRect(x: pad, y: y, width: contentWidth, height: 28)
        y += 36

        let tabW = (contentWidth - 8) / 2
        self.tabTon.frame = CGRect(x: pad, y: y, width: tabW, height: 32)
        self.tabStars.frame = CGRect(x: pad + tabW + 8, y: y, width: tabW, height: 32)
        y += 44

        let columns = 3
        let spacing: CGFloat = 8
        let cellW = (contentWidth - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let cellH: CGFloat = 120

        for (i, cell) in self.giftCells.enumerated() {
            let col = i % columns
            let row = i / columns
            let cx = pad + CGFloat(col) * (cellW + spacing)
            let cy = y + CGFloat(row) * (cellH + spacing)
            cell.frame = CGRect(x: cx, y: cy, width: cellW, height: cellH)
        }

        let gridRows = (self.giftCells.count + columns - 1) / columns
        y += CGFloat(gridRows) * (cellH + spacing) + 8

        self.ownedHeader.frame = CGRect(x: pad, y: y, width: contentWidth, height: 24)
        y += 32

        if self.ownedRows.isEmpty {
            self.emptyOwnedLabel.frame = CGRect(x: pad, y: y, width: contentWidth, height: 40)
            y += 48
        } else {
            for row in self.ownedRows {
                row.frame = CGRect(x: pad, y: y, width: contentWidth, height: 56)
                y += 56
            }
            y += 8
        }

        self.historyHeader.frame = CGRect(x: pad, y: y, width: contentWidth, height: 24)
        y += 32

        if self.historyRows.isEmpty {
            self.emptyHistoryLabel.frame = CGRect(x: pad, y: y, width: contentWidth, height: 40)
            y += 48
        } else {
            for row in self.historyRows {
                row.frame = CGRect(x: pad, y: y, width: contentWidth, height: 56)
                y += 56
            }
            y += 8
        }

        y += 40
        self.scrollView.contentSize = CGSize(width: w, height: y)
    }
}

// MARK: - Standalone Screen

private final class PampGramFakePortalsScreen: ViewController {
    private let context: AccountContext
    private var contentView: PampGramFakePortalsContentView?

    init(context: AccountContext, title: String = "Portals") {
        self.context = context
        super.init(navigationBarPresentationData: NavigationBarPresentationData(
            presentationData: context.sharedContext.currentPresentationData.with { $0 }
        ))
        self.title = title
        self.navigationItem.largeTitleDisplayMode = .never
    }

    required init(coder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNode.backgroundColor = PortalsColors.background
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let cv = PampGramFakePortalsContentView(context: self.context, presenter: self)
        self.contentView = cv
        self.displayNode.view.addSubview(cv)
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let top = (layout.statusBarHeight ?? 0.0) + (self.navigationHeight ?? 44.0)
        self.contentView?.frame = CGRect(x: 0, y: top, width: layout.size.width, height: layout.size.height - top)
    }
}

// MARK: - Public

public func pampGramFakePortalsController(context: AccountContext, title: String = "Portals") -> ViewController {
    return PampGramFakePortalsScreen(context: context, title: title)
}

public func pampGramFakePortalsContentView(context: AccountContext, presenter: ViewController) -> PampGramFakeMiniAppContent {
    return PampGramFakePortalsContentView(context: context, presenter: presenter)
}
