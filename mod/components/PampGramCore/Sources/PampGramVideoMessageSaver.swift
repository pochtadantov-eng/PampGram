import Foundation
import Photos
import Postbox
import TelegramCore
import SwiftSignalKit
import AccountContext

/// Автоматическое сохранение видеосообщений (кружков) в галерею.
///
/// Telegram не даёт сохранить кружок напрямую — нет кнопки "Сохранить" и нет share-sheet
/// для видеосообщений. Эта функция копирует уже скачанный ресурс (mp4) из Telegram-кэша
/// (`mediaBox`) в «Фотопленку» через `PHPhotoLibrary`.
///
/// Integration point (в патче):
///
/// `ChatMessageInteractiveInstantVideoNode.swift` (или `ChatMessageInstantVideoItemNode`),
/// метод, который вызывается при начале воспроизведения кружка. После того как Telegram
/// начал воспроизведение (ресурс уже в кэше):
///
/// ```swift
/// if PampGramVideoMessageSaver.shared.isEnabled(accountKey: context.account.peerId.toInt64()) {
///     PampGramVideoMessageSaver.shared.saveIfNeeded(context: context, message: message)
/// }
/// ```
///
/// Или из контекстного меню: добавить «Сохранить в галерею» для любого видеосообщения:
///
/// ```swift
/// items.append(.action(ContextMenuActionItem(
///     text: "Сохранить кружок",
///     icon: { theme in generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Save"), color: theme.contextMenu.primaryColor) },
///     action: { c, _ in
///         c?.dismiss(completion: {
///             PampGramVideoMessageSaver.shared.saveIfNeeded(context: context, message: message)
///         })
///     }
/// )))
/// ```
public final class PampGramVideoMessageSaver {
    public static let shared = PampGramVideoMessageSaver()

    private let lock = NSLock()
    private var enabledByAccount: [Int64: Bool] = [:]
    private var startedAccounts: Set<Int64> = []
    private var savedMessageIds: Set<String> = []
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
            self.enabledByAccount[accountKey] = settings.autoSaveVideoMessagesEnabled
            self.lock.unlock()
        })

        self.lock.lock()
        self.disposables[accountKey] = disposable
        self.lock.unlock()
    }

    /// Сохраняет кружок в галерею, если он ещё не был сохранён в этой сессии.
    /// Безопасно вызывать повторно — дубликатов не будет.
    public func saveIfNeeded(context: AccountContext, message: Message) {
        let key = "\(message.id.peerId.toInt64())_\(message.id.id)"

        self.lock.lock()
        if self.savedMessageIds.contains(key) {
            self.lock.unlock()
            return
        }
        self.savedMessageIds.insert(key)
        self.lock.unlock()

        guard let file = message.media.compactMap({ $0 as? TelegramMediaFile }).first,
              file.isInstantVideo else {
            return
        }

        let postbox = context.account.postbox
        let _ = (postbox.mediaBox.resourceData(file.resource, option: .complete(waitUntilFetchStatus: false), attemptSynchronously: false)
        |> take(1)
        |> deliverOnMainQueue).startStandalone(next: { resourceData in
            guard resourceData.complete else { return }
            let sourcePath = resourceData.path

            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                guard status == .authorized || status == .limited else { return }
                let sourceURL = URL(fileURLWithPath: sourcePath)
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: sourceURL)
                }, completionHandler: nil)
            }
        })
    }
}
