import Foundation
import Postbox
import SwiftSignalKit

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

    public var enqueueMessageHandler: ((_ peerId: PeerId, _ text: String) -> Void)?

    private init() {}

    public func insertSystemMessage(peerId: PeerId, type: SystemMessageType) {
        insertCustomSystemMessage(peerId: peerId, text: type.displayText)
    }

    public func insertCustomSystemMessage(peerId: PeerId, text: String) {
        enqueueMessageHandler?(peerId, text)
    }
}
