import Foundation

/// "Невидимые сообщения" — отправка сообщений из невидимых Unicode-символов.
///
/// Собеседник получает пуш-уведомление «Новое сообщение», открывает чат — а там визуально
/// пусто. Сообщение реальное (не локальное), просто состоит целиком из zero-width символов,
/// которые не отображаются в шрифте.
///
/// Используемые символы (смешиваются для обхода возможных фильтров):
/// - U+200B — Zero Width Space
/// - U+200C — Zero Width Non-Joiner
/// - U+200D — Zero Width Joiner
/// - U+2060 — Word Joiner
/// - U+FEFF — Zero Width No-Break Space (BOM)
///
/// Integration points (в патче):
///
/// 1. Контекстное меню чата (навбар или «⋯») — пункт «Невидимое сообщение»:
///    ```swift
///    if PampGramInvisibleMessageRuntime.shared.isAvailable {
///        items.append(.action(ContextMenuActionItem(
///            text: "Невидимое сообщение 👻",
///            icon: { theme in generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Eye"), color: theme.contextMenu.primaryColor) },
///            action: { c, _ in
///                c?.dismiss(completion: {
///                    let text = PampGramInvisibleMessageRuntime.shared.generateInvisibleText(length: 1)
///                    // Отправить text как обычное сообщение через enqueueMessages
///                })
///            }
///        )))
///    }
///    ```
///
/// 2. Или через поле ввода — специальная команда `/invisible` или `/👻`:
///    ```swift
///    if text.hasPrefix("/invisible") || text.hasPrefix("/👻") {
///        let invisibleText = PampGramInvisibleMessageRuntime.shared.generateInvisibleText(length: 1)
///        // Подменить text на invisibleText и отправить
///    }
///    ```
///
/// 3. Детекция (для отображения подсказки в своём чате):
///    ```swift
///    if PampGramInvisibleMessageRuntime.shared.isInvisibleMessage(message.text) {
///        // Показать маленький бейдж "👻" или подсказку "невидимое"
///    }
///    ```
public final class PampGramInvisibleMessageRuntime {
    public static let shared = PampGramInvisibleMessageRuntime()

    private static let zeroWidthChars: [Character] = [
        "\u{200B}",
        "\u{200C}",
        "\u{200D}",
        "\u{2060}",
        "\u{FEFF}"
    ]

    public var isAvailable: Bool { true }

    private init() {}

    /// Генерирует строку из невидимых символов заданной длины.
    /// `length` — количество символов (по умолчанию 1, обычно достаточно).
    /// Символы выбираются случайно из набора для обхода потенциальных фильтров.
    public func generateInvisibleText(length: Int = 1) -> String {
        let chars = Self.zeroWidthChars
        var result = ""
        for _ in 0..<max(1, length) {
            let index = Int.random(in: 0..<chars.count)
            result.append(chars[index])
        }
        return result
    }

    /// Проверяет, состоит ли сообщение целиком из невидимых символов.
    /// Используется для отображения подсказки «👻 невидимое» в своём чате.
    public func isInvisibleMessage(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let zeroWidthSet = CharacterSet(charactersIn: "\u{200B}\u{200C}\u{200D}\u{2060}\u{FEFF}")
        return text.unicodeScalars.allSatisfy { zeroWidthSet.contains($0) }
    }

    /// Генерирует «невидимый» ответ заданной «кажущейся длины».
    /// Полезно, если хочется, чтобы у собеседника в пуше отображалось
    /// "Сообщение" (а не пустота) — Telegram иногда обрезает пустые строки.
    /// `paddedLength` добавляет обычные пробелы в начале (Telegram их рендерит как пустоту,
    /// но не обрезает так агрессивно).
    public func generatePaddedInvisibleText(paddedLength: Int = 3) -> String {
        var result = generateInvisibleText(length: 1)
        for _ in 0..<paddedLength {
            result = "\u{200B}" + result
        }
        return result
    }
}
