import Foundation
import Photos
import Postbox
import SwiftSignalKit

public final class PampGramMediaGallerySaver {
    public static let shared = PampGramMediaGallerySaver()
    private init() {}

    /// Injected from AccountContextImpl (has TelegramCore access).
    /// Returns (resource, isVideo) for a message's main photo/video media.
    public var mediaResourceExtractor: ((_ message: Message) -> (MediaResource, Bool)?)?

    public func saveMessageMedia(postbox: Postbox, messageId: MessageId) {
        let _ = (postbox.transaction { transaction -> (MediaResource, Bool)? in
            guard let message = transaction.getMessage(messageId) else { return nil }
            return self.mediaResourceExtractor?(message)
        }
        |> mapToSignal { result -> Signal<(String, Bool)?, NoError> in
            guard let (resource, isVideo) = result else { return .single(nil) }
            return postbox.mediaBox.resourceData(resource, option: .complete(waitUntilFetchStatus: false), attemptSynchronously: false)
            |> take(1)
            |> map { resourceData -> (String, Bool)? in
                guard resourceData.complete else { return nil }
                return (resourceData.path, isVideo)
            }
        }
        |> deliverOnMainQueue).startStandalone(next: { result in
            guard let (path, isVideo) = result else { return }
            self.saveFileToPhotos(path: path, isVideo: isVideo)
        })
    }

    private func saveFileToPhotos(path: String, isVideo: Bool) {
        let url = URL(fileURLWithPath: path)
        let saveBlock: (@escaping () -> Void) -> Void = { completion in
            PHPhotoLibrary.shared().performChanges({
                if isVideo {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                } else {
                    PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                }
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
    }
}
