import Foundation

/// Which of the gift-sending screen's two fake tabs (if any) a purchase flow was reached
/// through — threaded from `GiftOptionsScreen` down through `GiftStoreScreen`/`GiftViewScreen`
/// (collectible path) and `GiftSetupScreen` (catalog path) to the actual send/receive call.
/// A plain `Bool` stopped being enough once there were two different fakes instead of one:
/// "send" and "receive" aren't independent flags, they're mutually exclusive alternatives to
/// the real flow, which is exactly what an enum is for.
///
/// Note: unique-gift marketplace buy via `buyStarGiftImpl` is **always local** on this
/// client (same approach as VisualGram's `buyGift`), for every flow except explicit
/// «Подарок мне». Real `payments.getPaymentForm` / `sendStarsForm` returns RPC 406
/// «Обновите Telegram» on unofficial api_id builds — toggles cannot fix that.
public enum PampGramGiftFlow: Equatable {
    /// Market entry without a fake-tab override. Still bought locally in `buyStarGiftImpl`
    /// (no Telegram payments RPC) — only the message framing differs from `.sendFake`.
    case real
    /// "Подарок ему": local buy + message framed as this account bought and sent the gift.
    case sendFake
    /// "Подарок мне": message framed as received from the other side — no balance spent;
    /// requires `fromHimGiftsEnabled`.
    case receiveFake
}
