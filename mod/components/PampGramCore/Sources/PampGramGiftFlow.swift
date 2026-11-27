import Foundation

/// Which of the gift-sending screen's two fake tabs (if any) a purchase flow was reached
/// through — threaded from `GiftOptionsScreen` down through `GiftStoreScreen`/`GiftViewScreen`
/// (collectible path) and `GiftSetupScreen` (catalog path) to the actual send/receive call.
/// A plain `Bool` stopped being enough once there were two different fakes instead of one:
/// "send" and "receive" aren't independent flags, they're mutually exclusive alternatives to
/// the real flow, which is exactly what an enum is for.
///
/// Note: unique-gift market (`buyStarGiftImpl`) and catalog gifts (`GiftSetupScreen`,
/// including 15⭐ «Мишка») are **always local** on this client (VisualGram-style), for
/// every flow except explicit «Подарок мне». Real `payments.getPaymentForm` /
/// `sendStarsForm` returns RPC 406 «Обновите Telegram» on unofficial api_id builds.
public enum PampGramGiftFlow: Equatable {
    /// Legacy / non-tab entry. Still bought locally — never hits Telegram payments.
    case real
    /// Local buy + message framed as this account bought and sent the gift.
    case sendFake
    /// Message framed as received from the other side — no balance spent;
    /// requires `fromHimGiftsEnabled`.
    case receiveFake
}
