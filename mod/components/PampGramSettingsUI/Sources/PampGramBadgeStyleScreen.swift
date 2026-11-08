import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import Postbox
import TelegramPresentationData
import AccountContext
import PampGramCore

/// "Галочки" (Подарки → Визуалы профиля → Галочка рядом с именем): picks which colored
/// checkmark, if any, PampGram draws next to the account owner's own name. Exactly one of
/// "Нет"/"Major"/"Hold" is selected at a time — a proper radio list, not three independent
/// switches — and the checkmark accessory sits on the trailing (right) side of the selected
/// row, matching the rest of iOS's own selection-list convention.
///
/// `PampGramNameBadgeStyle.major`/`.hold` only pick a *color*; both draw the exact same glyph
/// Telegram's own verified checkmark uses, recolored — see the `credibilityIcon` override this
/// setting drives in `apply-profile-visuals.py`'s patch to `PeerInfoHeaderNode.swift`. Shown
/// only on the account owner's own profile, same rule as the visual rating/anonymous number.
private func pampGramBadgeColor(_ style: PampGramNameBadgeStyle) -> UIColor? {
    switch style {
    case .none: return nil
    case .major: return UIColor(rgb: 0x8e44ec)
    case .hold: return UIColor(rgb: 0x34c759)
    }
}

/// A small filled circle with a white checkmark glyph — the same look Telegram draws for its
/// own verified badge, just recolored per `pampGramBadgeColor`.
private func pampGramBadgeGlyphView(color: UIColor, diameter: CGFloat) -> UIView {
    let container = UIView()
    container.translatesAutoresizingMaskIntoConstraints = false
    container.backgroundColor = color
    container.layer.cornerRadius = diameter / 2.0
    let glyph = UIImageView(image: UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: diameter * 0.5, weight: .bold)))
    glyph.translatesAutoresizingMaskIntoConstraints = false
    glyph.tintColor = .white
    glyph.contentMode = .center
    container.addSubview(glyph)
    NSLayoutConstraint.activate([
        container.widthAnchor.constraint(equalToConstant: diameter),
        container.heightAnchor.constraint(equalToConstant: diameter),
        glyph.centerXAnchor.constraint(equalTo: container.centerXAnchor),
        glyph.centerYAnchor.constraint(equalTo: container.centerYAnchor)
    ])
    return container
}

private final class PampGramBadgeOptionRow: UIControl {
    private let titleLabel = UILabel()
    private var glyphView: UIView?
    let style: PampGramNameBadgeStyle
    var action: (() -> Void)?

    init(style: PampGramNameBadgeStyle, primaryColor: UIColor) {
        self.style = style
        super.init(frame: .zero)

        self.titleLabel.translatesAutoresizingMaskIntoConstraints = false
        self.titleLabel.text = style.displayName
        self.titleLabel.font = .systemFont(ofSize: 17.0, weight: .regular)
        self.titleLabel.textColor = primaryColor
        self.addSubview(self.titleLabel)
        NSLayoutConstraint.activate([
            self.titleLabel.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 18.0),
            self.titleLabel.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            self.heightAnchor.constraint(equalToConstant: 54.0)
        ])
        self.addTarget(self, action: #selector(self.tapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func tapped() {
        self.action?()
    }

    func setSelected(_ selected: Bool) {
        self.glyphView?.removeFromSuperview()
        self.glyphView = nil
        guard selected, let color = pampGramBadgeColor(self.style) else {
            return
        }
        let glyph = pampGramBadgeGlyphView(color: color, diameter: 24.0)
        self.addSubview(glyph)
        NSLayoutConstraint.activate([
            glyph.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -18.0),
            glyph.centerYAnchor.constraint(equalTo: self.centerYAnchor)
        ])
        self.glyphView = glyph
    }
}

private final class PampGramBadgeStyleController: ViewController {
    private let context: AccountContext
    private let presentationData: PresentationData
    private let stateDisposable = MetaDisposable()

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let stackView = UIStackView()
    private var headerTopConstraint: NSLayoutConstraint?

    private var previewGlyphView: UIView?
    private var previewRow: UIView?
    private var optionRows: [PampGramBadgeOptionRow] = []

    private var primaryColor: UIColor = .label
    private var secondaryColor: UIColor = .secondaryLabel

    private var selectedStyle: PampGramNameBadgeStyle = .none

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
    }

    override func loadDisplayNode() {
        let node = ASDisplayNode()
        node.backgroundColor = self.presentationData.theme.list.blocksBackgroundColor
        self.displayNode = node
        self.displayNodeDidLoad()
        self.configureView(node.view)

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
        self.scrollView.contentInset.bottom = bottomInset + 24.0
        self.scrollView.verticalScrollIndicatorInsets.bottom = bottomInset
    }

    private func configureView(_ rootView: UIView) {
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

        let backButton = self.makeGlyphButton(systemName: "chevron.left", action: #selector(self.closePressed))
        header.addSubview(backButton)
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Галочки"
        titleLabel.font = .systemFont(ofSize: 17.0, weight: .semibold)
        titleLabel.textColor = self.primaryColor
        titleLabel.textAlignment = .center
        header.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12.0),
            backButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 34.0),
            backButton.heightAnchor.constraint(equalToConstant: 34.0),
            titleLabel.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor)
        ])

        self.scrollView.translatesAutoresizingMaskIntoConstraints = false
        self.scrollView.alwaysBounceVertical = true
        self.scrollView.showsVerticalScrollIndicator = false
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
        self.stackView.spacing = 18.0
        self.contentView.addSubview(self.stackView)
        NSLayoutConstraint.activate([
            self.stackView.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 16.0),
            self.stackView.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -16.0),
            self.stackView.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 12.0),
            self.stackView.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor, constant: -24.0)
        ])

        self.stackView.addArrangedSubview(self.makeSectionLabel("Предпросмотр"))
        self.stackView.addArrangedSubview(self.makePreviewPanel())

        self.stackView.addArrangedSubview(self.makeSectionLabel("Галочка рядом с именем"))
        self.stackView.addArrangedSubview(self.makeOptionsPanel())

        let footer = UILabel()
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.numberOfLines = 0
        footer.font = .systemFont(ofSize: 13.0, weight: .regular)
        footer.textColor = self.secondaryColor
        footer.text = "Локальная метка Major или Hold рядом с вашим именем. Видна только на этом устройстве."
        self.stackView.addArrangedSubview(footer)
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

    private func makeSectionLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.font = .systemFont(ofSize: 13.0, weight: .semibold)
        label.textColor = self.secondaryColor
        return label
    }

    private func makePreviewPanel() -> UIView {
        let panel = PampGramGlass.makePanel(cornerRadius: 20.0)
        panel.heightAnchor.constraint(equalToConstant: 54.0).isActive = true

        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            row.topAnchor.constraint(equalTo: panel.topAnchor),
            row.bottomAnchor.constraint(equalTo: panel.bottomAnchor)
        ])
        self.previewRow = row

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Ваш профиль"
        label.font = .systemFont(ofSize: 17.0, weight: .semibold)
        label.textColor = self.primaryColor
        row.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 18.0),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])

        return panel
    }

    private func makeOptionsPanel() -> UIView {
        let panel = PampGramGlass.makePanel(cornerRadius: 20.0)

        var rows: [UIView] = []
        for style in [PampGramNameBadgeStyle.none, .major, .hold] {
            let row = PampGramBadgeOptionRow(style: style, primaryColor: self.primaryColor)
            row.action = { [weak self, weak row] in
                guard let self, let row else { return }
                self.optionSelected(row.style)
            }
            self.optionRows.append(row)
            rows.append(row)
            if style != .hold {
                let divider = UIView()
                divider.translatesAutoresizingMaskIntoConstraints = false
                divider.backgroundColor = self.secondaryColor.withAlphaComponent(0.2)
                divider.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale).isActive = true
                rows.append(divider)
            }
        }

        let column = UIStackView(arrangedSubviews: rows)
        column.translatesAutoresizingMaskIntoConstraints = false
        column.axis = .vertical
        panel.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            column.topAnchor.constraint(equalTo: panel.topAnchor),
            column.bottomAnchor.constraint(equalTo: panel.bottomAnchor)
        ])
        return panel
    }

    private func applyInitialState(_ state: PampGramProfileVisualState) {
        self.selectedStyle = state.nameBadgeStyle
        self.updateSelection()
    }

    private func updateSelection() {
        for row in self.optionRows {
            row.setSelected(row.style == self.selectedStyle)
        }
        self.previewGlyphView?.removeFromSuperview()
        self.previewGlyphView = nil
        if let row = self.previewRow, let color = pampGramBadgeColor(self.selectedStyle) {
            let glyph = pampGramBadgeGlyphView(color: color, diameter: 22.0)
            row.addSubview(glyph)
            NSLayoutConstraint.activate([
                glyph.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -18.0),
                glyph.centerYAnchor.constraint(equalTo: row.centerYAnchor)
            ])
            self.previewGlyphView = glyph
        }
    }

    private func popSelf() {
        if let navigationController = self.navigationController as? NavigationController {
            let _ = navigationController.popViewController(animated: true)
        } else {
            self.dismiss(animated: true, completion: nil)
        }
    }

    @objc private func closePressed() {
        self.popSelf()
    }

    private func optionSelected(_ style: PampGramNameBadgeStyle) {
        guard style != self.selectedStyle else {
            return
        }
        self.selectedStyle = style
        self.updateSelection()
        let _ = self.context.account.postbox.transaction { transaction -> Void in
            PampGramProfileVisualStore.update(transaction: transaction, { state in
                var state = state
                state.nameBadgeStyle = style
                return state
            })
        }.start()
    }
}

public func pampGramBadgeStyleController(context: AccountContext) -> ViewController {
    return PampGramBadgeStyleController(context: context)
}
