import Foundation
import UIKit

/// Shared "liquid glass" building blocks for PampGram's full-screen editors. On iOS 26 these use the
/// real `UIGlassEffect`; on older systems they fall back to a translucent material blur, so the same
/// code gives a glassy, no-solid-color panel everywhere.
public enum PampGramGlass {
    /// A rounded translucent panel. Add content as subviews of the returned view — it sits above the
    /// glass. The panel has no solid fill of its own.
    public static func makePanel(cornerRadius: CGFloat = 18.0) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        container.layer.cornerRadius = cornerRadius
        container.layer.cornerCurve = .continuous
        container.clipsToBounds = true

        let effectView: UIVisualEffectView
        if #available(iOS 26.0, *) {
            let glass = UIGlassEffect(style: .regular)
            glass.isInteractive = false
            effectView = UIVisualEffectView(effect: glass)
        } else {
            effectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        }
        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.isUserInteractionEnabled = false
        container.addSubview(effectView)
        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            effectView.topAnchor.constraint(equalTo: container.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    /// A small round glass button (for the header back / close controls).
    public static func makeCircleButton(diameter: CGFloat) -> UIView {
        return makePanel(cornerRadius: diameter / 2.0)
    }
}

/// Draws a Telegram-style rating level badge: a rounded "seal" shape filled with a tier gradient and
/// the level number in the centre. Tiers change colour with the level, matching the real profile
/// rating badge look (grey → bronze → blue → purple → gold).
public enum PampGramRatingBadge {
    private static func tierColors(for level: Int) -> [UIColor] {
        switch level {
        case ..<10:
            return [UIColor(red: 0.62, green: 0.66, blue: 0.72, alpha: 1.0), UIColor(red: 0.45, green: 0.49, blue: 0.56, alpha: 1.0)]
        case 10..<20:
            return [UIColor(red: 0.86, green: 0.62, blue: 0.36, alpha: 1.0), UIColor(red: 0.70, green: 0.45, blue: 0.22, alpha: 1.0)]
        case 20..<30:
            return [UIColor(red: 0.36, green: 0.78, blue: 0.55, alpha: 1.0), UIColor(red: 0.19, green: 0.60, blue: 0.40, alpha: 1.0)]
        case 30..<50:
            return [UIColor(red: 0.30, green: 0.68, blue: 0.99, alpha: 1.0), UIColor(red: 0.16, green: 0.47, blue: 0.92, alpha: 1.0)]
        case 50..<75:
            return [UIColor(red: 0.62, green: 0.42, blue: 0.98, alpha: 1.0), UIColor(red: 0.42, green: 0.24, blue: 0.90, alpha: 1.0)]
        default:
            return [UIColor(red: 0.99, green: 0.80, blue: 0.30, alpha: 1.0), UIColor(red: 0.95, green: 0.58, blue: 0.13, alpha: 1.0)]
        }
    }

    private static func sealPath(in rect: CGRect) -> UIBezierPath {
        // A 12-lobed rounded seal (scalloped rounded square), like Telegram's rating badge outline.
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2.0
        let inner = outer * 0.82
        let lobes = 12
        let path = UIBezierPath()
        let step = (CGFloat.pi * 2.0) / CGFloat(lobes * 2)
        for i in 0 ..< (lobes * 2) {
            let radius = (i % 2 == 0) ? outer : inner
            let angle = step * CGFloat(i) - CGFloat.pi / 2.0
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.close()
        return path
    }

    /// Renders the badge at the given size for a level. `numberFont` scales with the size.
    public static func image(level: Int, size: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let rect = CGRect(x: 0.0, y: 0.0, width: size, height: size).insetBy(dx: size * 0.04, dy: size * 0.04)
            let path = sealPath(in: rect)
            cg.saveGState()
            path.addClip()
            let colors = tierColors(for: level)
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [colors[0].cgColor, colors[1].cgColor] as CFArray, locations: [0.0, 1.0])!
            cg.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.minY), end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
            cg.restoreGState()

            let numberString = "\(level)"
            let fontSize = size * (numberString.count >= 3 ? 0.34 : 0.44)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let attributed = NSAttributedString(string: numberString, attributes: attributes)
            let textSize = attributed.size()
            let textRect = CGRect(x: rect.midX - textSize.width / 2.0, y: rect.midY - textSize.height / 2.0, width: textSize.width, height: textSize.height)
            attributed.draw(in: textRect)
        }
    }
}
