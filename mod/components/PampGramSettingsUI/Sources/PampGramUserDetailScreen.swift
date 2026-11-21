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

private let pampGramUserDetailDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "dd.MM.yy HH:mm"
    return formatter
}()

private func pampGramUserDetailFormatMs(_ ms: Int64) -> String {
    guard ms > 0 else {
        return "—"
    }
    return pampGramUserDetailDateFormatter.string(from: Date(timeIntervalSince1970: Double(ms) / 1000.0))
}

private func pampGramUserDetailFormatOptionalMs(_ ms: Int64?) -> String {
    guard let ms, ms > 0 else {
        return "дата неизвестна"
    }
    return pampGramUserDetailFormatMs(ms)
}

private func pampGramUserDetailFormatTon(nanos: Int64) -> String {
    String(format: "%.4f TON", Double(nanos) / 1_000_000_000.0)
}

private func pampGramUserDetailKindName(_ kind: String) -> String {
    switch kind {
    case "topUp": return "Пополнение"
    case "purchase": return "Покупка"
    case "sale": return "Продажа"
    case "transfer": return "Передача"
    case "debit": return "Списание"
    case "credit": return "Зачисление"
    default: return kind.isEmpty ? "Операция" : kind
    }
}

private func pampGramUserDetailAmountText(currency: String, amount: Int64) -> String {
    switch currency {
    case "stars":
        return "\(amount >= 0 ? "+" : "")\(amount) ⭐"
    case "ton":
        let value = Double(amount) / 1_000_000_000.0
        return String(format: "%@%.4f TON", amount >= 0 ? "+" : "", value)
    case "rubles":
        let value = Double(amount) / 100.0
        return String(format: "%@%.2f ₽", amount >= 0 ? "+" : "", value)
    default:
        return "\(amount)"
    }
}

private final class PampGramUserDetailArguments {
    let reload: () -> Void
    let openBan: () -> Void
    let openTier: () -> Void
    let forceVideo: () -> Void
    let clearVideo: () -> Void
    let copyId: () -> Void

    init(reload: @escaping () -> Void, openBan: @escaping () -> Void, openTier: @escaping () -> Void, forceVideo: @escaping () -> Void, clearVideo: @escaping () -> Void, copyId: @escaping () -> Void) {
        self.reload = reload
        self.openBan = openBan
        self.openTier = openTier
        self.forceVideo = forceVideo
        self.clearVideo = clearVideo
        self.copyId = copyId
    }
}

private enum PampGramUserDetailSection: Int32 {
    case profile
    case status
    case sessions
    case real
    case nfts
    case ledger
    case actions
}

private enum PampGramUserDetailEntry: ItemListNodeEntry {
    case profileHeader(String)
    case profileRow(String, String)
    case statusHeader(String)
    case statusRow(String, String)
    case banAction(String)
    case tierAction(String)
    case videoAction(String)
    case clearVideoAction(String)
    case sessionsHeader(String)
    case sessionsSummary(String)
    case sessionRow(Int32, String)
    case realHeader(String)
    case realBalance(String)
    case realStats(String)
    case realEmpty(String)
    case realOp(Int32, String, String, String)
    case nftHeader(String)
    case nftSummary(String)
    case nftEmpty(String)
    case nftRow(Int32, String, String, String)
    case ledgerHeader(String)
    case ledgerBalance(String)
    case ledgerStats(String)
    case ledgerEmpty(String)
    case ledgerOp(Int32, String, String, String)
    case reloadAction(String)
    case footer(String)

    var section: ItemListSectionId {
        switch self {
        case .profileHeader, .profileRow:
            return PampGramUserDetailSection.profile.rawValue
        case .statusHeader, .statusRow, .banAction, .tierAction, .videoAction, .clearVideoAction:
            return PampGramUserDetailSection.status.rawValue
        case .sessionsHeader, .sessionsSummary, .sessionRow:
            return PampGramUserDetailSection.sessions.rawValue
        case .realHeader, .realBalance, .realStats, .realEmpty, .realOp:
            return PampGramUserDetailSection.real.rawValue
        case .nftHeader, .nftSummary, .nftEmpty, .nftRow:
            return PampGramUserDetailSection.nfts.rawValue
        case .ledgerHeader, .ledgerBalance, .ledgerStats, .ledgerEmpty, .ledgerOp:
            return PampGramUserDetailSection.ledger.rawValue
        case .reloadAction, .footer:
            return PampGramUserDetailSection.actions.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .profileHeader: return 1
        case let .profileRow(title, _):
            switch title {
            case "ID": return 2
            case "Username": return 3
            case "Имя": return 4
            case "Версия": return 5
            case "Первый вход": return 6
            case "Последний": return 7
            default: return 8
            }
        case .statusHeader: return 10
        case let .statusRow(title, _):
            return title == "Тариф" ? 11 : 12
        case .banAction: return 13
        case .tierAction: return 14
        case .videoAction: return 15
        case .clearVideoAction: return 16
        case .sessionsHeader: return 20
        case .sessionsSummary: return 21
        case let .sessionRow(index, _): return 22 + index
        case .realHeader: return 80
        case .realBalance: return 81
        case .realStats: return 82
        case .realEmpty: return 83
        case let .realOp(index, _, _, _): return 90 + index
        case .nftHeader: return 500
        case .nftSummary: return 501
        case .nftEmpty: return 502
        case let .nftRow(index, _, _, _): return 510 + index
        case .ledgerHeader: return 1200
        case .ledgerBalance: return 1201
        case .ledgerStats: return 1202
        case .ledgerEmpty: return 1203
        case let .ledgerOp(index, _, _, _): return 1210 + index
        case .reloadAction: return 9000
        case .footer: return 9001
        }
    }

    static func ==(lhs: PampGramUserDetailEntry, rhs: PampGramUserDetailEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.profileHeader(a), .profileHeader(b)),
             let (.statusHeader(a), .statusHeader(b)),
             let (.sessionsHeader(a), .sessionsHeader(b)),
             let (.sessionsSummary(a), .sessionsSummary(b)),
             let (.realHeader(a), .realHeader(b)),
             let (.realBalance(a), .realBalance(b)),
             let (.realStats(a), .realStats(b)),
             let (.realEmpty(a), .realEmpty(b)),
             let (.nftHeader(a), .nftHeader(b)),
             let (.nftSummary(a), .nftSummary(b)),
             let (.nftEmpty(a), .nftEmpty(b)),
             let (.ledgerHeader(a), .ledgerHeader(b)),
             let (.ledgerBalance(a), .ledgerBalance(b)),
             let (.ledgerStats(a), .ledgerStats(b)),
             let (.ledgerEmpty(a), .ledgerEmpty(b)),
             let (.reloadAction(a), .reloadAction(b)),
             let (.footer(a), .footer(b)),
             let (.banAction(a), .banAction(b)),
             let (.tierAction(a), .tierAction(b)),
             let (.videoAction(a), .videoAction(b)),
             let (.clearVideoAction(a), .clearVideoAction(b)):
            return a == b
        case let (.profileRow(a1, a2), .profileRow(b1, b2)),
             let (.statusRow(a1, a2), .statusRow(b1, b2)):
            return a1 == b1 && a2 == b2
        case let (.sessionRow(ai, at), .sessionRow(bi, bt)):
            return ai == bi && at == bt
        case let (.realOp(ai, a1, a2, a3), .realOp(bi, b1, b2, b3)),
             let (.nftRow(ai, a1, a2, a3), .nftRow(bi, b1, b2, b3)),
             let (.ledgerOp(ai, a1, a2, a3), .ledgerOp(bi, b1, b2, b3)):
            return ai == bi && a1 == b1 && a2 == b2 && a3 == b3
        default:
            return false
        }
    }

    static func <(lhs: PampGramUserDetailEntry, rhs: PampGramUserDetailEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramUserDetailArguments
        switch self {
        case let .profileHeader(text), let .statusHeader(text), let .sessionsHeader(text), let .realHeader(text), let .nftHeader(text), let .ledgerHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .profileRow(title, label), let .statusRow(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: title == "ID" ? {
                arguments.copyId()
            } : nil)
        case let .banAction(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.openBan()
            })
        case let .tierAction(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.openTier()
            })
        case let .videoAction(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.forceVideo()
            })
        case let .clearVideoAction(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.clearVideo()
            })
        case let .sessionsSummary(text), let .realBalance(text), let .realStats(text), let .realEmpty(text), let .nftSummary(text), let .nftEmpty(text), let .ledgerBalance(text), let .ledgerStats(text), let .ledgerEmpty(text), let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .sessionRow(_, text):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: text, label: "", sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case let .realOp(_, title, label, detail), let .nftRow(_, title, label, detail), let .ledgerOp(_, title, label, detail):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, additionalDetailLabel: detail, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case let .reloadAction(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.reload()
            })
        }
    }
}

private func pampGramUserDetailEntries(detail: PampGramUserDetail?) -> [PampGramUserDetailEntry] {
    guard let detail else {
        return [
            .profileHeader("ПРОФИЛЬ"),
            .profileRow("ID", "загрузка…"),
            .footer("Загружаю карточку пользователя…")
        ]
    }

    var entries: [PampGramUserDetailEntry] = [
        .profileHeader("ПРОФИЛЬ"),
        .profileRow("ID", detail.id)
    ]
    if !detail.username.isEmpty {
        entries.append(.profileRow("Username", "@\(detail.username)"))
    }
    if !detail.name.isEmpty {
        entries.append(.profileRow("Имя", detail.name))
    }
    let versionLabel: String
    if detail.appVersion.isEmpty {
        versionLabel = "нет данных"
    } else if detail.appBuild.isEmpty {
        versionLabel = detail.appVersion
    } else {
        versionLabel = "\(detail.appVersion) (\(detail.appBuild))"
    }
    entries.append(.profileRow("Версия", versionLabel))
    entries.append(.profileRow("Первый вход", pampGramUserDetailFormatMs(detail.firstSeen)))
    entries.append(.profileRow("Последний", pampGramUserDetailFormatMs(detail.lastSeen)))

    let banLabel: String
    if let full = detail.full {
        banLabel = "Полный бан · \(full.reason)"
    } else if !detail.sections.isEmpty {
        let names = detail.sections.keys.sorted().joined(separator: ", ")
        banLabel = "Разделы: \(names)"
    } else {
        banLabel = "Не забанен"
    }
    let tierLabel: String
    if let expiresAt = detail.expiresAt, expiresAt > 0 {
        tierLabel = "\(detail.tier == .pro ? "PRO" : "STANDARD") до \(pampGramUserDetailFormatMs(expiresAt))"
    } else {
        tierLabel = detail.tier == .pro ? "PRO" : "STANDARD"
    }

    entries.append(.statusHeader("СТАТУС"))
    entries.append(.statusRow("Тариф", tierLabel))
    entries.append(.statusRow("Бан", banLabel))
    entries.append(.banAction("Управление баном"))
    entries.append(.tierAction("Изменить тариф"))
    entries.append(.videoAction("Показать видео на весь экран"))
    entries.append(.clearVideoAction("Остановить видео"))

    entries.append(.sessionsHeader("ЗАХОДЫ"))
    entries.append(.sessionsSummary("Всего заходов: \(detail.sessions.count)"))
    for (index, session) in detail.sessions.reversed().prefix(12).enumerated() {
        entries.append(.sessionRow(Int32(index), pampGramUserDetailFormatMs(session)))
    }

    entries.append(.realHeader("НАСТОЯЩИЕ STARS / TON"))
    if let real = detail.real {
        entries.append(.realBalance("Баланс Telegram: \(real.starsBalance) ⭐ · \(pampGramUserDetailFormatTon(nanos: real.tonBalanceNanos))"))
        entries.append(.realStats("⭐ пришло \(real.starsReceived) / ушло \(real.starsSpent)\nTON пришло \(pampGramUserDetailFormatTon(nanos: real.tonReceivedNanos)) / ушло \(pampGramUserDetailFormatTon(nanos: real.tonSpentNanos))\nОпераций с подарками: \(real.giftOps)\nВсего: \(real.transactionCount)\nОбновлено: \(pampGramUserDetailFormatMs(real.updatedAt))"))
        if real.transactions.isEmpty {
            entries.append(.realEmpty("Telegram ещё не отдал историю (или она пустая)."))
        } else {
            for (index, tx) in real.transactions.enumerated() {
                let gift = tx.giftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                let base = tx.title.isEmpty ? (gift.isEmpty ? "Операция" : gift) : tx.title
                let title = !gift.isEmpty && !tx.title.isEmpty && gift != tx.title ? "\(base): \(gift)" : base
                let label = pampGramUserDetailAmountText(currency: tx.currency, amount: tx.amount)
                var parts = [pampGramUserDetailFormatMs(Int64(tx.date) * 1000)]
                if !tx.peer.isEmpty {
                    parts.append(tx.peer)
                }
                if !tx.description.isEmpty {
                    parts.append(tx.description)
                }
                if !tx.flags.isEmpty {
                    parts.append(tx.flags.joined(separator: ", "))
                }
                entries.append(.realOp(Int32(index), title, label, parts.joined(separator: " · ")))
            }
        }
    } else {
        entries.append(.realEmpty("Пока нет данных — клиент ещё не прислал настоящую историю Stars (раз в ~1 мин). Трата за подарок видна у отправителя, не у получателя."))
    }

    entries.append(.nftHeader("ЛОКАЛЬНЫЕ NFT / ПОДАРКИ (МОД)"))
    if let ledger = detail.ledger {
        entries.append(.nftSummary("Пришло \(ledger.nftReceived) · куплено \(ledger.nftBought) · продано \(ledger.nftSold) · передано \(ledger.nftTransferred)"))
        if ledger.nfts.isEmpty {
            entries.append(.nftEmpty("NFT/подарков в истории пока нет."))
        } else {
            for (index, nft) in ledger.nfts.prefix(200).enumerated() {
                let label = nft.amount == 0 ? nft.action : pampGramUserDetailAmountText(currency: nft.currency, amount: nft.amount)
                let detailLine = "\(nft.action) · \(pampGramUserDetailFormatMs(Int64(nft.date) * 1000))"
                entries.append(.nftRow(Int32(index), nft.name, label, detailLine))
            }
        }

        entries.append(.ledgerHeader("ЛОКАЛЬНАЯ ИСТОРИЯ МОДА"))
        var balanceParts = ["\(ledger.starsBalance) ⭐", pampGramUserDetailFormatTon(nanos: ledger.tonBalanceNanos)]
        if ledger.rublesBalanceKopecks != 0 || ledger.rublesSpent != 0 || ledger.rublesReceived != 0 {
            balanceParts.append(String(format: "%.2f ₽", Double(ledger.rublesBalanceKopecks) / 100.0))
        }
        entries.append(.ledgerBalance("Визуальный баланс: \(balanceParts.joined(separator: " · "))"))
        var stats = "⭐ пришло \(ledger.starsReceived) / ушло \(ledger.starsSpent)\nTON пришло \(pampGramUserDetailFormatTon(nanos: ledger.tonReceivedNanos)) / ушло \(pampGramUserDetailFormatTon(nanos: ledger.tonSpentNanos))"
        if ledger.rublesSpent != 0 || ledger.rublesReceived != 0 {
            stats += String(format: "\n₽ пришло %.2f / ушло %.2f", Double(ledger.rublesReceived) / 100.0, Double(ledger.rublesSpent) / 100.0)
        }
        stats += "\nВсего операций: \(ledger.operationCount)"
        entries.append(.ledgerStats(stats))
        if ledger.operations.isEmpty {
            entries.append(.ledgerEmpty("Операций пока нет."))
        } else {
            for (index, op) in ledger.operations.enumerated() {
                let giftName = op.details.trimmingCharacters(in: .whitespacesAndNewlines)
                let baseTitle = op.title.isEmpty ? pampGramUserDetailKindName(op.kind) : op.title
                let title = op.isGift && !giftName.isEmpty ? "\(baseTitle): \(giftName)" : baseTitle
                let label = pampGramUserDetailAmountText(currency: op.currency, amount: op.amount)
                var detailParts = [pampGramUserDetailKindName(op.kind), pampGramUserDetailFormatMs(Int64(op.date) * 1000)]
                if op.isGift {
                    detailParts.insert("NFT", at: 0)
                }
                if !op.isGift, !giftName.isEmpty, giftName != baseTitle {
                    detailParts.append(giftName)
                }
                entries.append(.ledgerOp(Int32(index), title, label, detailParts.joined(separator: " · ")))
            }
        }
    } else {
        entries.append(.nftEmpty("Локальных NFT мода пока нет."))
        entries.append(.ledgerHeader("ЛОКАЛЬНАЯ ИСТОРИЯ МОДА"))
        entries.append(.ledgerEmpty("Нет данных — устройство ещё не пушило /sync-ledger."))
    }

    entries.append(.reloadAction("Обновить"))
    entries.append(.footer("Сверху — настоящие Stars/TON из Telegram (его клиент шлёт раз в ~5 мин). Ниже — локальная история мода (визуальные балансы/NFT)."))
    return entries
}

/// Admin card for one user: who they are, when they opened the mod, PRO/STANDARD, ban, and
/// Stars/TON spend/credit history from their last synced ledger.
public func pampGramUserDetailController(context: AccountContext, userId: Int64, seed: PampGramUserSummary? = nil) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    var presentTooltipImpl: ((String) -> Void)?
    let detailPromise = Promise<PampGramUserDetail?>(nil)

    if let seed {
        detailPromise.set(.single(PampGramUserDetail(
            id: seed.id,
            username: seed.username,
            name: seed.name,
            appVersion: seed.appVersion,
            appBuild: "",
            firstSeen: seed.firstSeen,
            lastSeen: seed.lastSeen,
            sessions: [],
            tier: seed.tier,
            tierChangedAt: seed.tierChangedAt,
            expiresAt: nil,
            full: seed.full,
            sections: seed.sections,
            ledger: nil,
            real: nil
        )))
    }

    let requireAdminToken: (@escaping (String) -> Void) -> Void = { onToken in
        let _ = (context.account.postbox.transaction { transaction -> String? in
            return PampGramSubscriptionAPI.adminToken(transaction: transaction)
        }
        |> deliverOnMainQueue).start(next: { adminToken in
            guard let adminToken else {
                presentTooltipImpl?("Сначала задай админ-токен.")
                return
            }
            onToken(adminToken)
        })
    }

    let reload: () -> Void = {
        requireAdminToken { adminToken in
            PampGramSubscriptionAPI.fetchUserDetail(userId: userId, adminToken: adminToken) { detail in
                guard let detail else {
                    presentTooltipImpl?("Не удалось загрузить карточку.")
                    return
                }
                detailPromise.set(.single(detail))
            }
        }
    }

    let openBan: () -> Void = {
        requireAdminToken { adminToken in
            let _ = (detailPromise.get() |> take(1) |> deliverOnMainQueue).start(next: { detail in
                let user = detail?.summary ?? PampGramUserSummary(id: "\(userId)", tier: .standard, tierChangedAt: nil, lastSeen: 0, full: nil, sections: [:])
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                let sheet = ActionSheetController(presentationData: presentationData)
                var buttons: [ActionSheetItem] = []
                if let full = user.full {
                    buttons.append(ActionSheetTextItem(title: "Забанен полностью\nПричина: \(full.reason)\n\(pampGramUserDetailFormatOptionalMs(full.at))"))
                    buttons.append(ActionSheetButtonItem(title: "Снять полный бан", color: .accent, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                        PampGramSubscriptionAPI.unbanUser(userId: userId, scope: .full, adminToken: adminToken) { ok in
                            presentTooltipImpl?(ok ? "Полный бан снят." : "Не получилось.")
                            reload()
                        }
                    }))
                    buttons.append(ActionSheetButtonItem(title: "Ключ разбана (скопировать)", color: .accent, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                        PampGramSubscriptionAPI.generateUnbanKey(adminToken: adminToken) { key in
                            guard let key else {
                                presentTooltipImpl?("Не получилось сгенерировать ключ.")
                                return
                            }
                            UIPasteboard.general.string = key
                            presentTooltipImpl?("Ключ разбана скопирован: \(key)")
                        }
                    }))
                }
                for section in PampGramBanSection.allCases {
                    if let entry = user.sections[section.rawValue] {
                        buttons.append(ActionSheetTextItem(title: "Забанен: \(section.displayName)\nПричина: \(entry.reason)\n\(pampGramUserDetailFormatOptionalMs(entry.at))"))
                        buttons.append(ActionSheetButtonItem(title: "Снять бан «\(section.displayName)»", color: .accent, action: { [weak sheet] in
                            sheet?.dismissAnimated()
                            PampGramSubscriptionAPI.unbanUser(userId: userId, scope: .section(section), adminToken: adminToken) { ok in
                                presentTooltipImpl?(ok ? "Бан раздела снят." : "Не получилось.")
                                reload()
                            }
                        }))
                    }
                }
                if buttons.isEmpty {
                    buttons.append(ActionSheetTextItem(title: "Не забанен"))
                } else {
                    buttons.append(ActionSheetButtonItem(title: "Разбанить полностью", color: .destructive, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                        PampGramSubscriptionAPI.unbanUser(userId: userId, scope: .all, adminToken: adminToken) { ok in
                            presentTooltipImpl?(ok ? "Пользователь полностью разбанен." : "Не получилось.")
                            reload()
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
            })
        }
    }

    let openTier: () -> Void = {
        requireAdminToken { adminToken in
            let _ = (detailPromise.get() |> take(1) |> deliverOnMainQueue).start(next: { detail in
                let tier = detail?.tier ?? .standard
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                let sheet = ActionSheetController(presentationData: presentationData)
                let targetTier: PampGramSubscriptionTier = tier == .pro ? .standard : .pro
                sheet.setItemGroups([
                    ActionSheetItemGroup(items: [
                        ActionSheetTextItem(title: "Тариф: \(tier == .pro ? "PRO" : "STANDARD")\nИзменён: \(pampGramUserDetailFormatOptionalMs(detail?.tierChangedAt))"),
                        ActionSheetButtonItem(title: tier == .pro ? "Понизить до STANDARD" : "Повысить до PRO", color: .accent, action: { [weak sheet] in
                            sheet?.dismissAnimated()
                            PampGramSubscriptionAPI.grantTier(userId: userId, tier: targetTier, durationHours: nil, adminToken: adminToken) { ok in
                                presentTooltipImpl?(ok ? "Тариф изменён." : "Не получилось.")
                                reload()
                            }
                        })
                    ]),
                    ActionSheetItemGroup(items: [
                        ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                            sheet?.dismissAnimated()
                        })
                    ])
                ])
                presentControllerImpl?(sheet)
            })
        }
    }

    let forceVideo: () -> Void = {
        requireAdminToken { adminToken in
            presentControllerImpl?(promptController(
                context: context,
                text: "Видео на весь экран",
                subtitle: "HTTPS-ссылка на mp4/m3u8. Откроется у этого пользователя поверх приложения (~12 сек).",
                value: "",
                placeholder: "https://…/video.mp4",
                characterLimit: 2000,
                apply: { value in
                    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), value.lowercased().hasPrefix("https://") else {
                        presentTooltipImpl?("Нужна https-ссылка.")
                        return
                    }
                    PampGramSubscriptionAPI.forceVideo(targetId: "\(userId)", url: value, loop: true, dismissible: false, adminToken: adminToken) { ok in
                        presentTooltipImpl?(ok ? "Видео отправлено." : "Не получилось — проверь токен и URL.")
                    }
                }
            ))
        }
    }

    let clearVideo: () -> Void = {
        requireAdminToken { adminToken in
            PampGramSubscriptionAPI.clearForceVideo(targetId: "\(userId)", adminToken: adminToken) { ok in
                presentTooltipImpl?(ok ? "Видео для этого пользователя снято." : "Не получилось.")
            }
        }
    }

    let arguments = PampGramUserDetailArguments(
        reload: reload,
        openBan: openBan,
        openTier: openTier,
        forceVideo: forceVideo,
        clearVideo: clearVideo,
        copyId: {
            UIPasteboard.general.string = "\(userId)"
            presentTooltipImpl?("ID скопирован.")
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, detailPromise.get())
    |> deliverOnMainQueue
    |> map { presentationData, detail -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let title: String
        if let detail {
            if !detail.username.isEmpty {
                title = "@\(detail.username)"
            } else if !detail.name.isEmpty {
                title = detail.name
            } else {
                title = "ID \(detail.id)"
            }
        } else {
            title = "ID \(userId)"
        }
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(title),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: pampGramUserDetailEntries(detail: detail),
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

    reload()
    return controller
}
