import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramPresentationData
import AccountContext
import PampGramCore

/// Portals Market — visual-only mini-market styled after the real
/// portals-market Telegram mini-app. Standalone VC with a plain UIKit
/// view hierarchy (no ItemListNode): the market is a vertical scroll of
/// a balance row, a Halloween event banner with a live countdown, four
/// section tiles (Все / Коллекции / Звезды / Крафт), a filter chip
/// strip, and a list of item rows. Taps on a row open the detail VC;
/// taps on the GRAM pill open the balance editor.
///
/// Everything on this screen is local. "Buying" an item debits
/// `fakeTonBalanceNanos` (shown as GRAM) and credits `fakeStarsBalance`
/// (shown as ✦) via `PampGramLocalLedgerStore.addAndApply`.
public func pampGramPortalsScreenController(context: AccountContext) -> ViewController {
    return PampGramPortalsControllerImpl(context: context)
}

private enum PortalsPalette {
    static let surface          = UIColor(white: 0.043, alpha: 1.0)  // #0B0B0F
    static let surfaceElevated  = UIColor(white: 0.078, alpha: 1.0)  // #14141A
    static let surfaceChip      = UIColor(white: 0.118, alpha: 1.0)  // #1E1E26
    static let accentPrimary    = UIColor(red: 0.10, green: 0.79, blue: 1.00, alpha: 1.0)
    static let accentStars      = UIColor(red: 1.00, green: 0.71, blue: 0.00, alpha: 1.0)
    static let accentCraft      = UIColor(red: 0.18, green: 0.82, blue: 0.48, alpha: 1.0)
    static let accentLucky      = UIColor(red: 0.16, green: 0.35, blue: 0.18, alpha: 1.0)
    static let starsPillBg      = UIColor(red: 0.16, green: 0.12, blue: 0.04, alpha: 1.0)
    static let gramPillBg       = UIColor(red: 0.03, green: 0.15, blue: 0.23, alpha: 1.0)
    static let starsPillStroke  = UIColor(red: 1.00, green: 0.71, blue: 0.00, alpha: 0.4)
    static let gramPillStroke   = UIColor(red: 0.10, green: 0.79, blue: 1.00, alpha: 0.4)
    static let eventTop         = UIColor(red: 0.29, green: 0.12, blue: 0.38, alpha: 1.0)
    static let eventMid         = UIColor(red: 0.16, green: 0.05, blue: 0.23, alpha: 1.0)
    static let eventBottom      = UIColor(red: 0.10, green: 0.02, blue: 0.13, alpha: 1.0)
}

private final class PampGramPortalsControllerImpl: ViewController {
    private let context: AccountContext
    private let presentationData: PresentationData
    private var portalsNode: PampGramPortalsNode?

    init(context: AccountContext) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }

        // Portals is always dark — build a navigation bar theme that reads black and keeps the
        // Portals accent for the back-button chevron so it still contrasts.
        let navTheme = NavigationBarTheme(
            overallDarkAppearance: true,
            buttonColor: .white,
            disabledButtonColor: UIColor(white: 1.0, alpha: 0.5),
            primaryTextColor: .white,
            backgroundColor: PortalsPalette.surface,
            enableBackgroundBlur: false,
            separatorColor: UIColor(white: 1.0, alpha: 0.08),
            badgeBackgroundColor: PortalsPalette.accentPrimary,
            badgeStrokeColor: PortalsPalette.accentPrimary,
            badgeTextColor: .black,
            accentButtonColor: PortalsPalette.accentPrimary,
            accentDisabledButtonColor: UIColor(white: 1.0, alpha: 0.5),
            accentForegroundColor: .white
        )
        super.init(navigationBarPresentationData: NavigationBarPresentationData(
            theme: navTheme,
            strings: NavigationBarStrings(presentationStrings: self.presentationData.strings)
        ))

        self.statusBar.statusBarStyle = .White
        self.navigationPresentation = .default
        self.title = "Portals Market"
        self.navigationItem.backBarButtonItem = UIBarButtonItem(
            title: self.presentationData.strings.Common_Back, style: .plain, target: nil, action: nil)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadDisplayNode() {
        self.displayNode = ViewControllerTracingNode()
        self.displayNode.backgroundColor = PortalsPalette.surface

        let portalsNode = PampGramPortalsNode(context: self.context, present: { [weak self] controller in
            self?.present(controller, in: .window(.root))
        }, push: { [weak self] controller in
            self?.push(controller)
        })
        self.portalsNode = portalsNode
        self.displayNode.view.addSubview(portalsNode)

        self.displayNodeDidLoad()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.portalsNode?.startCountdown()
        self.portalsNode?.reloadSettings()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.portalsNode?.stopCountdown()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let navHeight: CGFloat = 44.0
        let topInset = (layout.statusBarHeight ?? 20.0) + navHeight
        self.portalsNode?.frame = CGRect(origin: .zero, size: layout.size)
        self.portalsNode?.updateLayout(size: layout.size, topInset: topInset, bottomInset: layout.intrinsicInsets.bottom)
    }
}

// MARK: - Portals root view (not a display node, a plain UIView wrapping a UIScrollView)

private final class PampGramPortalsNode: UIView {
    private let context: AccountContext
    private let present: (ViewController) -> Void
    private let push: (ViewController) -> Void

    private let scrollView = UIScrollView()
    private let contentView = UIStackView()

    // Live-updating subviews
    private var starsPill: PortalsPillButton!
    private var gramPill: PortalsPillButton!
    private var countdownLabel: UILabel!
    private var itemsStack: UIStackView!
    private var collectionChip: PortalsDropChip!
    private var filterClearChip: PortalsIconChip!
    private var sectionTiles: [PortalsSectionTile] = []

    // State
    private var selectedCollection: String?
    private var eventEnd: Date
    // Disambiguate: Foundation's Timer, not SwiftSignalKit's. The latter is also in scope via
    // the `SwiftSignalKit` import and would otherwise clash.
    private var countdownTimer: Foundation.Timer?

    private var fakeTonNanos: Int64 = 0
    private var fakeStars: Int64 = 0
    private var settingsDisposable: Disposable?

    init(context: AccountContext, present: @escaping (ViewController) -> Void, push: @escaping (ViewController) -> Void) {
        self.context = context
        self.present = present
        self.push = push
        self.eventEnd = Date().addingTimeInterval(7 * 24 * 60 * 60)
        super.init(frame: .zero)
        self.backgroundColor = PortalsPalette.surface

        self.scrollView.alwaysBounceVertical = true
        self.scrollView.showsVerticalScrollIndicator = false
        self.scrollView.contentInsetAdjustmentBehavior = .never
        self.addSubview(self.scrollView)

        self.contentView.axis = .vertical
        self.contentView.spacing = 0
        self.contentView.alignment = .fill
        self.scrollView.addSubview(self.contentView)

        self.buildContent()
        self.subscribeToSettings()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        self.settingsDisposable?.dispose()
        self.countdownTimer?.invalidate()
    }

    func updateLayout(size: CGSize, topInset: CGFloat, bottomInset: CGFloat) {
        self.scrollView.frame = CGRect(origin: .zero, size: size)
        self.scrollView.contentInset = UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset + 24, right: 0)
        let width = size.width
        let contentHeight = self.contentView.systemLayoutSizeFitting(
            CGSize(width: width, height: .greatestFiniteMagnitude),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        self.contentView.frame = CGRect(origin: .zero, size: CGSize(width: width, height: contentHeight))
        self.scrollView.contentSize = CGSize(width: width, height: contentHeight)
    }

    // MARK: - Settings pipeline

    private func subscribeToSettings() {
        let signal = PampGramCore.rawSettingsSignal(postbox: self.context.account.postbox) |> deliverOnMainQueue
        self.settingsDisposable = signal.start(next: { [weak self] settings in
            guard let self else { return }
            self.fakeTonNanos = settings.fakeTonBalanceNanos
            self.fakeStars = settings.fakeStarsBalance
            self.updateBalancePills()
        })
    }

    func reloadSettings() {
        // Pulled on viewWillAppear in case the detail screen's buy mutated the store while this
        // view wasn't observing — the Signal subscription will catch it, but a nudge here keeps
        // the pills right the moment we come back.
    }

    private func updateBalancePills() {
        self.starsPill.setText("✨ \(PampGramPortalsCatalog.formatCompact(Int(min(Int64(Int.max), self.fakeStars))))")
        self.gramPill.setText("💎 \(PampGramPortalsCatalog.formatGram(self.fakeTonNanos)) GRAM")
    }

    // MARK: - Content construction

    private func buildContent() {
        self.contentView.addArrangedSubview(self.buildBalanceRow())
        self.contentView.addArrangedSubview(self.buildEventBanner())
        self.contentView.addArrangedSubview(self.buildSectionTilesRow())
        self.contentView.addArrangedSubview(self.buildFilterChipsRow())

        let listContainer = UIView()
        listContainer.backgroundColor = .clear
        listContainer.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12)

        self.itemsStack = UIStackView()
        self.itemsStack.axis = .vertical
        self.itemsStack.spacing = 10
        self.itemsStack.translatesAutoresizingMaskIntoConstraints = false
        listContainer.addSubview(self.itemsStack)
        NSLayoutConstraint.activate([
            self.itemsStack.leadingAnchor.constraint(equalTo: listContainer.layoutMarginsGuide.leadingAnchor),
            self.itemsStack.trailingAnchor.constraint(equalTo: listContainer.layoutMarginsGuide.trailingAnchor),
            self.itemsStack.topAnchor.constraint(equalTo: listContainer.layoutMarginsGuide.topAnchor),
            self.itemsStack.bottomAnchor.constraint(equalTo: listContainer.layoutMarginsGuide.bottomAnchor)
        ])
        self.contentView.addArrangedSubview(listContainer)
        self.rebuildItems()

        let footer = UILabel()
        footer.text = "Portals Market визуально. Покупка списывает фейковый GRAM и зачисляет звёзды в награду. Ничего не уходит на сервер."
        footer.textColor = UIColor(white: 1.0, alpha: 0.4)
        footer.font = .systemFont(ofSize: 12)
        footer.numberOfLines = 0
        footer.textAlignment = .center
        let footerWrap = UIView()
        footerWrap.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 18, leading: 24, bottom: 6, trailing: 24)
        footerWrap.addSubview(footer)
        footer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            footer.leadingAnchor.constraint(equalTo: footerWrap.layoutMarginsGuide.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: footerWrap.layoutMarginsGuide.trailingAnchor),
            footer.topAnchor.constraint(equalTo: footerWrap.layoutMarginsGuide.topAnchor),
            footer.bottomAnchor.constraint(equalTo: footerWrap.layoutMarginsGuide.bottomAnchor)
        ])
        self.contentView.addArrangedSubview(footerWrap)
    }

    private func buildBalanceRow() -> UIView {
        let row = UIView()
        row.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 2, trailing: 16)

        self.starsPill = PortalsPillButton(bg: PortalsPalette.starsPillBg, stroke: PortalsPalette.starsPillStroke)
        self.starsPill.action = { [weak self] in self?.editStarsBalance() }

        self.gramPill = PortalsPillButton(bg: PortalsPalette.gramPillBg, stroke: PortalsPalette.gramPillStroke)
        self.gramPill.action = { [weak self] in self?.openXRocket() }
        // Long-press keeps the raw balance editor for debugging — tap goes to
        // xRocket, which is how a real user tops up their fake GRAM balance.
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(self.gramPillLongPressed(_:)))
        self.gramPill.addGestureRecognizer(longPress)

        row.addSubview(self.starsPill)
        row.addSubview(self.gramPill)
        self.starsPill.translatesAutoresizingMaskIntoConstraints = false
        self.gramPill.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            self.starsPill.leadingAnchor.constraint(equalTo: row.layoutMarginsGuide.leadingAnchor),
            self.starsPill.topAnchor.constraint(equalTo: row.layoutMarginsGuide.topAnchor),
            self.starsPill.bottomAnchor.constraint(equalTo: row.layoutMarginsGuide.bottomAnchor),
            self.gramPill.trailingAnchor.constraint(equalTo: row.layoutMarginsGuide.trailingAnchor),
            self.gramPill.centerYAnchor.constraint(equalTo: self.starsPill.centerYAnchor)
        ])
        return row
    }

    private func buildEventBanner() -> UIView {
        let banner = PortalsGradientView(colors: [PortalsPalette.eventTop, PortalsPalette.eventMid, PortalsPalette.eventBottom], horizontal: true)
        banner.layer.cornerRadius = 18
        banner.layer.borderWidth = 1
        banner.layer.borderColor = UIColor(white: 1.0, alpha: 0.2).cgColor
        banner.clipsToBounds = true

        let title = UILabel()
        title.text = "Halloween турнир"
        title.textColor = .white
        title.font = .systemFont(ofSize: 20, weight: .bold)

        self.countdownLabel = UILabel()
        self.countdownLabel.textColor = .white
        self.countdownLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        self.countdownLabel.backgroundColor = UIColor(white: 0.0, alpha: 0.3)
        self.countdownLabel.layer.cornerRadius = 12
        self.countdownLabel.clipsToBounds = true
        self.countdownLabel.textAlignment = .center
        // Insets via a container-free padding trick: setting attributed text with a line fragment
        // padding is too fiddly; use fixed width constraints and centred text instead.

        let leftStack = UIStackView(arrangedSubviews: [title, self.countdownLabel])
        leftStack.axis = .vertical
        leftStack.alignment = .leading
        leftStack.spacing = 10
        leftStack.translatesAutoresizingMaskIntoConstraints = false

        let pumpkins = UILabel()
        pumpkins.text = "🎃🎃🎃"
        pumpkins.font = .systemFont(ofSize: 40)
        pumpkins.translatesAutoresizingMaskIntoConstraints = false

        banner.addSubview(leftStack)
        banner.addSubview(pumpkins)
        NSLayoutConstraint.activate([
            leftStack.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 18),
            leftStack.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            pumpkins.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -16),
            pumpkins.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            self.countdownLabel.heightAnchor.constraint(equalToConstant: 26),
            self.countdownLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 110)
        ])

        let wrap = UIView()
        wrap.addSubview(banner)
        banner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            banner.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 16),
            banner.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -16),
            banner.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 12),
            banner.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -16),
            banner.heightAnchor.constraint(equalToConstant: 110)
        ])
        self.updateCountdownLabel()
        return wrap
    }

    private func buildSectionTilesRow() -> UIView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 8
        stack.alignment = .top
        stack.translatesAutoresizingMaskIntoConstraints = false

        let tiles: [(String, String, Bool, () -> Void)] = [
            ("🎁", "Все",       true,  { [weak self] in self?.selectedCollection = nil; self?.rebuildFilterUI(); self?.rebuildItems() }),
            ("👤", "Коллекции", false, { [weak self] in self?.openCollectionPicker() }),
            ("⭐", "Звезды",    false, { [weak self] in self?.showComingSoon("Звёзды") }),
            ("⛏️", "Крафт",    false, { [weak self] in self?.showComingSoon("Крафт") })
        ]
        for (emoji, label, active, action) in tiles {
            let tile = PortalsSectionTile(emoji: emoji, label: label, active: active)
            tile.action = action
            stack.addArrangedSubview(tile)
            self.sectionTiles.append(tile)
        }

        let wrap = UIView()
        wrap.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: 4)
        ])
        return wrap
    }

    private func buildFilterChipsRow() -> UIView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        let filterChip = PortalsIconChip(glyph: "⚙")
        filterChip.action = { [weak self] in self?.showComingSoon("Фильтры") }
        stack.addArrangedSubview(filterChip)

        let sortChip = PortalsIconChip(glyph: "⇅")
        sortChip.action = { [weak self] in self?.showComingSoon("Сортировка") }
        stack.addArrangedSubview(sortChip)

        let divider = UIView()
        divider.backgroundColor = UIColor(white: 1.0, alpha: 0.2)
        divider.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.heightAnchor.constraint(equalToConstant: 22)
        ])
        stack.addArrangedSubview(divider)

        self.filterClearChip = PortalsIconChip(glyph: "✕")
        self.filterClearChip.action = { [weak self] in
            self?.selectedCollection = nil
            self?.rebuildFilterUI()
            self?.rebuildItems()
        }
        self.filterClearChip.isHidden = true
        stack.addArrangedSubview(self.filterClearChip)

        self.collectionChip = PortalsDropChip(label: "Коллекция")
        self.collectionChip.action = { [weak self] in self?.openCollectionPicker() }
        stack.addArrangedSubview(self.collectionChip)

        let modelChip = PortalsDropChip(label: "Модель")
        modelChip.action = { [weak self] in self?.showComingSoon("Фильтр модели") }
        stack.addArrangedSubview(modelChip)

        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: scroll.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor),
            stack.heightAnchor.constraint(equalToConstant: 34)
        ])
        let wrap = UIView()
        wrap.addSubview(scroll)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 8),
            scroll.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -8),
            scroll.heightAnchor.constraint(equalToConstant: 34)
        ])
        return wrap
    }

    private func rebuildFilterUI() {
        self.collectionChip.setLabel(self.selectedCollection == nil ? "Коллекция" : "Коллекция 1")
        self.filterClearChip.isHidden = (self.selectedCollection == nil)
    }

    private func rebuildItems() {
        self.itemsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let visible = PampGramPortalsCatalog.items(in: self.selectedCollection)
        if visible.isEmpty {
            let empty = UILabel()
            empty.text = "В этой коллекции пока пусто."
            empty.textColor = UIColor(white: 1.0, alpha: 0.6)
            empty.font = .systemFont(ofSize: 14)
            empty.textAlignment = .center
            self.itemsStack.addArrangedSubview(empty)
            return
        }
        for item in visible {
            let row = PortalsItemRow(item: item)
            row.action = { [weak self] in
                guard let self else { return }
                self.push(pampGramPortalsDetailController(context: self.context, itemId: item.id))
            }
            self.itemsStack.addArrangedSubview(row)
        }
    }

    // MARK: - Countdown

    func startCountdown() {
        self.countdownTimer?.invalidate()
        let timer = Foundation.Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateCountdownLabel()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.countdownTimer = timer
        self.updateCountdownLabel()
    }

    func stopCountdown() {
        self.countdownTimer?.invalidate()
        self.countdownTimer = nil
    }

    private func updateCountdownLabel() {
        let interval = max(0, Int(self.eventEnd.timeIntervalSinceNow))
        let days = interval / 86400
        let hours = (interval / 3600) % 24
        let mins = (interval / 60) % 60
        let secs = interval % 60
        self.countdownLabel.text = "  \(days):\(String(format: "%02d", hours)):\(String(format: "%02d", mins)):\(String(format: "%02d", secs))  "
    }

    // MARK: - Pickers and balance editors

    private func openCollectionPicker() {
        let alert = UIAlertController(title: "Коллекция", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: (self.selectedCollection == nil ? "✓ " : "") + "Все (без фильтра)", style: .default, handler: { [weak self] _ in
            self?.selectedCollection = nil
            self?.rebuildFilterUI()
            self?.rebuildItems()
        }))
        for collection in PampGramPortalsCatalog.collections {
            let active = (self.selectedCollection == collection.name)
            let floor = PampGramPortalsCatalog.formatGram(collection.floorNanoGram)
            let title = (active ? "✓ " : "") + "\(collection.emoji) \(collection.name) — \(floor) GRAM" + (collection.isNew ? " · NEW" : "")
            alert.addAction(UIAlertAction(title: title, style: .default, handler: { [weak self] _ in
                self?.selectedCollection = collection.name
                self?.rebuildFilterUI()
                self?.rebuildItems()
            }))
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = self.collectionChip
            popover.sourceRect = self.collectionChip.bounds
        }
        self.presentUIKitAlert(alert)
    }

    private func openXRocket() {
        self.push(pampGramXRocketController(context: self.context))
    }

    @objc private func gramPillLongPressed(_ sender: UILongPressGestureRecognizer) {
        guard sender.state == .began else { return }
        self.editGramBalance()
    }

    private func editStarsBalance() {
        let alert = UIAlertController(title: "Звёзды PampGram", message: "Количество звёзд", preferredStyle: .alert)
        alert.addTextField { field in
            field.keyboardType = .numberPad
            field.text = "\(self.fakeStars)"
        }
        alert.addAction(UIAlertAction(title: "Сохранить", style: .default, handler: { [weak self, weak alert] _ in
            guard let text = alert?.textFields?.first?.text, let value = Int64(text), value >= 0, let self else { return }
            let delta = value - self.fakeStars
            let _ = self.context.account.postbox.transaction { tx in
                PampGramLocalLedgerStore.addAndApply(transaction: tx, currency: .stars,
                    kind: delta >= 0 ? .credit : .debit, amount: delta,
                    title: "Корректировка (Portals)", details: "")
            }.start()
        }))
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        self.presentUIKitAlert(alert)
    }

    private func editGramBalance() {
        let alert = UIAlertController(title: "GRAM (визуальный баланс)", message: "В нано (1 GRAM = 1 000 000 000)", preferredStyle: .alert)
        alert.addTextField { field in
            field.keyboardType = .numberPad
            field.text = "\(self.fakeTonNanos)"
        }
        alert.addAction(UIAlertAction(title: "Сохранить", style: .default, handler: { [weak self, weak alert] _ in
            guard let text = alert?.textFields?.first?.text, let value = Int64(text), value >= 0, let self else { return }
            let delta = value - self.fakeTonNanos
            let _ = self.context.account.postbox.transaction { tx in
                PampGramLocalLedgerStore.addAndApply(transaction: tx, currency: .ton,
                    kind: delta >= 0 ? .credit : .debit, amount: delta,
                    title: "Корректировка (Portals)", details: "")
            }.start()
        }))
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        self.presentUIKitAlert(alert)
    }

    private func showComingSoon(_ title: String) {
        let alert = UIAlertController(title: title, message: "Этот раздел появится в следующих версиях PampGram.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        self.presentUIKitAlert(alert)
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

// MARK: - Subcomponents

private final class PortalsPillButton: UIControl {
    private let label = UILabel()
    var action: (() -> Void)?

    init(bg: UIColor, stroke: UIColor) {
        super.init(frame: .zero)
        self.backgroundColor = bg
        self.layer.cornerRadius = 18
        self.layer.borderWidth = 1
        self.layer.borderColor = stroke.cgColor
        self.label.textColor = .white
        self.label.font = .systemFont(ofSize: 14, weight: .semibold)
        self.label.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.label)
        NSLayoutConstraint.activate([
            self.label.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 14),
            self.label.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -14),
            self.label.topAnchor.constraint(equalTo: self.topAnchor, constant: 7),
            self.label.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -7),
            self.heightAnchor.constraint(greaterThanOrEqualToConstant: 36)
        ])
        self.addTarget(self, action: #selector(self.tapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setText(_ text: String) { self.label.text = text }

    @objc private func tapped() { self.action?() }
}

private final class PortalsSectionTile: UIControl {
    private let iconHolder = UILabel()
    private let labelView = UILabel()
    var action: (() -> Void)?

    init(emoji: String, label: String, active: Bool) {
        super.init(frame: .zero)
        self.iconHolder.text = emoji
        self.iconHolder.font = .systemFont(ofSize: 30)
        self.iconHolder.textAlignment = .center
        self.iconHolder.backgroundColor = active ? UIColor(white: 0.12, alpha: 1.0) : UIColor(white: 0.075, alpha: 1.0)
        self.iconHolder.layer.cornerRadius = 22
        self.iconHolder.layer.borderWidth = 1
        self.iconHolder.layer.borderColor = active ? UIColor(white: 1.0, alpha: 0.33).cgColor : UIColor(white: 1.0, alpha: 0.1).cgColor
        self.iconHolder.clipsToBounds = true
        self.iconHolder.alpha = active ? 1.0 : 0.55
        self.iconHolder.translatesAutoresizingMaskIntoConstraints = false

        self.labelView.text = label
        self.labelView.font = .systemFont(ofSize: 13, weight: .semibold)
        self.labelView.textColor = active ? .white : UIColor(white: 1.0, alpha: 0.6)
        self.labelView.textAlignment = .center
        self.labelView.translatesAutoresizingMaskIntoConstraints = false

        self.addSubview(self.iconHolder)
        self.addSubview(self.labelView)
        NSLayoutConstraint.activate([
            self.iconHolder.topAnchor.constraint(equalTo: self.topAnchor),
            self.iconHolder.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            self.iconHolder.widthAnchor.constraint(equalToConstant: 68),
            self.iconHolder.heightAnchor.constraint(equalToConstant: 68),
            self.labelView.topAnchor.constraint(equalTo: self.iconHolder.bottomAnchor, constant: 6),
            self.labelView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.labelView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            self.labelView.bottomAnchor.constraint(equalTo: self.bottomAnchor)
        ])
        self.addTarget(self, action: #selector(self.tapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func tapped() { self.action?() }
}

private final class PortalsIconChip: UIControl {
    private let label = UILabel()
    var action: (() -> Void)?

    init(glyph: String) {
        super.init(frame: .zero)
        self.backgroundColor = PortalsPalette.surfaceChip
        self.layer.cornerRadius = 17
        self.label.text = glyph
        self.label.font = .systemFont(ofSize: 16)
        self.label.textColor = .white
        self.label.textAlignment = .center
        self.label.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.label)
        NSLayoutConstraint.activate([
            self.label.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            self.label.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            self.widthAnchor.constraint(equalToConstant: 40),
            self.heightAnchor.constraint(equalToConstant: 34)
        ])
        self.addTarget(self, action: #selector(self.tapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError() }
    @objc private func tapped() { self.action?() }
}

private final class PortalsDropChip: UIControl {
    private let label = UILabel()
    var action: (() -> Void)?

    init(label: String) {
        super.init(frame: .zero)
        self.backgroundColor = PortalsPalette.surfaceChip
        self.layer.cornerRadius = 17
        self.label.font = .systemFont(ofSize: 13, weight: .semibold)
        self.label.textColor = .white
        self.label.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.label)
        NSLayoutConstraint.activate([
            self.label.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 14),
            self.label.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -14),
            self.label.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            self.heightAnchor.constraint(equalToConstant: 34)
        ])
        self.setLabel(label)
        self.addTarget(self, action: #selector(self.tapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setLabel(_ text: String) {
        self.label.text = "\(text)  ▾"
    }

    @objc private func tapped() { self.action?() }
}

private final class PortalsItemRow: UIControl {
    var action: (() -> Void)?

    init(item: PampGramPortalsCatalog.Item) {
        super.init(frame: .zero)
        self.backgroundColor = PortalsPalette.surfaceElevated
        self.layer.cornerRadius = 18
        self.layer.masksToBounds = true

        let icon = PortalsGradientView(colors: [item.gradientTop, item.gradientBottom], horizontal: false)
        icon.layer.cornerRadius = 14
        icon.layer.borderWidth = 1
        icon.layer.borderColor = UIColor(white: 1.0, alpha: 0.13).cgColor
        icon.clipsToBounds = true
        icon.translatesAutoresizingMaskIntoConstraints = false

        let iconGlyph = UILabel()
        iconGlyph.text = item.emoji
        iconGlyph.font = .systemFont(ofSize: 28)
        iconGlyph.textAlignment = .center
        iconGlyph.translatesAutoresizingMaskIntoConstraints = false
        icon.addSubview(iconGlyph)
        NSLayoutConstraint.activate([
            iconGlyph.centerXAnchor.constraint(equalTo: icon.centerXAnchor),
            iconGlyph.centerYAnchor.constraint(equalTo: icon.centerYAnchor)
        ])

        let name = UILabel()
        name.text = item.collection
        name.font = .systemFont(ofSize: 16, weight: .bold)
        name.textColor = .white
        name.numberOfLines = 1

        let number = UILabel()
        number.text = "#\(item.number)"
        number.font = .systemFont(ofSize: 13)
        number.textColor = UIColor(white: 1.0, alpha: 0.5)

        let labels = UIStackView(arrangedSubviews: [name, number])
        labels.axis = .vertical
        labels.spacing = 2
        labels.alignment = .leading
        labels.translatesAutoresizingMaskIntoConstraints = false

        let price = UILabel()
        price.text = "\(PampGramPortalsCatalog.formatGram(item.priceNanoGram))  💎"
        price.font = .systemFont(ofSize: 14, weight: .bold)
        price.textColor = .white
        price.backgroundColor = PortalsPalette.accentPrimary
        price.layer.cornerRadius = 18
        price.clipsToBounds = true
        price.textAlignment = .center
        price.translatesAutoresizingMaskIntoConstraints = false

        let basket = UILabel()
        basket.text = "🛒"
        basket.font = .systemFont(ofSize: 16)
        basket.textAlignment = .center
        basket.backgroundColor = PortalsPalette.surfaceChip
        basket.layer.cornerRadius = 20
        basket.clipsToBounds = true
        basket.translatesAutoresizingMaskIntoConstraints = false

        self.addSubview(icon)
        self.addSubview(labels)
        self.addSubview(price)
        self.addSubview(basket)
        NSLayoutConstraint.activate([
            self.heightAnchor.constraint(equalToConstant: 76),
            icon.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 56),
            icon.heightAnchor.constraint(equalToConstant: 56),
            labels.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            labels.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: price.leadingAnchor, constant: -8),
            basket.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -10),
            basket.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            basket.widthAnchor.constraint(equalToConstant: 40),
            basket.heightAnchor.constraint(equalToConstant: 40),
            price.trailingAnchor.constraint(equalTo: basket.leadingAnchor, constant: -8),
            price.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            price.heightAnchor.constraint(equalToConstant: 34),
            price.widthAnchor.constraint(greaterThanOrEqualToConstant: 90)
        ])
        self.addTarget(self, action: #selector(self.tapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError() }
    @objc private func tapped() { self.action?() }
}

/// A plain two-color gradient view, used both for item icons and the Halloween banner. The
/// Portals look relies on these subtle vertical gradients inside each card, so a reusable
/// CAGradientLayer-backed view is cheaper than painting them per-cell in draw(_:).
final class PortalsGradientView: UIView {
    override class var layerClass: AnyClass { return CAGradientLayer.self }

    init(colors: [UIColor], horizontal: Bool) {
        super.init(frame: .zero)
        guard let gradient = self.layer as? CAGradientLayer else { return }
        gradient.colors = colors.map { $0.cgColor }
        if horizontal {
            gradient.startPoint = CGPoint(x: 0, y: 0.5)
            gradient.endPoint = CGPoint(x: 1, y: 0.5)
        } else {
            gradient.startPoint = CGPoint(x: 0.5, y: 0)
            gradient.endPoint = CGPoint(x: 0.5, y: 1)
        }
    }

    required init?(coder: NSCoder) { fatalError() }
}

