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
    let toggleBypassViewOnceMedia: (Bool) -> Void
    let toggleBypassTimedMedia: (Bool) -> Void
    let toggleBypassMarkViewed: (Bool) -> Void
    let toggleStorySaving: (Bool) -> Void
    let toggleScreenshotBypass: (Bool) -> Void
    let toggleHideOwnPhone: (Bool) -> Void
    let openFakePhoneNumber: () -> Void
    let toggleProfileIds: (Bool) -> Void
    let toggleAccountLink: (Bool) -> Void
    let openFakeBots: () -> Void

    init(toggleVoiceChanger: @escaping (Bool) -> Void, openVoicePreset: @escaping () -> Void, openUploadSpeed: @escaping () -> Void, openDownloadSpeed: @escaping () -> Void, openFakeLocation: @escaping () -> Void, openChatLock: @escaping () -> Void, openCallOverrides: @escaping () -> Void, openFakeAdmin: @escaping () -> Void, toggleInfinitePins: @escaping (Bool) -> Void, toggleLegalPremium: @escaping (Bool) -> Void, toggleBypassViewOnceMedia: @escaping (Bool) -> Void, toggleBypassTimedMedia: @escaping (Bool) -> Void, toggleBypassMarkViewed: @escaping (Bool) -> Void, toggleStorySaving: @escaping (Bool) -> Void, toggleScreenshotBypass: @escaping (Bool) -> Void, toggleHideOwnPhone: @escaping (Bool) -> Void, openFakePhoneNumber: @escaping () -> Void, toggleProfileIds: @escaping (Bool) -> Void, toggleAccountLink: @escaping (Bool) -> Void, openFakeBots: @escaping () -> Void) {
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
        self.toggleBypassViewOnceMedia = toggleBypassViewOnceMedia
        self.toggleBypassTimedMedia = toggleBypassTimedMedia
        self.toggleBypassMarkViewed = toggleBypassMarkViewed
        self.toggleStorySaving = toggleStorySaving
        self.toggleScreenshotBypass = toggleScreenshotBypass
        self.toggleHideOwnPhone = toggleHideOwnPhone
        self.openFakePhoneNumber = openFakePhoneNumber
        self.toggleProfileIds = toggleProfileIds
        self.toggleAccountLink = toggleAccountLink
        self.openFakeBots = openFakeBots
    }
}

private enum PampGramAdditionalSection: Int32 {
    case about
    case voice
    case speed
    case media
    case premium
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

    case mediaHeader(String)
    case viewOnceToggle(String, Bool)
    case timedToggle(String, Bool)
    case markViewedToggle(String, Bool)
    case screenshotsToggle(String, Bool)
    case chatScreenshotsToggle(String, Bool)
    case mediaFooter(String)

    case premiumHeader(String)
    case infinitePinsToggle(String, Bool)
    case legalPremiumToggle(String, Bool)
    case premiumFooter(String)

    case extrasHeader(String)
    case fakeLocationRow(String, String)
    case chatLockRow(String, String)
    case callOverridesRow(String)
    case fakeAdminRow(String)
    case hideOwnPhoneToggle(String, Bool)
    case fakePhoneNumberRow(String, String)
    case profileIdsToggle(String, Bool)
    case accountLinkToggle(String, Bool)
    case fakeBotsRow(String, String)
    case extrasFooter(String)

    var section: ItemListSectionId {
        switch self {
        case .aboutText:
            return PampGramAdditionalSection.about.rawValue
        case .voiceHeader, .voiceToggle, .voicePresetRow, .voiceFooter:
            return PampGramAdditionalSection.voice.rawValue
        case .speedHeader, .uploadSpeedRow, .downloadSpeedRow, .speedFooter:
            return PampGramAdditionalSection.speed.rawValue
        case .mediaHeader, .viewOnceToggle, .timedToggle, .markViewedToggle, .screenshotsToggle, .chatScreenshotsToggle, .mediaFooter:
            return PampGramAdditionalSection.media.rawValue
        case .premiumHeader, .infinitePinsToggle, .legalPremiumToggle, .premiumFooter:
            return PampGramAdditionalSection.premium.rawValue
        case .extrasHeader, .fakeLocationRow, .chatLockRow, .callOverridesRow, .fakeAdminRow, .hideOwnPhoneToggle, .fakePhoneNumberRow, .profileIdsToggle, .accountLinkToggle, .fakeBotsRow, .extrasFooter:
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
        case .mediaHeader:
            return 9
        case .viewOnceToggle:
            return 10
        case .timedToggle:
            return 11
        case .markViewedToggle:
            return 14
        case .screenshotsToggle:
            return 12
        case .chatScreenshotsToggle:
            return 13
        case .mediaFooter:
            return 15
        case .premiumHeader:
            return 16
        case .infinitePinsToggle:
            return 17
        case .legalPremiumToggle:
            return 18
        case .premiumFooter:
            return 19
        case .extrasHeader:
            return 20
        case .fakeLocationRow:
            return 21
        case .chatLockRow:
            return 22
        case .callOverridesRow:
            return 23
        case .fakeAdminRow:
            return 24
        case .hideOwnPhoneToggle:
            return 25
        case .fakePhoneNumberRow:
            return 26
        case .profileIdsToggle:
            return 27
        case .accountLinkToggle:
            return 28
        case .fakeBotsRow:
            return 30
        case .extrasFooter:
            return 40
        }
    }

    static func <(lhs: PampGramAdditionalEntry, rhs: PampGramAdditionalEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramAdditionalArguments
        switch self {
        case let .aboutText(text), let .voiceFooter(text), let .speedFooter(text), let .mediaFooter(text), let .premiumFooter(text), let .extrasFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .voiceHeader(text), let .speedHeader(text), let .mediaHeader(text), let .premiumHeader(text), let .extrasHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .viewOnceToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "eye.fill", backgroundColor: UIColor(rgb: 0x34c759)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleBypassViewOnceMedia(value)
            })
        case let .timedToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "timer", backgroundColor: UIColor(rgb: 0x34c759)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleBypassTimedMedia(value)
            })
        case let .markViewedToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "checkmark.circle.fill", backgroundColor: UIColor(rgb: 0x34c759)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleBypassMarkViewed(value)
            })
        case let .screenshotsToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "camera.viewfinder", backgroundColor: UIColor(rgb: 0xff9500)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleStorySaving(value)
            })
        case let .chatScreenshotsToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "eye.trianglebadge.exclamationmark", backgroundColor: UIColor(rgb: 0xff3b30)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleScreenshotBypass(value)
            })
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
        case let .fakeBotsRow(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "bitcoinsign.circle.fill", backgroundColor: UIColor(rgb: 0x1b8ed2)), title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openFakeBots()
            })
        case let .fakeAdminRow(title):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "megaphone.fill", backgroundColor: UIColor(rgb: 0xff3b30)), title: title, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openFakeAdmin()
            })
        case let .hideOwnPhoneToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "phone.down.fill", backgroundColor: UIColor(rgb: 0x8e8e93)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleHideOwnPhone(value)
            })
        case let .fakePhoneNumberRow(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "phone.badge.plus", backgroundColor: UIColor(rgb: 0x34c759)), title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openFakePhoneNumber()
            })
        case let .profileIdsToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "number", backgroundColor: UIColor(rgb: 0x5856d6)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleProfileIds(value)
            })
        case let .accountLinkToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "link", backgroundColor: UIColor(rgb: 0x007aff)), title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleAccountLink(value)
            })
        }
    }
}

private func pampGramAdditionalEntries(settings: PampGramSettings) -> [PampGramAdditionalEntry] {
    var entries: [PampGramAdditionalEntry] = []

    entries.append(.aboutText("Другие возможности PampGram: голос, скорость передачи файлов и отображение временной медиа."))

    entries.append(.voiceHeader("ИЗМЕНЕНИЕ ГОЛОСА"))
    entries.append(.voiceToggle("Изменять голос в сообщениях", settings.voiceChangerMessagesEnabled))
    entries.append(.voicePresetRow("Голос", settings.voicePreset.displayName))
    entries.append(.voiceFooter("Только для новых голосовых, до отправки. Звонков не касается."))

    entries.append(.speedHeader("СКОРОСТЬ ПЕРЕДАЧИ"))
    entries.append(.uploadSpeedRow("Ускорение загрузки", settings.uploadSpeedMode.displayName))
    entries.append(.downloadSpeedRow("Ускорение скачивания", settings.downloadSpeedMode.displayName))
    entries.append(.speedFooter("«Турбо» — максимум, который поддерживает сеть Telegram. Реальная скорость всё равно зависит от вашего интернета и сервера."))

    entries.append(.mediaHeader("МЕДИА И СКРИНШОТЫ"))
    entries.append(.viewOnceToggle("Обход одноразовых", settings.bypassViewOnceMediaEnabled))
    entries.append(.timedToggle("Обход с таймером", settings.bypassTimedMediaEnabled))
    entries.append(.screenshotsToggle("Сохранение историй", settings.storySavingEnabled))
    entries.append(.chatScreenshotsToggle("Обход скриншотов", settings.bypassScreenshotProtectionEnabled))
    entries.append(.markViewedToggle("Отмечать просмотренным", settings.bypassMarkViewedEnabled))
    entries.append(.mediaFooter("Одноразовое и временное медиа становится обычным: без отсчёта, остаётся в чате, его можно сохранить, а отметка «просмотрено» не отправляется. «Отмечать просмотренным»: когда вы открываете такое фото или видео, отправителю приходит отметка «просмотрено» (у него оно сгорает), а у вас оно остаётся. Без неё отправитель не узнаёт, что вы открывали. «Обход скриншотов» снимает защиту скриншотов и записи экрана. Секретных чатов не касается — там всё как в стоке."))

    entries.append(.premiumHeader("ПРЕМИУМ"))
    entries.append(.infinitePinsToggle("Закрепить чаты ∞", settings.infinitePinsEnabled))
    entries.append(.legalPremiumToggle("Легальный премиум", settings.legalPremiumEnabled))
    entries.append(.premiumFooter("Снимает лимиты закреплений и папок на этом устройстве. Может не синхронизироваться на другие."))

    entries.append(.extrasHeader("ЕЩЁ"))
    entries.append(.fakeLocationRow("Фейковая геолокация", settings.fakeLocationEnabled ? "Включено" : "Выключено"))
    entries.append(.chatLockRow("Блокировка чатов", settings.chatLockEnabled ? "Включено" : "Выключено"))
    entries.append(.callOverridesRow("Звонки"))
    entries.append(.fakeAdminRow("Фейк админ"))
    entries.append(.hideOwnPhoneToggle("Скрыть номер телефона", settings.hideOwnPhoneNumber))
    entries.append(.fakePhoneNumberRow("Фейковый номер телефона", settings.fakePhoneNumber.isEmpty ? "Выключено" : settings.fakePhoneNumber))
    entries.append(.profileIdsToggle("ID Профилей", settings.profileIdsEnabled))
    entries.append(.accountLinkToggle("Ссылка аккаунта", settings.accountLinkEnabled))
    let fakeBots = pampGramParseFakeBots(settings.fakeBotsRaw)
    let builtInCount = settings.fakeCryptoBotEnabled && !fakeBots.contains(where: { $0.id == PampGramFakeCryptoBotRuntime.officialBotUserId }) ? 1 : 0
    entries.append(.fakeBotsRow("Фейковые боты", "\(fakeBots.count + builtInCount)"))
    entries.append(.extrasFooter("Работает только на этом устройстве. «Фейк админ» — визуальные посты в любом канале. «Скрыть/фейковый номер» меняют то, что видно другим в профиле, не настоящий номер. «ID Профилей» и «Ссылка аккаунта» добавляют эти строки в чужие профили."))

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
/// never live calls, see `PampGramVoiceChanger.swift`), the upload/download speed presets
/// (Стандарт/Быстрый/Турбо — each just toggles existing, already-used parallelism knobs in
/// Telegram's own upload/download code), "Обход одноразовых"/"Обход с таймером" — the bubble is drawn as a normal
/// photo/video (`PampGramTemporaryMediaDisplay`, `ChatMessageInteractiveMediaNode.swift`) and the
/// message loses its self-destruct timers locally (`PampGramTemporaryMediaBypass`), so there is no
/// countdown and the picture can be saved — and
/// "Сохранение историй" — see `PampGramStorySavingDisplay` and its use in
/// `StoryItemContentComponent.swift` and `StoryItemSetContainerComponent.swift`.
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
        toggleBypassViewOnceMedia: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.bypassViewOnceMediaEnabled = value
                return settings
            }).start()
        },
        toggleBypassTimedMedia: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.bypassTimedMediaEnabled = value
                return settings
            }).start()
        },
        toggleBypassMarkViewed: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.bypassMarkViewedEnabled = value
                return settings
            }).start()
        },
        toggleStorySaving: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.storySavingEnabled = value
                return settings
            }).start()
        },
        toggleScreenshotBypass: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.bypassScreenshotProtectionEnabled = value
                return settings
            }).start()
        },
        toggleHideOwnPhone: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.hideOwnPhoneNumber = value
                return settings
            }).start()
        },
        openFakePhoneNumber: {
            let _ = (PampGramCore.settingsSignal(postbox: context.account.postbox) |> take(1) |> deliverOnMainQueue).start(next: { settings in
                presentControllerImpl?(promptController(
                    context: context,
                    text: "Фейковый номер телефона",
                    subtitle: "Показывается вместо настоящего — в настройках и в «Моём профиле». Пусто — выключено.",
                    value: settings.fakePhoneNumber,
                    placeholder: "+1 234 567 89 00",
                    characterLimit: 32,
                    apply: { value in
                        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                            var settings = settings
                            settings.fakePhoneNumber = trimmed
                            return settings
                        }).start()
                    }
                ))
            })
        },
        toggleProfileIds: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.profileIdsEnabled = value
                return settings
            }).start()
        },
        toggleAccountLink: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.accountLinkEnabled = value
                return settings
            }).start()
        },
        openFakeBots: {
            pushControllerImpl?(pampGramFakeBotsController(context: context))
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
    return controller
}
