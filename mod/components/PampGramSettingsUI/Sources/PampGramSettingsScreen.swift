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
import PhantomGiftKit

private final class PampGramSettingsArguments {
    let togglePhantomGifts: (Bool) -> Void
    let toggleFakeStarsDisplay: (Bool) -> Void
    let toggleFakeTonDisplay: (Bool) -> Void
    let editStarsBalance: () -> Void
    let editTonBalance: () -> Void
    let resetBalances: () -> Void
    let deleteAllPhantomGifts: () -> Void

    init(
        togglePhantomGifts: @escaping (Bool) -> Void,
        toggleFakeStarsDisplay: @escaping (Bool) -> Void,
        toggleFakeTonDisplay: @escaping (Bool) -> Void,
        editStarsBalance: @escaping () -> Void,
        editTonBalance: @escaping () -> Void,
        resetBalances: @escaping () -> Void,
        deleteAllPhantomGifts: @escaping () -> Void
    ) {
        self.togglePhantomGifts = togglePhantomGifts
        self.toggleFakeStarsDisplay = toggleFakeStarsDisplay
        self.toggleFakeTonDisplay = toggleFakeTonDisplay
        self.editStarsBalance = editStarsBalance
        self.editTonBalance = editTonBalance
        self.resetBalances = resetBalances
        self.deleteAllPhantomGifts = deleteAllPhantomGifts
    }
}

private enum PampGramSettingsSection: Int32 {
    case about
    case phantomGifts
    case starsBalance
    case tonBalance
    case resetBalances
    case storage
}

private enum PampGramSettingsEntry: ItemListNodeEntry {
    case aboutText(String)

    case phantomGiftsHeader(String)
    case phantomGiftsToggle(String, Bool)
    case phantomGiftsFooter(String)

    case starsBalanceHeader(String)
    case fakeStarsDisplayToggle(String, Bool)
    case starsBalance(String, String)
    case starsBalanceFooter(String)

    case tonBalanceHeader(String)
    case fakeTonDisplayToggle(String, Bool)
    case tonBalance(String, String)
    case tonBalanceFooter(String)

    case resetBalances(String)
    case resetBalancesFooter(String)

    case storageHeader(String)
    case phantomGiftsCount(String, String)
    case deleteAllPhantomGifts(String, Bool)
    case storageFooter(String)

    var section: ItemListSectionId {
        switch self {
        case .aboutText:
            return PampGramSettingsSection.about.rawValue
        case .phantomGiftsHeader, .phantomGiftsToggle, .phantomGiftsFooter:
            return PampGramSettingsSection.phantomGifts.rawValue
        case .starsBalanceHeader, .fakeStarsDisplayToggle, .starsBalance, .starsBalanceFooter:
            return PampGramSettingsSection.starsBalance.rawValue
        case .tonBalanceHeader, .fakeTonDisplayToggle, .tonBalance, .tonBalanceFooter:
            return PampGramSettingsSection.tonBalance.rawValue
        case .resetBalances, .resetBalancesFooter:
            return PampGramSettingsSection.resetBalances.rawValue
        case .storageHeader, .phantomGiftsCount, .deleteAllPhantomGifts, .storageFooter:
            return PampGramSettingsSection.storage.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .aboutText:
            return 0
        case .phantomGiftsHeader:
            return 1
        case .phantomGiftsToggle:
            return 2
        case .phantomGiftsFooter:
            return 3
        case .starsBalanceHeader:
            return 4
        case .fakeStarsDisplayToggle:
            return 5
        case .starsBalance:
            return 6
        case .starsBalanceFooter:
            return 7
        case .tonBalanceHeader:
            return 8
        case .fakeTonDisplayToggle:
            return 9
        case .tonBalance:
            return 10
        case .tonBalanceFooter:
            return 11
        case .resetBalances:
            return 12
        case .resetBalancesFooter:
            return 13
        case .storageHeader:
            return 14
        case .phantomGiftsCount:
            return 15
        case .deleteAllPhantomGifts:
            return 16
        case .storageFooter:
            return 17
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
        case let .phantomGiftsHeader(text), let .starsBalanceHeader(text), let .tonBalanceHeader(text), let .storageHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .phantomGiftsFooter(text), let .starsBalanceFooter(text), let .tonBalanceFooter(text), let .resetBalancesFooter(text), let .storageFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .phantomGiftsToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.togglePhantomGifts(value)
            })
        case let .fakeStarsDisplayToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleFakeStarsDisplay(value)
            })
        case let .fakeTonDisplayToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleFakeTonDisplay(value)
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
        case let .phantomGiftsCount(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, enabled: false, label: label, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case let .deleteAllPhantomGifts(title, enabled):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: enabled ? .destructive : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.deleteAllPhantomGifts()
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

private func pampGramSettingsEntries(settings: PampGramSettings, phantomGiftCount: Int) -> [PampGramSettingsEntry] {
    var entries: [PampGramSettingsEntry] = []

    entries.append(.aboutText("PampGram меняет только то, что видите вы на этом устройстве. Ничего из перечисленного ниже не отправляется в Telegram, не меняет состояние чужого аккаунта, не трогает настоящие Stars и не создаёт настоящие подарки."))

    entries.append(.phantomGiftsHeader("ЛОКАЛЬНЫЕ ПОДАРКИ"))
    entries.append(.phantomGiftsToggle("Вкладка «Подарок»", settings.phantomGiftsEnabled))
    entries.append(.phantomGiftsFooter("Пока включено, при отправке подарка появляется 4-я вкладка «Подарок» — тот же настоящий маркет Telegram, что и во вкладке «Все» (те же обычные и коллекционные подарки, те же настоящие предложения других пользователей). Отличие только в покупке: любая покупка, начатая из вкладки «Подарок», проходит визуально — диалог и анимация настоящие, но списывается локальный баланс, а не настоящие Stars или TON, лот никто не покупает по-настоящему и остаётся в маркете, собеседник ничего не получает и не видит. Вкладки «Все», «Мои» и «Коллекционные» всегда работают как в оригинальном Telegram."))

    entries.append(.starsBalanceHeader("ЛОКАЛЬНЫЕ ЗВЁЗДЫ"))
    entries.append(.fakeStarsDisplayToggle("Локальные звёзды", settings.fakeStarsDisplayEnabled))
    entries.append(.starsBalance("Фантом-Stars", "\(settings.fakeStarsBalance)"))
    entries.append(.starsBalanceFooter("Решает, показывается ли этот фейковый баланс вместо настоящего — в списке настроек Telegram, на экране «Мои звёзды» и в шапке отправки подарка. Выключение не сбрасывает число ниже — оно просто перестаёт показываться, пока переключатель снова не включат. Настоящий баланс Stars вашего аккаунта этот счётчик не читает и не меняет — Telegram о нём ничего не знает."))

    entries.append(.tonBalanceHeader("ЛОКАЛЬНЫЕ TON/GRAM"))
    entries.append(.fakeTonDisplayToggle("Локальные TON/GRAM", settings.fakeTonDisplayEnabled))
    entries.append(.tonBalance("Фантом-TON", formatFakeTon(nanos: settings.fakeTonBalanceNanos)))
    entries.append(.tonBalanceFooter("То же самое, но для TON/GRAM — независимо от переключателя звёзд выше: показывается на экране «Мои GRAM» и в шапке отправки подарка. Настоящий баланс TON вашего аккаунта этот счётчик не читает и не меняет."))

    entries.append(.resetBalances("Сбросить балансы"))
    entries.append(.resetBalancesFooter("Возвращает оба счётчика — Фантом-Stars и Фантом-TON — к значениям по умолчанию."))

    entries.append(.storageHeader("ЛОКАЛЬНЫЕ ДАННЫЕ"))
    entries.append(.phantomGiftsCount("Фантом-подарков на устройстве", "\(phantomGiftCount)"))
    entries.append(.deleteAllPhantomGifts("Удалить все фантом-подарки", phantomGiftCount > 0))
    entries.append(.storageFooter("Удаление уберёт и сами записи, и их сообщения из вашей истории чатов. Всё это хранится только на этом устройстве."))

    return entries
}

/// The "Подарки" section: everything about the "Подарок" tab and PampGram's local play-money
/// balances. Split out of what used to be the single PampGram settings screen — see
/// `PampGramHubScreen.swift` for the 5-section hub this is now pushed from.
public func pampGramGiftsSettingsController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    var presentTooltipImpl: ((String) -> Void)?

    let arguments = PampGramSettingsArguments(
        togglePhantomGifts: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.phantomGiftsEnabled = value
                return settings
            }).start()
        },
        toggleFakeStarsDisplay: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.fakeStarsDisplayEnabled = value
                return settings
            }).start()
        },
        toggleFakeTonDisplay: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.fakeTonDisplayEnabled = value
                return settings
            }).start()
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
        },
        deleteAllPhantomGifts: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let theme = AlertControllerTheme(presentationData: presentationData)
            let font = Font.regular(floor(theme.baseFontSize * 13.0 / 17.0))
            presentControllerImpl?(textAlertController(
                theme: theme,
                title: NSAttributedString(string: "Удалить все фантом-подарки?", font: Font.semibold(theme.baseFontSize), textColor: theme.primaryColor, paragraphAlignment: .center),
                text: NSAttributedString(string: "Записи и их сообщения исчезнут из вашей истории. Это действие нельзя отменить.", font: font, textColor: theme.primaryColor, paragraphAlignment: .center),
                actions: [
                    TextAlertAction(type: .genericAction, title: "Отмена", action: {}),
                    TextAlertAction(type: .destructiveAction, title: "Удалить", action: {
                        let _ = (PampGramPhantomGiftManager.deleteAll(context: context)
                        |> deliverOnMainQueue).start(completed: {
                            presentTooltipImpl?("Все фантом-подарки удалены.")
                        })
                    }),
                ],
                actionLayout: .horizontal
            ))
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        PampGramCore.settingsSignal(postbox: context.account.postbox),
        PampGramPhantomGiftStore.allGiftsSignal(context: context)
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings, phantomGifts -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Подарки"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: pampGramSettingsEntries(settings: settings, phantomGiftCount: phantomGifts.count),
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
