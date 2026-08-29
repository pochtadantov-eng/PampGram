import Foundation
import UIKit
import Display

/// A 30×30 rounded-square icon with a white SF Symbol glyph centered on a solid color — the
/// same "colored square + glyph" look Telegram's own root Settings rows use, generated at
/// runtime for the same reason as `pampGramSettingsIcon()`: no asset-catalog entries to merge
/// when rebasing.
public func generatePampGramSectionIcon(systemName: String, backgroundColor: UIColor) -> UIImage? {
    return generateImage(CGSize(width: 30.0, height: 30.0), rotatedContext: { size, context in
        let bounds = CGRect(origin: CGPoint(), size: size)
        context.clear(bounds)

        context.saveGState()
        context.addPath(UIBezierPath(roundedRect: bounds, cornerRadius: 8.0).cgPath)
        context.clip()
        context.setFillColor(backgroundColor.cgColor)
        context.fill(bounds)
        context.restoreGState()

        if let glyph = UIImage(systemName: systemName)?.withTintColor(.white, renderingMode: .alwaysOriginal) {
            let glyphSize = CGSize(width: 16.0, height: 16.0)
            let glyphRect = CGRect(
                origin: CGPoint(x: (size.width - glyphSize.width) / 2.0, y: (size.height - glyphSize.height) / 2.0),
                size: glyphSize
            )
            UIGraphicsPushContext(context)
            glyph.draw(in: glyphRect)
            UIGraphicsPopContext()
        }
    })
}
