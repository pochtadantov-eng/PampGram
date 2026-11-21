import Foundation
import SwiftSignalKit
import PampGramCore

/// Polls `/force-video` and drives `PampGramForceVideoOverlay` so an admin can push a
/// fullscreen video onto this install without the user opening PampGram settings.
public final class PampGramForceVideoRuntime {
    public static let shared = PampGramForceVideoRuntime()

    private static let pollIntervalSeconds: Double = 12.0

    private let lock = NSLock()
    private var startedAccounts: Set<Int64> = []
    private var timers: [Int64: SwiftSignalKit.Timer] = [:]
    private var inFlight: Set<Int64> = []
    private var activeUserId: Int64?

    private init() {
    }

    public func start(userId: Int64) {
        self.lock.lock()
        self.activeUserId = userId
        if self.startedAccounts.contains(userId) {
            self.lock.unlock()
            self.poll(userId: userId)
            return
        }
        self.startedAccounts.insert(userId)
        self.lock.unlock()

        self.poll(userId: userId)
        let queue = Queue.mainQueue()
        let timer = SwiftSignalKit.Timer(timeout: PampGramForceVideoRuntime.pollIntervalSeconds, repeat: true, completion: { [weak self] in
            self?.poll(userId: userId)
        }, queue: queue)
        self.lock.lock()
        self.timers[userId] = timer
        self.lock.unlock()
        timer.start()
    }

    private func poll(userId: Int64) {
        self.lock.lock()
        if self.inFlight.contains(userId) {
            self.lock.unlock()
            return
        }
        self.inFlight.insert(userId)
        let active = self.activeUserId
        self.lock.unlock()

        PampGramSubscriptionAPI.fetchForceVideo(userId: userId) { [weak self] command in
            guard let self else {
                return
            }
            self.lock.lock()
            self.inFlight.remove(userId)
            let stillActive = self.activeUserId == userId || active == userId
            self.lock.unlock()
            guard stillActive else {
                return
            }
            PampGramForceVideoOverlay.shared.apply(command)
        }
    }
}
