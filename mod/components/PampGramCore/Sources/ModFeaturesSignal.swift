import Foundation
import SwiftSignalKit

/// Snapshot of the six protection-related toggles that back the "guard" features
/// (copy bypass, forward-author preservation, TTL bypass, screenshot bypass,
/// screenshot blur, sponsored-message blocking). ItemList screens redraw off a
/// Signal, so ModSettings — which lives in UserDefaults — is exposed through this
/// value type plus `modFeaturesSignal()` below.
public struct ModFeaturesSnapshot: Equatable {
    public var bypassCopyProtection: Bool
    public var alwaysKeepForwardAuthor: Bool
    public var disableAutoDelete: Bool
    public var bypassScreenshotProtection: Bool
    public var hideChatOnScreenshot: Bool
    public var blockAds: Bool

    public init(bypassCopyProtection: Bool, alwaysKeepForwardAuthor: Bool, disableAutoDelete: Bool, bypassScreenshotProtection: Bool, hideChatOnScreenshot: Bool, blockAds: Bool) {
        self.bypassCopyProtection = bypassCopyProtection
        self.alwaysKeepForwardAuthor = alwaysKeepForwardAuthor
        self.disableAutoDelete = disableAutoDelete
        self.bypassScreenshotProtection = bypassScreenshotProtection
        self.hideChatOnScreenshot = hideChatOnScreenshot
        self.blockAds = blockAds
    }

    public static var current: ModFeaturesSnapshot {
        let s = ModSettings.shared
        return ModFeaturesSnapshot(
            bypassCopyProtection: s.bypassCopyProtection,
            alwaysKeepForwardAuthor: s.alwaysKeepForwardAuthor,
            disableAutoDelete: s.disableAutoDelete,
            bypassScreenshotProtection: s.bypassScreenshotProtection,
            hideChatOnScreenshot: s.hideChatOnScreenshot,
            blockAds: s.blockAds
        )
    }

    public var activeCount: Int {
        var n = 0
        if bypassCopyProtection { n += 1 }
        if alwaysKeepForwardAuthor { n += 1 }
        if disableAutoDelete { n += 1 }
        if bypassScreenshotProtection { n += 1 }
        if hideChatOnScreenshot { n += 1 }
        if blockAds { n += 1 }
        return n
    }

    public static var totalCount: Int { 6 }
}

private let modFeaturesChangeNotification = NSNotification.Name("ModSettingsDidChange")

/// Emits the current snapshot on subscribe and then on every ModSettings change.
public func modFeaturesSignal() -> Signal<ModFeaturesSnapshot, NoError> {
    return Signal { subscriber in
        subscriber.putNext(ModFeaturesSnapshot.current)
        let observer = NotificationCenter.default.addObserver(
            forName: modFeaturesChangeNotification,
            object: nil,
            queue: OperationQueue.main
        ) { _ in
            subscriber.putNext(ModFeaturesSnapshot.current)
        }
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

/// Activate every runtime hook the mod features need (screenshot observer, etc.).
/// Safe to call more than once — the shared controller sets itself up on first access.
public func activateModFeatures() {
    _ = ModFeaturesController.shared
}
