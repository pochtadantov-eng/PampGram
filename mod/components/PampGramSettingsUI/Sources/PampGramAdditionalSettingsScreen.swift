import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import PampGramCore

private func modSettingsChangedSignal() -> Signal<Void, NoError> {
    return Signal { subscriber in
        let token = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ModSettingsDidChange"),
            object: nil,
            queue: nil
        ) { _ in
            subscriber.putNext(())
        }
        subscriber.putNext(())
        return ActionDisposable {
            NotificationCenter.default.removeObserver(token)
        }
    }
}

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
    let toggleBypassCopyProtection: (Bool) -> Void
    let toggleAlwaysKeepForwardAuthor: (Bool) -> Void
    let toggleDisableAutoDelete: (Bool) -> Void
    let toggleBypassScreenshotProtection: (Bool) -> Void
    let toggleHideChatOnScreenshot: (Bool) -> Void
    let toggleBlockAds: (Bool) -> Void

    init(
        toggleVoiceChanger: @escaping (Bool) -> Void,
        openVoicePreset: @escaping () -> Void,
        openUploadSpeed: @escaping () -> Void,
        openDownloadSpeed: @escaping () -> Void,
        openFakeLocation: @escaping () -> Void,
        openChatLock: @escaping () -> Void,
        openCallOverrides: @escaping () -> Void,
        openFakeAdmin: @escaping () -> Void,
        toggleInfinitePins: @escaping (Bool) -> Void,
        toggleLegalPremium: @escaping (Bool) -> Void,
        toggleBypassCopyProtection: @escaping (Bool) -> Void,
        toggleAlwaysKeepForwardAuthor: @escaping (Bool) -> Void,
        toggleDisableAutoDelete: @escaping (Bool) -> Void,
        toggleBypassScreenshotProtection: @escaping (Bool) -> Void,
        toggleHideChatOnScreenshot: @escaping (Bool) -> Void,
        toggleBlockAds: @escaping (Bool) -> Void
    ) {
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
        self.toggleBypassCopyProtection = toggleBypassCopyProtection
        self.toggleAlwaysKeepForwardAuthor = toggleAlwaysKeepForwardAuthor
        self.toggleDisableAutoDelete = toggleDisableAutoDelete
        self.toggleBypassScreenshotProtection = toggleBypassScreenshotProtection
        self.toggleHideChatOnScreenshot = toggleHideChatOnScreenshot
        self.toggleBlockAds = toggleBlockAds
    }
}

private enum PampGramAdditionalSection: Int32 {
    case about
    case voice
    case speed
    case premium
    case extras
    case features
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

    case extrasHeader(String)
    case fakeLocationRow(String, String)
    case chatLockRow(String, String)
    case callOverridesRow(String)
    case fakeAdminRow(String)
    case extrasFooter(String)

    case featuresHeader(String)
    case bypassCopyProtectionToggle(String, Bool)
    case alwaysKeepForwardAuthorToggle(String, Bool)
    case disableAutoDeleteToggle(String, Bool)
    case bypassScreenshotProtectionToggle(String, Bool)
    case hideChatOnScreenshotToggle(String, Bool)
    case blockAdsToggle(String, Bool)
    case featuresFooter(String)

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
        case .extrasHeader, .fakeLocationRow, .chatLockRow, .callOverridesRow, .fakeAdminRow, .extrasFooter:
            return PampGramAdditionalSection.extras.rawValue
        case .featuresHeader, .bypassCopyProtectionToggle, .alwaysKeepForwardAuthorToggle, .disableAutoDeleteToggle, .bypassScreenshotProtectionToggle, .hideChatOnScreenshotToggle, .blockAdsToggle, .featuresFooter:
            return PampGramAdditionalSection.features.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .aboutText: return 0
        case .voiceHeader: return 1
        case .voiceToggle: return 2
        case .voicePresetRow: return 3
        case .voiceFooter: return 4
        case .speedHeader: return 5
        case .uploadSpeedRow: return 6
        case .downloadSpeedRow: return 7
        case .speedFooter: return 8
        case .premiumHeader: return 9
        case .infinitePinsToggle: return 10
        case .legalPremiumToggle: return 11
        case .premiumFooter: return 12
        case .extrasHeader: return 13
        case .fakeLocationRow: return 14
        case .chatLockRow: return 15
        case .callOverridesRow: return 16
        case .fakeAdminRow: return 17
        case .extrasFooter: return 18
        case .featuresHeader: return 19
        case .bypassCopyProtectionToggle: return 20
        case .alwaysKeepForwardAuthorToggle: return 21
        case .disableAutoDeleteToggle: return 22
        case .bypassScreenshotProtectionToggle: return 23
        case .hideChatOnScreenshotToggle: return 24
        case .blockAdsToggle: return 25
        case .featuresFooter: return 26
        }
    }

    static func <(lhs: PampGramAdditionalEntry, rhs: PampGramAdditionalEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramAdditionalArguments
        switch self {
        case let .aboutText(text), let .voiceFooter(text), let .speedFooter(text), let .premiumFooter(text), let .extrasFooter(text), let .featuresFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .voiceHeader(text), let .speedHeader(text), let .premiumHeader(text), let .extrasHeader(text), let .featuresHeader(text):
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
        case let .bypassCopyProtectionToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "doc.on.doc.fill", backgroundColor: UIColor(rgb: 0x34c759)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleBypassCopyProtection(value)
            })
        case let .alwaysKeepForwardAuthorToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "arrowshape.turn.up.right.fill", backgroundColor: UIColor(rgb: 0x007aff)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleAlwaysKeepForwardAuthor(value)
            })
        case let .disableAutoDeleteToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "timer", backgroundColor: UIColor(rgb: 0xff9500)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleDisableAutoDelete(value)
            })
        case let .bypassScreenshotProtectionToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "camera.fill", backgroundColor: UIColor(rgb: 0x5856d6)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleBypassScreenshotProtection(value)
            })
        case let .hideChatOnScreenshotToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "eye.slash.fill", backgroundColor: UIColor(rgb: 0x8e8e93)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleHideChatOnScreenshot(value)
            })
        case let .blockAdsToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "xmark.circle.fill", backgroundColor: UIColor(rgb: 0xff3b30)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleBlockAds(value)
            })
        }
    }
}

private func pampGramAdditionalEntries(settings: PampGramSettings) -> [PampGramAdditionalEntry] {
    var entries: [PampGramAdditionalEntry] = []
    let mod = ModSettings.shared

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

    entries.append(.extrasHeader("ЕЩЁ"))
    entries.append(.fakeLocationRow("Фейковая геолокация", settings.fakeLocationEnabled ? "Включено" : "Выключено"))
    entries.append(.chatLockRow("Блокировка чатов", settings.chatLockEnabled ? "Включено" : "Выключено"))
    entries.append(.callOverridesRow("Звонки"))
    entries.append(.fakeAdminRow("Фейк админ"))
    entries.append(.extrasFooter("Всё работает только на этом устройстве. «Фейк админ» позволяет визуально писать посты в любом канале — только у вас."))

    entries.append(.featuresHeader("ПРОЧЕЕ"))
    entries.append(.bypassCopyProtectionToggle("Обход защиты от копирования", mod.bypassCopyProtection))
    entries.append(.alwaysKeepForwardAuthorToggle("Добавлять от кого переслано", mod.alwaysKeepForwardAuthor))
    entries.append(.disableAutoDeleteToggle("Отключить автоудаление исчезающих", mod.disableAutoDelete))
    entries.append(.bypassScreenshotProtectionToggle("Обход защиты от скриншотов", mod.bypassScreenshotProtection))
    entries.append(.hideChatOnScreenshotToggle("Скрывать чат на скриншотах", mod.hideChatOnScreenshot))
    entries.append(.blockAdsToggle("Блокировать рекламу", mod.blockAds))
    entries.append(.featuresFooter("«Обход защиты от копирования» разрешает копировать текст из чатов с запретом. «Обход защиты от скриншотов» убирает системный запрет скриншотов. «Блокировать рекламу» скрывает спонсорские сообщения."))

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
        toggleBypassCopyProtection: { value in
            ModSettings.shared.bypassCopyProtection = value
        },
        toggleAlwaysKeepForwardAuthor: { value in
            ModSettings.shared.alwaysKeepForwardAuthor = value
        },
        toggleDisableAutoDelete: { value in
            ModSettings.shared.disableAutoDelete = value
        },
        toggleBypassScreenshotProtection: { value in
            ModSettings.shared.bypassScreenshotProtection = value
        },
        toggleHideChatOnScreenshot: { value in
            ModSettings.shared.hideChatOnScreenshot = value
        },
        toggleBlockAds: { value in
            ModSettings.shared.blockAds = value
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        PampGramCore.settingsSignal(postbox: context.account.postbox),
        modSettingsChangedSignal()
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
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
    return controller
}
