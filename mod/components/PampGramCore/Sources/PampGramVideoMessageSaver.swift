import Foundation
import Photos
import Postbox
import SwiftSignalKit

public final class PampGramVideoMessageSaver {
    public static let shared = PampGramVideoMessageSaver()

    private let lock = NSLock()
    private var enabledByAccount: [Int64: Bool] = [:]
    private var startedAccounts: Set<Int64> = []
    private var savedMessageIds: Set<String> = []
    private var disposables: [Int64: Disposable] = [:]

    /// Injected by AccountContext startup (has TelegramCore access).
    /// Extracts the instant-video MediaResource from a Message, or nil.
    public var instantVideoResourceExtractor: ((_ message: Message) -> MediaResource?)?

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

    public func saveIfNeeded(postbox: Postbox, message: Message) {
        let key = "\(message.id.peerId.toInt64())_\(message.id.id)"

        self.lock.lock()
        if self.savedMessageIds.contains(key) {
            self.lock.unlock()
            return
        }
        self.savedMessageIds.insert(key)
        self.lock.unlock()

        guard let resource = instantVideoResourceExtractor?(message) else {
            return
        }

        let _ = (postbox.mediaBox.resourceData(resource, option: .complete(waitUntilFetchStatus: false), attemptSynchronously: false)
        |> take(1)
        |> deliverOnMainQueue).startStandalone(next: { resourceData in
            guard resourceData.complete else { return }
            let sourcePath = resourceData.path

            let saveBlock: (@escaping () -> Void) -> Void = { completion in
                let sourceURL = URL(fileURLWithPath: sourcePath)
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: sourceURL)
                }, completionHandler: { _, _ in completion() })
            }

            if #available(iOS 14, *) {
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                    guard status == .authorized || status == .limited else { return }
                    saveBlock({})
                }
            } else {
                PHPhotoLibrary.requestAuthorization { status in
                    guard status == .authorized else { return }
                    saveBlock({})
                }
            }
        })
    }
}
