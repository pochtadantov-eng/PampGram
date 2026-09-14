import Foundation
import AccountContext
import TelegramCore

/**
 PUBLIC API для интеграции меню визуального чата
 ================================================

 Экспортирует публичный интерфейс для использования в Telegram-iOS
 */

/// Показывает меню создания визуального чата
/// - Parameters:
///   - context: AccountContext текущего аккаунта
///   - peerId: ID пира (чата/пользователя)
///
/// Использование:
/// ```swift
/// // Из ChatInputPanel или ChatController
/// PampGramVisualChat.presentMenu(context: self.context, peerId: peerId)
/// ```
public struct PampGramVisualChat {
    public static func presentMenu(context: AccountContext, peerId: EnginePeer.Id) {
        pampGramPresentVisualChatMenu(context: context, peerId: peerId)
    }
}

/// Быстрое добавление одного текстового сообщения
/// - Parameters:
///   - context: AccountContext
///   - peerId: ID пира
///   - text: Текст сообщения
///   - isIncoming: true = от собеседника, false = от меня
public func pampGramVisualChatAddText(
    context: AccountContext,
    peerId: EnginePeer.Id,
    text: String,
    isIncoming: Bool
) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    let insert = isIncoming
        ? pampGramInsertIncomingMessage(context: context, peerId: peerId, text: trimmed, media: [])
        : pampGramInsertOutgoingMessage(context: context, peerId: peerId, text: trimmed, media: [])

    let _ = insert.start()
}

/// Версии для быстрого добавления сообщений:
public func pampGramVisualChatAddMyText(context: AccountContext, peerId: EnginePeer.Id, text: String) {
    pampGramVisualChatAddText(context: context, peerId: peerId, text: text, isIncoming: false)
}

public func pampGramVisualChatAddTheirText(context: AccountContext, peerId: EnginePeer.Id, text: String) {
    pampGramVisualChatAddText(context: context, peerId: peerId, text: text, isIncoming: true)
}

// Re-export for convenience
// These functions already exist in PampGramFakeContentInsert.swift
public func pampGramVisualChatAddMyPhoto(context: AccountContext, peerId: EnginePeer.Id) {
    pampGramPresentInsertPhoto(context: context, peerId: peerId)
}

public func pampGramVisualChatAddTheirPhoto(context: AccountContext, peerId: EnginePeer.Id) {
    pampGramPresentInsertPhoto(context: context, peerId: peerId)
}

public func pampGramVisualChatAddMyVoice(context: AccountContext, peerId: EnginePeer.Id) {
    pampGramPresentInsertFile(context: context, peerId: peerId, asVoice: true)
}

public func pampGramVisualChatAddTheirVoice(context: AccountContext, peerId: EnginePeer.Id) {
    pampGramPresentInsertFile(context: context, peerId: peerId, asVoice: true)
}
