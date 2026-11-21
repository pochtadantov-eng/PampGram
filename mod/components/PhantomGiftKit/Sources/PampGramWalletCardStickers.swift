import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore
import AccountContext
import WalletContext
import PampGramCore

/// Local-only gift stickers on the Money / GRAM card: the same placements Telegram uses
/// (`WalletContext.CardSticker`), persisted in Postbox and never sent to the wallet API.
private struct PampGramCardStickersBlob: Codable, Equatable {
    var data: Data
}

public enum PampGramWalletCardStickers {
    /// Stable NFT address for a profile gift so card stickers survive restarts.
    public static func address(for unique: StarGift.UniqueGift) -> String {
        if let giftAddress = unique.giftAddress, !giftAddress.isEmpty {
            return giftAddress
        }
        return "pg:\(unique.slug)"
    }

    public static func collectible(from unique: StarGift.UniqueGift) -> WalletContext.Collectible {
        let address = self.address(for: unique)
        let nft = WalletNftItem(
            collectionAddress: nil,
            address: address,
            ownerAddress: "pampgram",
            index: "\(unique.number)",
            name: "\(unique.title) #\(unique.number)",
            description: nil,
            image: nil,
            imageSmall: nil,
            contentUrl: nil,
            lottie: nil,
            attributes: nil,
            extra: nil,
            gift: unique
        )
        return WalletContext.Collectible(nft: nft)
    }

    /// Unique gifts currently on the account owner's profile: real Telegram gifts plus local visual ones.
    public static func profileUniqueGiftsSignal(context: AccountContext) -> Signal<[StarGift.UniqueGift], NoError> {
        let real = ProfileGiftsContext(account: context.account, peerId: context.account.peerId, filter: [.unique, .displayed, .hidden]).state
        |> map { state -> [StarGift.UniqueGift] in
            var result: [StarGift.UniqueGift] = []
            var seen = Set<String>()
            for item in state.filteredGifts {
                if case let .unique(unique) = item.gift {
                    let key = unique.slug
                    if seen.insert(key).inserted {
                        result.append(unique)
                    }
                }
            }
            return result
        }
        let visual = PampGramPhantomGiftStore.resolvedProfileGiftsSignal(context: context)
        |> map { gifts -> [StarGift.UniqueGift] in
            var result: [StarGift.UniqueGift] = []
            var seen = Set<String>()
            for item in gifts {
                if case let .unique(unique) = item.gift {
                    let key = unique.slug
                    if seen.insert(key).inserted {
                        result.append(unique)
                    }
                }
            }
            return result
        }
        return combineLatest(real, visual)
        |> map { realGifts, visualGifts -> [StarGift.UniqueGift] in
            var result: [StarGift.UniqueGift] = []
            var seen = Set<String>()
            for unique in realGifts + visualGifts {
                if seen.insert(unique.slug).inserted {
                    result.append(unique)
                }
            }
            return result
        }
    }

    public static func profileCollectiblesSignal(context: AccountContext) -> Signal<[WalletContext.Collectible], NoError> {
        return self.profileUniqueGiftsSignal(context: context)
        |> map { gifts in
            gifts.map { self.collectible(from: $0) }
        }
    }

    public static func stickers(transaction: Transaction) -> [WalletContext.CardSticker] {
        guard let blob = transaction.getPreferencesEntry(key: PampGramPreferencesKeys.cardStickers)?.get(PampGramCardStickersBlob.self),
              let decoded = try? JSONDecoder().decode([WalletContext.CardSticker].self, from: blob.data) else {
            return []
        }
        return WalletContext.CardSticker.validated(decoded)
    }

    public static func signal(postbox: Postbox) -> Signal<[WalletContext.CardSticker], NoError> {
        return postbox.preferencesView(keys: [PampGramPreferencesKeys.cardStickers])
        |> map { view -> [WalletContext.CardSticker] in
            guard let blob = view.values[PampGramPreferencesKeys.cardStickers]?.get(PampGramCardStickersBlob.self),
                  let decoded = try? JSONDecoder().decode([WalletContext.CardSticker].self, from: blob.data) else {
                return []
            }
            return WalletContext.CardSticker.validated(decoded)
        }
        |> distinctUntilChanged
    }

    public static func setStickers(transaction: Transaction, stickers: [WalletContext.CardSticker]) {
        let validated = WalletContext.CardSticker.validated(stickers)
        let data = (try? JSONEncoder().encode(validated)) ?? Data()
        transaction.setPreferencesEntry(key: PampGramPreferencesKeys.cardStickers, value: PreferencesEntry(PampGramCardStickersBlob(data: data)))
    }
}

/// Synchronous mirror used by `WalletContext.pampGramApply` / sticker save hooks.
public final class PampGramWalletCardStickersRuntime {
    public static let shared = PampGramWalletCardStickersRuntime()

    private let lock = NSLock()
    private var collectiblesByAccount: [Int64: [WalletContext.Collectible]] = [:]
    private var stickersByAccount: [Int64: [WalletContext.CardSticker]] = [:]
    private var startedAccounts: Set<Int64> = []
    private var disposables: [Int64: Disposable] = [:]

    private init() {
    }

    public func start(context: AccountContext) {
        let accountKey = context.account.peerId.toInt64()
        self.lock.lock()
        if self.startedAccounts.contains(accountKey) {
            self.lock.unlock()
            return
        }
        self.startedAccounts.insert(accountKey)
        self.lock.unlock()

        let bag = DisposableSet()
        bag.add((PampGramWalletCardStickers.profileCollectiblesSignal(context: context)
        |> deliverOnMainQueue).start(next: { [weak self] items in
            guard let self else {
                return
            }
            self.lock.lock()
            self.collectiblesByAccount[accountKey] = items
            self.lock.unlock()
            WalletContext.pampGramNotifyVisualRefresh()
        }))
        bag.add((PampGramWalletCardStickers.signal(postbox: context.account.postbox)
        |> deliverOnMainQueue).start(next: { [weak self] stickers in
            guard let self else {
                return
            }
            self.lock.lock()
            self.stickersByAccount[accountKey] = stickers
            self.lock.unlock()
            WalletContext.pampGramNotifyVisualRefresh()
        }))
        // Seed stickers from Postbox once so the first Money open already has them.
        let _ = (context.account.postbox.transaction { transaction -> [WalletContext.CardSticker] in
            return PampGramWalletCardStickers.stickers(transaction: transaction)
        }
        |> deliverOnMainQueue).startStandalone(next: { [weak self] stickers in
            guard let self else {
                return
            }
            self.lock.lock()
            self.stickersByAccount[accountKey] = stickers
            self.lock.unlock()
            WalletContext.pampGramNotifyVisualRefresh()
        })

        self.lock.lock()
        self.disposables[accountKey] = bag
        self.lock.unlock()
    }

    public func collectibles(accountKey: Int64) -> [WalletContext.Collectible] {
        self.lock.lock()
        let result = self.collectiblesByAccount[accountKey] ?? []
        self.lock.unlock()
        return result
    }

    public func stickers(accountKey: Int64) -> [WalletContext.CardSticker] {
        self.lock.lock()
        let result = self.stickersByAccount[accountKey] ?? []
        self.lock.unlock()
        return result
    }

    public func setStickers(_ stickers: [WalletContext.CardSticker], accountKey: Int64, postbox: Postbox) {
        let validated = WalletContext.CardSticker.validated(stickers)
        self.lock.lock()
        self.stickersByAccount[accountKey] = validated
        self.lock.unlock()
        let _ = postbox.transaction { transaction in
            PampGramWalletCardStickers.setStickers(transaction: transaction, stickers: validated)
        }.startStandalone()
        WalletContext.pampGramNotifyVisualRefresh()
    }
}
