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

private struct PampGramFakeBotRow {
    let id: Int64
    let title: String
    let username: String
    /// The official @CryptoBot kept from the old single switch; removing it turns that switch off.
    let builtIn: Bool
}

private final class PampGramFakeBotsArguments {
    let addBot: () -> Void
    let openBot: (PampGramFakeBotRow) -> Void

    init(addBot: @escaping () -> Void, openBot: @escaping (PampGramFakeBotRow) -> Void) {
        self.addBot = addBot
        self.openBot = openBot
    }
}

private enum PampGramFakeBotsSection: Int32 {
    case about
    case bots
}

private enum PampGramFakeBotsEntry: ItemListNodeEntry {
    case aboutText(String)
    case bot(Int32, PampGramFakeBotRow)
    case add(String)
    case footer(String)

    var section: ItemListSectionId {
        switch self {
        case .aboutText:
            return PampGramFakeBotsSection.about.rawValue
        case .bot, .add, .footer:
            return PampGramFakeBotsSection.bots.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .aboutText:
            return 0
        case let .bot(index, _):
            return 1 + index
        case .add:
            return 1000
        case .footer:
            return 1001
        }
    }

    static func ==(lhs: PampGramFakeBotsEntry, rhs: PampGramFakeBotsEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.aboutText(a), .aboutText(b)):
            return a == b
        case let (.bot(indexA, rowA), .bot(indexB, rowB)):
            return indexA == indexB && rowA.id == rowB.id && rowA.title == rowB.title && rowA.username == rowB.username && rowA.builtIn == rowB.builtIn
        case let (.add(a), .add(b)):
            return a == b
        case let (.footer(a), .footer(b)):
            return a == b
        default:
            return false
        }
    }

    static func <(lhs: PampGramFakeBotsEntry, rhs: PampGramFakeBotsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramFakeBotsArguments
        switch self {
        case let .aboutText(text), let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .bot(_, row):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: generatePampGramSectionIcon(systemName: "bitcoinsign.circle.fill", backgroundColor: UIColor(rgb: 0x1b8ed2)), title: row.title, label: "@" + row.username, sectionId: self.section, style: .blocks, action: {
                arguments.openBot(row)
            })
        case let .add(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.addBot()
            })
        }
    }
}

private func pampGramFakeBotsEntries(settings: PampGramSettings) -> [PampGramFakeBotsEntry] {
    var rows: [PampGramFakeBotRow] = []
    let bots = pampGramParseFakeBots(settings.fakeBotsRaw)
    if settings.fakeCryptoBotEnabled && !bots.contains(where: { $0.id == PampGramFakeCryptoBotRuntime.officialBotUserId }) {
        rows.append(PampGramFakeBotRow(id: PampGramFakeCryptoBotRuntime.officialBotUserId, title: "CryptoBot", username: "CryptoBot", builtIn: true))
    }
    for bot in bots {
        rows.append(PampGramFakeBotRow(id: bot.id, title: bot.title, username: bot.username, builtIn: false))
    }

    var entries: [PampGramFakeBotsEntry] = []
    entries.append(.aboutText("У ботов из этого списка вместо их настоящего мини-аппа открывается копия CryptoBot с локальными балансами. Работает только на этом устройстве, другие люди видят обычного бота."))
    for (index, row) in rows.enumerated() {
        entries.append(.bot(Int32(index), row))
    }
    entries.append(.add("Добавить бота"))
    entries.append(.footer(rows.isEmpty ? "Список пуст. Добавь бота по его @username: можно любого, в том числе своего, созданного через @BotFather. Балансы у всех одни и те же, их меняет удержание суммы общего баланса." : "Нажми на бота, чтобы открыть его фейковый мини-апп или убрать его из списка. Балансы у всех ботов общие."))
    return entries
}

/// "Фейковые боты" (Дополнительно): the list of bots whose mini app is replaced by the fake
/// CryptoBot page, with adding by @username, opening the page full-screen and removing.
public func pampGramFakeBotsController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?
    var presentTooltipImpl: ((String) -> Void)?

    let arguments = PampGramFakeBotsArguments(
        addBot: {
            presentControllerImpl?(promptController(
                context: context,
                text: "Добавить бота",
                subtitle: "Имя пользователя бота, например @CryptoBot",
                value: "",
                placeholder: "@username",
                characterLimit: 64,
                apply: { value in
                    guard let value = value else {
                        return
                    }
                    var name = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    for prefix in ["https://t.me/", "http://t.me/", "t.me/", "@"] {
                        if name.lowercased().hasPrefix(prefix) {
                            name = String(name.dropFirst(prefix.count))
                        }
                    }
                    if let slash = name.firstIndex(where: { $0 == "/" || $0 == "?" }) {
                        name = String(name[name.startIndex ..< slash])
                    }
                    guard !name.isEmpty else {
                        return
                    }
                    presentTooltipImpl?("Ищу бота…")
                    let _ = (context.engine.peers.resolvePeerByName(name: name, referrer: nil)
                    |> mapToSignal { result -> Signal<EnginePeer?, NoError> in
                        guard case let .result(peer) = result else {
                            return .complete()
                        }
                        return .single(peer)
                    }
                    |> take(1)
                    |> deliverOnMainQueue).start(next: { peer in
                        guard let peer = peer else {
                            presentTooltipImpl?("Бот не найден.")
                            return
                        }
                        guard case let .user(user) = peer, user.botInfo != nil else {
                            presentTooltipImpl?("Это не бот.")
                            return
                        }
                        let bot = PampGramFakeBot(id: user.id.id._internalGetInt64Value(), username: peer.addressName ?? name, title: peer.debugDisplayTitle)
                        let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                            var settings = settings
                            var bots = pampGramParseFakeBots(settings.fakeBotsRaw)
                            bots.removeAll(where: { $0.id == bot.id })
                            bots.append(bot)
                            settings.fakeBotsRaw = pampGramSerializeFakeBots(bots)
                            return settings
                        }).start()
                        presentTooltipImpl?("Бот добавлен.")
                    })
                }
            ))
        },
        openBot: { row in
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let sheet = ActionSheetController(presentationData: presentationData)
            sheet.setItemGroups([
                ActionSheetItemGroup(items: [
                    ActionSheetTextItem(title: row.title),
                    ActionSheetButtonItem(title: "Открыть", color: .accent, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                        pushControllerImpl?(pampGramFakeCryptoBotController(context: context, title: row.title))
                    }),
                    ActionSheetButtonItem(title: "Убрать из списка", color: .destructive, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                        let _ = PampGramCore.updateSettingsInteractively(postbox: context.account.postbox, { settings in
                            var settings = settings
                            var bots = pampGramParseFakeBots(settings.fakeBotsRaw)
                            bots.removeAll(where: { $0.id == row.id })
                            settings.fakeBotsRaw = pampGramSerializeFakeBots(bots)
                            if row.builtIn {
                                settings.fakeCryptoBotEnabled = false
                            }
                            return settings
                        }).start()
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
        PampGramCore.settingsSignal(postbox: context.account.postbox)
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Фейковые боты"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: pampGramFakeBotsEntries(settings: settings),
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
