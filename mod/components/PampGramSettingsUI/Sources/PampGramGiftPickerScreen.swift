import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import ComponentFlow
import GiftItemComponent
import PhantomGiftKit
import UndoUI

/// "Не улучшенный гифт": every plain (not yet upgraded) gift of the real catalog as a grid of
/// pictures, drawn with Telegram's own gift tile. Tap one to select it, then "Добавить в профиль"
/// drops it, still plain, into the own profile — where the stock "Улучшить бесплатно" flow takes
/// over (`PampGramPhantomGiftManager.addGenericGiftToProfile`).
///
/// Opened by a long-press on "Вопросы о Telegram" in the Settings tab while the "Не улучшенный
/// гифт" switch in PampGram's gifts section is on.
public func pampGramGiftPickerController(context: AccountContext) -> ViewController {
    return PampGramGiftPickerController(context: context)
}

/// A soft fade behind the "Добавить в профиль" button so the tiles scrolling underneath it never
/// make its label hard to read.
private final class PampGramGiftPickerFadeView: UIView {
    override class var layerClass: AnyClass {
        return CAGradientLayer.self
    }

    func setColor(_ color: UIColor) {
        guard let layer = self.layer as? CAGradientLayer else {
            return
        }
        layer.colors = [color.withAlphaComponent(0.0).cgColor, color.withAlphaComponent(0.92).cgColor, color.cgColor]
        layer.locations = [0.0, 0.35, 1.0]
    }
}

private final class PampGramGiftPickerController: ViewController, UIScrollViewDelegate, UITextFieldDelegate {
    private let context: AccountContext
    private let presentationData: PresentationData

    private let scrollView = UIScrollView()
    private let addButton = UIButton(type: .custom)
    private let emptyLabel = UILabel()
    private let fadeView = PampGramGiftPickerFadeView()
    private let captionLabel = UILabel()
    private let minusButton = UIButton(type: .custom)
    private let plusButton = UIButton(type: .custom)
    private let countLabel = UILabel()
    private var quantity = 1
    private var holdDelayTimer: SwiftSignalKit.Timer?
    private var holdRepeatTimer: SwiftSignalKit.Timer?

    // The whole catalog (most expensive collectibles first) and what the search currently lets through.
    private var catalog: [StarGift.Gift] = []
    private var gifts: [StarGift.Gift] = []
    private var isCatalogLoaded = false
    private var query = ""
    private let searchContainer = UIView()
    private let searchIcon = UIImageView()
    private let searchField = UITextField()
    private let searchHeight: CGFloat = 40.0
    private var tiles: [Int64: ComponentView<Empty>] = [:]
    private var selectedGiftId: Int64?
    private var validLayout: ContainerViewLayout?
    private var isAdding = false

    private let refreshDisposable = MetaDisposable()
    private let giftsDisposable = MetaDisposable()
    private let addDisposable = MetaDisposable()

    private let columns = 3
    private let sideInset: CGFloat = 16.0
    private let spacing: CGFloat = 10.0
    private let buttonHeight: CGFloat = 50.0
    private let stepperHeight: CGFloat = 44.0
    private let stepperButtonSize: CGFloat = 44.0
    private let countLabelWidth: CGFloat = 48.0

    init(context: AccountContext) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }

        super.init(navigationBarPresentationData: NavigationBarPresentationData(
            theme: NavigationBarTheme(rootControllerTheme: self.presentationData.theme),
            strings: NavigationBarStrings(back: self.presentationData.strings.Common_Back, close: self.presentationData.strings.Common_Close)
        ))
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.holdDelayTimer?.invalidate()
        self.holdRepeatTimer?.invalidate()
        self.refreshDisposable.dispose()
        self.giftsDisposable.dispose()
        self.addDisposable.dispose()
    }

    override func loadView() {
        super.loadView()
        self.view.backgroundColor = self.presentationData.theme.list.blocksBackgroundColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = "Не улучшенный гифт"

        self.scrollView.delegate = self
        self.scrollView.alwaysBounceVertical = true
        self.scrollView.showsVerticalScrollIndicator = true
        self.scrollView.contentInsetAdjustmentBehavior = .never
        // The tiles scroll UNDER the navigation bar (which blurs them), never over it — the bar
        // is already in the view hierarchy by now, so they go in right below it.
        if let navigationBar = self.navigationBar {
            self.view.insertSubview(self.scrollView, belowSubview: navigationBar.view)
        } else {
            self.view.addSubview(self.scrollView)
        }
        self.scrollView.keyboardDismissMode = .onDrag

        // The search box is the first thing in the scrolling content, like a list's search bar.
        let listTheme = self.presentationData.theme.list
        self.searchContainer.backgroundColor = listTheme.itemBlocksBackgroundColor
        self.searchContainer.layer.cornerRadius = 12.0
        self.searchContainer.clipsToBounds = true
        self.scrollView.addSubview(self.searchContainer)

        self.searchIcon.image = UIImage(systemName: "magnifyingglass")
        self.searchIcon.tintColor = listTheme.itemSecondaryTextColor
        self.searchIcon.contentMode = .scaleAspectFit
        self.searchContainer.addSubview(self.searchIcon)

        self.searchField.attributedPlaceholder = NSAttributedString(string: "Поиск: Plush Pepe, ролекс, кольцо", attributes: [
            .foregroundColor: listTheme.itemPlaceholderTextColor,
            .font: UIFont.systemFont(ofSize: 16.0)
        ])
        self.searchField.font = UIFont.systemFont(ofSize: 16.0)
        self.searchField.textColor = listTheme.itemPrimaryTextColor
        self.searchField.tintColor = listTheme.itemAccentColor
        self.searchField.autocorrectionType = .no
        self.searchField.autocapitalizationType = .none
        self.searchField.returnKeyType = .search
        self.searchField.clearButtonMode = .whileEditing
        self.searchField.delegate = self
        self.searchField.addTarget(self, action: #selector(self.searchChanged), for: .editingChanged)
        self.searchContainer.addSubview(self.searchField)

        self.emptyLabel.text = "Каталог подарков загружается…"
        self.emptyLabel.textAlignment = .center
        self.emptyLabel.numberOfLines = 0
        self.emptyLabel.font = UIFont.systemFont(ofSize: 15.0)
        self.emptyLabel.textColor = self.presentationData.theme.list.itemSecondaryTextColor
        if let navigationBar = self.navigationBar {
            self.view.insertSubview(self.emptyLabel, belowSubview: navigationBar.view)
        } else {
            self.view.addSubview(self.emptyLabel)
        }

        self.fadeView.isUserInteractionEnabled = false
        self.fadeView.setColor(self.presentationData.theme.list.blocksBackgroundColor)
        self.view.addSubview(self.fadeView)

        self.captionLabel.textAlignment = .left
        self.captionLabel.font = UIFont.systemFont(ofSize: 15.0, weight: .semibold)
        self.captionLabel.textColor = self.presentationData.theme.list.itemPrimaryTextColor
        self.captionLabel.adjustsFontSizeToFitWidth = true
        self.captionLabel.minimumScaleFactor = 0.7
        self.view.addSubview(self.captionLabel)

        // "−  N  +": how many copies of the selected gift "Добавить в профиль" drops in. Holding
        // either button keeps counting, so 50 copies isn't 50 taps.
        for (button, title) in [(self.minusButton, "−"), (self.plusButton, "+")] {
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 26.0, weight: .medium)
            button.setTitleColor(self.presentationData.theme.list.itemAccentColor, for: .normal)
            button.setTitleColor(self.presentationData.theme.list.itemDisabledTextColor, for: .disabled)
            button.backgroundColor = self.presentationData.theme.list.itemBlocksBackgroundColor
            button.layer.cornerRadius = self.stepperButtonSize / 2.0
            button.clipsToBounds = true
            self.view.addSubview(button)
        }
        self.minusButton.addTarget(self, action: #selector(self.minusDown), for: .touchDown)
        self.plusButton.addTarget(self, action: #selector(self.plusDown), for: .touchDown)
        for button in [self.minusButton, self.plusButton] {
            button.addTarget(self, action: #selector(self.stepperReleased), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
        }

        self.countLabel.textAlignment = .center
        self.countLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 22.0, weight: .semibold)
        self.countLabel.textColor = self.presentationData.theme.list.itemPrimaryTextColor
        self.view.addSubview(self.countLabel)

        self.addButton.layer.cornerRadius = self.buttonHeight / 2.0
        self.addButton.clipsToBounds = true
        self.addButton.titleLabel?.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        self.addButton.setTitleColor(self.presentationData.theme.list.itemCheckColors.foregroundColor, for: .normal)
        self.addButton.addTarget(self, action: #selector(self.addPressed), for: .touchUpInside)
        self.view.addSubview(self.addButton)
        self.updateButton()

        // Same refresh trigger + cache read the other PampGram gift screens use.
        self.refreshDisposable.set(self.context.engine.payments.keepStarGiftsUpdated().start())
        self.giftsDisposable.set((self.context.engine.payments.cachedStarGifts()
        |> filter { $0 != nil }
        |> take(1)
        |> deliverOnMainQueue).start(next: { [weak self] starGifts in
            guard let self else {
                return
            }
            self.refreshDisposable.set(nil)
            let generic: [StarGift.Gift] = (starGifts ?? []).compactMap { starGift in
                if case let .generic(gift) = starGift {
                    return gift
                }
                return nil
            }
            // Limited and sold-out gifts first (the collectible ones people look for), then the
            // unlimited ones, each group most expensive first.
            self.catalog = generic.sorted(by: { lhs, rhs in
                let lhsLimited = lhs.soldOut != nil || lhs.availability != nil
                let rhsLimited = rhs.soldOut != nil || rhs.availability != nil
                if lhsLimited != rhsLimited {
                    return lhsLimited
                }
                return lhs.price > rhs.price
            })
            self.isCatalogLoaded = true
            self.applyFilter()
            self.updateLayoutIfPossible()
        }))
    }

    private func applyFilter() {
        let query = self.query
        self.gifts = self.catalog.filter { pampGramGiftMatches($0, query: query) }
        self.emptyLabel.isHidden = !self.gifts.isEmpty
        if self.gifts.isEmpty {
            if !self.isCatalogLoaded {
                self.emptyLabel.text = "Каталог подарков загружается…"
            } else if self.catalog.isEmpty {
                self.emptyLabel.text = "Подарки не найдены."
            } else {
                self.emptyLabel.text = "Ничего не найдено."
            }
        }
    }

    @objc private func searchChanged() {
        self.query = self.searchField.text ?? ""
        self.applyFilter()
        self.updateLayoutIfPossible()
        self.scrollView.setContentOffset(CGPoint(x: 0.0, y: -self.scrollView.contentInset.top), animated: false)
        self.updateVisibleTiles()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        self.validLayout = layout
        self.updateLayoutIfPossible()
    }

    private func updateLayoutIfPossible() {
        guard self.isViewLoaded, let layout = self.validLayout else {
            return
        }
        let navigationHeight = self.navigationLayout(layout: layout).navigationFrame.maxY
        let size = layout.size
        // With the keyboard up the bottom bar rides on top of it.
        let keyboardHeight = layout.inputHeight ?? 0.0
        let bottomInset = keyboardHeight > 0.0 ? keyboardHeight + 12.0 : max(layout.intrinsicInsets.bottom, 12.0)

        let buttonFrame = CGRect(x: self.sideInset, y: size.height - bottomInset - self.buttonHeight, width: size.width - self.sideInset * 2.0, height: self.buttonHeight)
        self.addButton.frame = buttonFrame
        // One row right above the button: the selected gift's name and price on the left (the tiles
        // show only pictures), the "−  N  +" quantity picker on the right.
        let rowFrame = CGRect(x: self.sideInset, y: buttonFrame.minY - 10.0 - self.stepperHeight, width: size.width - self.sideInset * 2.0, height: self.stepperHeight)
        let stepperWidth = self.stepperButtonSize * 2.0 + self.countLabelWidth
        let stepperOriginX = rowFrame.maxX - stepperWidth
        self.minusButton.frame = CGRect(x: stepperOriginX, y: rowFrame.minY, width: self.stepperButtonSize, height: self.stepperButtonSize)
        self.countLabel.frame = CGRect(x: stepperOriginX + self.stepperButtonSize, y: rowFrame.minY, width: self.countLabelWidth, height: self.stepperHeight)
        self.plusButton.frame = CGRect(x: stepperOriginX + self.stepperButtonSize + self.countLabelWidth, y: rowFrame.minY, width: self.stepperButtonSize, height: self.stepperButtonSize)
        self.captionLabel.frame = CGRect(x: rowFrame.minX, y: rowFrame.minY, width: max(0.0, stepperOriginX - rowFrame.minX - 8.0), height: self.stepperHeight)
        let fadeTop = rowFrame.minY - 24.0
        self.fadeView.frame = CGRect(x: 0.0, y: fadeTop, width: size.width, height: size.height - fadeTop)

        self.scrollView.frame = CGRect(origin: .zero, size: size)
        let itemSize = self.itemSize(width: size.width)
        let rows = (self.gifts.count + self.columns - 1) / self.columns
        let headerHeight = self.searchHeight + self.spacing
        let contentHeight = headerHeight + CGFloat(rows) * (itemSize.height + self.spacing)
        self.searchContainer.frame = CGRect(x: self.sideInset, y: 0.0, width: size.width - self.sideInset * 2.0, height: self.searchHeight)
        self.searchIcon.frame = CGRect(x: 10.0, y: 0.0, width: 20.0, height: self.searchHeight)
        self.searchField.frame = CGRect(x: 38.0, y: 0.0, width: max(0.0, self.searchContainer.bounds.width - 46.0), height: self.searchHeight)
        let topInset = navigationHeight + self.spacing
        let scrollBottomInset = size.height - rowFrame.minY + self.spacing
        self.scrollView.contentInset = UIEdgeInsets(top: topInset, left: 0.0, bottom: scrollBottomInset, right: 0.0)
        self.scrollView.scrollIndicatorInsets = UIEdgeInsets(top: navigationHeight, left: 0.0, bottom: scrollBottomInset, right: 0.0)
        let newContentSize = CGSize(width: size.width, height: contentHeight)
        if self.scrollView.contentSize != newContentSize {
            let isInitial = self.scrollView.contentSize == .zero
            self.scrollView.contentSize = newContentSize
            if isInitial {
                self.scrollView.contentOffset = CGPoint(x: 0.0, y: -topInset)
            }
        }

        self.emptyLabel.frame = CGRect(x: self.sideInset, y: navigationHeight + headerHeight + 40.0, width: size.width - self.sideInset * 2.0, height: 60.0)

        self.updateVisibleTiles()
    }

    private func itemSize(width: CGFloat) -> CGSize {
        let itemWidth = floor((width - self.sideInset * 2.0 - self.spacing * CGFloat(self.columns - 1)) / CGFloat(self.columns))
        return CGSize(width: itemWidth, height: floor(itemWidth * 1.2))
    }

    /// Only the tiles on (or just off) screen exist at any moment — the catalog has hundreds of
    /// animated gifts, and building them all at once would be exactly the kind of load this mod is
    /// trying not to put on a phone.
    private func updateVisibleTiles() {
        guard let layout = self.validLayout else {
            return
        }
        let size = layout.size
        let itemSize = self.itemSize(width: size.width)
        let rowHeight = itemSize.height + self.spacing
        let headerHeight = self.searchHeight + self.spacing
        let visibleTop = self.scrollView.contentOffset.y + self.scrollView.contentInset.top - 400.0 - headerHeight
        let visibleBottom = self.scrollView.contentOffset.y + size.height + 400.0 - headerHeight
        let firstRow = max(0, Int(floor(visibleTop / rowHeight)))
        let lastRow = max(firstRow, Int(ceil(visibleBottom / rowHeight)))

        var validIds = Set<Int64>()
        let theme = self.presentationData.theme
        let strings = self.presentationData.strings

        for (index, gift) in self.gifts.enumerated() {
            let row = index / self.columns
            if row < firstRow || row > lastRow {
                continue
            }
            let column = index % self.columns
            validIds.insert(gift.id)

            let tile: ComponentView<Empty>
            if let current = self.tiles[gift.id] {
                tile = current
            } else {
                tile = ComponentView<Empty>()
                self.tiles[gift.id] = tile
            }
            let giftId = gift.id
            let _ = tile.update(
                transition: .immediate,
                component: AnyComponent(
                    GiftItemComponent(
                        context: self.context,
                        style: .glass,
                        theme: theme,
                        strings: strings,
                        peer: nil,
                        subject: .starGift(gift: gift, price: "# \(gift.price)"),
                        isSelected: self.selectedGiftId == gift.id,
                        action: { [weak self] in
                            guard let self else {
                                return
                            }
                            self.searchField.resignFirstResponder()
                            self.selectedGiftId = (self.selectedGiftId == giftId) ? nil : giftId
                            self.updateButton()
                            self.updateVisibleTiles()
                        }
                    )
                ),
                environment: {},
                containerSize: itemSize
            )
            if let view = tile.view {
                if view.superview == nil {
                    self.scrollView.addSubview(view)
                }
                view.frame = CGRect(
                    x: self.sideInset + CGFloat(column) * (itemSize.width + self.spacing),
                    y: headerHeight + CGFloat(row) * rowHeight,
                    width: itemSize.width,
                    height: itemSize.height
                )
            }
        }

        for (id, tile) in self.tiles where !validIds.contains(id) {
            tile.view?.removeFromSuperview()
            self.tiles.removeValue(forKey: id)
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        self.updateVisibleTiles()
    }

    private func changeQuantity(by delta: Int) {
        let updated = max(1, min(PampGramPhantomGiftManager.maxGiftsPerAdd, self.quantity + delta))
        if updated == self.quantity {
            return
        }
        self.quantity = updated
        self.updateButton()
    }

    @objc private func minusDown() {
        self.startHold(delta: -1)
    }

    @objc private func plusDown() {
        self.startHold(delta: 1)
    }

    @objc private func stepperReleased() {
        self.stopHold()
    }

    /// One step right away, then — if the finger stays down — a steady run of them.
    private func startHold(delta: Int) {
        self.stopHold()
        self.changeQuantity(by: delta)
        let delayTimer = SwiftSignalKit.Timer(timeout: 0.45, repeat: false, completion: { [weak self] in
            guard let self else {
                return
            }
            let repeatTimer = SwiftSignalKit.Timer(timeout: 0.07, repeat: true, completion: { [weak self] in
                self?.changeQuantity(by: delta)
            }, queue: Queue.mainQueue())
            self.holdRepeatTimer = repeatTimer
            repeatTimer.start()
        }, queue: Queue.mainQueue())
        self.holdDelayTimer = delayTimer
        delayTimer.start()
    }

    private func stopHold() {
        self.holdDelayTimer?.invalidate()
        self.holdDelayTimer = nil
        self.holdRepeatTimer?.invalidate()
        self.holdRepeatTimer = nil
    }

    private func updateButton() {
        let hasSelection = self.selectedGiftId != nil
        self.countLabel.text = "\(self.quantity)"
        self.minusButton.isEnabled = self.quantity > 1 && !self.isAdding
        self.plusButton.isEnabled = self.quantity < PampGramPhantomGiftManager.maxGiftsPerAdd && !self.isAdding
        if let selectedGiftId = self.selectedGiftId, let gift = self.catalog.first(where: { $0.id == selectedGiftId }) {
            self.captionLabel.text = "\(gift.title ?? "Подарок") · ⭐️ \(gift.price)"
        } else {
            self.captionLabel.text = nil
        }
        let addTitle: String
        if !hasSelection {
            addTitle = "Выберите подарок"
        } else if self.quantity > 1 {
            addTitle = "Добавить в профиль · \(self.quantity) шт."
        } else {
            addTitle = "Добавить в профиль"
        }
        self.addButton.setTitle(addTitle, for: .normal)
        self.addButton.backgroundColor = self.presentationData.theme.list.itemCheckColors.fillColor
        self.addButton.alpha = (hasSelection && !self.isAdding) ? 1.0 : 0.5
        self.addButton.isEnabled = hasSelection && !self.isAdding
    }

    @objc private func addPressed() {
        guard let selectedGiftId = self.selectedGiftId, !self.isAdding, let gift = self.catalog.first(where: { $0.id == selectedGiftId }) else {
            return
        }
        self.stopHold()
        self.isAdding = true
        self.updateButton()
        self.addDisposable.set((PampGramPhantomGiftManager.addGenericGiftsToProfile(context: self.context, gift: gift, count: self.quantity)
        |> deliverOnMainQueue).start(next: { [weak self] addedCount in
            guard let self else {
                return
            }
            self.isAdding = false
            self.selectedGiftId = nil
            self.quantity = 1
            self.updateButton()
            self.updateVisibleTiles()

            let name = gift.title ?? "Подарок"
            let text: String
            if addedCount > 1 {
                if gift.upgradeStars != nil {
                    text = "«\(name)» × \(addedCount) добавлены в профиль. Откройте любой из них там и нажмите «Улучшить бесплатно»."
                } else {
                    text = "«\(name)» × \(addedCount) добавлены в профиль."
                }
            } else if gift.upgradeStars != nil {
                text = "«\(name)» добавлен в профиль. Откройте его там и нажмите «Улучшить бесплатно»."
            } else {
                text = "«\(name)» добавлен в профиль."
            }
            self.present(UndoOverlayController(presentationData: self.presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), in: .current)
        }))
    }
}
