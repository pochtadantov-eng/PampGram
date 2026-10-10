import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit

/// Personal bridge to the owner's casino bot. When a gift is withdrawn in the bot, the bot
/// (server side, only for the owner's Telegram id) queues it instead of sending a real one;
/// this polls that queue and draws each gift locally, as an incoming gift card from the bot —
/// the same local-only path as "От него" (`PampGramPhantomGiftManager.receiveGenericGift`).
/// Nothing is sent through Telegram and nothing is bought.
///
/// The server answers 403 unless the shared token matches AND this account's id is on its
/// `VISUAL_GIFT_USER_IDS` list, so a copy of the app on anyone else's account stays inert.
public enum PampGramCasinoBridge {
    /// Public URL of the casino server, e.g. "https://casino.example.com". Empty = bridge off.
    /// Fill in locally before building; do not commit real values.
    private static let baseURL = ""
    /// Same value as the server's `VISUAL_GIFT_TOKEN`. Empty = bridge off.
    private static let token = ""

    private static let pollInterval: Double = 15.0
    // main queue only
    private static var inFlight = Set<Int64>()
    private static let disposables = DisposableSet()

    private struct Pending: Decodable {
        struct Item: Decodable {
            let id: Int64
            let giftId: String
        }
        let botId: Int64
        let gifts: [Item]
    }

    public static func start(account: Account) -> Disposable {
        guard !baseURL.isEmpty, !token.isEmpty else {
            return EmptyDisposable
        }
        let userId = account.peerId.toInt64()
        let timer = SwiftSignalKit.Timer(timeout: pollInterval, repeat: true, completion: {
            poll(account: account, userId: userId)
        }, queue: Queue.mainQueue())
        timer.start()
        Queue.mainQueue().async {
            poll(account: account, userId: userId)
        }
        return ActionDisposable {
            timer.invalidate()
        }
    }

    private static func poll(account: Account, userId: Int64) {
        guard let url = URL(string: "\(baseURL)/visual/pending?uid=\(userId)&token=\(token)") else {
            return
        }
        URLSession.shared.dataTask(with: url) { data, response, _ in
            guard let data, (response as? HTTPURLResponse)?.statusCode == 200, let pending = try? JSONDecoder().decode(Pending.self, from: data), !pending.gifts.isEmpty else {
                return
            }
            Queue.mainQueue().async {
                for item in pending.gifts where !inFlight.contains(item.id) {
                    inFlight.insert(item.id)
                    deliver(account: account, userId: userId, botId: pending.botId, item: item)
                }
            }
        }.resume()
    }

    private static func deliver(account: Account, userId: Int64, botId: Int64, item: Pending.Item) {
        guard let giftId = Int64(item.giftId) else {
            return
        }
        let botPeerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(botId))
        let signal = TelegramEngine(account: account).payments.cachedStarGifts()
        |> take(1)
        |> mapToSignal { gifts -> Signal<Never, NoError> in
            guard let gifts, let gift = gifts.compactMap({ entry -> StarGift.Gift? in
                if case let .generic(gift) = entry, gift.id == giftId {
                    return gift
                }
                return nil
            }).first else {
                // Catalog not loaded yet (or the gift left it): try again on the next poll.
                return .complete()
            }
            return PampGramPhantomGiftManager.receiveGenericGift(postbox: account.postbox, peerId: botPeerId, gift: gift)
            |> then(Signal<Never, NoError> { subscriber in
                acknowledge(userId: userId, ids: [item.id])
                subscriber.putCompletion()
                return EmptyDisposable
            })
        }
        |> deliverOnMainQueue
        disposables.add(signal.start(completed: {
            inFlight.remove(item.id)
        }))
    }

    private static func acknowledge(userId: Int64, ids: [Int64]) {
        let list = ids.map { String($0) }.joined(separator: ",")
        guard let url = URL(string: "\(baseURL)/visual/ack?uid=\(userId)&token=\(token)&ids=\(list)") else {
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        URLSession.shared.dataTask(with: request).resume()
    }
}
