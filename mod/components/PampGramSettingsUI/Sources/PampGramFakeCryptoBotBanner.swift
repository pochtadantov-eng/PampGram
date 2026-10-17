import Foundation
import UIKit
import Display

/// The two kinds of controls on the wallet page that used to be pictures with the dark theme baked
/// in: the round buttons over the balance and the banners under the action buttons. They are drawn
/// in code now (only the glyphs and the stripe are cut from the real page), so they follow the
/// light/dark theme: the banner's background is its accent colour at 10 % over the page, as on the
/// real page, the round button is a light-grey disc in the light theme.

final class PampGramFakeCryptoBotRoundButton: UIControl {
    private let glyph = UIImageView()

    init(glyph name: String) {
        super.init(frame: .zero)
        self.backgroundColor = PampGramFakeCryptoBotColors.roundButton
        self.glyph.image = PampGramFakeCryptoBotAssets.image(name)?.withRenderingMode(.alwaysTemplate)
        self.glyph.tintColor = PampGramFakeCryptoBotColors.roundGlyph
        self.glyph.contentMode = .scaleAspectFit
        self.glyph.isUserInteractionEnabled = false
        self.addSubview(self.glyph)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.layer.cornerRadius = self.bounds.width / 2.0
        self.glyph.frame = self.bounds
    }

    override var isHighlighted: Bool {
        didSet {
            self.alpha = self.isHighlighted ? 0.6 : 1.0
        }
    }
}

final class PampGramFakeCryptoBotBannerView: UIControl {
    private let stripe = UIImageView()
    private let titleLabel = UILabel()
    private let lineLabels: [UILabel]
    private let chevron = UIImageView()
    private let textX: CGFloat
    private let titleCenter: CGFloat
    private let lineCenters: [CGFloat]

    init(title: String, lines: [String], accent: UIColor, stripeAsset: String, textX: CGFloat, titleCenter: CGFloat, lineCenters: [CGFloat]) {
        self.textX = textX
        self.titleCenter = titleCenter
        self.lineCenters = lineCenters
        var labels: [UILabel] = []
        for line in lines {
            let label = UILabel()
            label.text = line
            label.font = PampGramFakeCryptoBotFonts.font(13.0, .regular)
            label.textColor = PampGramFakeCryptoBotColors.text
            label.isUserInteractionEnabled = false
            labels.append(label)
        }
        self.lineLabels = labels
        super.init(frame: .zero)
        self.backgroundColor = accent.withAlphaComponent(0.1)
        self.layer.cornerRadius = 12.0
        self.layer.masksToBounds = true
        self.stripe.image = PampGramFakeCryptoBotAssets.image(stripeAsset)
        self.stripe.isUserInteractionEnabled = false
        self.addSubview(self.stripe)
        self.titleLabel.text = title
        self.titleLabel.font = PampGramFakeCryptoBotFonts.font(15.0, .medium)
        self.titleLabel.textColor = accent
        self.titleLabel.isUserInteractionEnabled = false
        self.addSubview(self.titleLabel)
        for label in labels {
            self.addSubview(label)
        }
        self.chevron.image = UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12.0, weight: .semibold))
        self.chevron.tintColor = accent.withAlphaComponent(0.7)
        self.chevron.contentMode = .center
        self.chevron.isUserInteractionEnabled = false
        self.addSubview(self.chevron)
        self.updateStripe()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The stripe is a little paler on the light page.
    private func updateStripe() {
        self.stripe.alpha = self.traitCollection.userInterfaceStyle == .light ? 0.78 : 1.0
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        self.updateStripe()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        self.updateStripe()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = self.bounds.width
        let height = self.bounds.height
        self.stripe.frame = CGRect(x: 0.0, y: 0.0, width: 4.0, height: height)
        let textWidth = max(0.0, width - self.textX - 28.0)
        self.titleLabel.frame = CGRect(x: self.textX, y: self.titleCenter - 10.0, width: textWidth, height: 20.0)
        for (index, label) in self.lineLabels.enumerated() where index < self.lineCenters.count {
            label.frame = CGRect(x: self.textX, y: self.lineCenters[index] - 9.0, width: textWidth, height: 18.0)
        }
        self.chevron.frame = CGRect(x: width - 17.5 - 9.0, y: 37.2 - 9.0, width: 18.0, height: 18.0)
        _ = height
    }
}
