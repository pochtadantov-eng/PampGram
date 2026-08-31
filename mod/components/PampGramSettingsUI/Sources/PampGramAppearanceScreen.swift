import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramPresentationData
import ItemListUI
import AccountContext
import PromptUI
import AppBundle
import PampGramCore

private final class PampGramAppearanceArguments {
    let choosePreset: () -> Void
    let editBubbleRadius: () -> Void
    let editBubbleOpacity: () -> Void
    let editBlur: () -> Void
    let editDensity: () -> Void
    let toggleReduceAnimations: (Bool) -> Void
    let toggleOled: (Bool) -> Void
    let toggleCompactHub: (Bool) -> Void
    let toggleMonochrome: (Bool) -> Void
    let toggleGlassCards: (Bool) -> Void
    let toggleMinimal: (Bool) -> Void
    let toggleChatPreview: (Bool) -> Void
    let toggleChatDate: (Bool) -> Void
    let editAvatarSize: () -> Void
    let editProfileBlur: () -> Void
    let openIconPicker: () -> Void
    let reset: () -> Void

    init(choosePreset: @escaping () -> Void, editBubbleRadius: @escaping () -> Void, editBubbleOpacity: @escaping () -> Void, editBlur: @escaping () -> Void, editDensity: @escaping () -> Void, toggleReduceAnimations: @escaping (Bool) -> Void, toggleOled: @escaping (Bool) -> Void, toggleCompactHub: @escaping (Bool) -> Void, toggleMonochrome: @escaping (Bool) -> Void, toggleGlassCards: @escaping (Bool) -> Void, toggleMinimal: @escaping (Bool) -> Void, toggleChatPreview: @escaping (Bool) -> Void, toggleChatDate: @escaping (Bool) -> Void, editAvatarSize: @escaping () -> Void, editProfileBlur: @escaping () -> Void, openIconPicker: @escaping () -> Void, reset: @escaping () -> Void) {
        self.choosePreset = choosePreset; self.editBubbleRadius = editBubbleRadius; self.editBubbleOpacity = editBubbleOpacity; self.editBlur = editBlur; self.editDensity = editDensity; self.toggleReduceAnimations = toggleReduceAnimations; self.toggleOled = toggleOled; self.toggleCompactHub = toggleCompactHub; self.toggleMonochrome = toggleMonochrome; self.toggleGlassCards = toggleGlassCards; self.toggleMinimal = toggleMinimal; self.toggleChatPreview = toggleChatPreview; self.toggleChatDate = toggleChatDate; self.editAvatarSize = editAvatarSize; self.editProfileBlur = editProfileBlur; self.openIconPicker = openIconPicker; self.reset = reset
    }
}

private enum PampGramAppearanceEntry: ItemListNodeEntry {
    case about(String)
    case presetHeader(String), preset(String, String)
    case chatHeader(String), bubbleRadius(String, String), bubbleOpacity(String, String), blur(String, String), density(String, String), chatPreview(String, Bool), chatDate(String, Bool), avatarSize(String, String)
    case uiHeader(String), glassCards(String, Bool), compactHub(String, Bool), monochrome(String, Bool), minimal(String, Bool), oled(String, Bool), profileBlur(String, String), reduceAnimations(String, Bool)
    case appHeader(String), icon(PresentationAppIcon)
    case reset(String), footer(String)

    var section: ItemListSectionId {
        switch self {
        case .about: return 0
        case .presetHeader, .preset: return 1
        case .chatHeader, .bubbleRadius, .bubbleOpacity, .blur, .density, .chatPreview, .chatDate, .avatarSize: return 2
        case .uiHeader, .glassCards, .compactHub, .monochrome, .minimal, .oled, .profileBlur, .reduceAnimations: return 3
        case .appHeader, .icon: return 4
        case .reset, .footer: return 5
        }
    }
    var stableId: Int32 {
        switch self {
        case .about: return 0; case .presetHeader: return 1; case .preset: return 2; case .chatHeader: return 10; case .bubbleRadius: return 11; case .bubbleOpacity: return 12; case .blur: return 13; case .density: return 14; case .chatPreview: return 15; case .chatDate: return 16; case .avatarSize: return 17; case .uiHeader: return 20; case .glassCards: return 21; case .compactHub: return 22; case .monochrome: return 23; case .minimal: return 24; case .oled: return 25; case .profileBlur: return 26; case .reduceAnimations: return 27; case .appHeader: return 30; case .icon: return 31; case .reset: return 40; case .footer: return 41
        }
    }
    static func <(lhs: Self, rhs: Self) -> Bool { lhs.stableId < rhs.stableId }
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let a = arguments as! PampGramAppearanceArguments
        switch self {
        case let .about(text), let .footer(text): return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .presetHeader(text), let .chatHeader(text), let .uiHeader(text), let .appHeader(text): return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .preset(title, label): return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, action: a.choosePreset)
        case let .bubbleRadius(title, label): return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, action: a.editBubbleRadius)
        case let .bubbleOpacity(title, label): return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, action: a.editBubbleOpacity)
        case let .blur(title, label): return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, action: a.editBlur)
        case let .density(title, label): return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, action: a.editDensity)
        case let .avatarSize(title, label): return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, action: a.editAvatarSize)
        case let .profileBlur(title, label): return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, action: a.editProfileBlur)
        case let .chatPreview(title, value): return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: a.toggleChatPreview)
        case let .chatDate(title, value): return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: a.toggleChatDate)
        case let .glassCards(title, value): return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: a.toggleGlassCards)
        case let .compactHub(title, value): return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: a.toggleCompactHub)
        case let .monochrome(title, value): return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: a.toggleMonochrome)
        case let .minimal(title, value): return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: a.toggleMinimal)
        case let .oled(title, value): return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: a.toggleOled)
        case let .reduceAnimations(title, value): return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: a.toggleReduceAnimations)
        case let .icon(icon):
            let preview = UIImage(named: icon.imageName, in: getAppBundle(), compatibleWith: nil).flatMap { generatePampGramIconPreview($0) }
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: preview, title: "Иконка приложения", label: pampGramIconDisplayName(icon), sectionId: self.section, style: .blocks, action: a.openIconPicker)
        case let .reset(title): return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: a.reset)
        }
    }
}

public func pampGramAppearanceController(context: AccountContext) -> ViewController {
    var present: ((ViewController) -> Void)?
    var currentIconNameValue = context.sharedContext.applicationBindings.getAlternateIconName()
    let currentIconName = ValuePromise<String?>(currentIconNameValue)
    var icons = context.sharedContext.applicationBindings.getAvailableAlternateIcons().filter { !$0.isPremium }

    func update(_ f: @escaping (PampGramAppearanceState) -> PampGramAppearanceState) { let _ = context.account.postbox.transaction { transaction in PampGramAppearanceStore.update(transaction: transaction, f) }.start() }
    func numericPrompt(title: String, current: Int32, range: ClosedRange<Int32>, apply: @escaping (inout PampGramAppearanceState, Int32) -> Void) {
        present?(promptController(context: context, text: title, subtitle: "Допустимо: \(range.lowerBound)…\(range.upperBound)", value: "\(current)", characterLimit: 5, apply: { value in
            guard let value, let number = Int32(value), range.contains(number) else { return }
            update { state in var state = state; apply(&state, number); return state }
        }))
    }

    let arguments = PampGramAppearanceArguments(
        choosePreset: {
            let pd = context.sharedContext.currentPresentationData.with { $0 }; let sheet = ActionSheetController(presentationData: pd)
            let buttons = PampGramAppearancePreset.allCases.map { preset in ActionSheetButtonItem(title: preset.displayName, color: .accent, action: { [weak sheet] in sheet?.dismissAnimated(); update { _ in
                var s = PampGramAppearanceState.default; s.preset = preset
                switch preset { case .standard: break; case .glass: s.glassCards = true; s.blurStrength = 65; s.bubbleOpacityPercent = 88; case .compact: s.chatDensity = 0; s.compactHub = true; s.avatarSize = 42; s.bubbleRadius = 12 }
                return s
            } }) }
            sheet.setItemGroups([ActionSheetItemGroup(items: buttons), ActionSheetItemGroup(items: [ActionSheetButtonItem(title: pd.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in sheet?.dismissAnimated() })])]); present?(sheet)
        },
        editBubbleRadius: { let _ = (PampGramAppearanceStore.signal(postbox: context.account.postbox) |> take(1) |> deliverOnMainQueue).start(next: { numericPrompt(title: "Радиус пузырей", current: $0.bubbleRadius, range: 4...32) { $0.bubbleRadius = $1 } }) },
        editBubbleOpacity: { let _ = (PampGramAppearanceStore.signal(postbox: context.account.postbox) |> take(1) |> deliverOnMainQueue).start(next: { numericPrompt(title: "Прозрачность пузырей", current: $0.bubbleOpacityPercent, range: 30...100) { $0.bubbleOpacityPercent = $1 } }) },
        editBlur: { let _ = (PampGramAppearanceStore.signal(postbox: context.account.postbox) |> take(1) |> deliverOnMainQueue).start(next: { numericPrompt(title: "Сила blur", current: $0.blurStrength, range: 0...100) { $0.blurStrength = $1 } }) },
        editDensity: { let _ = (PampGramAppearanceStore.signal(postbox: context.account.postbox) |> take(1) |> deliverOnMainQueue).start(next: { numericPrompt(title: "Плотность чатов", current: $0.chatDensity, range: 0...2) { $0.chatDensity = $1 } }) },
        toggleReduceAnimations: { v in update { var s=$0; s.reduceAnimations=v; return s } }, toggleOled: { v in update { var s=$0; s.oledBlack=v; return s } }, toggleCompactHub: { v in update { var s=$0; s.compactHub=v; return s } }, toggleMonochrome: { v in update { var s=$0; s.monochromeIcons=v; return s } }, toggleGlassCards: { v in update { var s=$0; s.glassCards=v; return s } }, toggleMinimal: { v in update { var s=$0; s.minimalMode=v; return s } }, toggleChatPreview: { v in update { var s=$0; s.showChatPreview=v; return s } }, toggleChatDate: { v in update { var s=$0; s.showChatDate=v; return s } },
        editAvatarSize: { let _ = (PampGramAppearanceStore.signal(postbox: context.account.postbox) |> take(1) |> deliverOnMainQueue).start(next: { numericPrompt(title: "Размер аватарок", current: $0.avatarSize, range: 36...64) { $0.avatarSize = $1 } }) },
        editProfileBlur: { let _ = (PampGramAppearanceStore.signal(postbox: context.account.postbox) |> take(1) |> deliverOnMainQueue).start(next: { numericPrompt(title: "Blur профиля", current: $0.profileHeaderBlur, range: 0...100) { $0.profileHeaderBlur = $1 } }) },
        openIconPicker: { pampGramPresentIconPicker(context: context, icons: icons, currentIconName: currentIconNameValue, onSelect: { icon in currentIconNameValue = icon.name; currentIconName.set(icon.name) }) },
        reset: { update { _ in .default } }
    )

    let signal = combineLatest(context.sharedContext.presentationData, PampGramAppearanceStore.signal(postbox: context.account.postbox), currentIconName.get())
    |> deliverOnMainQueue
    |> map { pd, state, selectedName -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [PampGramAppearanceEntry] = [.about("Настройки визуального движка PampGram. Пресет задаёт базу, отдельные параметры можно менять после него."), .presetHeader("ПРЕСЕТ"), .preset("Оформление", state.preset.displayName), .chatHeader("ЧАТЫ"), .bubbleRadius("Радиус пузырей", "\(state.bubbleRadius)"), .bubbleOpacity("Прозрачность пузырей", "\(state.bubbleOpacityPercent)%"), .blur("Blur / стекло", "\(state.blurStrength)%"), .density("Плотность", state.chatDensity == 0 ? "Compact" : state.chatDensity == 2 ? "Просторно" : "Обычно"), .chatPreview("Превью сообщений", state.showChatPreview), .chatDate("Дата в списке чатов", state.showChatDate), .avatarSize("Размер аватарок", "\(state.avatarSize)"), .uiHeader("ИНТЕРФЕЙС"), .glassCards("Стеклянные карточки", state.glassCards), .compactHub("Компактный PampGram", state.compactHub), .monochrome("Монохромные иконки", state.monochromeIcons), .minimal("Минималистичный режим", state.minimalMode), .oled("OLED Black", state.oledBlack), .profileBlur("Blur шапки профиля", "\(state.profileHeaderBlur)%"), .reduceAnimations("Уменьшить анимации", state.reduceAnimations), .appHeader("ПРИЛОЖЕНИЕ")]
        if let selected = icons.first(where: { $0.name == selectedName }) ?? icons.first(where: { $0.isDefault }) ?? icons.first { entries.append(.icon(selected)) }
        entries.append(.reset("Сбросить внешний вид")); entries.append(.footer("Сброс возвращает стандартный пресет. Тяжёлые эффекты можно отключить через «Уменьшить анимации»."))
        return (ItemListControllerState(presentationData: ItemListPresentationData(pd), title: .text("Внешний вид"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: pd.strings.Common_Back), animateChanges: false), (ItemListNodeState(presentationData: ItemListPresentationData(pd), entries: entries, style: .blocks, animateChanges: true), arguments))
    }
    let controller = ItemListController(context: context, state: signal); present = { [weak controller] c in controller?.present(c, in: .window(.root)) }; return controller
}
