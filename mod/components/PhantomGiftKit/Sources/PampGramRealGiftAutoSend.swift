import Foundation
import TelegramCore
import SwiftSignalKit
import AccountContext

/// Real, not-fake, automated gift sending: buys and sends two ordinary (non-unique) real gifts
/// priced at exactly 15 Stars each — the "Teddy Bear" starter gift — to a real peer, using this
/// account's real Stars balance. Nothing here is a Phantom Gift: every call goes through the
/// same public engine API the real gift-catalog screen (GiftSetupScreen.swift) uses for its own
/// "buy and send" button — `fetchBotPaymentForm` then `sendStarsPaymentForm` — so the spend, the
/// gift, and the recipient are all as real as tapping through that screen by hand twice in a
/// row. What's automated is only the tapping: picking the 15-Star gift out of the catalog,
/// filling in the recipient, and repeating it a second time.
public enum PampGramRealGiftAutoSendError {
    /// No catalog gift is currently priced at exactly 15 Stars (price changed, or the catalog
    /// hasn't loaded at all yet).
    case giftUnavailable
    /// `fetchBotPaymentForm`/`sendStarsPaymentForm` failed — most commonly an insufficient real
    /// Stars balance, but covers any other real rejection (out of stock, disallowed, etc.) too.
    case purchaseFailed
}

public enum PampGramRealGiftAutoSend {
    private static let targetPriceStars: Int64 = 15
    private static let giftCount = 2

    /// Finds the catalog's current 15-Star gift, then buys and sends it to `peerId` twice in a
    /// row (sequentially, never in parallel — same one-purchase-at-a-time posture as
    /// `PampGramRealGiftTools.sellRegularGifts`). `completion` fires once, on the main queue,
    /// with the final outcome; a failure partway through (e.g. balance ran out after the first
    /// gift) is reported honestly rather than pretending both went through.
    public static func sendTwoBears(context: AccountContext, peerId: EnginePeer.Id, completion: @escaping (Result<Void, PampGramRealGiftAutoSendError>) -> Void) {
        let refreshDisposable = MetaDisposable()
        refreshDisposable.set(context.engine.payments.keepStarGiftsUpdated().start())

        let _ = (context.engine.payments.cachedStarGifts()
        |> filter { $0 != nil }
        |> take(1)
        |> deliverOnMainQueue).start(next: { gifts in
            refreshDisposable.dispose()

            guard let match = (gifts ?? []).first(where: { starGift in
                guard case let .generic(gift) = starGift, gift.price == targetPriceStars else {
                    return false
                }
                if gift.soldOut != nil {
                    return false
                }
                if let availability = gift.availability, availability.remains <= 0 {
                    return false
                }
                return true
            }), case let .generic(bear) = match else {
                completion(.failure(.giftUnavailable))
                return
            }

            self.sendOne(context: context, peerId: peerId, giftId: bear.id, remaining: giftCount, completion: completion)
        })
    }

    private static func sendOne(context: AccountContext, peerId: EnginePeer.Id, giftId: Int64, remaining: Int, completion: @escaping (Result<Void, PampGramRealGiftAutoSendError>) -> Void) {
        if remaining <= 0 {
            completion(.success(()))
            return
        }

        // Same invoice source, reused for both the form fetch and the actual charge — exactly
        // what BotCheckoutController.InputData.fetch + its caller's sendStarsPaymentForm call
        // do for a real "Подарок" catalog purchase (see GiftSetupScreen.swift).
        let source: BotPaymentInvoiceSource = .starGift(hideName: false, includeUpgrade: false, peerId: peerId, giftId: giftId, text: nil, entities: nil)

        let _ = (context.engine.payments.fetchBotPaymentForm(source: source, themeParams: nil)
        |> mapError { _ -> PampGramRealGiftAutoSendError in
            return .purchaseFailed
        }
        |> mapToSignal { form -> Signal<Void, PampGramRealGiftAutoSendError> in
            return context.engine.payments.sendStarsPaymentForm(formId: form.id, source: source)
            |> mapError { _ -> PampGramRealGiftAutoSendError in
                return .purchaseFailed
            }
            |> map { _ in () }
        }
        |> deliverOnMainQueue).start(next: {
            self.sendOne(context: context, peerId: peerId, giftId: giftId, remaining: remaining - 1, completion: completion)
        }, error: { error in
            completion(.failure(error))
        })
    }
}
