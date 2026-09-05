import Foundation
import Postbox
import SwiftSignalKit

/// Process-lifetime cache of PampGram settings, kept warm by a shared signal subscription
/// so hot paths in tg-ios (message list rendering, copy/paste guards, screenshot hooks)
/// can consult the current toggle state synchronously — no signal disposable to plumb
/// through every consumer, no `postbox.transaction { … }` on the render path.
///
/// Only exposes the flags that need sub-frame reads. Anything that already lives in a
/// Signal path should keep using `PampGramCore.settingsSignal(postbox:)` — this cache is
/// deliberately eventual-consistent (a toggle flip is picked up on the next signal tick).
public final class PampGramLiveSettings {
    public static let shared = PampGramLiveSettings()

    private let lock = NSLock()
    private var boundAccountKey: Int64?
    private var disposable: Disposable?

    private var _copyProtectionBypassEnabled = false
    private var _forwardKeepAuthorEnabled = false
    private var _disableAutoDeleteEnabled = false
    private var _blockSponsoredMessagesEnabled = false
    private var _screenshotBypassEnabled = false
    private var _hideChatOnScreenshot = false

    private init() {}

    /// Starts (or rebinds) the subscription to the given account's PampGram settings.
    /// Safe to call from every hot path: idempotent per account, cheap after the first
    /// call. Consumers pass in `account.postbox` and any identifier that uniquely
    /// distinguishes the account.
    public func bind(postbox: Postbox, accountKey: Int64) {
        self.lock.lock()
        if self.boundAccountKey == accountKey {
            self.lock.unlock()
            return
        }
        self.disposable?.dispose()
        self.boundAccountKey = accountKey
        self.lock.unlock()
        self.disposable = PampGramCore.settingsSignal(postbox: postbox).start(next: { [weak self] settings in
            guard let self else { return }
            self.lock.lock()
            self._copyProtectionBypassEnabled = settings.copyProtectionBypassEnabled
            self._forwardKeepAuthorEnabled = settings.forwardKeepAuthorEnabled
            self._disableAutoDeleteEnabled = settings.disableAutoDeleteEnabled
            self._blockSponsoredMessagesEnabled = settings.blockSponsoredMessagesEnabled
            self._screenshotBypassEnabled = settings.screenshotBypassEnabled
            self._hideChatOnScreenshot = settings.hideChatOnScreenshot
            self.lock.unlock()
        })
    }

    public var copyProtectionBypassEnabled: Bool {
        self.lock.lock(); defer { self.lock.unlock() }
        return self._copyProtectionBypassEnabled
    }

    public var forwardKeepAuthorEnabled: Bool {
        self.lock.lock(); defer { self.lock.unlock() }
        return self._forwardKeepAuthorEnabled
    }

    public var disableAutoDeleteEnabled: Bool {
        self.lock.lock(); defer { self.lock.unlock() }
        return self._disableAutoDeleteEnabled
    }

    public var blockSponsoredMessagesEnabled: Bool {
        self.lock.lock(); defer { self.lock.unlock() }
        return self._blockSponsoredMessagesEnabled
    }

    public var screenshotBypassEnabled: Bool {
        self.lock.lock(); defer { self.lock.unlock() }
        return self._screenshotBypassEnabled
    }

    public var hideChatOnScreenshot: Bool {
        self.lock.lock(); defer { self.lock.unlock() }
        return self._hideChatOnScreenshot
    }
}
