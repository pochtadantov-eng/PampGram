import Foundation
import Photos
import UIKit
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

    public func saveFile(path: String, isVideo: Bool) {
        self.saveFileToPhotos(path: path, isVideo: isVideo)
    }

    private func saveFileToPhotos(path: String, isVideo: Bool) {
        // Resource files in the media box have no extension, which Photos needs for video; images
        // are decoded and handed over as UIImage for the same reason.
        var videoURL: URL?
        var image: UIImage?
        if isVideo {
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pampgram_\(UUID().uuidString).mp4")
            do {
                try FileManager.default.copyItem(atPath: path, toPath: url.path)
            } catch {
                return
            }
            videoURL = url
        } else {
            guard let decoded = UIImage(contentsOfFile: path) else {
                return
            }
            image = decoded
        }

        let saveBlock: () -> Void = {
            PHPhotoLibrary.shared().performChanges({
                if let videoURL {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
                } else if let image {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
            }, completionHandler: { _, _ in
                if let videoURL {
                    try? FileManager.default.removeItem(at: videoURL)
                }
            })
        }

        let cleanup: () -> Void = {
            if let videoURL {
                try? FileManager.default.removeItem(at: videoURL)
            }
        }

        if #available(iOS 14, *) {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                guard status == .authorized || status == .limited else {
                    cleanup()
                    return
                }
                saveBlock()
            }
        } else {
            PHPhotoLibrary.requestAuthorization { status in
                guard status == .authorized else {
                    cleanup()
                    return
                }
                saveBlock()
            }
        }
    }
}
