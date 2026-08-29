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

private final class PampGramAdminArguments {
    let setAdminToken: () -> Void
    let grantSubscription: () -> Void

    init(setAdminToken: @escaping () -> Void, grantSubscription: @escaping () -> Void) {
        self.setAdminToken = setAdminToken
        self.grantSubscription = grantSubscription
    }
}

private enum PampGramAdminSection: Int32 {
    case about
    case token
    case grant
}

private enum PampGramAdminEntry: ItemListNodeEntry {
    case aboutText(String)

    case tokenHeader(String)
    case tokenRow(String, String)
    case tokenFooter(String)

    case grantAction(String, Bool)
    case grantFooter(String)

    var section: ItemListSectionId {
        switch self {
        case .aboutText:
            return PampGramAdminSection.about.rawValue
        case .tokenHeader, .tokenRow, .tokenFooter:
            return PampGramAdminSection.token.rawValue
        case .grantAction, .grantFooter:
            return PampGramAdminSection.grant.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .aboutText:
            return 0
        case .tokenHeader:
            return 1
        case .tokenRow:
            return 2
        case .tokenFooter:
            return 3
        case .grantAction:
            return 4
        case .grantFooter:
            return 5
        }
    }

    static func ==(lhs: PampGramAdminEntry, rhs: PampGramAdminEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.aboutText(lhsText), .aboutText(rhsText)):
            return lhsText == rhsText
        case let (.tokenHeader(lhsText), .tokenHeader(rhsText)):
            return lhsText == rhsText
        case let (.tokenRow(lhsTitle, lhsLabel), .tokenRow(rhsTitle, rhsLabel)):
            return lhsTitle == rhsTitle && lhsLabel == rhsLabel
        case let (.tokenFooter(lhsText), .tokenFooter(rhsText)):
            return lhsText == rhsText
        case let (.grantAction(lhsTitle, lhsEnabled), .grantAction(rhsTitle, rhsEnabled)):
            return lhsTitle == rhsTitle && lhsEnabled == rhsEnabled
        case let (.grantFooter(lhsText), .grantFooter(rhsText)):
            return lhsText == rhsText
        default:
            return false
        }
    }

    static func <(lhs: PampGramAdminEntry, rhs: PampGramAdminEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramAdminArguments
        switch self {
        case let .aboutText(text), let .tokenFooter(text), let .grantFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .tokenHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .tokenRow(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.setAdminToken()
            })
        case let .grantAction(title, enabled):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: enabled ? .generic : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.grantSubscription()
            })
        }
    }
}

/// Only ever pushed for `PampGramSubscriptionAPI.adminAccountId` (see `PampGramHubScreen.swift`
/// — the hub row that opens this doesn't even exist in the entry list for anyone else). Talks
/// to PampGram's one server-backed feature; see `PampGramSubscriptionAPI.swift`'s own doc for
/// why a subscription needs a server at all, and `server/pampgram-subs-worker/` for that
/// server itself.
public func pampGramAdminController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    var presentTooltipImpl: ((String) -> Void)?

    let showTierChoice: (Int64, String, String) -> Void = { userId, displayName, adminToken in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }

        let apply: (PampGramSubscriptionTier) -> Void = { tier in
            PampGramSubscriptionAPI.grantTier(userId: userId, tier: tier, adminToken: adminToken) { ok in
                if ok {
                    presentTooltipImpl?("\(displayName): выдан тариф \(tier == .pro ? "PRO" : "STANDARD").")
                } else {
                    presentTooltipImpl?("Не получилось — проверь, что бэкенд задеплоен, baseURL заполнен, а токен совпадает с ADMIN_TOKEN на сервере.")
                }
            }
        }

        let sheet = ActionSheetController(presentationData: presentationData)
        sheet.setItemGroups([
            ActionSheetItemGroup(items: [
                ActionSheetTextItem(title: "Тариф для \(displayName)"),
                ActionSheetButtonItem(title: "PRO", color: .accent, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    apply(.pro)
                }),
                ActionSheetButtonItem(title: "STANDARD", color: .accent, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    apply(.standard)
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

    let arguments = PampGramAdminArguments(
        setAdminToken: {
            let _ = (context.account.postbox.transaction { transaction -> String? in
                return PampGramSubscriptionAPI.adminToken(transaction: transaction)
            }
            |> deliverOnMainQueue).start(next: { current in
                presentControllerImpl?(promptController(
                    context: context,
                    text: "Админ-токен",
                    subtitle: "Тот же секрет, что задан на сервере через wrangler secret put ADMIN_TOKEN. Хранится только на этом устройстве.",
                    value: current ?? "",
                    placeholder: "токен",
                    characterLimit: 256,
                    apply: { value in
                        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                            return
                        }
                        let _ = context.account.postbox.transaction { transaction in
                            PampGramSubscriptionAPI.setAdminToken(transaction: transaction, token: value)
                        }.start()
                        presentTooltipImpl?("Токен сохранён на этом устройстве.")
                    }
                ))
            })
        },
        grantSubscription: {
            let _ = (context.account.postbox.transaction { transaction -> String? in
                return PampGramSubscriptionAPI.adminToken(transaction: transaction)
            }
            |> deliverOnMainQueue).start(next: { adminToken in
                guard let adminToken else {
                    presentTooltipImpl?("Сначала задай админ-токен — пункт выше.")
                    return
                }
                presentControllerImpl?(promptController(
                    context: context,
                    text: "Кому выдать подписку?",
                    subtitle: "Юзернейм (без @) или числовой ID аккаунта",
                    value: "",
                    placeholder: "username или id",
                    characterLimit: 64,
                    apply: { value in
                        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                            return
                        }
                        if value.hasPrefix("@") {
                            value.removeFirst()
                        }
                        if let userId = Int64(value) {
                            showTierChoice(userId, "ID \(userId)", adminToken)
                        } else {
                            let _ = (context.engine.peers.resolvePeerByName(name: value, referrer: nil)
                            |> deliverOnMainQueue).start(next: { result in
                                guard case let .result(peer) = result else {
                                    return
                                }
                                guard let peer else {
                                    presentTooltipImpl?("Пользователь «\(value)» не найден.")
                                    return
                                }
                                showTierChoice(peer.id.id._internalGetInt64Value(), peer.compactDisplayTitle, adminToken)
                            })
                        }
                    }
                ))
            })
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        PampGramSubscriptionAPI.adminTokenSignal(postbox: context.account.postbox)
    )
    |> deliverOnMainQueue
    |> map { presentationData, adminToken -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Админ-панель"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let entries: [PampGramAdminEntry] = [
            .aboutText("Видно только этому аккаунту. Дальше сюда добавятся другие функции."),
            .tokenHeader("СЕРВЕР"),
            .tokenRow("Админ-токен", adminToken == nil ? "Не задан" : "Задан"),
            .tokenFooter("Секрет для авторизации на сервере — задаётся один раз, хранится только на этом устройстве."),
            .grantAction("Выдать подписку", adminToken != nil),
            .grantFooter("Меняет тариф человека на всех его устройствах — это единственная функция PampGram, которая обращается к серверу, а не хранит всё локально.")
        ]
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
