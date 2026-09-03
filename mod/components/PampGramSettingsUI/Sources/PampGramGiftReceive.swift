import Foundation
import SwiftSignalKit
import TelegramCore
import AccountContext
import PhantomGiftKit

/// Thin bridge so TelegramUI's message context menu (which already imports PampGramSettingsUI,
/// but not PhantomGiftKit) can detect and receive a PampGram gift carried in a message without
/// taking a direct dependency on PhantomGiftKit.

/// Whether a message's text carries a PampGram gift-transfer payload.
public func pampGramMessageCarriesGift(_ text: String) -> Bool {
    return PampGramPhantomGiftManager.transferToken(inText: text) != nil
}

/// Materializes the gift carried in `messageText` into the current account's own collection.
/// Returns true on success.
public func pampGramReceiveGift(context: AccountContext, messageText: String, fromPeerId: EnginePeer.Id) -> Signal<Bool, NoError> {
    guard let token = PampGramPhantomGiftManager.transferToken(inText: messageText) else {
        return .single(false)
    }
    return PampGramPhantomGiftManager.materializeReceivedGift(context: context, token: token, fromPeerId: fromPeerId)
}
