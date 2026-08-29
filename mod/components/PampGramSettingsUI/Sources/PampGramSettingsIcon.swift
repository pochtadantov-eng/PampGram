import Foundation
import UIKit
import Display

/// The PampGram mark — used for the "PampGram" row in Telegram's own settings list, the hub
/// screen's hero row, and the "PampGram Team" footer row. Embedded as a base64-encoded JPEG
/// literal rather than shipped as an asset-catalog entry: the mod adds no files to the app
/// bundle and therefore never has to touch Telegram's asset catalog, which is the one part of
/// the project that conflicts hardest when rebasing onto a new release. The source art
/// already has its rounded-square shape and dark background baked in; a matching corner-radius
/// clip is applied again here only to guarantee crisp edges at whatever size is requested.
///
/// Cached per requested size, since the settings list and hub screen ask for it on every
/// redraw and the source bytes never change.
public func pampGramSettingsIcon(size: CGFloat = 30.0) -> UIImage? {
    return pampGramIconCache.image(size: size)
}

private final class PampGramIconCache {
    private var cached: [CGFloat: UIImage] = [:]
    private let sourceImage: UIImage? = {
        guard let data = Data(base64Encoded: pampGramIconBase64) else {
            return nil
        }
        return UIImage(data: data)
    }()

    func image(size: CGFloat) -> UIImage? {
        if let existing = self.cached[size] {
            return existing
        }
        guard let sourceImage else {
            return nil
        }
        let rendered = generateImage(CGSize(width: size, height: size), rotatedContext: { imageSize, context in
            let bounds = CGRect(origin: CGPoint(), size: imageSize)
            context.clear(bounds)
            context.saveGState()
            context.addPath(UIBezierPath(roundedRect: bounds, cornerRadius: imageSize.width * (8.0 / 30.0)).cgPath)
            context.clip()
            UIGraphicsPushContext(context)
            sourceImage.draw(in: bounds)
            UIGraphicsPopContext()
            context.restoreGState()
        })
        if let rendered {
            self.cached[size] = rendered
        }
        return rendered
    }
}

private let pampGramIconCache = PampGramIconCache()

private let pampGramIconBase64: String =
    "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"
