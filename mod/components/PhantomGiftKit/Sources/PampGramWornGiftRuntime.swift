import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import AccountContext
import PampGramCore

/// What `PampGramWornGiftRuntime` has done to this account's own emoji status, persisted so a
/// restart can still undo it: `appliedStatus` is the status it last wrote (so a later read can
/// tell "still our override" from "the server replaced it with the real one"), `realStatus` is
/// whatever was showing right before the first override landed, restored on "Снять".
private struct PampGramWornStatusRecord: Codable, Equatable {
    var realStatus: PeerEmojiStatus?
    var appliedStatus: PeerEmojiStatus?
}

/// Makes "Носить" on a visual gift actually do something: while a Phantom Gift is flagged
/// `worn`, this account's own peer record carries that gift as its emoji status, so the profile
/// name icon, the collectible profile backdrop/pattern and every other place Telegram draws
/// `peer.emojiStatus` pick it up exactly like a real worn gift. Local-only — the real
/// `account.updateEmojiStatus` call is never made.
///
/// The peer record is overwritten again whenever Telegram syncs the real user, so the whole
/// thing is a reconcile loop rather than a one-shot write: any change to the peer's status or to
/// the worn flag re-runs it, and it only writes when what's shown differs from what it should be.
public final class PampGramWornGiftRuntime {
    public static let shared = PampGramWornGiftRuntime()

    private let lock = NSLock()
    private var startedAccounts: Set<Int64> = []
    private var disposables: [Int64: Disposable] = [:]

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

        let selfPeerId = context.account.peerId
        let peerStatus = context.account.postbox.peerView(id: selfPeerId)
        |> map { view -> PeerEmojiStatus? in
            return (view.peers[selfPeerId] as? TelegramUser)?.emojiStatus
        }
        |> distinctUntilChanged

        let wornGift = PampGramPhantomGiftStore.wornGiftSignal(context: context)
        |> map { gift -> Int64? in
            return gift?.id
        }
        |> distinctUntilChanged

        // The values are only triggers: `reconcile` re-reads everything inside one transaction.
        // `mapToQueue` (not `mapToSignal`) so a second trigger waits for the first to finish
        // instead of cancelling it half-way.
        let disposable = (combineLatest(queue: Queue.mainQueue(), peerStatus, wornGift)
        |> mapToQueue { _, _ -> Signal<Never, NoError> in
            return PampGramWornGiftRuntime.reconcile(context: context)
        }).start()

        self.lock.lock()
        self.disposables[accountKey] = disposable
        self.lock.unlock()
    }

    private static func emojiStatus(for uniqueGift: StarGift.UniqueGift) -> (status: PeerEmojiStatus, files: [TelegramMediaFile])? {
        var file: TelegramMediaFile?
        var patternFile: TelegramMediaFile?
        var innerColor: Int32?
        var outerColor: Int32?
        var patternColor: Int32?
        var textColor: Int32?
        for attribute in uniqueGift.attributes {
            switch attribute {
            case let .model(_, fileValue, _, _):
                file = fileValue
            case let .pattern(_, patternFileValue, _):
                patternFile = patternFileValue
            case let .backdrop(_, _, innerColorValue, outerColorValue, patternColorValue, textColorValue, _):
                innerColor = innerColorValue
                outerColor = outerColorValue
                patternColor = patternColorValue
                textColor = textColorValue
            default:
                break
            }
        }
        guard let file, let patternFile, let innerColor, let outerColor, let patternColor, let textColor else {
            return nil
        }
        let status = PeerEmojiStatus(content: .starGift(id: uniqueGift.id, fileId: file.fileId.id, title: uniqueGift.title, slug: uniqueGift.slug, patternFileId: patternFile.fileId.id, innerColor: innerColor, outerColor: outerColor, patternColor: patternColor, textColor: textColor), expirationDate: nil)
        return (status, [file, patternFile])
    }

    private static func reconcile(context: AccountContext) -> Signal<Never, NoError> {
        let selfPeerId = context.account.peerId
        return context.account.postbox.transaction { transaction -> Void in
            guard let user = transaction.getPeer(selfPeerId) as? TelegramUser else {
                return
            }
            let current = user.emojiStatus
            let record = transaction.getPreferencesEntry(key: PampGramPreferencesKeys.wornGiftStatus)?.get(PampGramWornStatusRecord.self) ?? PampGramWornStatusRecord(realStatus: nil, appliedStatus: nil)
            var newRecord = record

            let wornGift = PampGramPhantomGiftStore.allGifts(transaction: transaction).first(where: { $0.peerId == selfPeerId && $0.worn && $0.soldDate == nil })
            var desired: (status: PeerEmojiStatus, files: [TelegramMediaFile])?
            if let wornGift, case let .unique(uniqueGift) = wornGift.gift {
                desired = PampGramWornGiftRuntime.emojiStatus(for: uniqueGift)
            }

            if let desired {
                if current != desired.status {
                    // Whatever is showing now and isn't the status we wrote last time came from
                    // the server — remember it, that's what "Снять" has to bring back.
                    if current != record.appliedStatus {
                        newRecord.realStatus = current
                    }
                    for file in desired.files {
                        transaction.storeMediaIfNotPresent(media: file)
                    }
                    updatePeersCustom(transaction: transaction, peers: [user.withUpdatedEmojiStatus(desired.status)], update: { _, updated in
                        return updated
                    })
                }
                newRecord.appliedStatus = desired.status
            } else if let applied = record.appliedStatus {
                // Nothing is worn any more. Only put the old status back if our override is still
                // what's showing — if a server sync already replaced it, that's the real one.
                if current == applied {
                    updatePeersCustom(transaction: transaction, peers: [user.withUpdatedEmojiStatus(record.realStatus)], update: { _, updated in
                        return updated
                    })
                }
                newRecord = PampGramWornStatusRecord(realStatus: nil, appliedStatus: nil)
            }

            if newRecord != record {
                transaction.updatePreferencesEntry(key: PampGramPreferencesKeys.wornGiftStatus, { _ in
                    return PreferencesEntry(newRecord)
                })
            }
        }
        |> ignoreValues
    }
}
