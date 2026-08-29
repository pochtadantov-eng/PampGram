import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import AccountContext
import PampGramCore

private struct PampGramDeletedMessageList: Codable {
    var messages: [PampGramDeletedMessage]
}

/// Persistent, entirely local storage for the anti-delete feature's captured messages.
/// Backed by Postbox's own `PreferencesEntry` mechanism, same as `PampGramPhantomGiftStore` —
/// survives app restarts for free, never touches `account.network`.
public enum PampGramDeletedMessageStore {
    public static func all(transaction: Transaction) -> [PampGramDeletedMessage] {
        return transaction.getPreferencesEntry(key: PampGramPreferencesKeys.deletedMessages)?.get(PampGramDeletedMessageList.self)?.messages ?? []
    }

    public static func add(transaction: Transaction, message: PampGramDeletedMessage) {
        transaction.updatePreferencesEntry(key: PampGramPreferencesKeys.deletedMessages, { entry in
            var list = entry?.get(PampGramDeletedMessageList.self) ?? PampGramDeletedMessageList(messages: [])
            list.messages.append(message)
            return PreferencesEntry(list)
        })
    }

    public static func remove(transaction: Transaction, id: Int64) {
        transaction.updatePreferencesEntry(key: PampGramPreferencesKeys.deletedMessages, { entry in
            var list = entry?.get(PampGramDeletedMessageList.self) ?? PampGramDeletedMessageList(messages: [])
            list.messages.removeAll(where: { $0.id == id })
            return PreferencesEntry(list)
        })
    }

    public static func removeAll(transaction: Transaction) -> [PampGramDeletedMessage] {
        let existing = self.all(transaction: transaction)
        transaction.updatePreferencesEntry(key: PampGramPreferencesKeys.deletedMessages, { _ in
            return PreferencesEntry(PampGramDeletedMessageList(messages: []))
        })
        return existing
    }

    /// Live list of every captured message on this device, newest-deleted first.
    public static func allSignal(context: AccountContext) -> Signal<[PampGramDeletedMessage], NoError> {
        return context.account.postbox.preferencesView(keys: [PampGramPreferencesKeys.deletedMessages])
        |> map { view -> [PampGramDeletedMessage] in
            let messages = view.values[PampGramPreferencesKeys.deletedMessages]?.get(PampGramDeletedMessageList.self)?.messages ?? []
            return messages.sorted(by: { $0.deletedAt > $1.deletedAt })
        }
    }
}
