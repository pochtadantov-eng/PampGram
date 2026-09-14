import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import AccountContext

/// Bulk-converts REAL, ordinary (non-unique/NFT — those can't be converted at all) gifts in
/// this account's own profile back into real Stars, using the exact same `convertStarGift` API
/// call GiftViewScreen's own "Обменять на N звёзд" button makes for one gift at a time. Nothing
/// here is fake or local-only: every scanned gift, every conversion, and every Star credited is
/// real — this only automates pressing that same real button across many gifts at once, gated
/// to a chosen price range so a valuable NFT never gets caught in a sweep.
public struct PampGramGiftSaleSummary {
    public let sold: Int
    public let totalStars: Int64
    public let skipped: Int
}

public enum PampGramRealGiftTools {
    /// Real Telegram only allows converting a gift within a window after it was received
    /// (`GiftConfiguration.convertToStarsPeriod` in GiftViewScreen.swift, itself private to
    /// that file) — 90 days by default. Mirrored here so gifts past their window are skipped
    /// up front instead of failing the real API call one at a time.
    private static let convertToStarsPeriod: Int32 = 90 * 24 * 60 * 60

    /// Scans every gift on this account's own profile (paginating until the server reports no
    /// more), keeps only real, still-convertible, non-unique gifts whose catalog price falls in
    /// `priceRange`, then converts them to Stars one at a time — never in parallel, so a run of
    /// many gifts reads as the same steady sequence of taps a person would make by hand, not a
    /// burst that could trip a rate limit. `progress` is called before each conversion attempt
    /// with (current, total); `completion` fires once with the final tally.
    public static func sellRegularGifts(context: AccountContext, priceRange: ClosedRange<Int64>, progress: @escaping (Int, Int) -> Void, completion: @escaping (PampGramGiftSaleSummary) -> Void) {
        let giftsContext = ProfileGiftsContext(account: context.account, peerId: context.account.peerId)
        var disposable: Disposable?
        disposable = (giftsContext.state
        |> deliverOnMainQueue).start(next: { state in
            switch state.dataState {
            case .loading:
                break
            case let .ready(canLoadMore, _):
                if canLoadMore {
                    giftsContext.loadMore()
                    return
                }
                disposable?.dispose()

                let currentTime = Int32(Date().timeIntervalSince1970)
                let eligible = state.gifts.filter { gift -> Bool in
                    guard case let .generic(genericGift) = gift.gift else {
                        // .unique is an NFT — never convertible, always left alone.
                        return false
                    }
                    guard gift.reference != nil, gift.convertStars != nil else {
                        return false
                    }
                    guard priceRange.contains(genericGift.price) else {
                        return false
                    }
                    guard gift.date + self.convertToStarsPeriod >= currentTime else {
                        return false
                    }
                    return true
                }

                self.convertNext(context: context, gifts: eligible, index: 0, sold: 0, totalStars: 0, progress: progress, completion: completion)
            }
        })
        giftsContext.loadMore()
    }

    private static func convertNext(context: AccountContext, gifts: [ProfileGiftsContext.State.StarGift], index: Int, sold: Int, totalStars: Int64, progress: @escaping (Int, Int) -> Void, completion: @escaping (PampGramGiftSaleSummary) -> Void) {
        if index >= gifts.count {
            completion(PampGramGiftSaleSummary(sold: sold, totalStars: totalStars, skipped: gifts.count - sold))
            return
        }
        guard let reference = gifts[index].reference, let convertStars = gifts[index].convertStars else {
            self.convertNext(context: context, gifts: gifts, index: index + 1, sold: sold, totalStars: totalStars, progress: progress, completion: completion)
            return
        }
        progress(index + 1, gifts.count)
        let _ = (context.engine.payments.convertStarGift(reference: reference)
        |> deliverOnMainQueue).start(completed: {
            self.convertNext(context: context, gifts: gifts, index: index + 1, sold: sold + 1, totalStars: totalStars + convertStars, progress: progress, completion: completion)
        })
    }
}
