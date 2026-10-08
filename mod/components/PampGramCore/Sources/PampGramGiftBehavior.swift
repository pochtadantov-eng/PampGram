import Foundation
import Postbox
import SwiftSignalKit

/// Synchronous view of the two gift "behaviour" toggles, for call sites that decide on the spot
/// (the transfer check, the offer accept button) and cannot wait for a Postbox transaction.
/// Kept current by one subscription to the gated settings (so "Включить визуалку" off, the master
/// switch and a ban all turn it off as well).
public final class PampGramGiftBehavior {
    public static let shared = PampGramGiftBehavior()

    private struct State {
        /// Unix time the fake transfer cooldown ends; 0 while it is off.
        var cooldownUntil: Int32 = 0
        var offerAcceptFails: Bool = false
    }

    private let state = Atomic<State>(value: State())
    private let lock = NSLock()
    private var started = false
    private let disposable = MetaDisposable()

    private init() {
    }

    public func start(postbox: Postbox) {
        self.lock.lock()
        if self.started {
            self.lock.unlock()
            return
        }
        self.started = true
        self.lock.unlock()

        self.disposable.set((PampGramCore.settingsSignal(postbox: postbox)
        |> deliverOnMainQueue).start(next: { [weak self] settings in
            guard let self else {
                return
            }
            let until = settings.fakeTransferCooldownEnabled ? settings.fakeTransferCooldownUntil : 0
            let fails = settings.fakeOfferAcceptFailEnabled
            let _ = self.state.modify { _ in
                return State(cooldownUntil: until, offerAcceptFails: fails)
            }
        }))
    }

    /// The date a gift can be transferred from: the real one, or — while the fake cooldown is running —
    /// the moment it ends, so the standard "available on <date>" alert shows. Once that moment has
    /// passed the real date applies again, like a timer that ran out.
    public func effectiveTransferDate(_ real: Int32?) -> Int32? {
        let until = self.state.with { $0.cooldownUntil }
        if until <= 0 {
            return real
        }
        let now = Int32(Date().timeIntervalSince1970)
        if until <= now {
            return real
        }
        return max(real ?? 0, until)
    }

    public var offerAcceptFails: Bool {
        return self.state.with { $0.offerAcceptFails }
    }
}
