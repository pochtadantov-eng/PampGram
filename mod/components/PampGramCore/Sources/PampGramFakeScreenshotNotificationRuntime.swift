import Foundation
import Postbox

public final class PampGramFakeScreenshotNotificationRuntime {
    public static let shared = PampGramFakeScreenshotNotificationRuntime()

    public var sendScreenshotNotificationHandler: ((_ peerId: PeerId) -> Void)?

    private init() {}

    public func sendFakeScreenshotNotification(peerId: PeerId) {
        guard peerId.namespace == Namespaces.Peer.SecretChat else {
            return
        }
        sendScreenshotNotificationHandler?(peerId)
    }

    public func isSecretChat(peerId: PeerId) -> Bool {
        return peerId.namespace == Namespaces.Peer.SecretChat
    }
}
