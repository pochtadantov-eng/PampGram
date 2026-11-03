import Foundation
import Postbox
import SwiftSignalKit

public final class PampGramVoiceFileSaver {
    public static let shared = PampGramVoiceFileSaver()
    private init() {}

    public var voiceResourceExtractor: ((_ message: Message) -> (MediaResource, String)?)?
    public var presentShareSheet: ((_ fileURL: URL) -> Void)?

    public func saveVoiceAsFile(postbox: Postbox, messageId: MessageId) {
        let _ = (postbox.transaction { transaction -> (MediaResource, String)? in
            guard let message = transaction.getMessage(messageId) else { return nil }
            return self.voiceResourceExtractor?(message)
        }
        |> mapToSignal { result -> Signal<(String, String)?, NoError> in
            guard let (resource, fileName) = result else { return .single(nil) }
            return postbox.mediaBox.resourceData(resource, option: .complete(waitUntilFetchStatus: false), attemptSynchronously: false)
            |> take(1)
            |> map { data -> (String, String)? in
                guard data.complete else { return nil }
                return (data.path, fileName)
            }
        }
        |> deliverOnMainQueue).startStandalone(next: { [weak self] result in
            guard let (path, fileName) = result else { return }
            let tmpDir = NSTemporaryDirectory() + "pampgram_voice/"
            try? FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
            let destURL = URL(fileURLWithPath: tmpDir).appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: destURL)
            do {
                try FileManager.default.copyItem(atPath: path, toPath: destURL.path)
            } catch {
                return
            }
            self?.presentShareSheet?(destURL)
        })
    }
}
