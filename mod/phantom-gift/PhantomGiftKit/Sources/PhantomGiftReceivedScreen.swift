import Foundation
import SwiftSignalKit
import TelegramCore
import AccountContext
import UndoUI

/// Shows the reveal for an incoming "Фантом" gift link. Reuses the existing sticker
/// overlay UI (the same one used for e.g. "gift limit reached" toasts) instead of a
/// bespoke screen, and always labels the content as a phantom/cosmetic gift so it can
/// never be mistaken for a real StarGift receipt.
public enum PhantomGiftReceivedScreen {
    public static func present(context: AccountContext, payload: PhantomGiftPayload) {
        let _ = (context.engine.payments.cachedStarGifts()
        |> take(1)
        |> deliverOnMainQueue).start(next: { starGifts in
            guard let starGifts else {
                return
            }
            var matchedGift: StarGift.Gift?
            for starGift in starGifts {
                if case let .generic(gift) = starGift, gift.id == payload.giftId {
                    matchedGift = gift
                    break
                }
            }
            guard let gift = matchedGift else {
                return
            }

            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let title = gift.title ?? "Gift"
            let controller = UndoOverlayController(
                presentationData: presentationData,
                content: .sticker(
                    context: context,
                    file: gift.file,
                    loop: true,
                    title: "Фантом-подарок",
                    text: "«\(title)» от \(payload.senderName) — визуальный подарок, реальной передачи не было.",
                    undoText: nil,
                    customAction: nil
                ),
                action: { _ in return false }
            )
            context.sharedContext.presentGlobalController(controller, nil)
        })
    }
}
