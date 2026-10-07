import Foundation
import ImageIO
import Postbox
import TelegramCore
import SwiftSignalKit
import AccountContext
import PampGramCore

/// "Автомодерация": looks at every new incoming picture and sticker with a vision model and, when
/// it is explicit (18+) or graphic violence, deletes the message from this device and blocks its
/// sender. Strictly opt-in — see `PampGramSettings.moderationEnabled` — and it only ever runs with
/// the user's own Anthropic API key (`moderationApiKey`).
///
/// What leaves the phone: a downscaled JPEG copy of the one picture being checked, to
/// api.anthropic.com, and nothing else (no text, no names, no chat ids). Messages are looked at one
/// at a time, and a picture seen before (the same sticker, say) is answered from memory instead of
/// being sent again.
///
/// It leans towards NOT acting: the model is told to answer SAFE when unsure, any network or API
/// error counts as "nothing found", and every action is written to the journal in the settings
/// screen so a mistake can be spotted and undone.
public final class PampGramModerationRuntime {
    public static let shared = PampGramModerationRuntime()

    public enum Verdict: String {
        case safe = "SAFE"
        case nsfw = "NSFW"
        case gore = "GORE"
    }

    private struct Candidate {
        let messageId: MessageId
        let resource: MediaResource
        let reference: MediaResourceReference
        let authorId: PeerId?
        let authorTitle: String
    }

    private let lock = NSLock()
    private var startedAccounts: Set<Int64> = []
    private let queue = Queue(name: "pampgram.moderation", qos: .utility)

    // Everything below is only touched on `queue`.
    private var pending: [(context: AccountContext, messageId: MessageId)] = []
    private var isProcessing = false
    private var verdictCache: [String: Verdict] = [:]
    private let disposable = MetaDisposable()

    private init() {
    }

    public func start(accountKey: Int64, context: AccountContext) {
        self.lock.lock()
        if self.startedAccounts.contains(accountKey) {
            self.lock.unlock()
            return
        }
        self.startedAccounts.insert(accountKey)
        self.lock.unlock()

        PampGramModerationHook.shared.setHandler(accountPeerId: context.account.peerId, { [weak self, weak context] messageIds in
            guard let self, let context else {
                return
            }
            self.queue.async {
                for id in messageIds {
                    self.pending.append((context, id))
                }
                // A burst of messages (joining a busy group) must not queue without limit.
                if self.pending.count > 60 {
                    self.pending.removeFirst(self.pending.count - 60)
                }
                self.processNext()
            }
        })
    }

    // MARK: - Pipeline

    private func processNext() {
        guard !self.isProcessing, !self.pending.isEmpty else {
            return
        }
        self.isProcessing = true
        let item = self.pending.removeFirst()
        let context = item.context

        let work = context.account.postbox.transaction { transaction -> (Candidate?, PampGramSettings) in
            let settings = PampGramCore.settings(transaction: transaction)
            return (PampGramModerationRuntime.candidate(transaction: transaction, accountPeerId: context.account.peerId, messageId: item.messageId), settings)
        }
        |> deliverOn(self.queue)
        |> mapToSignal { [weak self] candidate, settings -> Signal<Void, NoError> in
            guard let self, let candidate, settings.moderationEnabled, !settings.moderationApiKey.isEmpty else {
                return .single(Void())
            }
            return self.check(context: context, candidate: candidate, settings: settings)
        }
        // One message at a time; the timeout only exists so a stuck request can never freeze the line.
        |> timeout(90.0, queue: self.queue, alternate: .complete())

        self.disposable.set(work.start(completed: { [weak self] in
            self?.queue.async {
                self?.isProcessing = false
                self?.processNext()
            }
        }))
    }

    private static func candidate(transaction: Transaction, accountPeerId: PeerId, messageId: MessageId) -> Candidate? {
        guard let message = transaction.getMessage(messageId), message.flags.contains(.Incoming) else {
            return nil
        }
        let messageReference = MessageReference(message)
        var resource: MediaResource?
        var reference: MediaResourceReference?
        for media in message.media {
            if let image = media as? TelegramMediaImage, let representation = largestImageRepresentation(image.representations) {
                resource = representation.resource
                reference = ImageMediaReference.message(message: messageReference, media: image).resourceReference(representation.resource)
                break
            } else if let file = media as? TelegramMediaFile {
                if file.isSticker && !file.isAnimatedSticker && !file.isVideoSticker && file.mimeType == "image/webp" {
                    // A still sticker is the picture itself.
                    resource = file.resource
                    reference = FileMediaReference.message(message: messageReference, media: file).resourceReference(file.resource)
                    break
                } else if let representation = largestImageRepresentation(file.previewRepresentations) {
                    // Animated stickers, videos and GIFs: their preview frame.
                    resource = representation.resource
                    reference = FileMediaReference.message(message: messageReference, media: file).resourceReference(representation.resource)
                    break
                }
            }
        }
        guard let resource, let reference else {
            return nil
        }
        var authorId: PeerId?
        var authorTitle = ""
        if let author = message.author {
            authorTitle = EnginePeer(author).debugDisplayTitle
            if author is TelegramUser, author.id != accountPeerId {
                authorId = author.id
            }
        }
        return Candidate(messageId: messageId, resource: resource, reference: reference, authorId: authorId, authorTitle: authorTitle)
    }

    private func check(context: AccountContext, candidate: Candidate, settings: PampGramSettings) -> Signal<Void, NoError> {
        let cacheKey = candidate.resource.id.stringRepresentation
        if let cached = self.verdictCache[cacheKey] {
            return self.act(context: context, candidate: candidate, verdict: cached, settings: settings)
        }
        let apiKey = settings.moderationApiKey
        return PampGramModerationRuntime.loadData(context: context, candidate: candidate)
        |> deliverOn(self.queue)
        |> mapToSignal { [weak self] data -> Signal<Void, NoError> in
            guard let self, let data, let encoded = PampGramModerationRuntime.downscaledJpegBase64(data: data) else {
                return .single(Void())
            }
            return PampGramModerationRuntime.classify(apiKey: apiKey, jpegBase64: encoded)
            |> deliverOn(self.queue)
            |> mapToSignal { [weak self] verdict -> Signal<Void, NoError> in
                guard let self, let verdict else {
                    // The check failed (network, key, quota): nothing is done.
                    return .single(Void())
                }
                if self.verdictCache.count > 500 {
                    self.verdictCache.removeAll()
                }
                self.verdictCache[cacheKey] = verdict
                return self.act(context: context, candidate: candidate, verdict: verdict, settings: settings)
            }
        }
    }

    private func act(context: AccountContext, candidate: Candidate, verdict: Verdict, settings: PampGramSettings) -> Signal<Void, NoError> {
        guard verdict != .safe else {
            return .single(Void())
        }
        let blockTarget: PeerId? = settings.moderationBlockSender ? candidate.authorId : nil
        let entry = PampGramModerationLogEntry(
            id: Int64.random(in: 1...Int64.max),
            date: Int32(Date().timeIntervalSince1970),
            title: candidate.authorTitle,
            verdict: verdict.rawValue,
            deleted: true,
            blocked: blockTarget != nil
        )
        let delete = context.engine.messages.deleteMessagesInteractively(messageIds: [candidate.messageId], type: .forLocalPeer)
        let block: Signal<Void, NoError>
        if let blockTarget {
            block = context.engine.privacy.requestUpdatePeerIsBlocked(peerId: blockTarget, isBlocked: true)
        } else {
            block = .single(Void())
        }
        let log = context.account.postbox.transaction { transaction -> Void in
            PampGramModerationLogStore.add(transaction: transaction, entry: entry)
        }
        return delete
        |> then(block)
        |> then(log)
    }

    // MARK: - Picture bytes

    private static func loadData(context: AccountContext, candidate: Candidate) -> Signal<Data?, NoError> {
        let mediaBox = context.account.postbox.mediaBox
        let fetch = fetchedMediaResource(mediaBox: mediaBox, userLocation: .peer(candidate.messageId.peerId), userContentType: .image, reference: candidate.reference)
        |> ignoreValues
        |> `catch` { _ -> Signal<Never, NoError> in
            return .complete()
        }
        let data = mediaBox.resourceData(candidate.resource, option: .complete(waitUntilFetchStatus: false))
        |> filter { $0.complete }
        |> take(1)
        |> map { resourceData -> Data? in
            return try? Data(contentsOf: URL(fileURLWithPath: resourceData.path), options: .mappedIfSafe)
        }
        |> timeout(30.0, queue: Queue.concurrentDefaultQueue(), alternate: .single(nil))

        return Signal { subscriber in
            let fetchDisposable = fetch.start()
            let dataDisposable = data.start(next: { value in
                subscriber.putNext(value)
            }, completed: {
                subscriber.putCompletion()
            })
            return ActionDisposable {
                fetchDisposable.dispose()
                dataDisposable.dispose()
            }
        }
    }

    /// A small JPEG is all the model needs, and keeps the upload (and the bill) down.
    private static func downscaledJpegBase64(data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 768
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return (output as Data).base64EncodedString()
    }

    // MARK: - Anthropic API

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let model = "claude-haiku-4-5-20251001"

    private static let prompt = "You are a content-safety classifier inside a messaging app. Look at the image and answer with exactly one word: NSFW if it shows nudity, sexual acts or explicit sexual content (photos, drawings, cartoons or stickers); GORE if it shows graphic violence such as dismemberment, mutilation, severe injury or dead bodies; otherwise SAFE. Swimwear, art, medical or news context, ordinary affection and mild cartoon violence are SAFE. If you are not sure, answer SAFE."

    private static func request(apiKey: String, content: [[String: Any]], maxTokens: Int) -> URLRequest {
        var request = URLRequest(url: self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 40.0
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = [
            "model": self.model,
            "max_tokens": maxTokens,
            "messages": [["role": "user", "content": content]]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// `nil` when the check could not be made — callers treat that as "nothing found".
    private static func classify(apiKey: String, jpegBase64: String) -> Signal<Verdict?, NoError> {
        return Signal { subscriber in
            let content: [[String: Any]] = [
                ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": jpegBase64]],
                ["type": "text", "text": PampGramModerationRuntime.prompt]
            ]
            let task = URLSession.shared.dataTask(with: PampGramModerationRuntime.request(apiKey: apiKey, content: content, maxTokens: 8), completionHandler: { data, response, _ in
                var verdict: Verdict?
                if let http = response as? HTTPURLResponse, http.statusCode == 200, let data,
                   let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                   let blocks = json["content"] as? [[String: Any]],
                   let text = blocks.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String {
                    let answer = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                    if answer.hasPrefix("NSFW") {
                        verdict = .nsfw
                    } else if answer.hasPrefix("GORE") {
                        verdict = .gore
                    } else if answer.hasPrefix("SAFE") {
                        verdict = .safe
                    }
                }
                subscriber.putNext(verdict)
                subscriber.putCompletion()
            })
            task.resume()
            return ActionDisposable {
                task.cancel()
            }
        }
    }

    /// For the "Проверить ключ" button: a one-word text request, so no picture is involved. Returns
    /// `nil` when the key works, otherwise a short explanation for the user.
    public static func testKey(apiKey: String, completion: @escaping (String?) -> Void) {
        let content: [[String: Any]] = [["type": "text", "text": "Reply with the single word OK."]]
        let task = URLSession.shared.dataTask(with: self.request(apiKey: apiKey, content: content, maxTokens: 8), completionHandler: { data, response, error in
            var result: String?
            if let http = response as? HTTPURLResponse {
                switch http.statusCode {
                case 200:
                    result = nil
                case 401, 403:
                    result = "Ключ не принят (ошибка \(http.statusCode)). Проверьте, что он скопирован целиком."
                case 429:
                    result = "Ключ работает, но лимит запросов исчерпан (429)."
                default:
                    result = "Сервис ответил ошибкой \(http.statusCode)."
                }
            } else {
                result = error?.localizedDescription ?? "Нет ответа от сервиса. Проверьте интернет."
            }
            DispatchQueue.main.async {
                completion(result)
            }
        })
        task.resume()
    }
}
