import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import PromptUI
import UndoUI
import PampGramCore

private final class PampGramAdditionalArguments {
    let toggleVoiceChanger: (Bool) -> Void
    let openVoicePreset: () -> Void
    let openUploadSpeed: () -> Void
    let openDownloadSpeed: () -> Void
    let openFakeLocation: () -> Void
    let openChatLock: () -> Void
    let openCallOverrides: () -> Void
    let openFakeAdmin: () -> Void
    let toggleInfinitePins: (Bool) -> Void
    let toggleLegalPremium: (Bool) -> Void
    let toggleScreenshotBypass: (Bool) -> Void
    let toggleScreenshotBlur: (Bool) -> Void
    let toggleCopyProtectionBypass: (Bool) -> Void
    let toggleAutoDeleteBypass: (Bool) -> Void
    let toggleBlockAds: (Bool) -> Void
    let redeemKey: () -> Void

    init(toggleVoiceChanger: @escaping (Bool) -> Void, openVoicePreset: @escaping () -> Void, openUploadSpeed: @escaping () -> Void, openDownloadSpeed: @escaping () -> Void, openFakeLocation: @escaping () -> Void, openChatLock: @escaping () -> Void, openCallOverrides: @escaping () -> Void, openFakeAdmin: @escaping () -> Void, toggleInfinitePins: @escaping (Bool) -> Void, toggleLegalPremium: @escaping (Bool) -> Void, toggleScreenshotBypass: @escaping (Bool) -> Void, toggleScreenshotBlur: @escaping (Bool) -> Void, toggleCopyProtectionBypass: @escaping (Bool) -> Void, toggleAutoDeleteBypass: @escaping (Bool) -> Void, toggleBlockAds: @escaping (Bool) -> Void, redeemKey: @escaping () -> Void) {
        self.toggleVoiceChanger = toggleVoiceChanger
        self.openVoicePreset = openVoicePreset
        self.openUploadSpeed = openUploadSpeed
        self.openDownloadSpeed = openDownloadSpeed
        self.openFakeLocation = openFakeLocation
        self.openChatLock = openChatLock
        self.openCallOverrides = openCallOverrides
        self.openFakeAdmin = openFakeAdmin
        self.toggleInfinitePins = toggleInfinitePins
        self.toggleLegalPremium = toggleLegalPremium
        self.toggleScreenshotBypass = toggleScreenshotBypass
        self.toggleScreenshotBlur = toggleScreenshotBlur
        self.toggleCopyProtectionBypass = toggleCopyProtectionBypass
        self.toggleAutoDeleteBypass = toggleAutoDeleteBypass
        self.toggleBlockAds = toggleBlockAds
        self.redeemKey = redeemKey
    }
}

private enum PampGramAdditionalSection: Int32 {
    case about
    case voice
    case speed
    case premium
    case telegram
    case keys
    case extras
}

private enum PampGramAdditionalEntry: ItemListNodeEntry {
    case aboutText(String)

    case voiceHeader(String)
    case voiceToggle(String, Bool)
    case voicePresetRow(String, String)
    case voiceFooter(String)

    case speedHeader(String)
    case uploadSpeedRow(String, String)
    case downloadSpeedRow(String, String)
    case speedFooter(String)

    case premiumHeader(String)
    case infinitePinsToggle(String, Bool)
    case legalPremiumToggle(String, Bool)
    case premiumFooter(String)

    case telegramHeader(String)
    case screenshotBypassToggle(String, Bool)
    case screenshotBlurToggle(String, Bool)
    case copyProtectionBypassToggle(String, Bool)
    case autoDeleteBypassToggle(String, Bool)
    case blockAdsToggle(String, Bool)
    case telegramFooter(String)

    case keysHeader(String)
    case redeemKeyAction(String)
    case keysFooter(String)

    case extrasHeader(String)
    case fakeLocationRow(String, String)
    case chatLockRow(String, String)
    case callOverridesRow(String)
    case fakeAdminRow(String)
    case extrasFooter(String)

    var section: ItemListSectionId {
        switch self {
        case .aboutText:
            return PampGramAdditionalSection.about.rawValue
        case .voiceHeader, .voiceToggle, .voicePresetRow, .voiceFooter:
            return PampGramAdditionalSection.voice.rawValue
        case .speedHeader, .uploadSpeedRow, .downloadSpeedRow, .speedFooter:
            return PampGramAdditionalSection.speed.rawValue
        case .premiumHeader, .infinitePinsToggle, .legalPremiumToggle, .premiumFooter:
            return PampGramAdditionalSection.premium.rawValue
        case .telegramHeader, .screenshotBypassToggle, .screenshotBlurToggle, .copyProtectionBypassToggle, .autoDeleteBypassToggle, .blockAdsToggle, .telegramFooter:
            return PampGramAdditionalSection.telegram.rawValue
        case .keysHeader, .redeemKeyAction, .keysFooter:
            return PampGramAdditionalSection.keys.rawValue
        case .extrasHeader, .fakeLocationRow, .chatLockRow, .callOverridesRow, .fakeAdminRow, .extrasFooter:
            return PampGramAdditionalSection.extras.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .aboutText:
            return 0
        case .voiceHeader:
            return 1
        case .voiceToggle:
            return 2
        case .voicePresetRow:
            return 3
        case .voiceFooter:
            return 4
        case .speedHeader:
            return 5
        case .uploadSpeedRow:
            return 6
        case .downloadSpeedRow:
            return 7
        case .speedFooter:
            return 8
        case .premiumHeader:
            return 9
        case .infinitePinsToggle:
            return 10
        case .legalPremiumToggle:
            return 11
        case .premiumFooter:
            return 12
        case .telegramHeader:
            return 13
        case .screenshotBypassToggle:
            return 14
        case .screenshotBlurToggle:
            return 15
        case .copyProtectionBypassToggle:
            return 16
        case .autoDeleteBypassToggle:
            return 17
        case .blockAdsToggle:
            return 18
        case .telegramFooter:
            return 19
        case .keysHeader:
            return 20
        case .redeemKeyAction:
            return 21
        case .keysFooter:
            return 22
        case .extrasHeader:
            return 23
        case .fakeLocationRow:
            return 24
        case .chatLockRow:
            return 25
        case .callOverridesRow:
            return 26
        case .fakeAdminRow:
            return 27
        case .extrasFooter:
            return 28
        }
    }

    static func <(lhs: PampGramAdditionalEntry, rhs: PampGramAdditionalEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramAdditionalArguments
        switch self {
        case let .aboutText(text), let .voiceFooter(text), let .speedFooter(text), let .premiumFooter(text), let .telegramFooter(text), let .keysFooter(text), let .extrasFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .voiceHeader(text), let .speedHeader(text), let .premiumHeader(text), let .telegramHeader(text), let .keysHeader(text), let .extrasHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .infinitePinsToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "infinity", backgroundColor: UIColor(rgb: 0x5856d6)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleInfinitePins(value)
            })
        case let .legalPremiumToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "star.circle.fill", backgroundColor: UIColor(rgb: 0xf5a623)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleLegalPremium(value)
            })
        case let .voiceToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleVoiceChanger(value)
            })
        case let .voicePresetRow(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openVoicePreset()
            })
        case let .uploadSpeedRow(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openUploadSpeed()
            })
        case let .downloadSpeedRow(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openDownloadSpeed()
            })
        case let .screenshotBypassToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "camera.viewfinder", backgroundColor: UIColor(rgb: 0x007aff)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleScreenshotBypass(value)
            })
        case let .screenshotBlurToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleScreenshotBlur(value)
            })
        case let .copyProtectionBypassToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "doc.on.doc.fill", backgroundColor: UIColor(rgb: 0x34c759)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleCopyProtectionBypass(value)
            })
        case let .autoDeleteBypassToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "clock.arrow.circlepath", backgroundColor: UIColor(rgb: 0xff9500)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleAutoDeleteBypass(value)
            })
        case let .blockAdsToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "eye.slash.circle.fill", backgroundColor: UIColor(rgb: 0xff3b30)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleBlockAds(value)
            })
        case let .redeemKeyAction(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.redeemKey()
            })
        case let .fakeLocationRow(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openFakeLocation()
            })
        case let .chatLockRow(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openChatLock()
            })
        case let .callOverridesRow(title):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openCallOverrides()
            })
        case let .fakeAdminRow(title):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "megaphone.fill", backgroundColor: UIColor(rgb: 0xff3b30)), title: title, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openFakeAdmin()
            })
        }
    }
}

private func pampGramAdditionalEntries(settings: PampGramSettings) -> [PampGramAdditionalEntry] {
    var entries: [PampGramAdditionalEntry] = []

    entries.append(.aboutText("Другие возможности PampGram: голос и скорость передачи файлов."))

    entries.append(.voiceHeader("ИЗМЕНЕНИЕ ГОЛОСА"))
    entries.append(.voiceToggle("Изменять голос в сообщениях", settings.voiceChangerMessagesEnabled))
    entries.append(.voicePresetRow("Голос", settings.voicePreset.displayName))
    entries.append(.voiceFooter("Применяется только к новым голосовым сообщениям, до отправки. Звонков не касается."))

    entries.append(.speedHeader("СКОРОСТЬ ПЕРЕДАЧИ"))
    entries.append(.uploadSpeedRow("Ускорение загрузки", settings.uploadSpeedMode.displayName))
    entries.append(.downloadSpeedRow("Ускорение скачивания", settings.downloadSpeedMode.displayName))
    entries.append(.speedFooter("Меняет, насколько параллельно Telegram передаёт части файлов. «Турбо» задействует потолок, уже используемый самим приложением для переноса истории — реальная скорость всё равно зависит от сети и сервера."))

    entries.append(.premiumHeader("ПРЕМИУМ"))
    entries.append(.infinitePinsToggle("Закрепить чаты ∞", settings.infinitePinsEnabled))
    entries.append(.legalPremiumToggle("Легальный премиум", settings.legalPremiumEnabled))
    entries.append(.premiumFooter("«Закрепить чаты ∞» снимает лимит на количество закреплённых чатов. «Легальный премиум» включает клиентские премиум-послабления, которые Telegram не проверяет на сервере (лимиты закреплений и папок). Закрепления сверх серверного лимита действуют на этом устройстве и могут не синхронизироваться на другие."))

    entries.append(.telegramHeader("TELEGRAM"))
    entries.append(.screenshotBypassToggle("Обход защиты от скриншотов", settings.screenshotBypassEnabled))
    entries.append(.screenshotBlurToggle("Скрыть чат при скриншоте", settings.screenshotBlurOnCapture))
    entries.append(.copyProtectionBypassToggle("Обход защиты от копирования", settings.copyProtectionBypassEnabled))
    entries.append(.autoDeleteBypassToggle("Отключить автоудаление", settings.autoDeleteBypassEnabled))
    entries.append(.blockAdsToggle("Блокировка рекламы", settings.blockAdsEnabled))
    entries.append(.telegramFooter("«Обход скриншотов» позволяет делать снимки экрана в защищённых чатах. «Скрыть чат» размывает экран при создании скриншота. «Обход копирования» разрешает копировать текст в защищённых каналах. «Автоудаление» не даёт удаляться сообщениям по таймеру. «Реклама» скрывает спонсорские сообщения."))

    entries.append(.keysHeader("ОДНОРАЗОВЫЕ КЛЮЧИ"))
    entries.append(.redeemKeyAction("Активировать ключ"))
    entries.append(.keysFooter("Введите одноразовый ключ для активации подписки PampGram."))

    entries.append(.extrasHeader("ЕЩЁ"))
    entries.append(.fakeLocationRow("Фейковая геолокация", settings.fakeLocationEnabled ? "Включено" : "Выключено"))
    entries.append(.chatLockRow("Блокировка чатов", settings.chatLockEnabled ? "Включено" : "Выключено"))
    entries.append(.callOverridesRow("Звонки"))
    entries.append(.fakeAdminRow("Фейк админ"))
    entries.append(.extrasFooter("Всё работает только на этом устройстве. «Фейк админ» позволяет визуально писать посты в любом канале — только у вас."))

    return entries
}

private func pampGramPresentModePicker(context: AccountContext, presentController: (ViewController) -> Void, title: String, current: PampGramSpeedMode, apply: @escaping (PampGramSpeedMode) -> Void) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let sheet = ActionSheetController(presentationData: presentationData)
    var buttons: [ActionSheetItem] = [ActionSheetTextItem(title: title)]
    for mode in PampGramSpeedMode.allCases {
        let label = mode == current ? "✓ \(mode.displayName)" : mode.displayName
        buttons.append(ActionSheetButtonItem(title: label, color: .accent, action: { [weak sheet] in
            sheet?.dismissAnimated()
            apply(mode)
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
    presentController(sheet)
}

private func pampGramPresentVoicePresetPicker(context: AccountContext, presentController: (ViewController) -> Void, current: PampGramVoicePreset, apply: @escaping (PampGramVoicePreset) -> Void) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let sheet = ActionSheetController(presentationData: presentationData)
    var buttons: [ActionSheetItem] = [ActionSheetTextItem(title: "Голос")]
    for preset in PampGramVoicePreset.allCases {
        let label = preset == current ? "✓ \(preset.displayName)" : preset.displayName
        buttons.append(ActionSheetButtonItem(title: label, color: .accent, action: { [weak sheet] in
            sheet?.dismissAnimated()
            apply(preset)
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
    presentController(sheet)
}

/// "Дополнительно": the voice-message pitch/tempo changer (5 fixed presets, messages only —
/// never live calls, see `PampGramVoiceChanger.swift`) and the upload/download speed presets
/// (Стандарт/Быстрый/Турбо — each just toggles existing, already-used parallelism knobs in
/// Telegram's own upload/download code).
public func pampGramAdditionalSettingsController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?
    var presentTooltipImpl: ((String) -> Void)?

    let arguments = PampGramAdditionalArguments(
        toggleVoiceChanger: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.voiceChangerMessagesEnabled = value
                return settings
            }).start()
        },
        openVoicePreset: {
            let _ = (PampGramCore.settingsSignal(postbox: context.account.postbox) |> take(1) |> deliverOnMainQueue).start(next: { settings in
                pampGramPresentVoicePresetPicker(context: context, presentController: { c in presentControllerImpl?(c) }, current: settings.voicePreset, apply: { preset in
                    let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                        var settings = settings
                        settings.voicePreset = preset
                        return settings
                    }).start()
                })
            })
        },
        openUploadSpeed: {
            let _ = (PampGramCore.settingsSignal(postbox: context.account.postbox) |> take(1) |> deliverOnMainQueue).start(next: { settings in
                pampGramPresentModePicker(context: context, presentController: { c in presentControllerImpl?(c) }, title: "Ускорение загрузки", current: settings.uploadSpeedMode, apply: { mode in
                    let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                        var settings = settings
                        settings.uploadSpeedMode = mode
                        return settings
                    }).start()
                })
            })
        },
        openDownloadSpeed: {
            let _ = (PampGramCore.settingsSignal(postbox: context.account.postbox) |> take(1) |> deliverOnMainQueue).start(next: { settings in
                pampGramPresentModePicker(context: context, presentController: { c in presentControllerImpl?(c) }, title: "Ускорение скачивания", current: settings.downloadSpeedMode, apply: { mode in
                    let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                        var settings = settings
                        settings.downloadSpeedMode = mode
                        return settings
                    }).start()
                })
            })
        },
        openFakeLocation: {
            pushControllerImpl?(pampGramFakeLocationController(context: context))
        },
        openChatLock: {
            pushControllerImpl?(pampGramChatLockController(context: context))
        },
        openCallOverrides: {
            pushControllerImpl?(pampGramCallOverridesController(context: context))
        },
        openFakeAdmin: {
            pushControllerImpl?(pampGramFakeAdminController(context: context))
        },
        toggleInfinitePins: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.infinitePinsEnabled = value
                return settings
            }).start()
        },
        toggleLegalPremium: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.legalPremiumEnabled = value
                return settings
            }).start()
        },
        toggleScreenshotBypass: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.screenshotBypassEnabled = value
                return settings
            }).start()
        },
        toggleScreenshotBlur: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.screenshotBlurOnCapture = value
                return settings
            }).start()
        },
        toggleCopyProtectionBypass: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.copyProtectionBypassEnabled = value
                return settings
            }).start()
        },
        toggleAutoDeleteBypass: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.autoDeleteBypassEnabled = value
                return settings
            }).start()
        },
        toggleBlockAds: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.blockAdsEnabled = value
                return settings
            }).start()
        },
        redeemKey: {
            presentControllerImpl?(promptController(
                context: context,
                text: "Активировать ключ",
                subtitle: "Введите одноразовый ключ, полученный от администратора PampGram.",
                value: "",
                placeholder: "XXXXXXXXXXXX",
                characterLimit: 32,
                apply: { value in
                    guard let key = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), !key.isEmpty else {
                        return
                    }
                    let userId = context.account.peerId.id._internalGetInt64Value()
                    PampGramSubscriptionAPI.redeemKey(userId: userId, key: key) { result in
                        switch result {
                        case let .success(tier):
                            presentTooltipImpl?("Ключ активирован! Тариф: \(tier == .pro ? "PRO" : "STANDARD").")
                        case .notFound:
                            presentTooltipImpl?("Ключ не найден. Проверьте правильность ввода.")
                        case .alreadyUsed:
                            presentTooltipImpl?("Этот ключ уже был использован.")
                        case .failed:
                            presentTooltipImpl?("Не удалось активировать ключ. Попробуйте позже.")
                        }
                    }
                }
            ))
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        PampGramCore.settingsSignal(postbox: context.account.postbox)
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Дополнительно"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: pampGramAdditionalEntries(settings: settings),
            style: .blocks,
            animateChanges: true
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        controller?.push(c)
    }
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    presentTooltipImpl = { [weak controller] text in
        guard let controller else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        controller.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), in: .current)
    }
    return controller
}
