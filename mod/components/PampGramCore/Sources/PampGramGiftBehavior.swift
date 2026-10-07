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
        var cooldownDays: Int32 = 0
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
            let days = settings.fakeTransferCooldownEnabled ? max(1, settings.fakeTransferCooldownDays) : 0
            let fails = settings.fakeOfferAcceptFailEnabled
            let _ = self.state.modify { _ in
                return State(cooldownDays: days, offerAcceptFails: fails)
            }
        }))
    }

    /// The date a gift can be transferred from: the real one, or — with the fake cooldown on —
    /// always the chosen number of days from now, so the standard "available on <date>" alert shows.
    public func effectiveTransferDate(_ real: Int32?) -> Int32? {
        let days = self.state.with { $0.cooldownDays }
        if days <= 0 {
            return real
        }
        let now = Int32(Date().timeIntervalSince1970)
        let fake = now + days * 24 * 60 * 60
        return max(real ?? 0, fake)
    }

    public var offerAcceptFails: Bool {
        return self.state.with { $0.offerAcceptFails }
    }
}
