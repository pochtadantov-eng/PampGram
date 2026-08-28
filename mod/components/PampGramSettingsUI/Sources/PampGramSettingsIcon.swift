import Foundation
import UIKit
import Display

/// The 30×30 rounded-square icon for the "PampGram" row in Telegram's own settings list,
/// drawn at runtime rather than shipped as an asset: the mod adds no files to the app
/// bundle and therefore never has to touch Telegram's asset catalog, which is the one part
/// of the project that conflicts hardest when rebasing onto a new release.
///
/// `rotatedContext` (not `contextGenerator`) because the glyph is drawn through UIKit,
/// which expects a top-left origin.
///
/// Cached, because the settings list rebuilds its items on every redraw and the icon never
/// changes — it is theme-independent by design, like the other coloured settings icons.
public func pampGramSettingsIcon() -> UIImage? {
    return cachedPampGramSettingsIcon
}

/// A global `let` rather than a mutable cache: Swift initializes these lazily and exactly
/// once, thread-safely, so this both defers the drawing until the settings list first asks
/// for it and stays clear of the concurrency-safety diagnostics a mutable global draws.
private let cachedPampGramSettingsIcon: UIImage? = generatePampGramSettingsIcon()

private func generatePampGramSettingsIcon() -> UIImage? {
    let size = CGSize(width: 30.0, height: 30.0)
    return generateImage(size, rotatedContext: { size, context in
        let bounds = CGRect(origin: CGPoint(), size: size)
        context.clear(bounds)

        context.saveGState()
        context.addPath(UIBezierPath(roundedRect: bounds, cornerRadius: 8.0).cgPath)
        context.clip()

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var locations: [CGFloat] = [0.0, 1.0]
        let colors: [CGColor] = [UIColor(rgb: 0xb37bf5).cgColor, UIColor(rgb: 0x8e44ec).cgColor]
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: &locations) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0.0, y: 0.0), end: CGPoint(x: size.width, y: size.height), options: CGGradientDrawingOptions())
        }
        context.restoreGState()

        let text = NSAttributedString(string: "P", attributes: [
            .font: Font.bold(19.0),
            .foregroundColor: UIColor.white
        ])
        let textSize = text.boundingRect(with: bounds.size, options: .usesLineFragmentOrigin, context: nil).size
        let textRect = CGRect(
            origin: CGPoint(x: floorToScreenPixels((size.width - textSize.width) / 2.0), y: floorToScreenPixels((size.height - textSize.height) / 2.0)),
            size: textSize
        )
        UIGraphicsPushContext(context)
        text.draw(in: textRect)
        UIGraphicsPopContext()
    })
}
