import Foundation

/// Which of the gift-sending screen's two fake tabs (if any) a purchase flow was reached
/// through — threaded from `GiftOptionsScreen` down through `GiftStoreScreen`/`GiftViewScreen`
/// (collectible path) and `GiftSetupScreen` (catalog path) to the actual send/receive call.
/// A plain `Bool` stopped being enough once there were two different fakes instead of one:
/// "send" and "receive" aren't independent flags, they're mutually exclusive alternatives to
/// the real flow, which is exactly what an enum is for.
public enum PampGramGiftFlow: Equatable {
    /// The real market: purchase spends real Stars/TON through the real Telegram API.
    case real
    /// "Подарок ему": the same real market, but the purchase is a local-only fake — deducts
    /// PampGram's own play-money balance and inserts a real-looking message as if this
    /// account bought and sent the gift.
    case sendFake
    /// "Подарок мне": the same real market, but the resulting message is inserted as if the
    /// *other* side bought and sent the gift to this account — no balance is touched at all,
    /// since nothing was "spent" by anyone.
    case receiveFake
}
