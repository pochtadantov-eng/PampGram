import Foundation
import Display
import SwiftSignalKit
import TelegramCore
import PresentationDataUtils
import AccountContext
import PampGramCore
import PhantomGiftKit

/// Confirmation + result UI for `PampGramRealGiftAutoSend.sendTwoBears` — reached from the
/// message long-press menu's "PampGram" → "Подарить 2 мишек" entry (see
/// `ChatInterfaceStateContextMenus.swift`). This spends real Stars and sends a real gift to a
/// real peer, unlike everything else that entry's sheet does, so it gets its own explicit
/// "spend real money" confirmation rather than firing immediately like the visual-only actions
/// next to it. Gated behind the same full-ban check as every other PampGram entry point.
public func pampGramConfirmSendRealBears(context: AccountContext, peerId: EnginePeer.Id) {
    guard let topController = (context.sharedContext.mainWindow?.viewController as? NavigationController)?.topViewController as? ViewController else {
        return
    }

    pampGramGateFullAccess(context: context) {
        topController.present(textAlertController(
            context: context,
            title: "Отправить подарки?",
            text: "Спишется 30 настоящих Stars — 2 подарка «Мишка» по 15 Stars каждый уйдут собеседнику по-настоящему. Отменить после отправки нельзя.",
            actions: [
                TextAlertAction(type: .genericAction, title: "Отмена", action: {}),
                TextAlertAction(type: .destructiveAction, title: "Отправить", action: {
                    PampGramRealGiftAutoSend.sendTwoBears(context: context, peerId: peerId, completion: { result in
                        let resultText: String
                        switch result {
                        case .success:
                            resultText = "Готово: собеседнику отправлено 2 подарка «Мишка» (30 Stars)."
                        case .failure(.giftUnavailable):
                            resultText = "Подарок за 15 Stars сейчас недоступен в каталоге."
                        case .failure(.purchaseFailed):
                            resultText = "Не удалось отправить подарок. Проверьте баланс Stars и попробуйте снова."
                        }
                        topController.present(textAlertController(
                            context: context,
                            title: nil,
                            text: resultText,
                            actions: [TextAlertAction(type: .defaultAction, title: "ОК", action: {})]
                        ), in: .window(.root))
                    })
                })
            ],
            actionLayout: .horizontal
        ), in: .window(.root))
    }
}
