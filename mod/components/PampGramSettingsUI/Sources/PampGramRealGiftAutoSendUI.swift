import Foundation
import Display
import SwiftSignalKit
import TelegramCore
import PresentationDataUtils
import AccountContext
import PampGramCore
import PhantomGiftKit

/// Confirmation + result UI for sending two 15-Star «Мишка» gifts — reached from the
/// message long-press menu's "PampGram" → "Подарить 2 мишек" entry (see
/// `ChatInterfaceStateContextMenus.swift`).
///
/// With «Подарок ему» or local Stars display on, both gifts are visual (fake balance,
/// local messages) — same rule as the catalog gift screen. Only when visual is off does
/// this spend real Stars via `PampGramRealGiftAutoSend`.
public func pampGramConfirmSendRealBears(context: AccountContext, peerId: EnginePeer.Id) {
    guard let topController = (context.sharedContext.mainWindow?.viewController as? NavigationController)?.topViewController as? ViewController else {
        return
    }

    pampGramGateFullAccess(context: context) {
        let _ = (PampGramCore.settingsSignal(postbox: context.account.postbox)
        |> take(1)
        |> deliverOnMainQueue).start(next: { settings in
            let visual = settings.phantomGiftsEnabled || settings.fakeStarsDisplayEnabled
            if visual {
                pampGramConfirmSendVisualBears(context: context, peerId: peerId, topController: topController, settings: settings)
            } else {
                pampGramConfirmSendLiveBears(context: context, peerId: peerId, topController: topController)
            }
        })
    }
}

private func pampGramConfirmSendVisualBears(context: AccountContext, peerId: EnginePeer.Id, topController: ViewController, settings: PampGramSettings) {
    let need: Int64 = 30
    guard settings.fakeStarsBalance >= need else {
        topController.present(textAlertController(
            context: context,
            title: "Недостаточно звёзд",
            text: "У вас ⭐ \(settings.fakeStarsBalance), а нужно ⭐ \(need).",
            actions: [TextAlertAction(type: .defaultAction, title: "ОК", action: {})]
        ), in: .window(.root))
        return
    }

    topController.present(textAlertController(
        context: context,
        title: "Отправить подарки?",
        text: "Спишется 30 локальных Stars — 2 подарка «Мишка» по 15 появятся у собеседника визуально.",
        actions: [
            TextAlertAction(type: .genericAction, title: "Отмена", action: {}),
            TextAlertAction(type: .defaultAction, title: "Отправить", action: {
                pampGramSendTwoVisualBears(context: context, peerId: peerId, topController: topController)
            })
        ],
        actionLayout: .horizontal
    ), in: .window(.root))
}

private func pampGramSendTwoVisualBears(context: AccountContext, peerId: EnginePeer.Id, topController: ViewController) {
    let refreshDisposable = MetaDisposable()
    refreshDisposable.set(context.engine.payments.keepStarGiftsUpdated().start())

    let _ = (context.engine.payments.cachedStarGifts()
    |> filter { $0 != nil }
    |> take(1)
    |> deliverOnMainQueue).start(next: { gifts in
        refreshDisposable.dispose()

        guard let match = (gifts ?? []).first(where: { starGift in
            guard case let .generic(gift) = starGift, gift.price == 15 else {
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
            topController.present(textAlertController(
                context: context,
                title: nil,
                text: "Подарок за 15 Stars сейчас недоступен в каталоге.",
                actions: [TextAlertAction(type: .defaultAction, title: "ОК", action: {})]
            ), in: .window(.root))
            return
        }

        let first = PampGramPhantomGiftManager.sendGenericGift(context: context, peerId: peerId, gift: bear, starPrice: 15)
        let second = PampGramPhantomGiftManager.sendGenericGift(context: context, peerId: peerId, gift: bear, starPrice: 15)
        let _ = (first |> then(second) |> deliverOnMainQueue).start(completed: {
            topController.present(textAlertController(
                context: context,
                title: nil,
                text: "Готово: 2 визуальных подарка «Мишка» (30 локальных Stars).",
                actions: [TextAlertAction(type: .defaultAction, title: "ОК", action: {})]
            ), in: .window(.root))
        })
    })
}

private func pampGramConfirmSendLiveBears(context: AccountContext, peerId: EnginePeer.Id, topController: ViewController) {
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
