import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import PromptUI
import UndoUI
import PampGramCore

private final class PampGramSettingsArguments {
    let openStarGiftMarketplace: () -> Void
    let editStarsBalance: () -> Void
    let editTonBalance: () -> Void
    let resetBalances: () -> Void

    init(
        openStarGiftMarketplace: @escaping () -> Void,
        editStarsBalance: @escaping () -> Void,
        editTonBalance: @escaping () -> Void,
        resetBalances: @escaping () -> Void
    ) {
        self.openStarGiftMarketplace = openStarGiftMarketplace
        self.editStarsBalance = editStarsBalance
        self.editTonBalance = editTonBalance
        self.resetBalances = resetBalances
    }
}

private enum PampGramSettingsSection: Int32 {
    case about
    case starGiftMarketplace
    case balances
}

private enum PampGramSettingsEntry: ItemListNodeEntry {
    case aboutText(String)

    case starGiftMarketplaceHeader(String)
    case openStarGiftMarketplace(String)
    case starGiftMarketplaceFooter(String)

    case balancesHeader(String)
    case starsBalance(String, String)
    case tonBalance(String, String)
    case resetBalances(String)
    case balancesFooter(String)

    var section: ItemListSectionId {
        switch self {
        case .aboutText:
            return PampGramSettingsSection.about.rawValue
        case .starGiftMarketplaceHeader, .openStarGiftMarketplace, .starGiftMarketplaceFooter:
            return PampGramSettingsSection.starGiftMarketplace.rawValue
        case .balancesHeader, .starsBalance, .tonBalance, .resetBalances, .balancesFooter:
            return PampGramSettingsSection.balances.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .aboutText:
            return 0
        case .starGiftMarketplaceHeader:
            return 1
        case .openStarGiftMarketplace:
            return 2
        case .starGiftMarketplaceFooter:
            return 3
        case .balancesHeader:
            return 4
        case .starsBalance:
            return 5
        case .tonBalance:
            return 6
        case .resetBalances:
            return 7
        case .balancesFooter:
            return 8
        }
    }

    static func <(lhs: PampGramSettingsEntry, rhs: PampGramSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramSettingsArguments
        switch self {
        case let .aboutText(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .starGiftMarketplaceHeader(text), let .balancesHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .starGiftMarketplaceFooter(text), let .balancesFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .openStarGiftMarketplace(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.openStarGiftMarketplace()
            })
        case let .starsBalance(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.editStarsBalance()
            })
        case let .tonBalance(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.editTonBalance()
            })
        case let .resetBalances(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.resetBalances()
            })
        }
    }
}

/// Formats nanotons as a plain TON amount with up to 9 decimals and no trailing zeroes.
/// Hand-rolled on purpose: the real TON formatters live behind the wallet/Stars UI, and
/// this is a play-money counter that must never be mistaken for a real wallet balance.
private func formatFakeTon(nanos: Int64) -> String {
    let sign = nanos < 0 ? "-" : ""
    let magnitude = nanos.magnitude
    let whole = magnitude / 1_000_000_000
    let fraction = magnitude % 1_000_000_000
    if fraction == 0 {
        return "\(sign)\(whole)"
    }
    // Padded by hand rather than with String(format:): the value is a UInt64 and there is
    // no length modifier here that would take one safely.
    var fractionString = String(fraction)
    while fractionString.count < 9 {
        fractionString = "0" + fractionString
    }
    while fractionString.hasSuffix("0") {
        fractionString.removeLast()
    }
    return "\(sign)\(whole).\(fractionString)"
}

/// Parses what the user typed back into nanotons, accepting both "1.5" and "1,5" and
/// ignoring spaces. Returns nil for anything that isn't a plain non-negative number.
private func parseFakeTon(_ text: String) -> Int64? {
    let normalized = text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ".")
    if normalized.isEmpty {
        return nil
    }
    let parts = normalized.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    guard let wholePart = parts.first else {
        return nil
    }
    let wholeString = wholePart.isEmpty ? "0" : String(wholePart)
    guard wholeString.allSatisfy({ $0.isNumber }), let whole = Int64(wholeString) else {
        return nil
    }
    var fraction: Int64 = 0
    if parts.count == 2 {
        var fractionString = String(parts[1])
        guard fractionString.allSatisfy({ $0.isNumber }) else {
            return nil
        }
        if fractionString.count > 9 {
            fractionString = String(fractionString.prefix(9))
        }
        while fractionString.count < 9 {
            fractionString.append("0")
        }
        guard let value = Int64(fractionString) else {
            return nil
        }
        fraction = value
    }
    let maxWhole = (Int64.max - fraction) / 1_000_000_000
    guard whole <= maxWhole else {
        return nil
    }
    return whole * 1_000_000_000 + fraction
}

private func parseFakeStars(_ text: String) -> Int64? {
    let normalized = text.replacingOccurrences(of: " ", with: "")
    guard !normalized.isEmpty, normalized.allSatisfy({ $0.isNumber }) else {
        return nil
    }
    return Int64(normalized)
}

private func pampGramSettingsEntries(settings: PampGramSettings) -> [PampGramSettingsEntry] {
    var entries: [PampGramSettingsEntry] = []

    entries.append(.aboutText("PampGram позволяет просматривать и отправлять подарки из маркетплейса Telegram. Вкладка показывает все доступные подарки со звёздами и позволяет покупать и отправлять их прямо из PampGram."))

    entries.append(.starGiftMarketplaceHeader("МАРКЕТПЛЕЙС ПОДАРКОВ"))
    entries.append(.openStarGiftMarketplace("Вкладка подарков Telegram"))
    entries.append(.starGiftMarketplaceFooter("Откройте вкладку с реальным маркетплейсом подарков Telegram. Все подарки покупаются за настоящие звёзды и отправляются как обычные подарки."))

    entries.append(.balancesHeader("ЛОКАЛЬНЫЕ БАЛАНСЫ"))
    entries.append(.starsBalance("Фантом-Stars", "\(settings.fakeStarsBalance)"))
    entries.append(.tonBalance("Фантом-TON", formatFakeTon(nanos: settings.fakeTonBalanceNanos)))
    entries.append(.resetBalances("Сбросить балансы"))
    entries.append(.balancesFooter("Это счётчики самого мода для тестирования. Настоящий баланс Stars вашего аккаунта не изменяется."))

    return entries
}

public func pampGramSettingsController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    var presentTooltipImpl: ((String) -> Void)?

    let arguments = PampGramSettingsArguments(
        openStarGiftMarketplace: {
            let controller = RealStarGiftMarketplaceController(context: context, peerId: context.account.peerId)
            presentControllerImpl?(controller)
        },
        editStarsBalance: {
            let _ = (context.account.postbox.transaction { transaction -> Int64 in
                return PampGramCore.settings(transaction: transaction).fakeStarsBalance
            }
            |> deliverOnMainQueue).start(next: { current in
                presentControllerImpl?(promptController(
                    context: context,
                    text: "Фантом-Stars",
                    subtitle: "Локальный счётчик мода. На настоящий баланс Stars это не влияет.",
                    value: "\(current)",
                    characterLimit: 18,
                    apply: { value in
                        guard let value, let stars = parseFakeStars(value) else {
                            return
                        }
                        let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                            var settings = settings
                            settings.fakeStarsBalance = stars
                            return settings
                        }).start()
                    }
                ))
            })
        },
        editTonBalance: {
            let _ = (context.account.postbox.transaction { transaction -> Int64 in
                return PampGramCore.settings(transaction: transaction).fakeTonBalanceNanos
            }
            |> deliverOnMainQueue).start(next: { current in
                presentControllerImpl?(promptController(
                    context: context,
                    text: "Фантом-TON",
                    subtitle: "Локальный счётчик мода. Кошелька у PampGram нет и никакие средства он не переводит.",
                    value: formatFakeTon(nanos: current),
                    characterLimit: 24,
                    apply: { value in
                        guard let value, let nanos = parseFakeTon(value) else {
                            return
                        }
                        let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                            var settings = settings
                            settings.fakeTonBalanceNanos = nanos
                            return settings
                        }).start()
                    }
                ))
            })
        },
        resetBalances: {
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.fakeStarsBalance = PampGramSettings.defaultFakeStarsBalance
                settings.fakeTonBalanceNanos = PampGramSettings.defaultFakeTonBalanceNanos
                return settings
            }).start()
            presentTooltipImpl?("Локальные балансы сброшены.")
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
            title: .text("PampGram"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: pampGramSettingsEntries(settings: settings),
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
        guard let controller else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        controller.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), in: .current)
    }
    return controller
}
