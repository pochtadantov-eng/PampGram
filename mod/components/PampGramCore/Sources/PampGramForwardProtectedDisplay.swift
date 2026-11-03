import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import AccountContext

/// Synchronous, in-memory mirror of "Пересылка в Избранное" (Дополнительно → Медиа и скриншоты).
///
/// Chat context-menu code (`ChatMessageContextMenuActions` / `chatMessageDisplaySendMessageOptions`)
/// checks `canForward` to decide whether to show the "Forward" action. Telegram hides it for
/// messages with `noForwards` (copy-protected chats) and for view-once / timed media. This
/// runtime exposes the setting synchronously so the patch can add a "В Избранное" action that
/// copies the message into Saved Messages instead of the normal forward path (which goes through
/// the server and would be blocked).
///
/// Integration point (in the patch):
///
/// 1. `ChatMessageContextMenuActions.swift` / `chatAvailableMessageActions` — after Telegram
///    builds its `[ContextMenuItem]`, if `forwardProtectedToSavedEnabled` is on AND the message
///    is in a no-forward chat or is a view-once/timed media, append:
///
///    ```swift
///    items.append(.action(ContextMenuActionItem(
///        text: "В Избранное",
///        icon: { theme in generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Save"), color: theme.contextMenu.primaryColor) },
///        action: { c, _ in
///            c?.dismiss(completion: {
///                PampGramForwardProtectedDisplay.saveToSavedMessages(context: context, message: message)
///            })
///        }
///    )))
///    ```
///
/// 2. The actual save copies the message content (text + media) into Saved Messages as a new
///    local-only outgoing message — never through `forwardMessages` (which the server would
///    refuse for protected content).
public final class PampGramForwardProtectedDisplay {
    public static let shared = PampGramForwardProtectedDisplay()

    private let lock = NSLock()
    private var enabledByAccount: [Int64: Bool] = [:]
    private var startedAccounts: Set<Int64> = []
    private var disposables: [Int64: Disposable] = [:]

    private init() {}

    public func isEnabled(accountKey: Int64) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.enabledByAccount[accountKey] ?? false
    }

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
            guard let self else { return }
            self.lock.lock()
            self.enabledByAccount[accountKey] = settings.forwardProtectedToSavedEnabled
            self.lock.unlock()
        })

        self.lock.lock()
        self.disposables[accountKey] = disposable
        self.lock.unlock()
    }

    /// Copies the message's text and first media attachment into Saved Messages as a new
    /// local outgoing message. Uses `enqueueMessages` with `.message(...)` — this is the
    /// same path Telegram uses for "send to self" and never touches the forward API that
    /// the server blocks for protected content.
    ///
    /// Call from the context-menu action closure:
    /// ```swift
    /// PampGramForwardProtectedDisplay.saveToSavedMessages(context: context, message: message)
    /// ```
    public static func saveToSavedMessages(context: AccountContext, message: Message) {
        let selfPeerId = context.account.peerId

        let mediaRef: AnyMediaReference?
        if let media = message.media.first {
            mediaRef = .standalone(media: media)
        } else {
            mediaRef = nil
        }

        let text = message.text
        let _ = enqueueMessages(
            account: context.account,
            peerId: selfPeerId,
            messages: [
                .message(
                    text: text,
                    attributes: [],
                    inlineStickers: [:],
                    mediaReference: mediaRef,
                    threadId: nil,
                    replyToMessageId: nil,
                    replyToStoryId: nil,
                    localGroupingKey: nil,
                    correlationId: nil,
                    bubbleUpEmojiOrStickersets: []
                )
            ]
        ).start()
    }
}
