import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import Postbox
import TelegramPresentationData
import AccountContext
import PampGramCore

/// A tappable rating-level badge sample in the preset strip.
private final class PampGramRatingPresetButton: UIControl {
    let level: Int
    private let imageView = UIImageView()
    private let ring = UIView()

    init(level: Int) {
        self.level = level
        super.init(frame: .zero)
        self.translatesAutoresizingMaskIntoConstraints = false
        self.isAccessibilityElement = true
        self.accessibilityLabel = "Уровень \(level)"

        self.ring.translatesAutoresizingMaskIntoConstraints = false
        self.ring.layer.cornerRadius = 25.0
        self.ring.layer.borderWidth = 2.0
        self.ring.layer.borderColor = UIColor.clear.cgColor
        self.ring.isUserInteractionEnabled = false
        self.addSubview(self.ring)

        self.imageView.translatesAutoresizingMaskIntoConstraints = false
        self.imageView.image = PampGramRatingBadge.image(level: level, size: 42.0)
        self.imageView.contentMode = .scaleAspectFit
        self.imageView.isUserInteractionEnabled = false
        self.addSubview(self.imageView)

        NSLayoutConstraint.activate([
            self.widthAnchor.constraint(equalToConstant: 50.0),
            self.heightAnchor.constraint(equalToConstant: 50.0),
            self.ring.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.ring.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            self.ring.topAnchor.constraint(equalTo: self.topAnchor),
            self.ring.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            self.imageView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            self.imageView.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            self.imageView.widthAnchor.constraint(equalToConstant: 42.0),
            self.imageView.heightAnchor.constraint(equalToConstant: 42.0)
        ])
        self.updateAppearance(selected: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateAppearance(selected: Bool) {
        self.ring.layer.borderColor = (selected ? UIColor.white : UIColor.clear).cgColor
        self.imageView.alpha = selected ? 1.0 : 0.7
    }
}

/// Local-only visual rating editor — full-screen, "liquid glass" style. Writes into PampGram's
/// Postbox preferences only on save; nothing here touches Telegram server rating data.
private final class PampGramProfileRatingEditorController: ViewController {
    private let context: AccountContext
    private let presentationData: PresentationData
    private let stateDisposable = MetaDisposable()

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let stackView = UIStackView()
    private var headerTopConstraint: NSLayoutConstraint?

    private let previewBadgeView = UIImageView()
    private let previewLevelLabel = UILabel()
    private let previewPointsLabel = UILabel()
    private let levelValueLabel = UILabel()
    private let pointsValueLabel = UILabel()
    private let pointsRangeLabel = UILabel()
    private let levelSlider = UISlider()
    private let pointsSlider = UISlider()
    private let displaySwitch = UISwitch()
    private let presetScrollView = UIScrollView()
    private let presetStackView = UIStackView()
    private var presetButtons: [PampGramRatingPresetButton] = []

    private var primaryColor: UIColor = .label
    private var secondaryColor: UIColor = .secondaryLabel

    private var selectedLevel: Int = 1
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
        let titleLabel = self.makeLabel("Рейтинг профиля", font: .systemFont(ofSize: 17.0, weight: .semibold), color: self.primaryColor)
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

        // Scroll + content.
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
        self.stackView.spacing = 14.0
        self.contentView.addSubview(self.stackView)
        NSLayoutConstraint.activate([
            self.stackView.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 16.0),
            self.stackView.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -16.0),
            self.stackView.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 12.0),
            self.stackView.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor, constant: -24.0)
        ])

        self.stackView.addArrangedSubview(self.makePreviewPanel())
        self.stackView.addArrangedSubview(self.makePresetPanel())
        self.stackView.addArrangedSubview(self.makeLevelPanel())
        self.stackView.addArrangedSubview(self.makePointsPanel())
        self.stackView.addArrangedSubview(self.makeDisplayPanel())

        self.updateUI()
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
        panel.heightAnchor.constraint(equalToConstant: 96.0).isActive = true

        self.previewBadgeView.translatesAutoresizingMaskIntoConstraints = false
        self.previewBadgeView.contentMode = .scaleAspectFit
        panel.addSubview(self.previewBadgeView)

        self.previewLevelLabel.translatesAutoresizingMaskIntoConstraints = false
        self.previewLevelLabel.font = .systemFont(ofSize: 22.0, weight: .bold)
        self.previewLevelLabel.textColor = self.primaryColor
        panel.addSubview(self.previewLevelLabel)

        self.previewPointsLabel.translatesAutoresizingMaskIntoConstraints = false
        self.previewPointsLabel.font = .systemFont(ofSize: 15.0, weight: .regular)
        self.previewPointsLabel.textColor = self.secondaryColor
        panel.addSubview(self.previewPointsLabel)

        NSLayoutConstraint.activate([
            self.previewBadgeView.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 18.0),
            self.previewBadgeView.centerYAnchor.constraint(equalTo: panel.centerYAnchor),
            self.previewBadgeView.widthAnchor.constraint(equalToConstant: 58.0),
            self.previewBadgeView.heightAnchor.constraint(equalToConstant: 58.0),
            self.previewLevelLabel.leadingAnchor.constraint(equalTo: self.previewBadgeView.trailingAnchor, constant: 16.0),
            self.previewLevelLabel.topAnchor.constraint(equalTo: panel.topAnchor, constant: 24.0),
            self.previewLevelLabel.trailingAnchor.constraint(lessThanOrEqualTo: panel.trailingAnchor, constant: -16.0),
            self.previewPointsLabel.leadingAnchor.constraint(equalTo: self.previewLevelLabel.leadingAnchor),
            self.previewPointsLabel.topAnchor.constraint(equalTo: self.previewLevelLabel.bottomAnchor, constant: 3.0),
            self.previewPointsLabel.trailingAnchor.constraint(lessThanOrEqualTo: panel.trailingAnchor, constant: -16.0)
        ])
        return panel
    }

    private func makePresetPanel() -> UIView {
        let panel = PampGramGlass.makePanel(cornerRadius: 20.0)
        panel.heightAnchor.constraint(equalToConstant: 74.0).isActive = true

        self.presetScrollView.translatesAutoresizingMaskIntoConstraints = false
        self.presetScrollView.showsHorizontalScrollIndicator = false
        self.presetScrollView.alwaysBounceHorizontal = true
        panel.addSubview(self.presetScrollView)
        self.presetStackView.translatesAutoresizingMaskIntoConstraints = false
        self.presetStackView.axis = .horizontal
        self.presetStackView.alignment = .center
        self.presetStackView.spacing = 10.0
        self.presetScrollView.addSubview(self.presetStackView)
        NSLayoutConstraint.activate([
            self.presetScrollView.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            self.presetScrollView.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            self.presetScrollView.topAnchor.constraint(equalTo: panel.topAnchor),
            self.presetScrollView.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
            self.presetStackView.leadingAnchor.constraint(equalTo: self.presetScrollView.contentLayoutGuide.leadingAnchor, constant: 16.0),
            self.presetStackView.trailingAnchor.constraint(equalTo: self.presetScrollView.contentLayoutGuide.trailingAnchor, constant: -16.0),
            self.presetStackView.centerYAnchor.constraint(equalTo: self.presetScrollView.frameLayoutGuide.centerYAnchor)
        ])

        for level in [1, 10, 20, 30, 40, 50, 60, 70, 80, 90, 99] {
            let button = PampGramRatingPresetButton(level: level)
            button.addTarget(self, action: #selector(self.presetPressed(_:)), for: .touchUpInside)
            self.presetButtons.append(button)
            self.presetStackView.addArrangedSubview(button)
        }
        return panel
    }

    private func makeLevelPanel() -> UIView {
        let panel = PampGramGlass.makePanel(cornerRadius: 20.0)
        let title = self.makeLabel("Уровень", font: .systemFont(ofSize: 17.0, weight: .semibold), color: self.primaryColor)
        panel.addSubview(title)
        self.levelValueLabel.translatesAutoresizingMaskIntoConstraints = false
        self.levelValueLabel.font = .systemFont(ofSize: 17.0, weight: .semibold)
        self.levelValueLabel.textColor = self.primaryColor
        self.levelValueLabel.textAlignment = .right
        panel.addSubview(self.levelValueLabel)
        self.configureSlider(self.levelSlider)
        self.levelSlider.minimumValue = 1.0
        self.levelSlider.maximumValue = 99.0
        self.levelSlider.addTarget(self, action: #selector(self.levelChanged(_:)), for: .valueChanged)
        panel.addSubview(self.levelSlider)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 18.0),
            title.topAnchor.constraint(equalTo: panel.topAnchor, constant: 16.0),
            self.levelValueLabel.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -18.0),
            self.levelValueLabel.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            self.levelSlider.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 18.0),
            self.levelSlider.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -18.0),
            self.levelSlider.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10.0),
            self.levelSlider.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -16.0)
        ])
        return panel
    }

    private func makePointsPanel() -> UIView {
        let panel = PampGramGlass.makePanel(cornerRadius: 20.0)
        let title = self.makeLabel("Очки", font: .systemFont(ofSize: 17.0, weight: .semibold), color: self.primaryColor)
        panel.addSubview(title)
        self.pointsValueLabel.translatesAutoresizingMaskIntoConstraints = false
        self.pointsValueLabel.font = .systemFont(ofSize: 17.0, weight: .semibold)
        self.pointsValueLabel.textColor = self.primaryColor
        self.pointsValueLabel.textAlignment = .right
        panel.addSubview(self.pointsValueLabel)
        self.pointsRangeLabel.translatesAutoresizingMaskIntoConstraints = false
        self.pointsRangeLabel.font = .systemFont(ofSize: 13.0, weight: .regular)
        self.pointsRangeLabel.textColor = self.secondaryColor
        panel.addSubview(self.pointsRangeLabel)
        self.configureSlider(self.pointsSlider)
        self.pointsSlider.minimumValue = 0.0
        self.pointsSlider.maximumValue = 1.0
        self.pointsSlider.addTarget(self, action: #selector(self.pointsChanged(_:)), for: .valueChanged)
        panel.addSubview(self.pointsSlider)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 18.0),
            title.topAnchor.constraint(equalTo: panel.topAnchor, constant: 16.0),
            self.pointsValueLabel.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -18.0),
            self.pointsValueLabel.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            self.pointsRangeLabel.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 18.0),
            self.pointsRangeLabel.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -18.0),
            self.pointsRangeLabel.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4.0),
            self.pointsSlider.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 18.0),
            self.pointsSlider.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -18.0),
            self.pointsSlider.topAnchor.constraint(equalTo: self.pointsRangeLabel.bottomAnchor, constant: 8.0),
            self.pointsSlider.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -16.0)
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

    private func configureSlider(_ slider: UISlider) {
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.minimumTrackTintColor = self.primaryColor
        slider.maximumTrackTintColor = self.secondaryColor.withAlphaComponent(0.25)
        slider.thumbTintColor = self.primaryColor
        slider.isContinuous = true
    }

    private func applyInitialState(_ state: PampGramProfileVisualState) {
        guard !self.didLoadInitialState else {
            return
        }
        self.didLoadInitialState = true
        let storedLevel = min(Int64(99), max(Int64(1), state.ratingValue))
        self.selectedLevel = Int(storedLevel)
        if state.ratingPoints > 0 {
            self.pointsProgress = self.progress(for: state.ratingPoints, at: self.selectedLevel)
        }
        self.showInProfile = state.ratingEnabled
        self.updateUI()
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

    @objc private func presetPressed(_ sender: PampGramRatingPresetButton) {
        self.selectedLevel = sender.level
        self.updateUI()
    }

    @objc private func levelChanged(_ slider: UISlider) {
        self.selectedLevel = min(99, max(1, Int(slider.value.rounded())))
        self.updateUI()
    }

    @objc private func pointsChanged(_ slider: UISlider) {
        self.pointsProgress = min(1.0, max(0.0, slider.value))
        self.updateUI()
    }

    @objc private func toggleDisplay() {
        self.showInProfile = self.displaySwitch.isOn
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
        self.popSelf()
    }

    private func updateUI() {
        let points = self.points(for: self.selectedLevel, progress: self.pointsProgress)
        let range = self.pointsRange(for: self.selectedLevel)
        self.levelSlider.value = Float(self.selectedLevel)
        self.pointsSlider.value = self.pointsProgress
        self.levelValueLabel.text = "\(self.selectedLevel)"
        self.pointsValueLabel.text = self.formatPoints(points)
        self.pointsRangeLabel.text = "\(self.formatPoints(range.lowerBound)) — \(self.formatPoints(range.upperBound))"
        self.previewBadgeView.image = PampGramRatingBadge.image(level: self.selectedLevel, size: 58.0)
        self.previewLevelLabel.text = "Уровень \(self.selectedLevel)"
        self.previewPointsLabel.text = "\(self.formatPoints(points)) очков"
        self.displaySwitch.isOn = self.showInProfile

        let nearestPreset = self.presetButtons.filter { $0.level <= self.selectedLevel }.last?.level ?? 1
        for button in self.presetButtons {
            button.updateAppearance(selected: button.level == nearestPreset)
        }
    }

    /// Telegram's real per-level point thresholds (min, max), levels 1–99 — the actual server
    /// values, not an approximation. 99 is the real maximum level; there is no level 100.
    private static let levelPointRanges: [(Int64, Int64)] = [
        (1, 4999), (5000, 11999), (12000, 18999), (19000, 26999), (27000, 35999), (36000, 45999),
        (46000, 56999), (57000, 67999), (68000, 80999), (81000, 93999), (94000, 106999), (107000, 119999),
        (120000, 132999), (133000, 145999), (146000, 159999), (160000, 172999), (173000, 185999), (186000, 198999),
        (199000, 211999), (212000, 224999), (225000, 237999), (238000, 250999), (251000, 264999), (265000, 277999),
        (278000, 290999), (291000, 303999), (304000, 316999), (317000, 329999), (330000, 342999), (343000, 355999),
        (356000, 369999), (370000, 382999), (383000, 395999), (396000, 408999), (409000, 421999), (422000, 434999),
        (435000, 447999), (448000, 460999), (461000, 474999), (475000, 487999), (488000, 500999), (501000, 513999),
        (514000, 526999), (527000, 539999), (540000, 552999), (553000, 565999), (566000, 579999), (580000, 592999),
        (593000, 605999), (606000, 618999), (619000, 631999), (632000, 644999), (645000, 657999), (658000, 670999),
        (671000, 684999), (685000, 697999), (698000, 710999), (711000, 723999), (724000, 736999), (737000, 749999),
        (750000, 762999), (763000, 775999), (776000, 789999), (790000, 802999), (803000, 815999), (816000, 828999),
        (829000, 841999), (842000, 854999), (855000, 867999), (868000, 880999), (881000, 884999), (885000, 907999),
        (908000, 920999), (921000, 933999), (934000, 946999), (947000, 959999), (960000, 972999), (973000, 985999),
        (986000, 999999), (1000000, 1399999), (1400000, 1959999), (1960000, 2743999), (2744000, 3841999), (3842000, 5378999),
        (5379000, 7530999), (7531000, 10542999), (10543000, 14759999), (14760000, 20663999), (20664000, 28929999), (28930000, 40501999),
        (40502000, 56702999), (56703000, 79383999), (79384000, 111138948), (111138949, 155596416), (155596417, 217837626), (217837627, 304976378),
        (304976379, 426972111), (426972112, 597768210), (597768211, 836885651)
    ]

    private func pointsRange(for level: Int) -> ClosedRange<Int64> {
        let clampedLevel = min(99, max(1, level))
        let (lowerBound, upperBound) = Self.levelPointRanges[clampedLevel - 1]
        return lowerBound...upperBound
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
}

func pampGramProfileRatingEditorController(context: AccountContext) -> ViewController {
    return PampGramProfileRatingEditorController(context: context)
}
