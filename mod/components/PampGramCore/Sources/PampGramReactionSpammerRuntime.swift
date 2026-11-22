import Foundation
import Postbox
import SwiftSignalKit

public final class PampGramReactionSpammerRuntime {
    public static let shared = PampGramReactionSpammerRuntime()

    private struct ActiveSpammer {
        let messageId: MessageId
        let reaction: String
        let timer: SwiftSignalKit.Timer
        let disposable: Disposable
    }

    private let lock = NSLock()
    private var spammers: [MessageId: ActiveSpammer] = [:]

    /// Injected by AccountContext startup (has TelegramCore access).
    /// Toggles a reaction on/off for a message. `reaction` nil = remove.
    public var toggleReactionHandler: ((_ messageId: MessageId, _ reaction: String?) -> Void)?

    private init() {}

    public func start(messageId: MessageId, peerId: PeerId, reaction: String, interval: Double = 1.0) {
        stop(messageId: messageId)

        var isSet = false

        let toggle: () -> Void = { [weak self] in
            guard let self else { return }
            if isSet {
                self.toggleReactionHandler?(messageId, nil)
            } else {
                self.toggleReactionHandler?(messageId, reaction)
            }
            isSet = !isSet
        }

        toggle()

        let timer = SwiftSignalKit.Timer(timeout: interval, repeat: true, completion: {
            toggle()
        }, queue: Queue.mainQueue())
        timer.start()

        let disposable = ActionDisposable {
            timer.invalidate()
        }

        self.lock.lock()
        self.spammers[messageId] = ActiveSpammer(
            messageId: messageId,
            reaction: reaction,
            timer: timer,
            disposable: disposable
        )
        self.lock.unlock()
    }

    public func stop(messageId: MessageId) {
        self.lock.lock()
        let spammer = self.spammers.removeValue(forKey: messageId)
        self.lock.unlock()
        spammer?.disposable.dispose()
    }

    public func stopAll(forPeerId peerId: PeerId) {
        self.lock.lock()
        let matching = self.spammers.filter { $0.key.peerId == peerId }
        for key in matching.keys {
            self.spammers.removeValue(forKey: key)
        }
        self.lock.unlock()
        for (_, spammer) in matching {
            spammer.disposable.dispose()
        }
    }

    public func stopAll() {
        self.lock.lock()
        let all = self.spammers
        self.spammers.removeAll()
        self.lock.unlock()
        for (_, spammer) in all {
            spammer.disposable.dispose()
        }
    }

    public func isActive(messageId: MessageId) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.spammers[messageId] != nil
    }

    public func activeCount() -> Int {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.spammers.count
    }
}
