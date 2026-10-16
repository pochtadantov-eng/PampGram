import Foundation
import SwiftSignalKit

/// What "Режим призрака" has actually done since the app was launched — the numbers shown in the
/// "Диагностика" block of the Ghost screen. In memory only (a restart starts them from zero), and
/// written from the same single decision points that do the hiding, so the screen can't claim
/// something the hooks didn't do.
///
/// It exists because Ghost can't be checked from the device that runs it: whether a read receipt
/// went out is only visible on the other person's phone. With these counters the owner can open
/// a chat, come back to the screen and see "скрыто: 1" — or see "ушло: 1" together with the
/// reason it wasn't hidden (a chat exception, "Читать при действиях", a switch that is off).
public struct PampGramGhostDiagnosticsSnapshot: Equatable {
    public var readHidden: Int = 0
    public var readSent: Int = 0
    public var storyHidden: Int = 0
    public var storySent: Int = 0
    public var typingHidden: Int = 0
    public var typingSent: Int = 0
    /// `account.updateStatus(offline: false)` / `(offline: true)` requests this launch.
    public var onlineSent: Int = 0
    public var offlineSent: Int = 0
    /// Why the most recent signal of each kind was NOT hidden ("" if none yet).
    public var lastReadSentReason: String = ""
    public var lastStorySentReason: String = ""
    public var lastTypingSentReason: String = ""

    public init() {
    }
}

public final class PampGramGhostDiagnostics {
    public enum Kind {
        case readReceipts
        case storyViews
        case typing
    }

    public static let shared = PampGramGhostDiagnostics()

    private let state = Atomic<PampGramGhostDiagnosticsSnapshot>(value: PampGramGhostDiagnosticsSnapshot())

    private init() {
    }

    public func snapshot() -> PampGramGhostDiagnosticsSnapshot {
        return self.state.with { $0 }
    }

    /// The signal was withheld.
    public func recordHidden(_ kind: Kind) {
        let _ = self.state.modify { current in
            var current = current
            switch kind {
            case .readReceipts:
                current.readHidden += 1
            case .storyViews:
                current.storyHidden += 1
            case .typing:
                current.typingHidden += 1
            }
            return current
        }
    }

    /// The signal went out; `reason` says why Ghost let it through.
    public func recordSent(_ kind: Kind, reason: String) {
        let _ = self.state.modify { current in
            var current = current
            switch kind {
            case .readReceipts:
                current.readSent += 1
                current.lastReadSentReason = reason
            case .storyViews:
                current.storySent += 1
                current.lastStorySentReason = reason
            case .typing:
                current.typingSent += 1
                current.lastTypingSentReason = reason
            }
            return current
        }
    }

    public func recordPresence(online: Bool) {
        let _ = self.state.modify { current in
            var current = current
            if online {
                current.onlineSent += 1
            } else {
                current.offlineSent += 1
            }
            return current
        }
    }
}
