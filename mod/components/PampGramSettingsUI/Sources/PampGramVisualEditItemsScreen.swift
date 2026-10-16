import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import PampGramCore

private final class PampGramVisualEditItemsArguments {
    let toggle: (WritableKeyPath<PampGramSettings, Bool>) -> (Bool) -> Void

    init(toggle: @escaping (WritableKeyPath<PampGramSettings, Bool>) -> (Bool) -> Void) {
        self.toggle = toggle
    }
}

private enum PampGramVisualEditItemsEntry: ItemListNodeEntry {
    case aboutText(String)
    case item(Int32, String, Bool, WritableKeyPath<PampGramSettings, Bool>)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case .aboutText:
            return 0
        case let .item(index, _, _, _):
            return 1 + index
        }
    }

    static func ==(lhs: PampGramVisualEditItemsEntry, rhs: PampGramVisualEditItemsEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.aboutText(lhsText), .aboutText(rhsText)):
            return lhsText == rhsText
        case let (.item(lhsIndex, lhsTitle, lhsValue, lhsKeyPath), .item(rhsIndex, rhsTitle, rhsValue, rhsKeyPath)):
            return lhsIndex == rhsIndex && lhsTitle == rhsTitle && lhsValue == rhsValue && lhsKeyPath == rhsKeyPath
        default:
            return false
        }
    }

    static func <(lhs: PampGramVisualEditItemsEntry, rhs: PampGramVisualEditItemsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramVisualEditItemsArguments
        switch self {
        case let .aboutText(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .item(_, title, value, keyPath):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: arguments.toggle(keyPath))
        }
    }
}

/// Every individual row the "PampGram" long-press menu can show, paired with the
/// `PampGramSettings` field that gates it — kept as one array so both the entries builder and
/// `pampGramVisualEditItemsController` share a single source of truth for "which items exist".
private let pampGramVisualEditItems: [(title: String, keyPath: WritableKeyPath<PampGramSettings, Bool>)] = [
    ("Изменить текст", \.visualEditTextItemEnabled),
    ("Отправить фото", \.visualEditPhotoItemEnabled),
    ("Отправить голосовое", \.visualEditVoiceItemEnabled),
    ("Отправить файл", \.visualEditFileItemEnabled),
    ("Показать звонок", \.visualEditCallItemEnabled),
    ("Подарить Premium", \.visualEditPremiumGiftItemEnabled),
    ("Поставить реакцию", \.visualEditReactionItemEnabled),
    ("Сохранить одноразовое", \.visualEditSaveOneTimeItemEnabled),
    ("Визуальное фото в канал", \.visualEditChannelPhotoItemEnabled),
    ("Подарить 2 мишек", \.visualEditRealBearsItemEnabled),
]

private func pampGramVisualEditItemsEntries(settings: PampGramSettings) -> [PampGramVisualEditItemsEntry] {
    var entries: [PampGramVisualEditItemsEntry] = []
    entries.append(.aboutText("Выключенные пункты просто не показываются в меню «PampGram» при зажатии сообщения — остальные работают как раньше."))
    for (index, entry) in pampGramVisualEditItems.enumerated() {
        entries.append(.item(Int32(index), entry.title, settings[keyPath: entry.keyPath], entry.keyPath))
    }
    return entries
}

/// "Изменить визуально" → "Настроить пункты" (Чаты): lets each row of the "PampGram" long-press
/// menu be hidden independently, instead of the single master "Изменить визуально" toggle being
/// the only way to turn any of it off.
public func pampGramVisualEditItemsController(context: AccountContext) -> ViewController {
    let arguments = PampGramVisualEditItemsArguments(toggle: { keyPath in
        return { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings[keyPath: keyPath] = value
                return settings
            }).start()
        }
    })

    let signal = combineLatest(
        context.sharedContext.presentationData,
        PampGramCore.settingsSignal(postbox: context.account.postbox)
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Пункты меню"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: pampGramVisualEditItemsEntries(settings: settings),
            style: .blocks,
            animateChanges: true
        )
        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
