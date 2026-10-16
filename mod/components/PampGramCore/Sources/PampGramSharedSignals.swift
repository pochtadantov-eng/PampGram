import Foundation
import Postbox
import SwiftSignalKit

/// One live, decoded copy of a Postbox-backed value per account, shared by every consumer.
///
/// Before this, each call to `PampGramCore.settingsSignal` (the chat bubbles, every media fetch
/// and upload, the balance pills, the profile header ...) opened its own Postbox preferences view
/// and decoded the whole `PampGramSettings` JSON for itself, and the gift list and the ledger
/// were decoded again by each profile, grid and screen that watched them. Here the underlying
/// signal runs once, for the lifetime of the account, and `Promise` replays its latest value to
/// anyone who subscribes — so a new subscriber costs a lock instead of a database read plus a
/// decode, and a change is decoded once however many places are listening.
public enum PampGramSharedSignals {
    private final class Entry {
        // Keeps the Postbox alive, so its `ObjectIdentifier` can never be handed to a different
        // Postbox while this entry still exists.
        let postbox: Postbox
        var promises: [String: Any] = [:]

        init(postbox: Postbox) {
            self.postbox = postbox
        }
    }

    private static let lock = NSLock()
    private static var entries: [ObjectIdentifier: Entry] = [:]

    public static func shared<T>(postbox: Postbox, name: String, make: () -> Signal<T, NoError>) -> Signal<T, NoError> {
        let id = ObjectIdentifier(postbox)

        self.lock.lock()
        let existing = self.entries[id]?.promises[name] as? Promise<T>
        self.lock.unlock()
        if let existing {
            return existing.get()
        }

        // Built outside the lock: `make` may itself ask for another shared signal (the gated
        // settings are derived from the raw ones), and `NSLock` is not re-entrant.
        let created = Promise<T>(initializeOnFirstAccess: make())

        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        let entry: Entry
        if let current = self.entries[id] {
            entry = current
        } else {
            entry = Entry(postbox: postbox)
            self.entries[id] = entry
        }
        if let raced = entry.promises[name] as? Promise<T> {
            return raced.get()
        }
        entry.promises[name] = created
        return created.get()
    }
}
