import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import PromptUI
import UndoUI
import PampGramCore

private struct PampGramCallRow: Equatable {
    let messageId: MessageId
    let title: String
    let realDurationSeconds: Int32
    let realMissed: Bool
    let override: PampGramCallOverrideDisplay?

    static func ==(lhs: PampGramCallRow, rhs: PampGramCallRow) -> Bool {
        return lhs.messageId == rhs.messageId && lhs.title == rhs.title && lhs.realDurationSeconds == rhs.realDurationSeconds && lhs.realMissed == rhs.realMissed && lhs.override == rhs.override
    }
}

private struct PampGramCallOverrideDisplay: Equatable {
    let durationSeconds: Int32
    let showAsMissed: Bool
}

private func pampGramCallDurationLabel(seconds: Int32) -> String {
    if seconds < 60 {
        return "\(seconds) сек"
    }
    return "\(seconds / 60) мин"
}

private func pampGramCallStatusLabel(row: PampGramCallRow) -> String {
    if let override = row.override {
        let base = override.showAsMissed ? "Пропущенный" : pampGramCallDurationLabel(seconds: override.durationSeconds)
        return "\(base) (подмена)"
    }
    return row.realMissed ? "Пропущенный" : pampGramCallDurationLabel(seconds: row.realDurationSeconds)
}

private final class PampGramCallOverridesArguments {
    let editRow: (PampGramCallRow) -> Void

    init(editRow: @escaping (PampGramCallRow) -> Void) {
        self.editRow = editRow
    }
}

private enum PampGramCallOverridesEntry: ItemListNodeEntry {
    case aboutText(String)
    case callsHeader(String)
    case call(Int, PampGramCallRow)
    case callsEmpty(String)

    var section: ItemListSectionId {
        switch self {
        case .aboutText:
            return 0
        case .callsHeader, .call, .callsEmpty:
            return 1
        }
    }

    var stableId: Int64 {
        switch self {
        case .aboutText:
            return 0
        case .callsHeader:
            return 1
        case .callsEmpty:
            return 2
        case let .call(_, row):
            return 100 + Int64(row.messageId.id)
        }
    }

    static func ==(lhs: PampGramCallOverridesEntry, rhs: PampGramCallOverridesEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.aboutText(lhsText), .aboutText(rhsText)):
            return lhsText == rhsText
        case let (.callsHeader(lhsText), .callsHeader(rhsText)):
            return lhsText == rhsText
        case let (.callsEmpty(lhsText), .callsEmpty(rhsText)):
            return lhsText == rhsText
        case let (.call(lhsIndex, lhsRow), .call(rhsIndex, rhsRow)):
            return lhsIndex == rhsIndex && lhsRow == rhsRow
        default:
            return false
        }
    }

    static func <(lhs: PampGramCallOverridesEntry, rhs: PampGramCallOverridesEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramCallOverridesArguments
        switch self {
        case let .aboutText(text), let .callsEmpty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .callsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .call(_, row):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: row.title,
                label: pampGramCallStatusLabel(row: row),
                additionalDetailLabelColor: row.override != nil ? .constructive : .generic,
                sectionId: self.section,
                style: .blocks,
                action: {
                    arguments.editRow(row)
                }
            )
        }
    }
}

private func pampGramCallOverridesEntries(rows: [PampGramCallRow]) -> [PampGramCallOverridesEntry] {
    var entries: [PampGramCallOverridesEntry] = []

    entries.append(.aboutText("Меняет, как последние звонки выглядят в этом списке — только на этом устройстве, реальные звонки не трогает."))
    entries.append(.callsHeader("НЕДАВНИЕ ЗВОНКИ"))
    if rows.isEmpty {
        entries.append(.callsEmpty("Пока нет звонков."))
    } else {
        for (index, row) in rows.enumerated() {
            entries.append(.call(index, row))
        }
    }

    return entries
}

private func pampGramCallRowsSignal(context: AccountContext) -> Signal<[PampGramCallRow], NoError> {
    return context.engine.messages.callList(scope: .all, index: EngineMessage.Index.absoluteUpperBound(), itemCount: 50)
    |> map { list -> [PampGramCallRow] in
        var rows: [PampGramCallRow] = []
        for item in list.items {
            guard case let .message(message, _) = item else {
                continue
            }
            var realDuration: Int32 = 0
            var realMissed = false
            var isPhoneCall = false
            if let action = message.media.first(where: { $0 is TelegramMediaAction }) as? TelegramMediaAction {
                if case let .phoneCall(_, discardReason, duration, _) = action.action {
                    isPhoneCall = true
                    realDuration = duration ?? 0
                    if let discardReason, case .missed = discardReason {
                        realMissed = true
                    }
                }
            }
            guard isPhoneCall else {
                continue
            }
            var title = "Неизвестный собеседник"
            if let peer = message.peers[message.id.peerId] {
                title = EnginePeer(peer).compactDisplayTitle
            }
            var override: PampGramCallOverrideDisplay?
            if let attribute = message.attributes.first(where: { $0 is PampGramCallOverrideAttribute }) as? PampGramCallOverrideAttribute {
                override = PampGramCallOverrideDisplay(durationSeconds: attribute.durationSeconds, showAsMissed: attribute.showAsMissed)
            }
            rows.append(PampGramCallRow(messageId: message.id, title: title, realDurationSeconds: realDuration, realMissed: realMissed, override: override))
        }
        return rows
    }
}

private func pampGramApplyCallOverride(context: AccountContext, messageId: MessageId, override: PampGramCallOverrideDisplay?) {
    let _ = context.account.postbox.transaction { transaction -> Void in
        transaction.updateMessage(messageId, update: { message -> PostboxUpdateMessage in
            var attributes = message.attributes.filter { !($0 is PampGramCallOverrideAttribute) }
            if let override = override {
                attributes.append(PampGramCallOverrideAttribute(durationSeconds: override.durationSeconds, showAsMissed: override.showAsMissed))
            }
            let updatedMessage = StoreMessage(
                id: messageId,
                customStableId: nil,
                globallyUniqueId: message.globallyUniqueId,
                groupingKey: message.groupingKey,
                threadId: message.threadId,
                timestamp: message.timestamp,
                flags: StoreMessageFlags(message.flags),
                tags: message.tags,
                globalTags: message.globalTags,
                localTags: message.localTags,
                forwardInfo: message.forwardInfo.map(StoreMessageForwardInfo.init),
                authorId: message.author?.id,
                text: message.text,
                attributes: attributes,
                media: message.media
            )
            return .update(updatedMessage)
        })
    }.start()
}

/// "Звонки" (Дополнительно): a purely cosmetic, local override of how a specific past call
/// displays in the Calls tab — see the patch to `CallListCallItem.swift`, which reads
/// `PampGramCallOverrideAttribute` off the call's own message the same way "Изменить
/// визуально" already reads/writes a message's text.
public func pampGramCallOverridesController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?

    let arguments = PampGramCallOverridesArguments(
        editRow: { row in
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let sheet = ActionSheetController(presentationData: presentationData)
            var buttons: [ActionSheetItem] = [ActionSheetTextItem(title: row.title)]
            buttons.append(ActionSheetButtonItem(title: "Показать как обычный…", color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                presentControllerImpl?(promptController(
                    context: context,
                    text: "Длительность (сек)",
                    subtitle: nil,
                    value: "\(row.override?.durationSeconds ?? row.realDurationSeconds)",
                    placeholder: "60",
                    characterLimit: 6,
                    apply: { value in
                        guard let value = value, let seconds = Int32(value), seconds >= 0 else {
                            return
                        }
                        pampGramApplyCallOverride(context: context, messageId: row.messageId, override: PampGramCallOverrideDisplay(durationSeconds: seconds, showAsMissed: false))
                    }
                ))
            }))
            buttons.append(ActionSheetButtonItem(title: "Показать как пропущенный", color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                pampGramApplyCallOverride(context: context, messageId: row.messageId, override: PampGramCallOverrideDisplay(durationSeconds: 0, showAsMissed: true))
            }))
            if row.override != nil {
                buttons.append(ActionSheetButtonItem(title: "Сбросить (показывать как есть)", color: .destructive, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    pampGramApplyCallOverride(context: context, messageId: row.messageId, override: nil)
                }))
            }
            sheet.setItemGroups([
                ActionSheetItemGroup(items: buttons),
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                    })
                ])
            ])
            presentControllerImpl?(sheet)
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        pampGramCallRowsSignal(context: context)
    )
    |> deliverOnMainQueue
    |> map { presentationData, rows -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Звонки"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: pampGramCallOverridesEntries(rows: rows),
            style: .blocks,
            animateChanges: true
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}
