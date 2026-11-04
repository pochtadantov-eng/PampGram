import Foundation
import UIKit
import Display
import AccountContext
import TelegramCore
import TelegramPresentationData
import Postbox
import SwiftSignalKit
import PromptUI
import UndoUI
import PampGramCore

public func pampGramPresentMainMenu(context: AccountContext, peerId: EnginePeer.Id, peerName: String) {
    let _ = (PampGramCore.settingsSignal(postbox: context.account.postbox)
    |> take(1)
    |> deliverOnMainQueue).startStandalone(next: { settings in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        guard let topVC = (context.sharedContext.mainWindow?.viewController as? NavigationController)?.topViewController as? ViewController else { return }

        let sheet = ActionSheetController(presentationData: presentationData)
        var buttons: [ActionSheetItem] = [ActionSheetTextItem(title: "PampGram — Меню")]

        if settings.visualEditCallItemEnabled {
            buttons.append(ActionSheetButtonItem(title: "Показать звонок", color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                pampGramPresentInsertCall(context: context, peerId: peerId)
            }))
        }

        if settings.invisibleMessagesEnabled {
            buttons.append(ActionSheetButtonItem(title: "Невидимое сообщение 👻", color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                let invisible = PampGramInvisibleMessageRuntime.shared.generateInvisibleText(length: 1)
                let _ = enqueueMessages(account: context.account, peerId: peerId, messages: [.message(text: invisible, attributes: [], inlineStickers: [:], mediaReference: nil, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])]).startStandalone()
            }))
        }

        if settings.fakeIncomingCallEnabled {
            buttons.append(ActionSheetButtonItem(title: "Фейк звонок", color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                PampGramFakeIncomingCallRuntime.shared.triggerFakeCall(peerName: peerName, avatarImage: nil)
            }))
        }

        if settings.fakeTypingEnabled {
            let isActive = PampGramFakeActivityRuntime.shared.isActive(peerId: peerId)
            buttons.append(ActionSheetButtonItem(title: isActive ? "Стоп набор текста" : "Фейк печатает…", color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                if isActive {
                    PampGramFakeActivityRuntime.shared.stop(peerId: peerId)
                } else {
                    PampGramFakeActivityRuntime.shared.start(peerId: peerId, mode: .typing)
                }
            }))
        }

        if settings.fakeSystemMessagesEnabled {
            buttons.append(ActionSheetButtonItem(title: "Фейк системное", color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                pampGramPresentFakeSystemMessagePicker(context: context, peerId: peerId)
            }))
        }

        if settings.fakePaymentReceiptsEnabled {
            buttons.append(ActionSheetButtonItem(title: "Фейк чек", color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                pampGramPresentFakePaymentReceiptPicker(context: context, peerId: peerId)
            }))
        }

        if settings.fakeScreenshotNotificationEnabled && PampGramFakeScreenshotNotificationRuntime.shared.isSecretChat(peerId: peerId) {
            buttons.append(ActionSheetButtonItem(title: "Фейк скриншот", color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                PampGramFakeScreenshotNotificationRuntime.shared.sendFakeScreenshotNotification(peerId: peerId)
            }))
        }

        if buttons.count <= 1 {
            topVC.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: "Нет включённых функций. Включите в настройках PampGram → Чаты.", timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), in: .current)
            return
        }

        sheet.setItemGroups([
            ActionSheetItemGroup(items: buttons),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                })
            ])
        ])
        topVC.present(sheet, in: .window(.root))
    })
}

private func pampGramPresentFakeSystemMessagePicker(context: AccountContext, peerId: EnginePeer.Id) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    guard let topVC = (context.sharedContext.mainWindow?.viewController as? NavigationController)?.topViewController as? ViewController else { return }

    let sheet = ActionSheetController(presentationData: presentationData)
    var buttons: [ActionSheetItem] = [ActionSheetTextItem(title: "Тип системного сообщения")]
    for msgType in PampGramFakeSystemMessagesRuntime.SystemMessageType.allCases {
        buttons.append(ActionSheetButtonItem(title: msgType.displayText, color: .accent, action: { [weak sheet] in
            sheet?.dismissAnimated()
            PampGramFakeSystemMessagesRuntime.shared.insertSystemMessage(peerId: peerId, type: msgType)
        }))
    }
    buttons.append(ActionSheetButtonItem(title: "Свой текст…", color: .accent, action: { [weak sheet] in
        sheet?.dismissAnimated()
        topVC.present(promptController(context: context, text: "Системное сообщение", subtitle: "Текст, который увидит собеседник в сером поле", value: "", placeholder: "Аккаунт верифицирован", characterLimit: 256, apply: { text in
            guard let text = text, !text.isEmpty else { return }
            PampGramFakeSystemMessagesRuntime.shared.insertCustomSystemMessage(peerId: peerId, text: text)
        }), in: .window(.root))
    }))
    sheet.setItemGroups([
        ActionSheetItemGroup(items: buttons),
        ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                sheet?.dismissAnimated()
            })
        ])
    ])
    topVC.present(sheet, in: .window(.root))
}

private func pampGramPresentFakePaymentReceiptPicker(context: AccountContext, peerId: EnginePeer.Id) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    guard let topVC = (context.sharedContext.mainWindow?.viewController as? NavigationController)?.topViewController as? ViewController else { return }

    let sheet = ActionSheetController(presentationData: presentationData)
    var buttons: [ActionSheetItem] = [ActionSheetTextItem(title: "Тип чека")]
    buttons.append(ActionSheetButtonItem(title: "Stars перевод", color: .accent, action: { [weak sheet] in
        sheet?.dismissAnimated()
        topVC.present(promptController(context: context, text: "Сумма Stars", subtitle: "", value: "1000", placeholder: "1000", characterLimit: 12, apply: { val in
            guard let val = val, let amount = Int64(val) else { return }
            PampGramFakePaymentReceiptRuntime.shared.generateReceipt(peerId: peerId, type: .starsTransfer(amount: amount))
        }), in: .window(.root))
    }))
    buttons.append(ActionSheetButtonItem(title: "TON перевод", color: .accent, action: { [weak sheet] in
        sheet?.dismissAnimated()
        topVC.present(promptController(context: context, text: "Сумма TON", subtitle: "", value: "10", placeholder: "10", characterLimit: 12, apply: { val in
            guard let val = val, let amount = Double(val) else { return }
            PampGramFakePaymentReceiptRuntime.shared.generateReceipt(peerId: peerId, type: .tonTransfer(amount: amount))
        }), in: .window(.root))
    }))
    buttons.append(ActionSheetButtonItem(title: "Premium подарок", color: .accent, action: { [weak sheet] in
        sheet?.dismissAnimated()
        PampGramFakePaymentReceiptRuntime.shared.generateReceipt(peerId: peerId, type: .premiumGift(months: 12))
    }))
    sheet.setItemGroups([
        ActionSheetItemGroup(items: buttons),
        ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                sheet?.dismissAnimated()
            })
        ])
    ])
    topVC.present(sheet, in: .window(.root))
}
