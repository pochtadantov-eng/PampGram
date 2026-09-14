import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import PampGramCore

/// "Защита от краш-стикеров" (Ghost): watches every incoming message account-wide via the same
/// real, already-existing `account.stateManager.notificationMessages` signal Telegram itself
/// uses to drive local push notifications — no patch to the sync engine itself, just another
/// subscriber to a signal that already fires for every new message while the app is running.
///
/// For each incoming sticker, checks its file metadata against real Telegram's own server-side
/// sticker limits (Bot API: static WEBP ≤ 512 KB, animated TGS ≤ 64 KB, video WEBM ≤ 256 KB;
/// canvas at most 512px on the long side). A sticker arriving several times past those — the
/// shape a deliberately malformed "crash" sticker exploiting a rendering bug tends to take —
/// gets deleted locally (`deleteMessagesInteractively(..., type: .forLocalPeer)`) and its sender
/// blocked (`requestUpdatePeerIsBlocked`), both real, already-existing actions, then a plain
/// local note is dropped into Saved Messages recording what happened.
///
/// This is a heuristic, not a guarantee: it only catches a file that is already anomalous by
/// the numbers. A new exploit hidden inside an otherwise ordinary-looking sticker would not be
/// caught here — there is no general way to know a specific file will crash the renderer short
/// of actually rendering it.
public enum PampGramCrashStickerGuard {
    private static let staticStickerMaxBytes: Int64 = 512 * 1024 * 4
    private static let animatedStickerMaxBytes: Int64 = 64 * 1024 * 6
    private static let videoStickerMaxBytes: Int64 = 256 * 1024 * 4
    private static let maxDimension: Int32 = 2048

    private static func isDangerous(file: TelegramMediaFile) -> Bool {
        guard file.isSticker else {
            return false
        }
        if let size = file.size {
            if file.isAnimatedSticker {
                if size > self.animatedStickerMaxBytes {
                    return true
                }
            } else if file.isVideoSticker {
                if size > self.videoStickerMaxBytes {
                    return true
                }
            } else if size > self.staticStickerMaxBytes {
                return true
            }
        }
        for attribute in file.attributes {
            if case let .ImageSize(dimensions) = attribute {
                if dimensions.width <= 0 || dimensions.height <= 0 || dimensions.width > self.maxDimension || dimensions.height > self.maxDimension {
                    return true
                }
            }
            if case let .Video(_, dimensions, _, _, _, _) = attribute {
                if dimensions.width > self.maxDimension || dimensions.height > self.maxDimension {
                    return true
                }
            }
        }
        return false
    }

    /// One MetaDisposable-held subscription, set up once per account in `AccountContextImpl.init`
    /// alongside the other account-wide observers — see `submodules/TelegramUI/Sources/AccountContext.swift`.
    public static func startObserving(account: Account) -> Disposable {
        let engine = TelegramEngine(account: account)
        let enabledSignal = PampGramCore.settingsSignal(postbox: account.postbox)
        |> map { $0.crashStickerProtectionEnabled }
        |> distinctUntilChanged
        return (combineLatest(account.stateManager.notificationMessages, enabledSignal)
        |> deliverOnMainQueue).startStrict(next: { batches, enabled in
            guard enabled else {
                return
            }
            for (messages, _, _, _) in batches {
                for message in messages {
                    guard let authorId = message.author?.id, authorId != account.peerId else {
                        continue
                    }
                    let hasDangerousSticker = message.media.contains { media in
                        guard let file = media as? TelegramMediaFile else {
                            return false
                        }
                        return self.isDangerous(file: file)
                    }
                    guard hasDangerousSticker else {
                        continue
                    }
                    let _ = engine.messages.deleteMessagesInteractively(messageIds: [message.id], type: .forLocalPeer).start()
                    let _ = engine.privacy.requestUpdatePeerIsBlocked(peerId: authorId, isBlocked: true, sourceMessageId: message.id).start()
                    self.noteAction(account: account, authorId: authorId)
                }
            }
        })
    }

    private static func noteAction(account: Account, authorId: PeerId) {
        let _ = account.postbox.transaction { transaction -> Void in
            guard let authorPeer = transaction.getPeer(authorId) else {
                return
            }
            let title = EnginePeer(authorPeer).compactDisplayTitle
            let text = "PampGram: обнаружен подозрительный стикер от \(title) — сообщение удалено, отправитель заблокирован."
            let globallyUniqueId = Int64.random(in: Int64.min ... Int64.max)
            let storeMessage = StoreMessage(
                id: .Partial(account.peerId, Namespaces.Message.Local),
                customStableId: nil,
                globallyUniqueId: globallyUniqueId,
                groupingKey: nil,
                threadId: nil,
                timestamp: Int32(Date().timeIntervalSince1970),
                flags: StoreMessageFlags(),
                tags: [],
                globalTags: [],
                localTags: [],
                forwardInfo: nil,
                authorId: account.peerId,
                text: text,
                attributes: [],
                media: []
            )
            let _ = transaction.addMessages([storeMessage], location: .Random)
        }.start()
    }
}
