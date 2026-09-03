import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import Postbox
import TelegramPresentationData
import AccountContext
import PampGramCore

private let pampGramRatingAccent = UIColor(red: 0.49, green: 0.22, blue: 0.93, alpha: 1.0)

/// A compact visual sample in the preset strip. The actual level is still chosen with the
/// slider below, so a preset never limits the available range of 1...100.
private final class PampGramRatingPresetButton: UIControl {
    let level: Int
    private let imageView = UIImageView()
    private let valueLabel = UILabel()
    private let primaryColor: UIColor
    private let secondaryColor: UIColor

    init(level: Int, symbolName: String, primaryColor: UIColor, secondaryColor: UIColor) {
        self.level = level
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        super.init(frame: .zero)

        self.translatesAutoresizingMaskIntoConstraints = false
        self.layer.cornerRadius = 12.0
        self.layer.borderWidth = 1.0
        self.isAccessibilityElement = true
        self.accessibilityLabel = "Уровень \(level)"

        self.imageView.translatesAutoresizingMaskIntoConstraints = false
        self.imageView.image = UIImage(systemName: symbolName)
        self.imageView.contentMode = .scaleAspectFit
        self.addSubview(self.imageView)

        self.valueLabel.translatesAutoresizingMaskIntoConstraints = false
        self.valueLabel.text = "\(level)"
        self.valueLabel.font = .systemFont(ofSize: 12.0, weight: .bold)
        self.valueLabel.textAlignment = .center
        self.addSubview(self.valueLabel)

        NSLayoutConstraint.activate([
            self.widthAnchor.constraint(equalToConstant: 48.0),
            self.heightAnchor.constraint(equalToConstant: 58.0),
            self.imageView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            self.imageView.topAnchor.constraint(equalTo: self.topAnchor, constant: 8.0),
            self.imageView.widthAnchor.constraint(equalToConstant: 27.0),
            self.imageView.heightAnchor.constraint(equalToConstant: 27.0),
            self.valueLabel.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            self.valueLabel.topAnchor.constraint(equalTo: self.imageView.bottomAnchor, constant: 1.0),
            self.valueLabel.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -5.0)
        ])

        self.updateAppearance(selected: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateAppearance(selected: Bool) {
        self.backgroundColor = selected ? pampGramRatingAccent.withAlphaComponent(0.14) : .clear
        self.layer.borderColor = (selected ? pampGramRatingAccent : self.secondaryColor.withAlphaComponent(0.35)).cgColor
        self.imageView.tintColor = selected ? pampGramRatingAccent : self.secondaryColor
        self.valueLabel.textColor = selected ? pampGramRatingAccent : self.primaryColor
    }
}

/// Local-only visual rating editor. It writes into PampGram's Postbox preferences only after
/// "Сохранить"; nothing in this controller sends or alters Telegram server rating data.
private final class PampGramProfileRatingEditorController: ViewController {
    private let context: AccountContext
    private let presentationData: PresentationData
    private let stateDisposable = MetaDisposable()

    private let sheetView = UIView()
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let stackView = UIStackView()
    private var sheetHeightConstraint: NSLayoutConstraint?

    private let subtitleLabel = UILabel()
    private let previewIconView = UIImageView()
    private let previewBadgeLabel = UILabel()
    private let previewLevelLabel = UILabel()
    private let previewDetailsLabel = UILabel()
    private let levelValueLabel = UILabel()
    private let pointsValueLabel = UILabel()
    private let pointsRangeLabel = UILabel()
    private let levelSlider = UISlider()
    private let pointsSlider = UISlider()
    private let displayButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)
    private let presetScrollView = UIScrollView()
    private let presetStackView = UIStackView()
    private var presetButtons: [PampGramRatingPresetButton] = []

    private var selectedLevel: Int = 1
    /// The relative position in a level's range. It intentionally does not change when the
    /// level changes, which keeps the points slider in the same place as requested.
    private var pointsProgress: Float = 0.5
    private var showInProfile = false
    private var didLoadInitialState = false

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
        node.backgroundColor = .clear
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
        self.sheetHeightConstraint?.constant = min(700.0, max(470.0, layout.size.height - 12.0))
    }

    private func configureView(_ rootView: UIView) {
        let theme = self.presentationData.theme.list
        rootView.backgroundColor = .clear
        // Dragging the sliders must not trigger the navigation's interactive back/dismiss gesture
        // (which slid the whole sheet away). The editor closes only via its own X / Save buttons.
        rootView.disablesInteractiveTransitionGestureRecognizer = true

        self.sheetView.translatesAutoresizingMaskIntoConstraints = false
        self.sheetView.backgroundColor = theme.blocksBackgroundColor
        self.sheetView.layer.cornerRadius = 28.0
        self.sheetView.clipsToBounds = true
        if #available(iOS 11.0, *) {
            self.sheetView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        }
        rootView.addSubview(self.sheetView)
        let heightConstraint = self.sheetView.heightAnchor.constraint(equalToConstant: 680.0)
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

        let presetsTitle = self.makeLabel("Как выглядит на каждом уровне", font: .systemFont(ofSize: 16.0, weight: .regular), color: theme.itemSecondaryTextColor)
        self.stackView.addArrangedSubview(presetsTitle)
        self.stackView.addArrangedSubview(self.makePresetStrip(primaryColor: theme.itemPrimaryTextColor, secondaryColor: theme.itemSecondaryTextColor))

        self.stackView.setCustomSpacing(16.0, after: self.presetScrollView)
        self.stackView.addArrangedSubview(self.makeValueHeader(title: "Уровень", valueLabel: self.levelValueLabel, primaryColor: theme.itemPrimaryTextColor))
        self.configureSlider(self.levelSlider, accent: pampGramRatingAccent, secondary: theme.itemSecondaryTextColor)
        self.levelSlider.minimumValue = 1.0
        self.levelSlider.maximumValue = 100.0
        self.levelSlider.addTarget(self, action: #selector(self.levelChanged(_:)), for: .valueChanged)
        self.levelSlider.heightAnchor.constraint(equalToConstant: 28.0).isActive = true
        self.stackView.addArrangedSubview(self.levelSlider)

        self.stackView.setCustomSpacing(16.0, after: self.levelSlider)
        self.stackView.addArrangedSubview(self.makeValueHeader(title: "Очки", valueLabel: self.pointsValueLabel, primaryColor: theme.itemPrimaryTextColor))
        self.pointsRangeLabel.font = .systemFont(ofSize: 14.0, weight: .regular)
        self.pointsRangeLabel.textColor = theme.itemSecondaryTextColor
        self.pointsRangeLabel.numberOfLines = 1
        self.stackView.addArrangedSubview(self.pointsRangeLabel)
        self.configureSlider(self.pointsSlider, accent: pampGramRatingAccent, secondary: theme.itemSecondaryTextColor)
        self.pointsSlider.minimumValue = 0.0
        self.pointsSlider.maximumValue = 1.0
        self.pointsSlider.addTarget(self, action: #selector(self.pointsChanged(_:)), for: .valueChanged)
        self.pointsSlider.heightAnchor.constraint(equalToConstant: 28.0).isActive = true
        self.stackView.addArrangedSubview(self.pointsSlider)

        self.stackView.setCustomSpacing(18.0, after: self.pointsSlider)
        self.configurePillButton(self.displayButton, title: "Показывать в профиле: выкл", primary: false)
        self.displayButton.addTarget(self, action: #selector(self.toggleDisplay), for: .touchUpInside)
        self.displayButton.heightAnchor.constraint(equalToConstant: 46.0).isActive = true
        self.stackView.addArrangedSubview(self.displayButton)

        self.configurePillButton(self.saveButton, title: "Сохранить", primary: true)
        self.saveButton.addTarget(self, action: #selector(self.savePressed), for: .touchUpInside)
        self.saveButton.heightAnchor.constraint(equalToConstant: 52.0).isActive = true
        self.stackView.addArrangedSubview(self.saveButton)

        self.updateUI()
    }

    private func makeHeader(primaryColor: UIColor, secondaryColor: UIColor) -> UIView {
        let container = UIView()
        container.heightAnchor.constraint(equalToConstant: 53.0).isActive = true

        let titleLabel = self.makeLabel("Рейтинг профиля", font: .systemFont(ofSize: 27.0, weight: .bold), color: primaryColor)
        container.addSubview(titleLabel)
        self.subtitleLabel.font = .systemFont(ofSize: 15.0, weight: .regular)
        self.subtitleLabel.textColor = secondaryColor
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
        card.heightAnchor.constraint(equalToConstant: 94.0).isActive = true

        let iconContainer = UIView()
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.tintColor = pampGramRatingAccent
        card.addSubview(iconContainer)
        self.previewIconView.translatesAutoresizingMaskIntoConstraints = false
        self.previewIconView.contentMode = .scaleAspectFit
        self.previewIconView.tintColor = pampGramRatingAccent
        iconContainer.addSubview(self.previewIconView)
        self.previewBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
        self.previewBadgeLabel.font = .systemFont(ofSize: 18.0, weight: .bold)
        self.previewBadgeLabel.textColor = primaryColor
        self.previewBadgeLabel.textAlignment = .center
        iconContainer.addSubview(self.previewBadgeLabel)

        self.previewLevelLabel.translatesAutoresizingMaskIntoConstraints = false
        self.previewLevelLabel.font = .systemFont(ofSize: 22.0, weight: .bold)
        self.previewLevelLabel.textColor = primaryColor
        card.addSubview(self.previewLevelLabel)
        self.previewDetailsLabel.translatesAutoresizingMaskIntoConstraints = false
        self.previewDetailsLabel.font = .systemFont(ofSize: 15.0, weight: .regular)
        self.previewDetailsLabel.textColor = secondaryColor
        card.addSubview(self.previewDetailsLabel)

        NSLayoutConstraint.activate([
            iconContainer.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18.0),
            iconContainer.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 54.0),
            iconContainer.heightAnchor.constraint(equalToConstant: 54.0),
            self.previewIconView.leadingAnchor.constraint(equalTo: iconContainer.leadingAnchor),
            self.previewIconView.trailingAnchor.constraint(equalTo: iconContainer.trailingAnchor),
            self.previewIconView.topAnchor.constraint(equalTo: iconContainer.topAnchor),
            self.previewIconView.bottomAnchor.constraint(equalTo: iconContainer.bottomAnchor),
            self.previewBadgeLabel.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            self.previewBadgeLabel.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor, constant: 1.0),
            self.previewLevelLabel.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 15.0),
            self.previewLevelLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 22.0),
            self.previewLevelLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16.0),
            self.previewDetailsLabel.leadingAnchor.constraint(equalTo: self.previewLevelLabel.leadingAnchor),
            self.previewDetailsLabel.topAnchor.constraint(equalTo: self.previewLevelLabel.bottomAnchor, constant: 2.0),
            self.previewDetailsLabel.trailingAnchor.constraint(equalTo: self.previewLevelLabel.trailingAnchor)
        ])
        return card
    }

    private func makePresetStrip(primaryColor: UIColor, secondaryColor: UIColor) -> UIView {
        self.presetScrollView.showsHorizontalScrollIndicator = false
        self.presetScrollView.alwaysBounceHorizontal = true
        self.presetScrollView.heightAnchor.constraint(equalToConstant: 58.0).isActive = true
        self.presetStackView.translatesAutoresizingMaskIntoConstraints = false
        self.presetStackView.axis = .horizontal
        self.presetStackView.alignment = .fill
        self.presetStackView.spacing = 8.0
        self.presetScrollView.addSubview(self.presetStackView)
        NSLayoutConstraint.activate([
            self.presetStackView.leadingAnchor.constraint(equalTo: self.presetScrollView.contentLayoutGuide.leadingAnchor),
            self.presetStackView.trailingAnchor.constraint(equalTo: self.presetScrollView.contentLayoutGuide.trailingAnchor),
            self.presetStackView.topAnchor.constraint(equalTo: self.presetScrollView.contentLayoutGuide.topAnchor),
            self.presetStackView.bottomAnchor.constraint(equalTo: self.presetScrollView.contentLayoutGuide.bottomAnchor),
            self.presetStackView.heightAnchor.constraint(equalTo: self.presetScrollView.frameLayoutGuide.heightAnchor)
        ])

        for level in [1, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100] {
            let button = PampGramRatingPresetButton(level: level, symbolName: self.symbolName(for: level), primaryColor: primaryColor, secondaryColor: secondaryColor)
            button.addTarget(self, action: #selector(self.presetPressed(_:)), for: .touchUpInside)
            self.presetButtons.append(button)
            self.presetStackView.addArrangedSubview(button)
        }
        return self.presetScrollView
    }

    private func makeValueHeader(title: String, valueLabel: UILabel, primaryColor: UIColor) -> UIView {
        let container = UIView()
        container.heightAnchor.constraint(equalToConstant: 24.0).isActive = true
        let titleLabel = self.makeLabel(title, font: .systemFont(ofSize: 19.0, weight: .medium), color: primaryColor)
        container.addSubview(titleLabel)
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.font = .systemFont(ofSize: 19.0, weight: .medium)
        valueLabel.textColor = pampGramRatingAccent
        valueLabel.textAlignment = .right
        container.addSubview(valueLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 12.0)
        ])
        return container
    }

    private func makeLabel(_ text: String, font: UIFont, color: UIColor) -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.font = font
        label.textColor = color
        return label
    }

    private func configureSlider(_ slider: UISlider, accent: UIColor, secondary: UIColor) {
        slider.minimumTrackTintColor = accent
        slider.maximumTrackTintColor = secondary.withAlphaComponent(0.22)
        slider.thumbTintColor = accent
        slider.isContinuous = true
    }

    private func configurePillButton(_ button: UIButton, title: String, primary: Bool) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18.0, weight: .semibold)
        button.layer.cornerRadius = primary ? 26.0 : 23.0
        button.backgroundColor = primary ? pampGramRatingAccent : pampGramRatingAccent.withAlphaComponent(0.14)
        button.setTitleColor(primary ? .white : pampGramRatingAccent, for: .normal)
    }

    private func applyInitialState(_ state: PampGramProfileVisualState) {
        guard !self.didLoadInitialState else {
            return
        }
        self.didLoadInitialState = true
        let storedLevel = min(Int64(100), max(Int64(1), state.ratingValue))
        self.selectedLevel = Int(storedLevel)
        if state.ratingPoints > 0 {
            self.pointsProgress = self.progress(for: state.ratingPoints, at: self.selectedLevel)
        }
        self.showInProfile = state.ratingEnabled
        self.updateUI()
    }

    @objc private func closePressed() {
        self.dismiss(animated: true, completion: nil)
    }

    @objc private func presetPressed(_ sender: PampGramRatingPresetButton) {
        self.selectedLevel = sender.level
        self.updateUI()
    }

    @objc private func levelChanged(_ slider: UISlider) {
        self.selectedLevel = min(100, max(1, Int(slider.value.rounded())))
        // Do not recalculate pointsProgress here: this preserves the second slider position.
        self.updateUI()
    }

    @objc private func pointsChanged(_ slider: UISlider) {
        self.pointsProgress = min(1.0, max(0.0, slider.value))
        self.updateUI()
    }

    @objc private func toggleDisplay() {
        self.showInProfile.toggle()
        self.updateUI()
    }

    @objc private func savePressed() {
        let level = Int64(self.selectedLevel)
        let points = self.points(for: self.selectedLevel, progress: self.pointsProgress)
        let shouldShow = self.showInProfile
        let _ = self.context.account.postbox.transaction { transaction -> Void in
            PampGramProfileVisualStore.update(transaction: transaction, { state in
                var state = state
                state.ratingValue = level
                state.ratingPoints = points
                state.ratingEnabled = shouldShow
                return state
            })
        }.start()
        self.dismiss(animated: true, completion: nil)
    }

    private func updateUI() {
        let points = self.points(for: self.selectedLevel, progress: self.pointsProgress)
        let range = self.pointsRange(for: self.selectedLevel)
        self.levelSlider.value = Float(self.selectedLevel)
        self.pointsSlider.value = self.pointsProgress
        self.levelValueLabel.text = "\(self.selectedLevel)"
        self.pointsValueLabel.text = self.formatPoints(points)
        self.pointsRangeLabel.text = "Диапазон уровня: \(self.formatPoints(range.lowerBound)) — \(self.formatPoints(range.upperBound))"
        self.subtitleLabel.text = "уровень \(self.selectedLevel) · \(self.formatPoints(points)) очков"
        self.previewIconView.image = UIImage(systemName: self.symbolName(for: self.selectedLevel))
        self.previewBadgeLabel.text = "\(self.selectedLevel)"
        self.previewLevelLabel.text = "Уровень \(self.selectedLevel)"
        if self.selectedLevel < 100 {
            self.previewDetailsLabel.text = "до \(self.selectedLevel + 1)-го: \(self.formatPoints(range.upperBound - points)) очков"
        } else {
            self.previewDetailsLabel.text = "максимальный уровень · \(self.formatPoints(points)) очков"
        }

        let nearestPreset = self.presetButtons.filter { $0.level <= self.selectedLevel }.last?.level ?? 1
        for button in self.presetButtons {
            button.updateAppearance(selected: button.level == nearestPreset)
        }

        let displayText = self.showInProfile ? "Показывать в профиле: вкл" : "Показывать в профиле: выкл"
        self.displayButton.setTitle(displayText, for: .normal)
        self.displayButton.backgroundColor = self.showInProfile ? pampGramRatingAccent : pampGramRatingAccent.withAlphaComponent(0.14)
        self.displayButton.setTitleColor(self.showInProfile ? .white : pampGramRatingAccent, for: .normal)
    }

    private func pointsRange(for level: Int) -> ClosedRange<Int64> {
        let value = Int64(min(100, max(1, level)))
        // A deterministic visual range for every local level. It is intentionally not presented
        // as Telegram server data, but keeps the range and preview coherent in the editor.
        let lowerBound = value * 10_840 + value * value * 24
        return lowerBound...(lowerBound + 13_100)
    }

    private func points(for level: Int, progress: Float) -> Int64 {
        let range = self.pointsRange(for: level)
        let fraction = Double(min(1.0, max(0.0, progress)))
        return range.lowerBound + Int64((Double(range.upperBound - range.lowerBound) * fraction).rounded())
    }

    private func progress(for points: Int64, at level: Int) -> Float {
        let range = self.pointsRange(for: level)
        guard range.upperBound > range.lowerBound else {
            return 0.0
        }
        let clamped = min(range.upperBound, max(range.lowerBound, points))
        return Float(Double(clamped - range.lowerBound) / Double(range.upperBound - range.lowerBound))
    }

    private func formatPoints(_ value: Int64) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000.0)
        } else if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000.0)
        } else {
            return "\(value)"
        }
    }

    private func symbolName(for level: Int) -> String {
        switch level {
        case 1...9:
            return "shield"
        case 10...29:
            return "hexagon"
        case 30...49:
            return "shield.lefthalf.filled"
        case 50...69:
            return "seal"
        case 70...89:
            return "seal.fill"
        default:
            return "diamond"
        }
    }
}

func pampGramProfileRatingEditorController(context: AccountContext) -> ViewController {
    return PampGramProfileRatingEditorController(context: context)
}
