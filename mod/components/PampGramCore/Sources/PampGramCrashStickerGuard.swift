import Foundation
import SwiftSignalKit

public final class PampGramCrashStickerGuard {
    public static let shared = PampGramCrashStickerGuard()

    public static let maxDimension: Int = 4096
    public static let maxArea: Int = 16_000_000
    public static let maxFileSize: Int64 = 5 * 1024 * 1024

    private let _enabled = Atomic<Bool>(value: false)

    private init() {}

    public var enabled: Bool {
        get { _enabled.with { $0 } }
        set { let _ = _enabled.modify { _ in newValue } }
    }

    public func isSafe(width: Int, height: Int, fileSize: Int64) -> Bool {
        guard enabled else { return true }
        if width > Self.maxDimension || height > Self.maxDimension { return false }
        if width > 0 && height > 0 && width * height > Self.maxArea { return false }
        if fileSize > Self.maxFileSize { return false }
        return true
    }
}
