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

// MARK: - Verification badge (copied from a verified account)

private final class PampGramBadgeScreenController: PampGramVisualPageController {
    private var usernameField = UITextField()
    private let statusLabel = UILabel()

    override func buildContent() {
        let intro = self.makeLabel("Галочка рядом с вашим именем в профиле — такая же, как у аккаунтов с верификацией Major, Hold и т.п. Введите юзернейм любого аккаунта, у которого есть нужная галочка, и она скопируется к вам. Видно только на этом устройстве.", size: 14.0, weight: .regular, color: self.secondaryColor)
        self.stack.addArrangedSubview(intro)

        self.usernameField = self.makeField(placeholder: "@username с галочкой Major или Hold", keyboard: .asciiCapable)
        self.statusLabel.translatesAutoresizingMaskIntoConstraints = false
        self.statusLabel.font = UIFont.systemFont(ofSize: 14.0, weight: .medium)
        self.statusLabel.textColor = self.primaryColor
        self.statusLabel.numberOfLines = 0
        let copyButton = self.makeButton("Скопировать галочку", filled: true, action: #selector(self.copyPressed))
        let removeButton = self.makeButton("Убрать галочку", filled: false, action: #selector(self.removePressed))
        self.stack.addArrangedSubview(self.makePanel(title: "Галочка верификации", content: [self.usernameField, copyButton, removeButton, self.statusLabel]))

        self.loadExtras { [weak self] extras in
            if extras.badgeFileId != 0 {
                self?.statusLabel.text = "Сейчас: галочка с \(extras.badgeSource.isEmpty ? "аккаунта" : extras.badgeSource)."
            } else {
                self?.statusLabel.text = "Сейчас: галочки нет."
            }
        }
    }

    @objc private func copyPressed() {
        var name = (self.usernameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = name.range(of: "t.me/") {
            name = String(name[range.upperBound...])
        }
        if name.hasPrefix("@") {
            name.removeFirst()
        }
        let finalName = name
        guard !finalName.isEmpty else {
            self.statusLabel.text = "Введите юзернейм."
            return
        }
        self.statusLabel.text = "Ищу @\(finalName)…"
        let _ = (self.context.engine.peers.resolvePeerByName(name: finalName, referrer: nil)
        |> mapToSignal { result -> Signal<EnginePeer?, NoError> in
            guard case let .result(peer) = result else {
                return .complete()
            }
            return .single(peer)
        }
        |> deliverOnMainQueue).startStandalone(next: { [weak self] peer in
            guard let self = self else {
                return
            }
            guard let peer = peer, let fileId = peer.verificationIconFileId else {
                self.statusLabel.text = "У @\(finalName) нет галочки верификации (Major, Hold и т.п.)."
                return
            }
            let source = "@" + finalName
            self.updateExtras { extras in
                extras.badgeFileId = fileId
                extras.badgeSource = source
            }
            self.statusLabel.text = "Галочка скопирована с \(source). Откройте свой профиль."
        })
    }

    @objc private func removePressed() {
        self.updateExtras { extras in
            extras.badgeFileId = 0
            extras.badgeSource = ""
        }
        self.statusLabel.text = "Галочка убрана."
    }
}

// MARK: - GRAM card

private final class PampGramCardScreenController: PampGramVisualPageController {
    private let enableSwitch = UISwitch()
    private var balanceField = UITextField()

    override func buildContent() {
        let intro = self.makeLabel("Подменяет баланс в настоящем кошельке Telegram: на карточке кошелька («Open My Money»), в сумме в долларах и в плашке «Balance» под именем в профиле. Нужен созданный кошелёк в Telegram. Фон и наклейки карточки настраиваются в самом кошельке — это настоящий редактор Telegram.", size: 14.0, weight: .regular, color: self.secondaryColor)
        self.stack.addArrangedSubview(intro)

        let switchRow = UIStackView(arrangedSubviews: [self.makeLabel("Подменять баланс", size: 16.0, weight: .regular, color: self.primaryColor), self.enableSwitch])
        switchRow.axis = .horizontal
        switchRow.alignment = .center
        self.enableSwitch.addTarget(self, action: #selector(self.switchChanged), for: .valueChanged)
        self.balanceField = self.makeField(placeholder: "Баланс GRAM", keyboard: .numberPad)
        self.balanceField.addTarget(self, action: #selector(self.balanceChanged(_:)), for: .editingChanged)
        self.stack.addArrangedSubview(self.makePanel(title: "Баланс GRAM", content: [switchRow, self.balanceField]))

        self.loadExtras { [weak self] extras in
            self?.enableSwitch.isOn = extras.cardEnabled
            self?.balanceField.text = extras.cardBalance > 0 ? "\(extras.cardBalance)" : ""
        }
    }

    @objc private func switchChanged() {
        let value = self.enableSwitch.isOn
        self.updateExtras { extras in
            extras.cardEnabled = value
        }
    }

    @objc private func balanceChanged(_ field: UITextField) {
        let digits = String((field.text ?? "").filter { $0.isNumber }.prefix(12))
        let value = Int64(digits) ?? 0
        self.updateExtras { extras in
            extras.cardBalance = value
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
        let boughtAt = Int32(self.datePicker.date.timeIntervalSince1970)
        let finalName = name
        self.nameField.text = nil
        self.priceField.text = nil
        self.errorLabel.text = "Добавляю…"
        // The collectible-username sheet shows a dollar price too: take today's TON rate once,
        // at the moment the username is added (stays 0 if the rate can't be fetched).
        PampGramTonRateService.currentRate(completion: { [weak self] rate in
            let usdCents = Int64(((rate ?? 0.0) * price * 100.0).rounded())
            let item = PampGramVisualUsername(name: finalName, priceTon: price, boughtAt: boughtAt, priceUsdCents: usdCents)
            self?.items.append(item)
            self?.updateExtras { extras in
                extras.usernames.append(item)
            }
            self?.errorLabel.text = "Добавлено. Откройте свой профиль: юзернейм появится рядом с основным."
            self?.reloadList()
        })
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
