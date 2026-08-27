import Foundation
import SwiftSignalKit
import TelegramCore
import AccountContext
import UndoUI

/// Shows the reveal for an incoming "Фантом" gift link (tapping the 🎁 in the message
/// text). Reuses the existing sticker overlay UI instead of a bespoke screen, and always
/// labels the content as a phantom/cosmetic gift so it can never be mistaken for a real
/// StarGift receipt. The persistent gift-card bubble itself (matching the real send-gift
/// look) is rendered separately, synthesized locally in ChatMessageBubbleItemNode.
public enum PhantomGiftReceivedScreen {
    public static func present(context: AccountContext, payload: PhantomGiftPayload) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let title = payload.gift.title ?? "Gift"
        let controller = UndoOverlayController(
            presentationData: presentationData,
            content: .sticker(
                context: context,
                file: payload.gift.file,
                loop: true,
                title: "Фантом-подарок",
                text: "«\(title)» от \(payload.senderName) — визуальный подарок, реальной передачи не было.",
                undoText: nil,
                customAction: nil
            ),
            action: { _ in return false }
        )
        context.sharedContext.presentGlobalController(controller, nil)
    }
}
