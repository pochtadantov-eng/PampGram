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

/// Shortens a cosmetic address for list rows ("UQAbc1…9xYz"); the receive sheet still shows
/// the full string.
private func pampGramWalletShortAddress(_ address: String) -> String {
    guard address.count > 12 else {
        return address
    }
    return "\(address.prefix(6))…\(address.suffix(4))"
}

private final class PampGramWalletArguments {
    let chooseWallet: () -> Void
    let send: () -> Void
    let receive: () -> Void
    let topUp: () -> Void

    init(chooseWallet: @escaping () -> Void, send: @escaping () -> Void, receive: @escaping () -> Void, topUp: @escaping () -> Void) {
        self.chooseWallet = chooseWallet
        self.send = send
        self.receive = receive
        self.topUp = topUp
    }
}

private enum PampGramWalletSection: Int32 {
    case switcher
    case balance
    case actions
    case activity
    case footer
}

private enum PampGramWalletEntry: ItemListNodeEntry {
    case switcher(String)
    case balance(String)
    case address(String)
    case send
    case receive
    case topUp
    case activityHeader
    case activityEmpty
    case activityItem(Int64, String, String, String)
    case footer(String)

    var section: ItemListSectionId {
        switch self {
        case .switcher:
            return PampGramWalletSection.switcher.rawValue
        case .balance, .address:
            return PampGramWalletSection.balance.rawValue
        case .send, .receive, .topUp:
            return PampGramWalletSection.actions.rawValue
        case .activityHeader, .activityEmpty, .activityItem:
            return PampGramWalletSection.activity.rawValue
        case .footer:
            return PampGramWalletSection.footer.rawValue
        }
    }

    var stableId: Int64 {
        switch self {
        case .switcher: return 0
        case .balance: return 1
        case .address: return 2
        case .send: return 3
        case .receive: return 4
        case .topUp: return 5
        case .activityHeader: return 6
        case .activityEmpty: return 7
        case let .activityItem(id, _, _, _): return 1_000 + id
        case .footer: return Int64.max
        }
    }

    static func ==(lhs: PampGramWalletEntry, rhs: PampGramWalletEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.switcher(a), .switcher(b)):
            return a == b
        case let (.balance(a), .balance(b)):
            return a == b
        case let (.address(a), .address(b)):
            return a == b
        case (.send, .send), (.receive, .receive), (.topUp, .topUp), (.activityHeader, .activityHeader), (.activityEmpty, .activityEmpty):
            return true
        case let (.activityItem(a1, a2, a3, a4), .activityItem(b1, b2, b3, b4)):
            return a1 == b1 && a2 == b2 && a3 == b3 && a4 == b4
        case let (.footer(a), .footer(b)):
            return a == b
        default:
            return false
        }
    }

    static func <(lhs: PampGramWalletEntry, rhs: PampGramWalletEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramWalletArguments
        switch self {
        case let .switcher(text):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Активный кошелёк", label: text, sectionId: self.section, style: .blocks, action: arguments.chooseWallet)
        case let .balance(text):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Баланс", titleFont: .bold, label: text, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case let .address(text):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Адрес", label: text, sectionId: self.section, style: .blocks, action: arguments.receive)
        case .send:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Отправить", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: arguments.send)
        case .receive:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Получить", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: arguments.receive)
        case .topUp:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Пополнить", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: arguments.topUp)
        case .activityHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "АКТИВНОСТЬ", sectionId: self.section)
        case .activityEmpty:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Операций по этому кошельку пока нет."), sectionId: self.section)
        case let .activityItem(_, title, amount, detail):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: amount, additionalDetailLabel: detail, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

/// A small TonKeeper-styled wallet screen over PampGram's play-money TON: two local phantom
/// wallets ("Кошелёк 1" is the same `fakeTonBalanceNanos` counter the rest of the app already
/// shows, "Кошелёк 2" is new) with their own cosmetic address and activity list, and a Send
/// flow that only ever moves the balance between those same two local wallets. See
/// `PampGramPhantomWalletStore` for why the addresses can't receive real TON and why a
/// transfer never touches the network.
public func pampGramWalletController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    var presentTooltipImpl: ((String) -> Void)?

    let _ = (PampGramPhantomWalletStore.ensureSeeded(postbox: context.account.postbox)).start()

    func currentWallets() -> Signal<[PampGramPhantomWalletView], NoError> {
        return context.account.postbox.transaction { transaction -> [PampGramPhantomWalletView] in
            return PampGramPhantomWalletStore.wallets(transaction: transaction)
        }
    }

    let arguments = PampGramWalletArguments(
        chooseWallet: {
            let _ = (currentWallets() |> deliverOnMainQueue).start(next: { wallets in
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                let sheet = ActionSheetController(presentationData: presentationData)
                sheet.setItemGroups([
                    ActionSheetItemGroup(items: wallets.map { wallet in
                        ActionSheetButtonItem(title: "\(wallet.isSelected ? "✓ " : "")\(wallet.title) · \(formatFakeTon(nanos: wallet.balanceNanos)) TON", color: .accent, action: { [weak sheet] in
                            sheet?.dismissAnimated()
                            let _ = context.account.postbox.transaction { transaction -> Void in
                                PampGramPhantomWalletStore.selectWallet(transaction: transaction, id: wallet.id)
                            }.start()
                        })
                    }),
                    ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                    })])
                ])
                presentControllerImpl?(sheet)
            })
        },
        send: {
            let _ = (currentWallets() |> deliverOnMainQueue).start(next: { wallets in
                guard let selected = wallets.first(where: { $0.isSelected }), let other = wallets.first(where: { !$0.isSelected }) else {
                    return
                }
                presentControllerImpl?(promptController(
                    context: context,
                    text: "Отправить TON",
                    subtitle: "С «\(selected.title)» на «\(other.title)» (\(pampGramWalletShortAddress(other.address))). Баланс «\(selected.title)»: \(formatFakeTon(nanos: selected.balanceNanos)) TON. Локальный перевод внутри PampGram, реальные средства не переводятся.",
                    value: "",
                    placeholder: "1.0",
                    characterLimit: 24,
                    apply: { value in
                        guard let value, let amount = parseFakeTon(value), amount > 0 else {
                            return
                        }
                        presentControllerImpl?(textAlertController(
                            context: context,
                            title: "Отправить \(formatFakeTon(nanos: amount)) TON?",
                            text: "Локальный перевод с «\(selected.title)» на «\(other.title)» внутри PampGram. Реальные TON эта функция не трогает.",
                            actions: [
                                TextAlertAction(type: .genericAction, title: "Отмена", action: {}),
                                TextAlertAction(type: .destructiveAction, title: "Отправить", action: {
                                    let _ = (context.account.postbox.transaction { transaction -> Bool in
                                        return PampGramPhantomWalletStore.send(transaction: transaction, amountNanos: amount, comment: "")
                                    }
                                    |> deliverOnMainQueue).start(next: { ok in
                                        presentTooltipImpl?(ok ? "Отправлено \(formatFakeTon(nanos: amount)) TON на «\(other.title)»." : "Недостаточно средств на «\(selected.title)».")
                                    })
                                })
                            ],
                            actionLayout: .horizontal
                        ))
                    }
                ))
            })
        },
        receive: {
            let _ = (currentWallets() |> deliverOnMainQueue).start(next: { wallets in
                guard let selected = wallets.first(where: { $0.isSelected }) else {
                    return
                }
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                let sheet = ActionSheetController(presentationData: presentationData)
                sheet.setItemGroups([
                    ActionSheetItemGroup(items: [
                        ActionSheetTextItem(title: selected.address),
                        ActionSheetButtonItem(title: "Скопировать адрес", color: .accent, action: { [weak sheet] in
                            sheet?.dismissAnimated()
                            UIPasteboard.general.string = selected.address
                            presentTooltipImpl?("Адрес скопирован.")
                        })
                    ]),
                    ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                    })])
                ])
                presentControllerImpl?(sheet)
            })
        },
        topUp: {
            let _ = (currentWallets() |> deliverOnMainQueue).start(next: { wallets in
                guard let selected = wallets.first(where: { $0.isSelected }) else {
                    return
                }
                presentControllerImpl?(promptController(
                    context: context,
                    text: "Пополнить «\(selected.title)»",
                    subtitle: "Сумма добавится к локальному балансу этого кошелька.",
                    value: "",
                    placeholder: "10.0",
                    characterLimit: 24,
                    apply: { value in
                        guard let value, let amount = parseFakeTon(value), amount > 0 else {
                            return
                        }
                        let _ = context.account.postbox.transaction { transaction -> Void in
                            PampGramPhantomWalletStore.topUp(transaction: transaction, walletId: selected.id, amountNanos: amount)
                        }.start()
                    }
                ))
            })
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        PampGramPhantomWalletStore.walletsSignal(postbox: context.account.postbox)
    )
    |> deliverOnMainQueue
    |> map { presentationData, wallets -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let selected = wallets.first(where: { $0.isSelected }) ?? wallets[0]

        var entries: [PampGramWalletEntry] = [
            .switcher(selected.title),
            .balance("\(formatFakeTon(nanos: selected.balanceNanos)) TON"),
            .address(pampGramWalletShortAddress(selected.address)),
            .send,
            .receive,
            .topUp,
            .activityHeader
        ]
        if selected.transactions.isEmpty {
            entries.append(.activityEmpty)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            for tx in selected.transactions {
                let date = formatter.string(from: Date(timeIntervalSince1970: Double(tx.date)))
                let title = tx.outgoing ? "Исходящий перевод" : "Входящий перевод"
                let amount = "\(tx.outgoing ? "-" : "+")\(formatFakeTon(nanos: tx.amountNanos)) TON"
                entries.append(.activityItem(tx.id, title, amount, date))
            }
        }
        entries.append(.footer("Кошелёк полностью локальный: адрес нигде не зарегистрирован в сети TON, у него нет настоящего ключа, и он не может принять настоящие средства. «Отправить» переводит баланс только между этими двумя локальными кошельками внутри PampGram — сеть TON и настоящий Telegram-баланс эта функция не трогает."))

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Кошелёк"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
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
