import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import AccountContext

/// «Фейк системные сообщения» — вставляет в чат сообщения, которые выглядят как от Telegram.
///
/// Серый текст по центру, без отправителя — идентично настоящим системным сообщениям:
/// «Этот аккаунт верифицирован», «Пользователь сменил номер», «Аккаунт заблокирован за нарушения»
/// и т.д. Локально — собеседник ничего не видит, но на скриншоте не отличить.
///
/// Integration point (в патче):
///
/// 1. Контекстное меню чата (навбар или «⋯»): добавить пункт «Фейк системное»:
///
///    ```swift
///    items.append(.action(ContextMenuActionItem(
///        text: "Фейк системное",
///        icon: { theme in generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Info"), color: theme.contextMenu.primaryColor) },
///        action: { c, _ in
///            c?.dismiss(completion: {
///                // Показать пикер типа сообщения, затем:
///                PampGramFakeSystemMessagesRuntime.shared.insertSystemMessage(
///                    context: context,
///                    peerId: peerId,
///                    type: .accountVerified
///                )
///            })
///        }
///    )))
///    ```
///
/// 2. В рендеринге сообщений: если сообщение содержит `PampGramFakeSystemMessageAttribute`,
///    отрисовывать его как системное (серый текст по центру, без пузыря).
public final class PampGramFakeSystemMessagesRuntime {
    public static let shared = PampGramFakeSystemMessagesRuntime()

    public enum SystemMessageType: CaseIterable {
        case accountVerified
        case phoneChanged
        case accountBanned
        case messageVerified
        case accountRestricted

        public static var allCases: [SystemMessageType] {
            return [.accountVerified, .phoneChanged, .accountBanned, .messageVerified, .accountRestricted]
        }

        public var displayText: String {
            switch self {
            case .accountVerified:
                return "Этот аккаунт верифицирован Telegram"
            case .phoneChanged:
                return "Пользователь сменил номер телефона"
            case .accountBanned:
                return "Аккаунт заблокирован за нарушение правил Telegram"
            case .messageVerified:
                return "Это сообщение проверено и подтверждено Telegram"
            case .accountRestricted:
                return "Аккаунт временно ограничен"
            }
        }

        public var menuTitle: String {
            switch self {
            case .accountVerified: return "Аккаунт верифицирован"
            case .phoneChanged: return "Сменил номер"
            case .accountBanned: return "Аккаунт заблокирован"
            case .messageVerified: return "Сообщение подтверждено"
            case .accountRestricted: return "Аккаунт ограничен"
            }
        }
    }

    private init() {}

    /// Вставляет фейковое системное сообщение в чат.
    ///
    /// Использует `enqueueMessages` для создания локального сообщения. Текст берётся из
    /// `SystemMessageType.displayText`. Для кастомного текста используйте `insertCustomSystemMessage`.
    ///
    /// Сообщение отправляется как обычный текст — чтобы оно отображалось как системное,
    /// нужен патч в рендеринге, который проверяет `PampGramFakeSystemMessageAttribute`.
    public func insertSystemMessage(context: AccountContext, peerId: PeerId, type: SystemMessageType) {
        insertCustomSystemMessage(context: context, peerId: peerId, text: type.displayText)
    }

    /// Вставляет произвольный текст как системное сообщение.
    public func insertCustomSystemMessage(context: AccountContext, peerId: PeerId, text: String) {
        let _ = enqueueMessages(
            account: context.account,
            peerId: peerId,
            messages: [
                .message(
                    text: text,
                    attributes: [],
                    inlineStickers: [:],
                    mediaReference: nil,
                    threadId: nil,
                    replyToMessageId: nil,
                    replyToStoryId: nil,
                    localGroupingKey: nil,
                    correlationId: nil,
                    bubbleUpEmojiOrStickersets: []
                )
            ]
        ).start()
    }
}
