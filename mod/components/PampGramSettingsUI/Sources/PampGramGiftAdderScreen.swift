import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import PhantomGiftKit
import UndoUI
import PromptUI

private struct PampGramGiftAdderCatalog {
    var gifts: [StarGift.Gift]?
    var query: String = ""
}

/// Telegram's gift titles come from the server in English, so the search also understands a few
/// Russian words people actually type for the well-known ones.
private let pampGramGiftSearchAliases: [(words: [String], fragment: String)] = [
    (["ролекс", "часы", "часики"], "watch"),
    (["пепе", "пепа", "лягушка"], "pepe"),
    (["кольцо", "перстень", "печатка"], "ring"),
    (["кепка", "шапка"], "cap"),
    (["сердце", "медальон"], "locket"),
    (["торт", "тортик"], "cake"),
    (["мишка", "медведь"], "bear"),
    (["ракета"], "rocket"),
    (["роза", "цветок", "цветы"], "rose"),
    (["персик"], "peach"),
    (["шар", "шарик"], "balloon"),
    (["кубок"], "cup")
]

private func pampGramGiftMatches(_ gift: StarGift.Gift, query: String) -> Bool {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if query.isEmpty {
        return true
    }
    let title = (gift.title ?? "").lowercased()
    if title.contains(query) {
        return true
    }
    for alias in pampGramGiftSearchAliases {
        if alias.words.contains(where: { $0.hasPrefix(query) || query.hasPrefix($0) }) && title.contains(alias.fragment) {
            return true
        }
    }
    return false
}

private final class PampGramGiftAdderArguments {
    let add: (StarGift.Gift) -> Void
    let search: () -> Void

    init(add: @escaping (StarGift.Gift) -> Void, search: @escaping () -> Void) {
        self.add = add
        self.search = search
    }
}

private enum PampGramGiftAdderEntry: ItemListNodeEntry {
    case about(String)
    case search(String)
    case loading(String)
    case limitedHeader(String)
    case limitedGift(Int32, StarGift.Gift)
    case regularHeader(String)
    case regularGift(Int32, StarGift.Gift)
    case empty(String)

    var section: ItemListSectionId {
        switch self {
        case .about, .search, .loading, .empty:
            return 0
        case .limitedHeader, .limitedGift:
            return 1
        case .regularHeader, .regularGift:
            return 2
        }
    }

    var stableId: Int32 {
        switch self {
        case .about: return 0
        case .search: return 1
        case .loading: return 2
        case .empty: return 3
        case .limitedHeader: return 4
        case let .limitedGift(index, _): return 100 + index
        case .regularHeader: return 100_000
        case let .regularGift(index, _): return 100_001 + index
        }
    }

    static func ==(lhs: PampGramGiftAdderEntry, rhs: PampGramGiftAdderEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.about(a), .about(b)):
            return a == b
        case let (.search(a), .search(b)):
            return a == b
        case let (.loading(a), .loading(b)):
            return a == b
        case let (.empty(a), .empty(b)):
            return a == b
        case let (.limitedHeader(a), .limitedHeader(b)):
            return a == b
        case let (.regularHeader(a), .regularHeader(b)):
            return a == b
        case let (.limitedGift(ai, ag), .limitedGift(bi, bg)):
            return ai == bi && ag == bg
        case let (.regularGift(ai, ag), .regularGift(bi, bg)):
            return ai == bi && ag == bg
        default:
            return false
        }
    }

    static func <(lhs: PampGramGiftAdderEntry, rhs: PampGramGiftAdderEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramGiftAdderArguments
        switch self {
        case let .about(text), let .loading(text), let .empty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .search(query):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: generatePampGramSectionIcon(systemName: "magnifyingglass", backgroundColor: UIColor(rgb: 0x8e8e93)),
                title: "Поиск по названию",
                label: query.isEmpty ? "Например, Plush Pepe или ролекс" : query,
                sectionId: self.section,
                style: .blocks,
                action: { arguments.search() }
            )
        case let .limitedHeader(text), let .regularHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .limitedGift(_, gift), let .regularGift(_, gift):
            var label = "\(gift.price) ⭐"
            if gift.soldOut != nil {
                label += " · раскуплен"
            } else if gift.availability != nil {
                label += " · лимит"
            }
            if gift.upgradeStars != nil {
                label += " · NFT"
            }
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: gift.title ?? "Подарок",
                label: label,
                sectionId: self.section,
                style: .blocks,
                action: { arguments.add(gift) }
            )
        }
    }
}

/// "Добавить подарок в профиль": the whole real gift catalog — Plush Pepe down to a lollipop —
/// as one tappable list. A tap drops the plain gift straight into the own profile (local, free,
/// see `PampGramPhantomGiftManager.addGenericGiftToProfile`); the profile card then offers the
/// ordinary "Улучшить" button for every gift that can be upgraded, run locally.
public func pampGramGiftAdderController(context: AccountContext) -> ViewController {
    var presentTooltipImpl: ((String) -> Void)?
    var presentControllerImpl: ((ViewController) -> Void)?

    let giftsPromise = Promise<PampGramGiftAdderCatalog>(PampGramGiftAdderCatalog(gifts: nil))
    func updateCatalog(_ f: @escaping (inout PampGramGiftAdderCatalog) -> Void) {
        let _ = (giftsPromise.get() |> take(1) |> deliverOnMainQueue).start(next: { current in
            var catalog = current
            f(&catalog)
            giftsPromise.set(.single(catalog))
        })
    }

    let refreshDisposable = MetaDisposable()
    refreshDisposable.set(context.engine.payments.keepStarGiftsUpdated().start())
    let _ = (context.engine.payments.cachedStarGifts()
    |> filter { $0 != nil }
    |> take(1)
    |> deliverOnMainQueue).start(next: { gifts in
        refreshDisposable.dispose()
        let generic: [StarGift.Gift] = (gifts ?? []).compactMap { starGift in
            if case let .generic(gift) = starGift {
                return gift
            }
            return nil
        }
        // Most expensive first: that's where the rare collectibles sit.
        updateCatalog { $0.gifts = generic.sorted(by: { $0.price > $1.price }) }
    })

    let arguments = PampGramGiftAdderArguments(add: { gift in
        let _ = (PampGramPhantomGiftManager.addGenericGiftToProfile(context: context, gift: gift)
        |> deliverOnMainQueue).start(next: { _ in
            if gift.upgradeStars != nil {
                presentTooltipImpl?("«\(gift.title ?? "Подарок")» добавлен в профиль. Откройте его — там кнопка «Улучшить».")
            } else {
                presentTooltipImpl?("«\(gift.title ?? "Подарок")» добавлен в профиль.")
            }
        })
    }, search: {
        let _ = (giftsPromise.get() |> take(1) |> deliverOnMainQueue).start(next: { catalog in
            presentControllerImpl?(promptController(
                context: context,
                text: "Поиск подарка",
                subtitle: "Название на английском или русское слово: ролекс, пепе, кольцо. Пусто — показать всё.",
                value: catalog.query,
                placeholder: "Название",
                characterLimit: 40,
                apply: { value in
                    let query = value ?? ""
                    updateCatalog { $0.query = query }
                }
            ))
        })
    })

    let signal = combineLatest(
        context.sharedContext.presentationData,
        giftsPromise.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, catalog -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Добавить подарок"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        var entries: [PampGramGiftAdderEntry] = [
            .about("Нажмите на подарок — он появится в вашем профиле (только у вас, бесплатно). У подарков с пометкой NFT откройте карточку и нажмите «Улучшить»: пойдёт настоящая анимация Telegram и подарок станет уникальным. Улучшение списывается с локального баланса звёзд."),
            .search(catalog.query)
        ]
        if let gifts = catalog.gifts {
            let matching = gifts.filter { pampGramGiftMatches($0, query: catalog.query) }
            // Limited-supply and sold-out gifts (watches, rings, Plush Pepe and the like) first —
            // those are the ones people look for — then the ordinary unlimited ones.
            let limited = matching.filter { $0.soldOut != nil || $0.availability != nil }
            let regular = matching.filter { $0.soldOut == nil && $0.availability == nil }
            if matching.isEmpty {
                entries.append(.empty("Ничего не найдено."))
            }
            if !limited.isEmpty {
                entries.append(.limitedHeader("ЛИМИТИРОВАННЫЕ И РАСКУПЛЕННЫЕ (\(limited.count))"))
                for (index, gift) in limited.enumerated() {
                    entries.append(.limitedGift(Int32(index), gift))
                }
            }
            if !regular.isEmpty {
                entries.append(.regularHeader("ОБЫЧНЫЕ (\(regular.count))"))
                for (index, gift) in regular.enumerated() {
                    entries.append(.regularGift(Int32(index), gift))
                }
            }
        } else {
            entries.append(.loading("Каталог подарков загружается…"))
        }
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks,
            animateChanges: false
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
