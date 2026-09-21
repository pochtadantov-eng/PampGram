import Foundation
import Display
import AccountContext
import PromptUI
import PampGramCore

/// A short "до 21.10, 14:32"-style label for a subscription's expiry. Shared between the
/// "Статус" badge and the redeem-key success tooltip so both read the date the same way.
func pampGramFormatSubscriptionExpiry(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return "до \(formatter.string(from: date))"
}

/// The "Активировать ключ" prompt-and-redeem flow, shared by `PampGramStatusScreen.swift` and
/// `PampGramPremiumScreen.swift` — same prompt copy, same API call, same success/failure
/// tooltip, so activating a key looks and behaves identically no matter which screen it was
/// opened from. `presentController`/`presentTooltip` let each caller decide how to present
/// (pushed `ItemListController` vs. a plain `UIViewController`); `onActivated` lets the caller
/// refresh its own displayed tier after a successful redeem.
func pampGramPresentRedeemKeyFlow(context: AccountContext, presentController: @escaping (ViewController) -> Void, presentTooltip: @escaping (String) -> Void, onActivated: ((PampGramSubscriptionStatus) -> Void)? = nil) {
    presentController(promptController(
        context: context,
        text: "Активировать ключ",
        subtitle: "Ключ, который тебе дали или продали — например, XXXX-XXXX-XXXX-XXXX",
        value: "",
        placeholder: "ключ",
        characterLimit: 64,
        apply: { value in
            guard let key = value?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
                return
            }
            let accountId = context.account.peerId.id._internalGetInt64Value()
            PampGramSubscriptionAPI.redeemKey(userId: accountId, key: key) { status in
                guard let status else {
                    presentTooltip("Ключ не подошёл — проверь, что он введён верно и ещё не использован.")
                    return
                }
                let durationText = status.expiresAt.map { " (\(pampGramFormatSubscriptionExpiry($0)))" } ?? ""
                presentTooltip("Активировано: тариф \(status.tier == .pro ? "PRO" : "STANDARD")\(durationText).")
                onActivated?(status)
            }
        }
    ))
}
