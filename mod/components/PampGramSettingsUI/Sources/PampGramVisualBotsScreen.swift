import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import PromptUI
import UndoUI
import PampGramCore
import PhantomGiftKit

// MARK: - Known currencies

/// One row of the UI's currency picker — the subset of real xRocket / Crypto Bot assets the
/// section surfaces by default. Users can still see any other currency a bot already holds (the
/// store's balance table is keyed by free-form code), but new ones are added through this list
/// so a typo doesn't create a parallel "Usdt" wallet next to the real "USDT" one.
private struct PampGramVisualCurrency {
    let code: String
    let decimals: Int
    let emoji: String
}

/// Picker list, ordered by how often each asset shows up on the real bots. Decimals match each
/// chain's smallest whole unit; `Int64` holds 1 ETH worth of wei with 10× headroom, so even
/// 18-decimal currencies work for play amounts without needing a bigger integer type.
private let pampGramKnownCurrencies: [PampGramVisualCurrency] = [
    PampGramVisualCurrency(code: "USDT", decimals: 6, emoji: "💵"),
    PampGramVisualCurrency(code: "TON", decimals: 9, emoji: "💎"),
    PampGramVisualCurrency(code: "BTC", decimals: 8, emoji: "🟡"),
    PampGramVisualCurrency(code: "ETH", decimals: 18, emoji: "🪙"),
    PampGramVisualCurrency(code: "BNB", decimals: 18, emoji: "🟠"),
    PampGramVisualCurrency(code: "LTC", decimals: 8, emoji: "⚪"),
    PampGramVisualCurrency(code: "SOL", decimals: 9, emoji: "🟣"),
    PampGramVisualCurrency(code: "TRX", decimals: 6, emoji: "🔺"),
    PampGramVisualCurrency(code: "DOGE", decimals: 8, emoji: "🐕"),
    PampGramVisualCurrency(code: "NOT", decimals: 9, emoji: "💠")
]

private func pampGramCurrencyInfo(code: String) -> PampGramVisualCurrency {
    return pampGramKnownCurrencies.first(where: { $0.code == code })
        ?? PampGramVisualCurrency(code: code, decimals: 2, emoji: "💲")
}

/// Divide `minorUnits` by `10^decimals` and render with at most 8 fractional digits. 8 is a
/// hard cap, not a derived one: ETH's 18-decimal representation would otherwise print rows
/// nobody can read, and 8 digits is already finer than any amount the user is likely to type
/// in — real xRocket/CryptoBot UIs clamp around 6-8 for the same reason.
private func pampGramFormatVisualAmount(currency: String, minorUnits: Int64) -> String {
    let info = pampGramCurrencyInfo(code: currency)
    let displayDecimals = min(info.decimals, 8)
    let divisor = pow(10.0, Double(info.decimals))
    let value = Double(minorUnits) / divisor
    return String(format: "%.\(displayDecimals)f %@", value, currency)
}

/// Same scaling as `pampGramFormatVisualAmount`, but suitable for prefilling a prompt — no
/// currency suffix (the sheet labels that separately) and trailing zeros trimmed so the
/// prompt reads as "100" instead of "100.000000". Returns an empty string for 0 so the
/// placeholder shows through.
private func pampGramFormatVisualAmountInput(currency: String, minorUnits: Int64) -> String {
    if minorUnits == 0 {
        return ""
    }
    let info = pampGramCurrencyInfo(code: currency)
    let displayDecimals = min(info.decimals, 8)
    let divisor = pow(10.0, Double(info.decimals))
    let value = Double(minorUnits) / divisor
    var text = String(format: "%.\(displayDecimals)f", value)
    if text.contains(".") {
        while text.hasSuffix("0") {
            text.removeLast()
        }
        if text.hasSuffix(".") {
            text.removeLast()
        }
    }
    return text
}

/// Parse free-form user input into `minorUnits`. Accepts both decimal separators (`.` and `,`)
/// because iOS Russian keyboards produce `,` by default. Returns nil for anything negative or
/// unparseable — the caller shows a tooltip instead of substituting a 0.
private func pampGramParseVisualAmount(currency: String, text: String) -> Int64? {
    let info = pampGramCurrencyInfo(code: currency)
    let normalized = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
    guard let value = Double(normalized), value.isFinite, value >= 0.0 else {
        return nil
    }
    let factor = pow(10.0, Double(info.decimals))
    let scaled = (value * factor).rounded()
    if scaled > Double(Int64.max) {
        return nil
    }
    return Int64(scaled)
}

// MARK: - Entries

private final class PampGramVisualBotsArguments {
    let toggleMaster: (Bool) -> Void
    let toggleBot: (String, Bool) -> Void
    let editBalance: (String, String) -> Void
    let addCurrency: (String) -> Void
    let transferFrom: (String) -> Void
    let createCheckFrom: (String) -> Void
    let redeemCheck: () -> Void
    let openHistory: () -> Void
    let resetBot: (String) -> Void

    init(
        toggleMaster: @escaping (Bool) -> Void,
        toggleBot: @escaping (String, Bool) -> Void,
        editBalance: @escaping (String, String) -> Void,
        addCurrency: @escaping (String) -> Void,
        transferFrom: @escaping (String) -> Void,
        createCheckFrom: @escaping (String) -> Void,
        redeemCheck: @escaping () -> Void,
        openHistory: @escaping () -> Void,
        resetBot: @escaping (String) -> Void
    ) {
        self.toggleMaster = toggleMaster
        self.toggleBot = toggleBot
        self.editBalance = editBalance
        self.addCurrency = addCurrency
        self.transferFrom = transferFrom
        self.createCheckFrom = createCheckFrom
        self.redeemCheck = redeemCheck
        self.openHistory = openHistory
        self.resetBot = resetBot
    }
}

/// Fixed section ids for the top and bottom chrome; each bot gets its own section id
/// computed from its index (`100 + idx`) so adding another bot in the future doesn't force
/// the already-stored ones to renumber.
private enum PampGramVisualBotsSection: Int32 {
    case master = 0
    case about = 1
    case global = 90
    case history = 200
    case footer = 201
}

private enum PampGramVisualBotsEntry: ItemListNodeEntry {
    case masterToggle(Bool)
    case masterFooter(String)

    case aboutText(String)

    case redeemCheck
    case historyRow(String)
    case globalFooter(String)
    case footer(String)

    // Bot rows (dynamic): sectionId = 100 + botIdx.
    case botHeader(Int, Int32, String)
    case botToggle(Int, Int32, String, String, Bool, Bool)        // (idx, sectionId, botId, title, value, enabled)
    case botBalance(Int, Int32, Int, String, String, String, Bool) // (idx, sectionId, balanceIdx, botId, currency, labelText, enabled)
    case botEmptyBalances(Int, Int32)
    case botAddCurrency(Int, Int32, String, Bool)                 // (idx, sectionId, botId, enabled)
    case botTransfer(Int, Int32, String, Bool)
    case botCreateCheck(Int, Int32, String, Bool)
    case botReset(Int, Int32, String, Bool)

    var section: ItemListSectionId {
        switch self {
        case .masterToggle, .masterFooter:
            return PampGramVisualBotsSection.master.rawValue
        case .aboutText:
            return PampGramVisualBotsSection.about.rawValue
        case .redeemCheck, .globalFooter:
            return PampGramVisualBotsSection.global.rawValue
        case .historyRow:
            return PampGramVisualBotsSection.history.rawValue
        case .footer:
            return PampGramVisualBotsSection.footer.rawValue
        case let .botHeader(_, sectionId, _),
             let .botToggle(_, sectionId, _, _, _, _),
             let .botBalance(_, sectionId, _, _, _, _, _),
             let .botEmptyBalances(_, sectionId),
             let .botAddCurrency(_, sectionId, _, _),
             let .botTransfer(_, sectionId, _, _),
             let .botCreateCheck(_, sectionId, _, _),
             let .botReset(_, sectionId, _, _):
            return sectionId
        }
    }

    /// Stable within one render pass: 8-digit prefix per section, bot index multiplied in,
    /// then a small per-entry constant. Keeps the global rows at the top and bottom distinct
    /// from any bot and lets `<` sort them without a lookup table.
    var stableId: Int64 {
        switch self {
        case .masterToggle:
            return 0
        case .masterFooter:
            return 1
        case .aboutText:
            return 2
        case let .botHeader(idx, _, _):
            return 10_000 + Int64(idx) * 100 + 0
        case let .botToggle(idx, _, _, _, _, _):
            return 10_000 + Int64(idx) * 100 + 1
        case let .botBalance(idx, _, balanceIdx, _, _, _, _):
            // Within one bot, rows are offset by `balanceIdx` — their rank in the sorted
            // balances list — so each currency row is unique and the order matches render.
            return 10_000 + Int64(idx) * 100 + 10 + Int64(balanceIdx)
        case let .botEmptyBalances(idx, _):
            return 10_000 + Int64(idx) * 100 + 9
        case let .botAddCurrency(idx, _, _, _):
            return 10_000 + Int64(idx) * 100 + 70
        case let .botTransfer(idx, _, _, _):
            return 10_000 + Int64(idx) * 100 + 71
        case let .botCreateCheck(idx, _, _, _):
            return 10_000 + Int64(idx) * 100 + 72
        case let .botReset(idx, _, _, _):
            return 10_000 + Int64(idx) * 100 + 73
        case .redeemCheck:
            return 90_000
        case .globalFooter:
            return 90_001
        case .historyRow:
            return 95_000
        case .footer:
            return 99_000
        }
    }

    static func ==(lhs: PampGramVisualBotsEntry, rhs: PampGramVisualBotsEntry) -> Bool {
        return lhs.stableId == rhs.stableId
    }

    static func <(lhs: PampGramVisualBotsEntry, rhs: PampGramVisualBotsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramVisualBotsArguments
        switch self {
        case let .masterToggle(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Включить визуалку", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleMaster(value)
            })
        case let .masterFooter(text), let .aboutText(text), let .globalFooter(text), let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .botHeader(_, _, title):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: title, sectionId: self.section)
        case let .botToggle(_, _, botId, title, value, enabled):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, enabled: enabled, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleBot(botId, value)
            })
        case let .botBalance(_, _, _, botId, currency, labelText, enabled):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: currency, enabled: enabled, label: labelText, sectionId: self.section, style: .blocks, action: {
                arguments.editBalance(botId, currency)
            })
        case .botEmptyBalances:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Пока нет кошельков. Добавьте валюту ниже."), sectionId: self.section)
        case let .botAddCurrency(_, _, botId, _):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Добавить валюту", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.addCurrency(botId)
            })
        case let .botTransfer(_, _, botId, _):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Перевести на другого бота", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.transferFrom(botId)
            })
        case let .botCreateCheck(_, _, botId, _):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Создать чек", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.createCheckFrom(botId)
            })
        case let .botReset(_, _, botId, _):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Обнулить балансы", kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.resetBot(botId)
            })
        case .redeemCheck:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Активировать чек", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.redeemCheck()
            })
        case let .historyRow(label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "История операций", label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openHistory()
            })
        }
    }
}

private func pampGramVisualBotsEntries(settings: PampGramSettings, bots: [PampGramVisualBot], operationCount: Int) -> [PampGramVisualBotsEntry] {
    var entries: [PampGramVisualBotsEntry] = []

    let masterOn = settings.visualBotsEnabled

    entries.append(.masterToggle(masterOn))
    entries.append(.masterFooter("Переводы, чеки и балансы существуют только на этом устройстве. Настоящие xRocket и Crypto Bot ничего об этом не знают."))

    entries.append(.aboutText("Включайте нужных ботов ниже. В чате с настоящим ботом (`@xrocket`, `@CryptoBot`) появится визуальный интерфейс с кошельком."))

    for (idx, bot) in bots.enumerated() {
        let sectionId: Int32 = 100 + Int32(idx)
        let header = "\(bot.displayName.uppercased()) · @\(bot.username)"
        entries.append(.botHeader(idx, sectionId, header))
        entries.append(.botToggle(idx, sectionId, bot.id, "Включить этого бота", bot.enabled, masterOn))

        let rowsEnabled = masterOn && bot.enabled
        if bot.balances.isEmpty {
            entries.append(.botEmptyBalances(idx, sectionId))
        } else {
            // Sort by the picker's order so USDT comes before BTC, then by code for anything
            // outside the picker — stable and predictable rather than preserving the mutation
            // order on disk.
            let sortedBalances = bot.balances.sorted(by: { lhs, rhs in
                let lhsIndex = pampGramKnownCurrencies.firstIndex(where: { $0.code == lhs.currency }) ?? Int.max
                let rhsIndex = pampGramKnownCurrencies.firstIndex(where: { $0.code == rhs.currency }) ?? Int.max
                if lhsIndex != rhsIndex {
                    return lhsIndex < rhsIndex
                }
                return lhs.currency < rhs.currency
            })
            for (balanceIdx, balance) in sortedBalances.enumerated() {
                let labelText = pampGramFormatVisualAmount(currency: balance.currency, minorUnits: balance.minorUnits)
                entries.append(.botBalance(idx, sectionId, balanceIdx, bot.id, balance.currency, labelText, rowsEnabled))
            }
        }

        if rowsEnabled {
            entries.append(.botAddCurrency(idx, sectionId, bot.id, true))
            entries.append(.botTransfer(idx, sectionId, bot.id, true))
            entries.append(.botCreateCheck(idx, sectionId, bot.id, true))
            if !bot.balances.isEmpty {
                entries.append(.botReset(idx, sectionId, bot.id, true))
            }
        }
    }

    entries.append(.redeemCheck)
    entries.append(.globalFooter("Чек погашается на этом же устройстве. Ссылка t.me/<бот>?start=<код> на другом телефоне откроет настоящего бота и ничего не сделает."))
    entries.append(.historyRow(operationCount == 0 ? "Пусто" : "\(operationCount)"))

    entries.append(.footer("Полностью локальные боты, балансы и переводы. Любая настоящая Telegram-операция остаётся нетронутой."))

    return entries
}

// MARK: - Pickers

private func pampGramPresentVisualCurrencyPicker(context: AccountContext, present: (ViewController) -> Void, title: String, excluded: Set<String> = [], pick: @escaping (String) -> Void) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let sheet = ActionSheetController(presentationData: presentationData)
    var buttons: [ActionSheetItem] = [ActionSheetTextItem(title: title)]
    for currency in pampGramKnownCurrencies where !excluded.contains(currency.code) {
        buttons.append(ActionSheetButtonItem(title: "\(currency.emoji) \(currency.code)", color: .accent, action: { [weak sheet] in
            sheet?.dismissAnimated()
            pick(currency.code)
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
    present(sheet)
}

private func pampGramPresentVisualBotPicker(context: AccountContext, present: (ViewController) -> Void, title: String, bots: [PampGramVisualBot], pick: @escaping (PampGramVisualBot) -> Void) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let sheet = ActionSheetController(presentationData: presentationData)
    var buttons: [ActionSheetItem] = [ActionSheetTextItem(title: title)]
    for bot in bots {
        buttons.append(ActionSheetButtonItem(title: bot.displayName, color: .accent, action: { [weak sheet] in
            sheet?.dismissAnimated()
            pick(bot)
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
    present(sheet)
}

// MARK: - Controller

/// "Визуальные боты" settings screen: lists the stored visual bots, lets the owner toggle each,
/// edit per-currency balances, move money between bots, and issue or redeem a local check. UI
/// code never writes to `PampGramVisualBot.balances` directly — every balance change goes
/// through `PampGramVisualBotStore.apply`/`.transfer`/`.createCheck`/`.redeemCheck`, so the
/// operation history stays complete and the "balances are a projection of operations" invariant
/// holds.
public func pampGramVisualBotsController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    var presentTooltipImpl: ((String) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?

    func withBots(_ f: @escaping ([PampGramVisualBot]) -> Void) {
        let _ = (context.account.postbox.transaction { transaction -> [PampGramVisualBot] in
            return PampGramVisualBotStore.allBots(transaction: transaction)
        }
        |> deliverOnMainQueue).start(next: f)
    }

    let editBalanceAction: (String, String) -> Void = { botId, currency in
        withBots { bots in
            guard let bot = bots.first(where: { $0.id == botId }) else { return }
            let currentUnits = bot.balance(currency: currency)
            let currentText = pampGramFormatVisualAmountInput(currency: currency, minorUnits: currentUnits)
            presentControllerImpl?(promptController(
                context: context,
                text: "\(bot.displayName) · \(currency)",
                subtitle: "Введите новый баланс. Разница пойдёт в историю как корректировка.",
                value: currentText,
                placeholder: "0",
                characterLimit: 24,
                apply: { value in
                    guard let value = value, let newUnits = pampGramParseVisualAmount(currency: currency, text: value) else { return }
                    let delta = newUnits - currentUnits
                    if delta == 0 { return }
                    let _ = context.account.postbox.transaction { transaction -> Void in
                        PampGramVisualBotStore.apply(
                            transaction: transaction,
                            botId: botId,
                            kind: .manual,
                            currency: currency,
                            minorUnits: delta,
                            note: "Ручная корректировка"
                        )
                    }.start()
                }
            ))
        }
    }

    let addCurrencyAction: (String) -> Void = { botId in
        withBots { bots in
            guard let bot = bots.first(where: { $0.id == botId }) else { return }
            let excluded = Set(bot.balances.map { $0.currency })
            pampGramPresentVisualCurrencyPicker(context: context, present: { c in presentControllerImpl?(c) }, title: "Добавить валюту", excluded: excluded) { currency in
                editBalanceAction(botId, currency)
            }
        }
    }

    let transferAction: (String) -> Void = { fromBotId in
        withBots { bots in
            guard let fromBot = bots.first(where: { $0.id == fromBotId }) else { return }
            if fromBot.balances.isEmpty {
                presentTooltipImpl?("У \(fromBot.displayName) нет кошельков — сначала добавьте валюту.")
                return
            }
            let otherBots = bots.filter { $0.id != fromBotId }
            if otherBots.isEmpty {
                presentTooltipImpl?("Нет другого визуального бота для перевода.")
                return
            }
            // Pick: currency → target bot → amount.
            let availableCurrencies = fromBot.balances.map { $0.currency }
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let sheet = ActionSheetController(presentationData: presentationData)
            var buttons: [ActionSheetItem] = [ActionSheetTextItem(title: "Валюта для перевода")]
            for currency in availableCurrencies {
                let have = fromBot.balance(currency: currency)
                let label = "\(currency) · \(pampGramFormatVisualAmount(currency: currency, minorUnits: have))"
                buttons.append(ActionSheetButtonItem(title: label, color: .accent, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    pampGramPresentVisualBotPicker(context: context, present: { c in presentControllerImpl?(c) }, title: "Куда переводим", bots: otherBots) { toBot in
                        presentControllerImpl?(promptController(
                            context: context,
                            text: "\(fromBot.displayName) → \(toBot.displayName)",
                            subtitle: "Сумма в \(currency). Доступно: \(pampGramFormatVisualAmount(currency: currency, minorUnits: have)).",
                            value: "",
                            placeholder: "0",
                            characterLimit: 24,
                            apply: { value in
                                guard let value = value, let units = pampGramParseVisualAmount(currency: currency, text: value), units > 0 else { return }
                                let _ = (context.account.postbox.transaction { transaction -> PampGramVisualBotTransferResult in
                                    return PampGramVisualBotStore.transfer(
                                        transaction: transaction,
                                        fromBotId: fromBotId,
                                        toBotId: toBot.id,
                                        currency: currency,
                                        minorUnits: units,
                                        note: nil
                                    )
                                }
                                |> deliverOnMainQueue).start(next: { result in
                                    switch result {
                                    case .success:
                                        presentTooltipImpl?("Переведено \(pampGramFormatVisualAmount(currency: currency, minorUnits: units)) на \(toBot.displayName).")
                                    case .insufficientFunds:
                                        presentTooltipImpl?("Недостаточно средств для перевода.")
                                    case .sameBot:
                                        presentTooltipImpl?("Нельзя переводить самому себе.")
                                    case .unknownBot:
                                        presentTooltipImpl?("Бот не найден.")
                                    }
                                })
                            }
                        ))
                    }
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
    }

    let createCheckAction: (String) -> Void = { botId in
        withBots { bots in
            guard let bot = bots.first(where: { $0.id == botId }) else { return }
            if bot.balances.isEmpty {
                presentTooltipImpl?("У \(bot.displayName) нет кошельков — сначала добавьте валюту.")
                return
            }
            let currencies = bot.balances.map { $0.currency }
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let sheet = ActionSheetController(presentationData: presentationData)
            var buttons: [ActionSheetItem] = [ActionSheetTextItem(title: "Валюта чека")]
            for currency in currencies {
                let have = bot.balance(currency: currency)
                let label = "\(currency) · \(pampGramFormatVisualAmount(currency: currency, minorUnits: have))"
                buttons.append(ActionSheetButtonItem(title: label, color: .accent, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    presentControllerImpl?(promptController(
                        context: context,
                        text: "Чек от \(bot.displayName)",
                        subtitle: "Сумма в \(currency). Доступно: \(pampGramFormatVisualAmount(currency: currency, minorUnits: have)).",
                        value: "",
                        placeholder: "0",
                        characterLimit: 24,
                        apply: { value in
                            guard let value = value, let units = pampGramParseVisualAmount(currency: currency, text: value), units > 0 else { return }
                            let _ = (context.account.postbox.transaction { transaction -> PampGramVisualBotCheck? in
                                return PampGramVisualBotStore.createCheck(
                                    transaction: transaction,
                                    botId: botId,
                                    currency: currency,
                                    minorUnits: units,
                                    comment: nil
                                )
                            }
                            |> deliverOnMainQueue).start(next: { check in
                                guard let check = check else {
                                    presentTooltipImpl?("Не удалось создать чек: проверьте баланс.")
                                    return
                                }
                                let link = "t.me/\(bot.username)?start=\(check.code)"
                                UIPasteboard.general.string = link
                                presentTooltipImpl?("Ссылка скопирована: \(link)")
                            })
                        }
                    ))
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
    }

    let redeemCheckAction: () -> Void = {
        presentControllerImpl?(promptController(
            context: context,
            text: "Активировать чек",
            subtitle: "Введите код чека или всю ссылку. Регистр не важен.",
            value: "",
            placeholder: "CQxxxxxxxxxx",
            characterLimit: 128,
            apply: { value in
                guard let value = value else { return }
                // Accept both "CQxxxx" and the full "t.me/<bot>?start=CQxxxx" shape.
                let code: String
                if let range = value.range(of: "start=") {
                    code = String(value[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                } else {
                    code = value.trimmingCharacters(in: .whitespaces)
                }
                if code.isEmpty { return }
                withBots { bots in
                    let enabledBots = bots.filter { $0.enabled }
                    if enabledBots.isEmpty {
                        presentTooltipImpl?("Нет включённых визуальных ботов — некуда зачислять чек.")
                        return
                    }
                    pampGramPresentVisualBotPicker(context: context, present: { c in presentControllerImpl?(c) }, title: "Зачислить на какого бота", bots: enabledBots) { bot in
                        let _ = (context.account.postbox.transaction { transaction -> PampGramVisualBotCheckRedeemResult in
                            return PampGramVisualBotStore.redeemCheck(transaction: transaction, code: code, targetBotId: bot.id)
                        }
                        |> deliverOnMainQueue).start(next: { result in
                            switch result {
                            case let .success(_, _, amount, currency):
                                presentTooltipImpl?("Чек погашен: +\(pampGramFormatVisualAmount(currency: currency, minorUnits: amount)) на \(bot.displayName).")
                            case .alreadyRedeemed:
                                presentTooltipImpl?("Чек уже погашен.")
                            case .unknownCode:
                                presentTooltipImpl?("Такого чека нет на этом устройстве.")
                            case .targetBotDisabled:
                                presentTooltipImpl?("Включите бота, прежде чем зачислять на него чек.")
                            case .unknownTargetBot:
                                presentTooltipImpl?("Бот не найден.")
                            }
                        })
                    }
                }
            }
        ))
    }

    let resetAction: (String) -> Void = { botId in
        withBots { bots in
            guard let bot = bots.first(where: { $0.id == botId }) else { return }
            if bot.balances.isEmpty { return }
            presentControllerImpl?(textAlertController(
                context: context,
                title: "Обнулить балансы \(bot.displayName)?",
                text: "Все кошельки этого бота обнулятся. Это действие нельзя отменить.",
                actions: [
                    TextAlertAction(type: .genericAction, title: "Отмена", action: {}),
                    TextAlertAction(type: .destructiveAction, title: "Обнулить", action: {
                        let _ = context.account.postbox.transaction { transaction -> Void in
                            guard let fresh = PampGramVisualBotStore.bot(transaction: transaction, id: botId) else { return }
                            for balance in fresh.balances where balance.minorUnits != 0 {
                                PampGramVisualBotStore.apply(
                                    transaction: transaction,
                                    botId: botId,
                                    kind: .manual,
                                    currency: balance.currency,
                                    minorUnits: -balance.minorUnits,
                                    note: "Сброс балансов"
                                )
                            }
                        }.start()
                        presentTooltipImpl?("Балансы \(bot.displayName) сброшены.")
                    })
                ],
                actionLayout: .horizontal
            ))
        }
    }

    let arguments = PampGramVisualBotsArguments(
        toggleMaster: { value in
            let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                var settings = settings
                settings.visualBotsEnabled = value
                return settings
            }).start()
        },
        toggleBot: { botId, value in
            let _ = context.account.postbox.transaction { transaction -> Void in
                PampGramVisualBotStore.setBotEnabled(transaction: transaction, id: botId, enabled: value)
            }.start()
        },
        editBalance: editBalanceAction,
        addCurrency: addCurrencyAction,
        transferFrom: transferAction,
        createCheckFrom: createCheckAction,
        redeemCheck: redeemCheckAction,
        openHistory: {
            pushControllerImpl?(pampGramVisualBotsHistoryController(context: context))
        },
        resetBot: resetAction
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        PampGramCore.rawSettingsSignal(postbox: context.account.postbox),
        PampGramVisualBotStore.botsSignal(context: context),
        PampGramVisualBotStore.operationsSignal(context: context)
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings, bots, operations -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Визуальные боты"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: pampGramVisualBotsEntries(settings: settings, bots: bots, operationCount: operations.count),
            style: .blocks,
            animateChanges: true
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    pushControllerImpl = { [weak controller] c in
        controller?.push(c)
    }
    presentTooltipImpl = { [weak controller] text in
        guard let controller else { return }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        controller.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), in: .current)
    }
    return controller
}
