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
import PhantomGiftKit
import PromptUI
import UndoUI

private func pampGramAttributeName(_ attribute: StarGift.UniqueGift.Attribute) -> String {
    switch attribute {
    case let .model(name, _, _, _):
        return name
    case let .pattern(name, _, _):
        return name
    case let .backdrop(name, _, _, _, _, _, _):
        return name
    case .originalInfo:
        return ""
    }
}

private func pampGramBackdropColor(_ attribute: StarGift.UniqueGift.Attribute) -> UIColor {
    if case let .backdrop(_, _, innerColor, _, _, _, _) = attribute {
        return UIColor(rgb: UInt32(bitPattern: innerColor))
    }
    return .gray
}

// `StarGift.UniqueGift.Attribute.AttributeType` doesn't conform to `Equatable`, so filtering by
// case goes through these instead of `attributeType == .model` etc.
private func pampGramIsModel(_ attribute: StarGift.UniqueGift.Attribute) -> Bool {
    if case .model = attribute { return true }
    return false
}

private func pampGramIsBackdrop(_ attribute: StarGift.UniqueGift.Attribute) -> Bool {
    if case .backdrop = attribute { return true }
    return false
}

private func pampGramIsPattern(_ attribute: StarGift.UniqueGift.Attribute) -> Bool {
    if case .pattern = attribute { return true }
    return false
}

/// Everything the screen needs to redraw, rebuilt and re-set as one value on every change —
/// same "whole state in one Promise" idiom `PampGramUsersListScreen` already uses, simpler
/// here than combining half a dozen independent Promises for fields that always change
/// together (picking a new base gift always resets model/backdrop/pattern, for instance).
private struct PampGramGiftConstructorState {
    var baseGiftOptions: [StarGift.Gift] = []
    var baseGift: StarGift.Gift?
    /// `getStarGiftUpgradePreview`'s real sample attributes for `baseGift` — the actual
    /// model/backdrop/pattern catalog Telegram's own server returns for this gift, same data
    /// the real upgrade-preview flow reads. Empty until `baseGift` is chosen and this loads.
    var attributes: [StarGift.UniqueGift.Attribute] = []
    var isLoadingAttributes: Bool = false
    var model: StarGift.UniqueGift.Attribute?
    var backdrop: StarGift.UniqueGift.Attribute?
    var pattern: StarGift.UniqueGift.Attribute?
    var number: Int32 = Int32.random(in: 1...9999)
}

private final class PampGramGiftConstructorArguments {
    let pickBaseGift: () -> Void
    let pickModel: () -> Void
    let pickBackdrop: () -> Void
    let pickPattern: () -> Void
    let pickNumber: () -> Void
    let randomize: () -> Void
    let save: () -> Void
    let openSaved: (PampGramPhantomGift) -> Void

    init(pickBaseGift: @escaping () -> Void, pickModel: @escaping () -> Void, pickBackdrop: @escaping () -> Void, pickPattern: @escaping () -> Void, pickNumber: @escaping () -> Void, randomize: @escaping () -> Void, save: @escaping () -> Void, openSaved: @escaping (PampGramPhantomGift) -> Void) {
        self.pickBaseGift = pickBaseGift
        self.pickModel = pickModel
        self.pickBackdrop = pickBackdrop
        self.pickPattern = pickPattern
        self.pickNumber = pickNumber
        self.randomize = randomize
        self.save = save
        self.openSaved = openSaved
    }
}

private enum PampGramGiftConstructorSection: Int32 {
    case about
    case picker
    case actions
    case saved
}

private enum PampGramGiftConstructorEntry: ItemListNodeEntry {
    case about(String)
    case baseGift(StarGift.Gift?)
    case model(StarGift.UniqueGift.Attribute?, Bool)
    case backdrop(StarGift.UniqueGift.Attribute?, Bool)
    case pattern(StarGift.UniqueGift.Attribute?, Bool)
    case number(Int32)
    case randomize
    case save
    case savedHeader
    case savedEmpty(String)
    case savedGift(Int32, PampGramPhantomGift)

    var section: ItemListSectionId {
        switch self {
        case .about:
            return PampGramGiftConstructorSection.about.rawValue
        case .baseGift, .model, .backdrop, .pattern, .number:
            return PampGramGiftConstructorSection.picker.rawValue
        case .randomize, .save:
            return PampGramGiftConstructorSection.actions.rawValue
        case .savedHeader, .savedEmpty, .savedGift:
            return PampGramGiftConstructorSection.saved.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .about: return 0
        case .baseGift: return 1
        case .model: return 2
        case .backdrop: return 3
        case .pattern: return 4
        case .number: return 5
        case .randomize: return 6
        case .save: return 7
        case .savedHeader: return 8
        case .savedEmpty: return 9
        case let .savedGift(index, _): return 10 + index
        }
    }

    static func ==(lhs: PampGramGiftConstructorEntry, rhs: PampGramGiftConstructorEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.about(a), .about(b)):
            return a == b
        case let (.baseGift(a), .baseGift(b)):
            return a?.id == b?.id
        case let (.model(a, al), .model(b, bl)):
            return a.map(pampGramAttributeName) == b.map(pampGramAttributeName) && al == bl
        case let (.backdrop(a, al), .backdrop(b, bl)):
            return a.map(pampGramAttributeName) == b.map(pampGramAttributeName) && al == bl
        case let (.pattern(a, al), .pattern(b, bl)):
            return a.map(pampGramAttributeName) == b.map(pampGramAttributeName) && al == bl
        case let (.number(a), .number(b)):
            return a == b
        case (.randomize, .randomize), (.save, .save), (.savedHeader, .savedHeader), (.savedEmpty, .savedEmpty):
            return true
        case let (.savedGift(ai, ag), .savedGift(bi, bg)):
            return ai == bi && ag == bg
        default:
            return false
        }
    }

    static func <(lhs: PampGramGiftConstructorEntry, rhs: PampGramGiftConstructorEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let a = arguments as! PampGramGiftConstructorArguments
        switch self {
        case let .about(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .baseGift(gift):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: generatePampGramSectionIcon(systemName: "gift.fill", backgroundColor: UIColor(rgb: 0xff9500)),
                title: "Подарок",
                label: gift?.title ?? "Выбрать",
                sectionId: self.section,
                style: .blocks,
                action: { a.pickBaseGift() }
            )
        case let .model(attribute, enabled):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: generatePampGramSectionIcon(systemName: "cube.fill", backgroundColor: UIColor(rgb: 0x5856d6)),
                title: "Модель",
                label: attribute.map(pampGramAttributeName) ?? (enabled ? "Выбрать" : "Сначала подарок"),
                sectionId: self.section,
                style: .blocks,
                action: { a.pickModel() }
            )
        case let .backdrop(attribute, enabled):
            let color = attribute.map(pampGramBackdropColor) ?? UIColor(rgb: 0x8e8e93)
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: generatePampGramSectionIcon(systemName: "circle.fill", backgroundColor: color),
                title: "Фон",
                label: attribute.map(pampGramAttributeName) ?? (enabled ? "Выбрать" : "Сначала подарок"),
                sectionId: self.section,
                style: .blocks,
                action: { a.pickBackdrop() }
            )
        case let .pattern(attribute, enabled):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: generatePampGramSectionIcon(systemName: "sparkles", backgroundColor: UIColor(rgb: 0x34c759)),
                title: "Символ",
                label: attribute.map(pampGramAttributeName) ?? (enabled ? "Выбрать" : "Сначала подарок"),
                sectionId: self.section,
                style: .blocks,
                action: { a.pickPattern() }
            )
        case let .number(number):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: generatePampGramSectionIcon(systemName: "number", backgroundColor: UIColor(rgb: 0x8e8e93)),
                title: "Номер подарка",
                label: "#\(number)",
                sectionId: self.section,
                style: .blocks,
                action: { a.pickNumber() }
            )
        case .randomize:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "🎲 Случайно", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: { a.randomize() })
        case .save:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Сохранить в профиль", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: { a.save() })
        case .savedHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "В ПРОФИЛЕ", sectionId: self.section)
        case let .savedEmpty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .savedGift(_, gift):
            let title = gift.number.map { "\(gift.title) #\($0)" } ?? gift.title
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "sparkle", backgroundColor: UIColor(rgb: 0xaf52de)), title: title, label: "", sectionId: self.section, style: .blocks, action: { a.openSaved(gift) })
        }
    }
}

private func pampGramGiftConstructorEntries(state: PampGramGiftConstructorState, savedGifts: [PampGramPhantomGift]) -> [PampGramGiftConstructorEntry] {
    var entries: [PampGramGiftConstructorEntry] = [
        .about("Соберите собственный визуальный NFT-подарок из настоящего каталога Telegram — любая модель, фон и символ, в любой комбинации. Появится в сетке подарков вашего профиля, видно только вам."),
        .baseGift(state.baseGift)
    ]
    let hasAttributes = state.baseGift != nil && !state.isLoadingAttributes
    entries.append(.model(state.model, hasAttributes))
    entries.append(.backdrop(state.backdrop, hasAttributes))
    entries.append(.pattern(state.pattern, hasAttributes))
    entries.append(.number(state.number))
    entries.append(.randomize)
    entries.append(.save)
    entries.append(.savedHeader)
    if savedGifts.isEmpty {
        entries.append(.savedEmpty("Пока нет сконструированных подарков."))
    } else {
        for (index, gift) in savedGifts.enumerated() {
            entries.append(.savedGift(Int32(index), gift))
        }
    }
    return entries
}

/// "Конструктор подарка": lets the owner freely assemble a unique gift from real Telegram
/// catalog data — a real base gift plus whatever real model/backdrop/pattern
/// `getStarGiftUpgradePreview` offers for it — in any combination, not limited to combinations
/// that exist on a real unique gift. Saved via `PampGramPhantomGiftManager.constructUniqueGift`
/// straight into this account's own profile grid; the real `GiftsListView`/`GiftViewScreen`
/// (both untouched stock code) render the result exactly like any other unique gift, since the
/// attributes themselves are genuine Telegram data.
public func pampGramGiftConstructorController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    var presentTooltipImpl: ((String) -> Void)?

    let statePromise = Promise<PampGramGiftConstructorState>(PampGramGiftConstructorState())

    func updateState(_ f: (inout PampGramGiftConstructorState) -> Void) {
        let _ = (statePromise.get() |> take(1) |> deliverOnMainQueue).start(next: { current in
            var state = current
            f(&state)
            statePromise.set(.single(state))
        })
    }

    // Loaded once, up front: the real generic-gift catalog this screen's "Подарок" picker
    // offers. `keepStarGiftsUpdated` is the same fire-and-forget refresh trigger
    // `PampGramRealGiftAutoSend` already uses before reading `cachedStarGifts()`.
    let refreshDisposable = MetaDisposable()
    refreshDisposable.set(context.engine.payments.keepStarGiftsUpdated().start())
    let _ = (context.engine.payments.cachedStarGifts()
    |> filter { $0 != nil }
    |> take(1)
    |> deliverOnMainQueue).start(next: { gifts in
        refreshDisposable.dispose()
        let baseGifts: [StarGift.Gift] = (gifts ?? []).compactMap { starGift in
            if case let .generic(gift) = starGift {
                return gift
            }
            return nil
        }.sorted(by: { $0.price < $1.price })
        updateState { state in
            state.baseGiftOptions = baseGifts
        }
    })

    func loadAttributes(for gift: StarGift.Gift) {
        updateState { state in
            state.isLoadingAttributes = true
            state.attributes = []
        }
        let _ = (context.engine.payments.starGiftUpgradePreview(giftId: gift.id)
        |> deliverOnMainQueue).start(next: { preview in
            updateState { state in
                guard state.baseGift?.id == gift.id else {
                    // The user picked a different base gift again before this came back —
                    // this response is for the stale one, discard it rather than overwrite
                    // whatever the newer request is about to deliver.
                    return
                }
                state.attributes = preview?.attributes ?? []
                state.isLoadingAttributes = false
            }
        })
    }

    func presentPicker(title: String, options: [(String, () -> Void)]) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let sheet = ActionSheetController(presentationData: presentationData)
        var buttons: [ActionSheetItem] = [ActionSheetTextItem(title: title)]
        for (label, action) in options {
            buttons.append(ActionSheetButtonItem(title: label, color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                action()
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

    let arguments = PampGramGiftConstructorArguments(
        pickBaseGift: {
            let _ = (statePromise.get() |> take(1) |> deliverOnMainQueue).start(next: { state in
                guard !state.baseGiftOptions.isEmpty else {
                    presentTooltipImpl?("Каталог подарков ещё загружается.")
                    return
                }
                presentPicker(title: "Какой подарок?", options: state.baseGiftOptions.map { gift in
                    (gift.title ?? "Подарок", {
                        updateState { s in
                            s.baseGift = gift
                            s.model = nil
                            s.backdrop = nil
                            s.pattern = nil
                        }
                        loadAttributes(for: gift)
                    })
                })
            })
        },
        pickModel: {
            let _ = (statePromise.get() |> take(1) |> deliverOnMainQueue).start(next: { state in
                let models = state.attributes.filter(pampGramIsModel)
                guard !models.isEmpty else {
                    presentTooltipImpl?(state.baseGift == nil ? "Сначала выберите подарок." : "Подождите, варианты ещё загружаются.")
                    return
                }
                presentPicker(title: "Какая модель?", options: models.map { attribute in
                    (pampGramAttributeName(attribute), {
                        updateState { s in s.model = attribute }
                    })
                })
            })
        },
        pickBackdrop: {
            let _ = (statePromise.get() |> take(1) |> deliverOnMainQueue).start(next: { state in
                let backdrops = state.attributes.filter(pampGramIsBackdrop)
                guard !backdrops.isEmpty else {
                    presentTooltipImpl?(state.baseGift == nil ? "Сначала выберите подарок." : "Подождите, варианты ещё загружаются.")
                    return
                }
                presentPicker(title: "Какой фон?", options: backdrops.map { attribute in
                    (pampGramAttributeName(attribute), {
                        updateState { s in s.backdrop = attribute }
                    })
                })
            })
        },
        pickPattern: {
            let _ = (statePromise.get() |> take(1) |> deliverOnMainQueue).start(next: { state in
                let patterns = state.attributes.filter(pampGramIsPattern)
                guard !patterns.isEmpty else {
                    presentTooltipImpl?(state.baseGift == nil ? "Сначала выберите подарок." : "Подождите, варианты ещё загружаются.")
                    return
                }
                presentPicker(title: "Какой символ?", options: patterns.map { attribute in
                    (pampGramAttributeName(attribute), {
                        updateState { s in s.pattern = attribute }
                    })
                })
            })
        },
        pickNumber: {
            presentControllerImpl?(promptController(
                context: context,
                text: "Номер подарка",
                subtitle: "Любое число — просто отображается как #номер.",
                value: "",
                placeholder: "Например, 42",
                characterLimit: 7,
                apply: { value in
                    guard let text = value, let number = Int32(text), number > 0 else {
                        return
                    }
                    updateState { s in s.number = number }
                }
            ))
        },
        randomize: {
            let _ = (statePromise.get() |> take(1) |> deliverOnMainQueue).start(next: { state in
                guard !state.baseGiftOptions.isEmpty else {
                    presentTooltipImpl?("Каталог подарков ещё загружается.")
                    return
                }
                let gift = state.baseGiftOptions.randomElement()!
                updateState { s in
                    s.baseGift = gift
                    s.model = nil
                    s.backdrop = nil
                    s.pattern = nil
                    s.number = Int32.random(in: 1...9999)
                }
                let _ = (context.engine.payments.starGiftUpgradePreview(giftId: gift.id)
                |> deliverOnMainQueue).start(next: { preview in
                    let attributes = preview?.attributes ?? []
                    updateState { s in
                        guard s.baseGift?.id == gift.id else { return }
                        s.attributes = attributes
                        s.isLoadingAttributes = false
                        s.model = attributes.filter(pampGramIsModel).randomElement()
                        s.backdrop = attributes.filter(pampGramIsBackdrop).randomElement()
                        s.pattern = attributes.filter(pampGramIsPattern).randomElement()
                    }
                })
            })
        },
        save: {
            let _ = (statePromise.get() |> take(1) |> deliverOnMainQueue).start(next: { state in
                guard let baseGift = state.baseGift, let model = state.model, let backdrop = state.backdrop, let pattern = state.pattern else {
                    presentTooltipImpl?("Выберите подарок, модель, фон и символ.")
                    return
                }
                let title = pampGramAttributeName(model)
                let _ = (PampGramPhantomGiftManager.constructUniqueGift(context: context, baseGift: baseGift, title: title, model: model, backdrop: backdrop, pattern: pattern, number: state.number)
                |> deliverOnMainQueue).start(next: { _ in
                    presentTooltipImpl?("Сохранено в профиль: «\(title)».")
                })
            })
        },
        openSaved: { gift in
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let sheet = ActionSheetController(presentationData: presentationData)
            sheet.setItemGroups([
                ActionSheetItemGroup(items: [
                    ActionSheetTextItem(title: gift.number.map { "\(gift.title) #\($0)" } ?? gift.title),
                    ActionSheetButtonItem(title: "Удалить", color: .destructive, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                        let _ = context.account.postbox.transaction { transaction in
                            PampGramPhantomGiftStore.remove(transaction: transaction, id: gift.id)
                        }.start()
                    })
                ]),
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
        statePromise.get(),
        PampGramPhantomGiftStore.allGiftsSignal(context: context)
    )
    |> deliverOnMainQueue
    |> map { presentationData, state, allGifts -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let savedGifts = allGifts.filter { $0.isConstructed && $0.peerId == context.account.peerId }
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Конструктор подарка"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: pampGramGiftConstructorEntries(state: state, savedGifts: savedGifts),
            style: .blocks,
            animateChanges: true
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    presentTooltipImpl = { [weak controller] text in
        guard let controller else { return }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        controller.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), in: .current)
    }
    return controller
}
