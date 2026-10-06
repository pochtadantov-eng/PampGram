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

private struct PampGramGiftAdderCatalog {
    var gifts: [StarGift.Gift]?
}

private final class PampGramGiftAdderArguments {
    let add: (StarGift.Gift) -> Void

    init(add: @escaping (StarGift.Gift) -> Void) {
        self.add = add
    }
}

private enum PampGramGiftAdderEntry: ItemListNodeEntry {
    case about(String)
    case loading(String)
    case gift(Int32, StarGift.Gift)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case .about: return 0
        case .loading: return 1
        case let .gift(index, _): return 10 + index
        }
    }

    static func ==(lhs: PampGramGiftAdderEntry, rhs: PampGramGiftAdderEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.about(a), .about(b)):
            return a == b
        case let (.loading(a), .loading(b)):
            return a == b
        case let (.gift(ai, ag), .gift(bi, bg)):
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
        case let .about(text), let .loading(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .gift(_, gift):
            var label = "\(gift.price) ⭐"
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

    let giftsPromise = Promise<PampGramGiftAdderCatalog>(PampGramGiftAdderCatalog(gifts: nil))
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
        giftsPromise.set(.single(PampGramGiftAdderCatalog(gifts: generic.sorted(by: { $0.price > $1.price }))))
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
            .about("Нажмите на подарок — он появится в вашем профиле (только у вас, бесплатно). У подарков с пометкой NFT откройте карточку и нажмите «Улучшить»: пойдёт настоящая анимация Telegram и подарок станет уникальным. Улучшение списывается с локального баланса звёзд.")
        ]
        if let gifts = catalog.gifts {
            for (index, gift) in gifts.enumerated() {
                entries.append(.gift(Int32(index), gift))
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
    presentTooltipImpl = { [weak controller] text in
        guard let controller else { return }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        controller.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), in: .current)
    }
    return controller
}
