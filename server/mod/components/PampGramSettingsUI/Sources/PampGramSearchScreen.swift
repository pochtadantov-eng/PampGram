import Foundation
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

private enum PampGramSearchDestination: Int32 {
    case gifts, messages, ghost, appearance, other, additional, status
}

private struct PampGramSearchItem: Equatable {
    let title: String
    let section: String
    let detail: String
    let keywords: String
    let destination: PampGramSearchDestination
}

private let pampGramSearchCatalog: [PampGramSearchItem] = [
    .init(title: "Подарок ему", section: "Подарки", detail: "Визуальная отправка подарка", keywords: "от себя ему подарок вкладка", destination: .gifts),
    .init(title: "Подарок мне", section: "Подарки", detail: "Подарок выглядит полученным от собеседника", keywords: "от него мне подарок вкладка", destination: .gifts),
    .init(title: "Локальные звёзды", section: "Подарки", detail: "Локальный баланс Stars", keywords: "stars звезды баланс", destination: .gifts),
    .init(title: "Локальные TON", section: "Подарки", detail: "Локальный баланс TON/GRAM", keywords: "ton gram тоны баланс", destination: .gifts),
    .init(title: "Локальные рубли", section: "Подарки", detail: "Локальная карта для визуальной покупки Stars", keywords: "рубли карта купить звезды", destination: .gifts),
    .init(title: "Удалённые сообщения", section: "Чаты", detail: "Локальное сохранение удалённых сообщений", keywords: "антиудаление удаленные сообщения", destination: .messages),
    .init(title: "Изменить визуально", section: "Чаты", detail: "Локальное изменение отображаемого текста", keywords: "редактор сообщение визуально", destination: .messages),
    .init(title: "Нечиталка", section: "Ghost", detail: "Управление локальными privacy-функциями", keywords: "ghost read прочитано", destination: .ghost),
    .init(title: "Маскировка онлайна", section: "Ghost", detail: "Настройки отображения присутствия", keywords: "онлайн online ghost", destination: .ghost),
    .init(title: "Иконка приложения", section: "Статус", detail: "Выбор альтернативной иконки PampGram", keywords: "иконка значок цвет синяя", destination: .status),
    .init(title: "Обход защиты от копирования", section: "Прочее", detail: "Настройка копирования в обычных облачных чатах", keywords: "копировать copy защита", destination: .other),
    .init(title: "Добавлять от кого переслано", section: "Прочее", detail: "Показывать источник пересланного сообщения", keywords: "переслано forward автор", destination: .other),
    .init(title: "Отключить автоудаление", section: "Прочее", detail: "Локальная настройка исчезающих сообщений", keywords: "таймер исчезающие автоудаление", destination: .other),
    .init(title: "Обход защиты от скриншотов", section: "Прочее", detail: "Настройка скриншотов обычных чатов", keywords: "скрин screenshot защита", destination: .other),
    .init(title: "Скрывать чат на скриншотах", section: "Прочее", detail: "Маска при захвате экрана", keywords: "скрин запись экран скрыть", destination: .other),
    .init(title: "Блокировать рекламу", section: "Прочее", detail: "Скрытие sponsored-сообщений", keywords: "реклама ads sponsored", destination: .other),
    .init(title: "Изменение голоса", section: "Дополнительно", detail: "Пресеты для новых голосовых сообщений", keywords: "голос voice", destination: .additional),
    .init(title: "Ускорение загрузки", section: "Дополнительно", detail: "Профиль параллельной загрузки", keywords: "upload скорость", destination: .additional),
    .init(title: "Ускорение скачивания", section: "Дополнительно", detail: "Профиль параллельного скачивания", keywords: "download скорость", destination: .additional),
    .init(title: "Фейковая геолокация", section: "Дополнительно", detail: "Локальная подстановка координаты при отправке", keywords: "гео location координаты", destination: .additional),
    .init(title: "Блокировка чатов", section: "Дополнительно", detail: "Локальный PIN для выбранных чатов", keywords: "pin пароль lock", destination: .additional)
]

private func pampGramSearchScore(_ item: PampGramSearchItem, query: String) -> Int {
    let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    if q.isEmpty { return 1 }
    let title = item.title.lowercased()
    let haystack = "\(title) \(item.section.lowercased()) \(item.detail.lowercased()) \(item.keywords.lowercased())"
    if title == q { return 100 }
    if title.hasPrefix(q) { return 80 }
    if title.contains(q) { return 65 }
    if haystack.contains(q) { return 50 }
    let tokens = q.split(separator: " ").map(String.init)
    let matches = tokens.filter { haystack.contains($0) }.count
    return matches == 0 ? 0 : 20 + matches * 8
}

private final class PampGramSearchArguments {
    let update: (String) -> Void
    let open: (PampGramSearchDestination) -> Void
    init(update: @escaping (String) -> Void, open: @escaping (PampGramSearchDestination) -> Void) { self.update = update; self.open = open }
}

private enum PampGramSearchEntry: ItemListNodeEntry {
    case input(String)
    case result(Int32, PampGramSearchItem)
    case empty(String)
    var section: ItemListSectionId { return 0 }
    var stableId: Int32 { switch self { case .input: return 0; case let .result(i, _): return 10 + i; case .empty: return 999 } }
    static func <(lhs: Self, rhs: Self) -> Bool { lhs.stableId < rhs.stableId }
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! PampGramSearchArguments
        switch self {
        case let .input(text):
            return ItemListMultilineInputItem(presentationData: presentationData, systemStyle: .glass, text: text, placeholder: "Поиск функции или раздела", maxLength: ItemListMultilineInputItemTextLimit(value: 80, display: false), sectionId: 0, style: .blocks, capitalization: false, autocorrection: true, textUpdated: arguments.update)
        case let .result(_, result):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: result.title, label: result.section, additionalDetailLabel: result.detail, sectionId: 0, style: .blocks, action: { arguments.open(result.destination) })
        case let .empty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: 0)
        }
    }
}

public func pampGramSearchController(context: AccountContext) -> ViewController {
    let query = ValuePromise<String>("", ignoreRepeated: true)
    var push: ((ViewController) -> Void)?
    let arguments = PampGramSearchArguments(update: { query.set($0) }, open: { destination in
        let controller: ViewController
        switch destination {
        case .gifts: controller = pampGramGiftsSettingsController(context: context)
        case .messages: controller = pampGramMessagesSettingsController(context: context)
        case .ghost: controller = pampGramGhostSettingsController(context: context)
        case .appearance: controller = pampGramPlaceholderController(context: context, title: "Внешний вид")
        case .other: controller = pampGramOtherSettingsController(context: context)
        case .additional: controller = pampGramAdditionalSettingsController(context: context)
        case .status: controller = pampGramStatusController(context: context)
        }
        push?(controller)
    })
    let signal = combineLatest(context.sharedContext.presentationData, query.get())
    |> map { presentationData, text -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let ranked = pampGramSearchCatalog.map { ($0, pampGramSearchScore($0, query: text)) }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.prefix(text.isEmpty ? 8 : 12)
        var entries: [PampGramSearchEntry] = [.input(text)]
        if ranked.isEmpty { entries.append(.empty("Ничего похожего не найдено. Попробуй другое слово.")) }
        else { for (index, pair) in ranked.enumerated() { entries.append(.result(Int32(index), pair.0)) } }
        return (ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Поиск"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false), (ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true), arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    push = { [weak controller] c in controller?.push(c) }
    return controller
}
