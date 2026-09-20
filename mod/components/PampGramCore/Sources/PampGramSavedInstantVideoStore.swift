import Foundation
import Postbox
import SwiftSignalKit

/// One saved-once marker for a round-video ("кружочек") message that "Сохранение видео"
/// already copied into Photos, so it never writes the same clip twice — across scroll
/// re-layouts within a launch, or across app relaunches while the message is still around.
public struct PampGramSavedInstantVideoRef: Codable, Hashable {
    public let peerId: Int64
    public let namespace: Int32
    public let id: Int32

    public init(peerId: Int64, namespace: Int32, id: Int32) {
        self.peerId = peerId
        self.namespace = namespace
        self.id = id
    }
}

private struct PampGramSavedInstantVideoList: Codable {
    var refs: [PampGramSavedInstantVideoRef]
}

/// Persistent, entirely local marker set for "Сохранение видео" (Ghost). Backed by Postbox's
/// own `PreferencesEntry`, same mechanism as `PampGramDeletedMessageStore`.
public enum PampGramSavedInstantVideoStore {
    public static func contains(transaction: Transaction, ref: PampGramSavedInstantVideoRef) -> Bool {
        let list = transaction.getPreferencesEntry(key: PampGramPreferencesKeys.savedInstantVideos)?.get(PampGramSavedInstantVideoList.self)?.refs ?? []
        return list.contains(ref)
    }

    public static func add(transaction: Transaction, ref: PampGramSavedInstantVideoRef) {
        transaction.updatePreferencesEntry(key: PampGramPreferencesKeys.savedInstantVideos, { entry in
            var list = entry?.get(PampGramSavedInstantVideoList.self) ?? PampGramSavedInstantVideoList(refs: [])
            if !list.refs.contains(ref) {
                list.refs.append(ref)
            }
            return PreferencesEntry(list)
        })
    }
}
