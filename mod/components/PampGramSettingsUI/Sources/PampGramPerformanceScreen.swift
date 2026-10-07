import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext

private final class PampGramPerformanceArguments {
    let toggleSmooth: (Bool) -> Void

    init(toggleSmooth: @escaping (Bool) -> Void) {
        self.toggleSmooth = toggleSmooth
    }
}

private enum PampGramPerformanceEntry: ItemListNodeEntry {
    case about(String)
    case smooth(Bool)
    case smoothFooter(String)

    var section: ItemListSectionId {
        switch self {
        case .about:
            return 0
        case .smooth, .smoothFooter:
            return 1
        }
    }

    var stableId: Int32 {
        switch self {
        case .about: return 0
        case .smooth: return 1
        case .smoothFooter: return 2
        }
    }

    static func <(lhs: PampGramPerformanceEntry, rhs: PampGramPerformanceEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramPerformanceArguments
        switch self {
        case let .about(text), let .smoothFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .smooth(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "bolt.batteryblock.fill", backgroundColor: UIColor(rgb: 0x34c759)), title: "Максимальная плавность", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleSmooth(value)
            })
        }
    }
}

/// Telegram's own power-saving mode ("Настройки → Энергосбережение"), switched to "всегда включено"
/// with one tap. It is what most reduces lag and battery use in the app, because the load comes from
/// drawing: looping stickers and emoji, autoplaying videos, translucent glass/blur everywhere and
/// background downloads — not from anything PampGram runs.
public func pampGramPerformanceController(context: AccountContext) -> ViewController {
    let arguments = PampGramPerformanceArguments(toggleSmooth: { value in
        let _ = updateMediaDownloadSettingsInteractively(accountManager: context.sharedContext.accountManager, { settings in
            var settings = settings
            if value {
                var energy = EnergyUsageSettings.powerSavingDefault
                // 96 and above is Telegram's own "always on".
                energy.activationThreshold = 96
                settings.energyUsageSettings = energy
            } else {
                settings.energyUsageSettings = EnergyUsageSettings.default
            }
            return settings
        }).start()
    })

    let signal = combineLatest(
        context.sharedContext.presentationData,
        context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.automaticMediaDownloadSettings])
    )
    |> deliverOnMainQueue
    |> map { presentationData, sharedData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let settings = sharedData.entries[ApplicationSpecificSharedDataKeys.automaticMediaDownloadSettings]?.get(MediaAutoDownloadSettings.self) ?? MediaAutoDownloadSettings.defaultSettings
        let isOn = settings.energyUsageSettings.activationThreshold >= 96

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Плавность и заряд"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let entries: [PampGramPerformanceEntry] = [
            .about("Если приложение тормозит или быстро разряжает телефон, почти всегда причина в анимации и эффектах: стикеры и эмодзи, которые крутятся без остановки, автозапуск видео, прозрачные «стеклянные» панели и загрузки в фоне. Один переключатель ниже отключает всё это."),
            .smooth(isOn),
            .smoothFooter("Включает режим энергосбережения Telegram «всегда»: стикеры и эмодзи не зацикливаются, видео и GIF не запускаются сами, прозрачность и размытие упрощаются, фоновые загрузки и работа в фоне отключаются. Всё работает как раньше, просто тише. Выключение возвращает обычные настройки. Тонкая настройка: Настройки → Энергосбережение.")
        ]
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks,
            animateChanges: false
        )
        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
