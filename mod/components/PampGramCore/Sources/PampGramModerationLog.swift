import Foundation
import Postbox
import SwiftSignalKit

/// One thing the auto-moderation did, kept so the user can always see what was removed and who was
/// blocked (a mistaken block must be easy to spot and undo).
public struct PampGramModerationLogEntry: Codable, Equatable {
    public var id: Int64
    public var date: Int32
    /// The sender's name as it was when the message arrived.
    public var title: String
    /// "NSFW" or "GORE".
    public var verdict: String
    public var deleted: Bool
    public var blocked: Bool

    public init(id: Int64, date: Int32, title: String, verdict: String, deleted: Bool, blocked: Bool) {
        self.id = id
        self.date = date
        self.title = title
        self.verdict = verdict
        self.deleted = deleted
        self.blocked = blocked
    }
}

private struct PampGramModerationLogList: Codable {
    var entries: [PampGramModerationLogEntry]
}

public enum PampGramModerationLogStore {
    private static let limit = 100

    public static func add(transaction: Transaction, entry: PampGramModerationLogEntry) {
        transaction.updatePreferencesEntry(key: PampGramPreferencesKeys.moderationLog, { current in
            var list = current?.get(PampGramModerationLogList.self) ?? PampGramModerationLogList(entries: [])
            list.entries.append(entry)
            if list.entries.count > self.limit {
                list.entries.removeFirst(list.entries.count - self.limit)
            }
            return PreferencesEntry(list)
        })
    }

    public static func clear(transaction: Transaction) {
        transaction.setPreferencesEntry(key: PampGramPreferencesKeys.moderationLog, value: PreferencesEntry(PampGramModerationLogList(entries: [])))
    }

    /// Newest first.
    public static func signal(postbox: Postbox) -> Signal<[PampGramModerationLogEntry], NoError> {
        return postbox.preferencesView(keys: [PampGramPreferencesKeys.moderationLog])
        |> map { view -> [PampGramModerationLogEntry] in
            let entries = view.values[PampGramPreferencesKeys.moderationLog]?.get(PampGramModerationLogList.self)?.entries ?? []
            return entries.reversed()
        }
    }
}
