import Foundation
import Postbox

private let secretChatNamespace = PeerId.Namespace._internalFromInt32Value(3)

public final class PampGramFakeScreenshotNotificationRuntime {
    public static let shared = PampGramFakeScreenshotNotificationRuntime()

    public var sendScreenshotNotificationHandler: ((_ peerId: PeerId) -> Void)?

    private init() {}

    public func sendFakeScreenshotNotification(peerId: PeerId) {
        guard peerId.namespace == secretChatNamespace else {
            return
        }
        sendScreenshotNotificationHandler?(peerId)
    }

    public func isSecretChat(peerId: PeerId) -> Bool {
        return peerId.namespace == secretChatNamespace
    }
}
