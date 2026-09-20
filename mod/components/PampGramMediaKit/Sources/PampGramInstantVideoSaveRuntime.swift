import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore
import AccountContext
import SaveToCameraRoll
import PampGramCore

/// "Сохранение видео" (Ghost): the moment an incoming round-video ("кружочек") message sent
/// as view-once or with a self-destruct timer is laid out in an open chat, save it into this
/// device's Photos library — bypassing the restriction stock Telegram puts on secret media
/// (its own "Save to Camera Roll" action is hidden for it, see
/// `ChatInterfaceStateContextMenus.swift`). Warmed once per account at `AccountContextImpl`
/// init (see the patch), same pattern as `PampGramFakeAdminRuntime`/`PampGramTemporaryMediaDisplay`.
///
/// Purely local: nothing is sent back to Telegram, and the message's real timer, consumption,
/// and deletion are untouched — this only keeps a copy of media this account already received
/// before the timer removes it from the chat.
public final class PampGramInstantVideoSaveRuntime {
    public static let shared = PampGramInstantVideoSaveRuntime()

    private let lock = NSLock()
    private var enabledByAccount: [Int64: Bool] = [:]
    private var startedAccounts: Set<Int64> = []
    private var settingsDisposables: [Int64: Disposable] = [:]
    private var attemptedByAccount: [Int64: Set<PampGramSavedInstantVideoRef>] = [:]

    private init() {
    }

    public func isEnabled(accountKey: Int64) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.enabledByAccount[accountKey] ?? false
    }

    /// Starts (once per account) the subscription that keeps the flag current.
    public func start(accountKey: Int64, postbox: Postbox) {
        self.lock.lock()
        if self.startedAccounts.contains(accountKey) {
            self.lock.unlock()
            return
        }
        self.startedAccounts.insert(accountKey)
        self.lock.unlock()

        let disposable = (PampGramCore.settingsSignal(postbox: postbox)
        |> deliverOn(Queue.concurrentDefaultQueue())).start(next: { [weak self] settings in
            guard let self else {
                return
            }
            self.lock.lock()
            self.enabledByAccount[accountKey] = settings.saveInstantVideosEnabled
            self.lock.unlock()
        })

        self.lock.lock()
        self.settingsDisposables[accountKey] = disposable
        self.lock.unlock()
    }

    /// Called from `ChatMessageInteractiveInstantVideoNode` whenever it lays out an incoming
    /// self-destructing/view-once round video and the setting is on. Saves it into Photos at
    /// most once per message: an in-memory guard stops duplicate triggers from scroll/reuse
    /// churn within this launch, a Postbox-persisted marker (`PampGramSavedInstantVideoStore`)
    /// stops a second save if the message is still around on the next launch.
    public func saveIfNeeded(context: AccountContext, message: Message, file: TelegramMediaFile) {
        let accountKey = context.account.peerId.toInt64()
        guard self.isEnabled(accountKey: accountKey) else {
            return
        }
        let ref = PampGramSavedInstantVideoRef(peerId: message.id.peerId.toInt64(), namespace: message.id.namespace, id: message.id.id)

        self.lock.lock()
        var attempted = self.attemptedByAccount[accountKey] ?? Set()
        if attempted.contains(ref) {
            self.lock.unlock()
            return
        }
        attempted.insert(ref)
        self.attemptedByAccount[accountKey] = attempted
        self.lock.unlock()

        let postbox = context.account.postbox
        let peerId = message.id.peerId
        let mediaReference = FileMediaReference.standalone(media: file).abstract
        let _ = (postbox.transaction { transaction -> Bool in
            return PampGramSavedInstantVideoStore.contains(transaction: transaction, ref: ref)
        }
        |> deliverOnMainQueue
        |> mapToSignal { alreadySaved -> Signal<Never, NoError> in
            if alreadySaved {
                return .complete()
            }
            return saveToCameraRoll(context: context, userLocation: .peer(peerId), mediaReference: mediaReference)
            |> ignoreValues
            |> then(
                postbox.transaction { transaction -> Void in
                    PampGramSavedInstantVideoStore.add(transaction: transaction, ref: ref)
                }
                |> ignoreValues
            )
        }).start()
    }
}
