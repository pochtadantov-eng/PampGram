import Foundation
import UIKit
import Display

/// One page of the first-launch onboarding carousel: a big colored icon, a title and a short
/// description. Purely illustrative — there is no way to grab a real in-app screenshot from
/// this build pipeline (no simulator here), so every page describes the feature in words
/// instead of showing a picture of it.
private struct PampGramOnboardingPage {
    let systemImageName: String
    let color: UIColor
    let title: String
    let subtitle: String
}

private let pampGramOnboardingPages: [PampGramOnboardingPage] = [
    PampGramOnboardingPage(systemImageName: "sparkles", color: UIColor(rgb: 0x8e44ec), title: "PampGram", subtitle: "Расширяй. Скрывай. Контролируй.\nВсё, что ты сейчас увидишь, работает локально — на этом устройстве."),
    PampGramOnboardingPage(systemImageName: "gift.fill", color: UIColor(rgb: 0x8e44ec), title: "Подарки", subtitle: "Локальные подарки, визуальные балансы Stars и TON, своя коллекция и маркет — видно только тебе."),
    PampGramOnboardingPage(systemImageName: "eye.slash.fill", color: UIColor(rgb: 0x34c759), title: "Ghost", subtitle: "Скрывай «в сети», «печатает» и отметки о прочтении — собеседник не узнает, что ты был здесь."),
    PampGramOnboardingPage(systemImageName: "message.fill", color: UIColor(rgb: 0x3b82f6), title: "Чаты", subtitle: "Удалённые сообщения остаются в переписке — свои и чужие. История никуда не пропадает."),
    PampGramOnboardingPage(systemImageName: "paintbrush.fill", color: UIColor(rgb: 0xff9500), title: "Внешний вид", subtitle: "Пресеты Standard, Glass и Compact — выбери иконку приложения и стиль интерфейса под себя."),
]

private final class PampGramOnboardingPageView: UIView {
    private let iconContainer = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    init(page: PampGramOnboardingPage) {
        super.init(frame: .zero)

        self.iconContainer.backgroundColor = page.color.withAlphaComponent(0.16)
        self.iconContainer.layer.cornerRadius = 56.0
        self.addSubview(self.iconContainer)

        self.iconView.image = UIImage(systemName: page.systemImageName)?.withRenderingMode(.alwaysTemplate)
        self.iconView.tintColor = page.color
        self.iconView.contentMode = .scaleAspectFit
        self.iconContainer.addSubview(self.iconView)

        self.titleLabel.text = page.title
        self.titleLabel.font = UIFont.systemFont(ofSize: 26.0, weight: .bold)
        self.titleLabel.textColor = .white
        self.titleLabel.textAlignment = .center
        self.addSubview(self.titleLabel)

        self.subtitleLabel.text = page.subtitle
        self.subtitleLabel.font = UIFont.systemFont(ofSize: 15.0, weight: .regular)
        self.subtitleLabel.textColor = UIColor(white: 1.0, alpha: 0.6)
        self.subtitleLabel.textAlignment = .center
        self.subtitleLabel.numberOfLines = 0
        self.addSubview(self.subtitleLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let width = self.bounds.width
        let containerSide: CGFloat = 112.0
        let centerY = self.bounds.height * 0.38
        self.iconContainer.frame = CGRect(x: (width - containerSide) / 2.0, y: centerY - containerSide, width: containerSide, height: containerSide)
        let glyphSide: CGFloat = 48.0
        self.iconView.frame = CGRect(x: (containerSide - glyphSide) / 2.0, y: (containerSide - glyphSide) / 2.0, width: glyphSide, height: glyphSide)

        let textWidth = min(300.0, width - 48.0)
        self.titleLabel.frame = CGRect(x: (width - textWidth) / 2.0, y: self.iconContainer.frame.maxY + 28.0, width: textWidth, height: 32.0)

        let subtitleSize = self.subtitleLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))
        self.subtitleLabel.frame = CGRect(x: (width - textWidth) / 2.0, y: self.titleLabel.frame.maxY + 12.0, width: textWidth, height: subtitleSize.height)
    }
}

private final class PampGramOnboardingViewController: UIViewController, UIScrollViewDelegate {
    private let onFinished: () -> Void

    private let scrollView = UIScrollView()
    private let skipButton = UIButton(type: .system)
    private let dotsStack = UIStackView()
    private var dots: [UIView] = []
    private let nextButton = UIButton(type: .system)

    init(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
        super.init(nibName: nil, bundle: nil)
        self.modalPresentationStyle = .fullScreen
        self.modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = UIColor(rgb: 0x0e0e14)

        self.scrollView.isPagingEnabled = true
        self.scrollView.showsHorizontalScrollIndicator = false
        self.scrollView.delegate = self
        self.view.addSubview(self.scrollView)

        for page in pampGramOnboardingPages {
            self.scrollView.addSubview(PampGramOnboardingPageView(page: page))
        }

        self.skipButton.setTitle("Пропустить", for: .normal)
        self.skipButton.setTitleColor(UIColor(white: 1.0, alpha: 0.5), for: .normal)
        self.skipButton.titleLabel?.font = UIFont.systemFont(ofSize: 15.0, weight: .regular)
        self.skipButton.addTarget(self, action: #selector(self.skipPressed), for: .touchUpInside)
        self.view.addSubview(self.skipButton)

        self.dotsStack.axis = .horizontal
        self.dotsStack.spacing = 6.0
        self.dotsStack.alignment = .center
        self.view.addSubview(self.dotsStack)
        for _ in pampGramOnboardingPages {
            let dot = UIView()
            dot.backgroundColor = UIColor(white: 1.0, alpha: 0.25)
            dot.layer.cornerRadius = 3.0
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: 6.0).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 6.0).isActive = true
            self.dotsStack.addArrangedSubview(dot)
            self.dots.append(dot)
        }
        self.updateDots(activeIndex: 0)

        self.nextButton.backgroundColor = .white
        self.nextButton.setTitleColor(.black, for: .normal)
        self.nextButton.titleLabel?.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        self.nextButton.layer.cornerRadius = 14.0
        self.nextButton.setTitle("Далее", for: .normal)
        self.nextButton.addTarget(self, action: #selector(self.nextPressed), for: .touchUpInside)
        self.view.addSubview(self.nextButton)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let width = self.view.bounds.width
        let topInset = self.view.safeAreaInsets.top
        let bottomInset = self.view.safeAreaInsets.bottom

        self.skipButton.sizeToFit()
        self.skipButton.frame = CGRect(x: width - self.skipButton.frame.width - 20.0, y: topInset + 8.0, width: self.skipButton.frame.width, height: 32.0)

        let buttonHeight: CGFloat = 52.0
        self.nextButton.frame = CGRect(x: 20.0, y: self.view.bounds.height - bottomInset - buttonHeight - 20.0, width: width - 40.0, height: buttonHeight)

        self.dotsStack.frame.size = self.dotsStack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        self.dotsStack.frame.origin = CGPoint(x: (width - self.dotsStack.frame.width) / 2.0, y: self.nextButton.frame.minY - 28.0)

        self.scrollView.frame = CGRect(x: 0.0, y: topInset + 44.0, width: width, height: self.dotsStack.frame.minY - topInset - 44.0)
        self.scrollView.contentSize = CGSize(width: width * CGFloat(pampGramOnboardingPages.count), height: self.scrollView.frame.height)
        for (index, subview) in self.scrollView.subviews.enumerated() {
            subview.frame = CGRect(x: width * CGFloat(index), y: 0.0, width: width, height: self.scrollView.frame.height)
        }
    }

    private func updateDots(activeIndex: Int) {
        for (index, dot) in self.dots.enumerated() {
            dot.backgroundColor = index == activeIndex ? .white : UIColor(white: 1.0, alpha: 0.25)
        }
        self.nextButton.setTitle(activeIndex == pampGramOnboardingPages.count - 1 ? "Начать" : "Далее", for: .normal)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.bounds.width > 0 else {
            return
        }
        let index = Int((scrollView.contentOffset.x / scrollView.bounds.width).rounded())
        self.updateDots(activeIndex: max(0, min(pampGramOnboardingPages.count - 1, index)))
    }

    @objc private func skipPressed() {
        self.finish()
    }

    @objc private func nextPressed() {
        let currentIndex = Int((self.scrollView.contentOffset.x / max(1.0, self.scrollView.bounds.width)).rounded())
        if currentIndex >= pampGramOnboardingPages.count - 1 {
            self.finish()
        } else {
            let nextOffset = CGPoint(x: self.scrollView.bounds.width * CGFloat(currentIndex + 1), y: 0.0)
            self.scrollView.setContentOffset(nextOffset, animated: true)
        }
    }

    private func finish() {
        self.dismiss(animated: true, completion: self.onFinished)
    }
}

private let pampGramOnboardingShownKey = "PampGram_OnboardingShown_v1"

/// Shown once, the very first time the app launches — before the user has an account, so this
/// can't read `PampGramSettings` (that lives in a Postbox, which needs a logged-in account) and
/// uses a plain `UserDefaults` flag instead. Presents on top of whatever the app already put on
/// screen (its own real launch flow — phone-number entry or the chat list — is untouched
/// underneath) rather than intercepting that decision, so there is nothing here that can break
/// getting into the app if this screen has a bug.
public func pampGramPresentOnboardingIfNeeded(on window: UIWindow) {
    guard !UserDefaults.standard.bool(forKey: pampGramOnboardingShownKey) else {
        return
    }
    UserDefaults.standard.set(true, forKey: pampGramOnboardingShownKey)

    let onboarding = PampGramOnboardingViewController(onFinished: {})
    window.rootViewController?.present(onboarding, animated: false, completion: nil)
}
