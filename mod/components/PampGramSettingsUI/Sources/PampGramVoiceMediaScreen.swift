import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import AccountContext
import PampGramCore

private final class PampGramVoiceMediaArguments {
    let toggleVoiceChanger: (Bool) -> Void
    let openVoicePreset: () -> Void
    let openUploadSpeed: () -> Void
    let openDownloadSpeed: () -> Void

    init(toggleVoiceChanger: @escaping (Bool) -> Void, openVoicePreset: @escaping () -> Void, openUploadSpeed: @escaping () -> Void, openDownloadSpeed: @escaping () -> Void) {
        self.toggleVoiceChanger = toggleVoiceChanger
        self.openVoicePreset = openVoicePreset
        self.openUploadSpeed = openUploadSpeed
        self.openDownloadSpeed = openDownloadSpeed
    }
}

private enum PampGramVoiceMediaSection: Int32 {
    case about
    case voice
    case transfer
}

private enum PampGramVoiceMediaEntry: ItemListNodeEntry {
    case about(String)
    case voiceHeader(String)
    case voiceToggle(String, Bool)
    case voicePreset(String, String)
    case voiceFooter(String)
    case transferHeader(String)
    case upload(String, String)
    case download(String, String)
    case transferFooter(String)

    var section: ItemListSectionId {
        switch self {
        case .about: return PampGramVoiceMediaSection.about.rawValue
        case .voiceHeader, .voiceToggle, .voicePreset, .voiceFooter: return PampGramVoiceMediaSection.voice.rawValue
        case .transferHeader, .upload, .download, .transferFooter: return PampGramVoiceMediaSection.transfer.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .about: return 0
        case .voiceHeader: return 1
        case .voiceToggle: return 2
        case .voicePreset: return 3
        case .voiceFooter: return 4
        case .transferHeader: return 5
        case .upload: return 6
        case .download: return 7
        case .transferFooter: return 8
        }
    }

    static func < (lhs: PampGramVoiceMediaEntry, rhs: PampGramVoiceMediaEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramVoiceMediaArguments
        switch self {
        case let .about(text), let .voiceFooter(text), let .transferFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .voiceHeader(text), let .transferHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .voiceToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: arguments.toggleVoiceChanger)
        case let .voicePreset(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, action: arguments.openVoicePreset)
        case let .upload(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, action: arguments.openUploadSpeed)
        case let .download(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, action: arguments.openDownloadSpeed)
        }
    }
}

private func pampGramVoiceMediaEntries(settings: PampGramSettings) -> [PampGramVoiceMediaEntry] {
    return [
        .about("Голосовые сообщения и параметры передачи медиа собраны в одном разделе."),
        .voiceHeader("ГОЛОСОВЫЕ СООБЩЕНИЯ"),
        .voiceToggle("Изменять голос в сообщениях", settings.voiceChangerMessagesEnabled),
        .voicePreset("Голос", settings.voicePreset.displayName),
        .voiceFooter("Эффект применяется к новым голосовым до отправки. Скорость записи остаётся обычной."),
        .transferHeader("ПЕРЕДАЧА МЕДИА"),
        .upload("Ускорение загрузки", settings.uploadSpeedMode.displayName),
        .download("Ускорение скачивания", settings.downloadSpeedMode.displayName),
        .transferFooter("Настраивает параллельность передачи файлов. Реальная скорость зависит от сети и серверов Telegram.")
    ]
}

private func pampGramVoiceMediaPresentSpeedPicker(context: AccountContext, present: (ViewController) -> Void, title: String, current: PampGramSpeedMode, apply: @escaping (PampGramSpeedMode) -> Void) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let sheet = ActionSheetController(presentationData: presentationData)
    var items: [ActionSheetItem] = [ActionSheetTextItem(title: title)]
    for mode in PampGramSpeedMode.allCases {
        items.append(ActionSheetButtonItem(title: mode == current ? "✓ \(mode.displayName)" : mode.displayName, color: .accent, action: { [weak sheet] in
            sheet?.dismissAnimated()
            apply(mode)
        }))
    }
    sheet.setItemGroups([
        ActionSheetItemGroup(items: items),
        ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in sheet?.dismissAnimated() })])
    ])
    present(sheet)
}

private func pampGramVoiceMediaPresentPresetPicker(context: AccountContext, present: (ViewController) -> Void, current: PampGramVoicePreset, apply: @escaping (PampGramVoicePreset) -> Void) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let sheet = ActionSheetController(presentationData: presentationData)
    var items: [ActionSheetItem] = [ActionSheetTextItem(title: "Голос")]
    for preset in PampGramVoicePreset.allCases {
        items.append(ActionSheetButtonItem(title: preset == current ? "✓ \(preset.displayName)" : preset.displayName, color: .accent, action: { [weak sheet] in
            sheet?.dismissAnimated()
            apply(preset)
        }))
    }
    sheet.setItemGroups([
        ActionSheetItemGroup(items: items),
        ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in sheet?.dismissAnimated() })])
    ])
    present(sheet)
}

public func pampGramVoiceMediaController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    var latestSettings = PampGramSettings.defaultSettings

    let update: (@escaping (inout PampGramSettings) -> Void) -> Void = { change in
        let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
            var settings = settings
            change(&settings)
            return settings
        }).start()
    }

    let arguments = PampGramVoiceMediaArguments(
        toggleVoiceChanger: { value in update { $0.voiceChangerMessagesEnabled = value } },
        openVoicePreset: {
            pampGramVoiceMediaPresentPresetPicker(context: context, present: { presentControllerImpl?($0) }, current: latestSettings.voicePreset, apply: { preset in
                update { $0.voicePreset = preset }
            })
        },
        openUploadSpeed: {
            pampGramVoiceMediaPresentSpeedPicker(context: context, present: { presentControllerImpl?($0) }, title: "Ускорение загрузки", current: latestSettings.uploadSpeedMode, apply: { mode in
                update { $0.uploadSpeedMode = mode }
            })
        },
        openDownloadSpeed: {
            pampGramVoiceMediaPresentSpeedPicker(context: context, present: { presentControllerImpl?($0) }, title: "Ускорение скачивания", current: latestSettings.downloadSpeedMode, apply: { mode in
                update { $0.downloadSpeedMode = mode }
            })
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, PampGramCore.settingsSignal(postbox: context.account.postbox))
    |> deliverOnMainQueue
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        latestSettings = settings
        return (
            ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Голос / Медиа"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false),
            (ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: pampGramVoiceMediaEntries(settings: settings), style: .blocks, animateChanges: true), arguments)
        )
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in controller?.present(c, in: .window(.root)) }
    return controller
}
