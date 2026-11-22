import Foundation
import Postbox
import SwiftSignalKit

public final class PampGramFakeActivityRuntime {
    public static let shared = PampGramFakeActivityRuntime()

    public enum Mode: String, CaseIterable {
        case typing
        case recordingVoice
        case uploadingVideo
        case recordingRound

        public var displayName: String {
            switch self {
            case .typing: return "Печатает..."
            case .recordingVoice: return "Записывает ГС..."
            case .uploadingVideo: return "Записывает видео..."
            case .recordingRound: return "Записывает кружок..."
            }
        }
    }

    private struct ActiveSession {
        let peerId: PeerId
        let mode: Mode
        let timer: SwiftSignalKit.Timer
        let disposable: Disposable
    }

    private let lock = NSLock()
    private var sessions: [Int64: ActiveSession] = [:]

    /// Injected by AccountContext startup (has TelegramCore access).
    /// Sends a typing/recording activity to the given peer. Pass nil mode to clear.
    public var sendActivityHandler: ((_ peerId: PeerId, _ threadId: Int64?, _ mode: Mode?) -> Void)?

    private init() {}

    public func start(peerId: PeerId, threadId: Int64? = nil, mode: Mode) {
        let key = peerId.toInt64()

        stop(peerId: peerId)

        let sendActivity: () -> Void = { [weak self] in
            guard let self else { return }
            self.sendActivityHandler?(peerId, threadId, mode)
        }

        sendActivity()

        let timer = SwiftSignalKit.Timer(timeout: 4.0, repeat: true, completion: {
            sendActivity()
        }, queue: Queue.mainQueue())
        timer.start()

        let disposable = ActionDisposable { [weak self] in
            timer.invalidate()
            self?.sendActivityHandler?(peerId, threadId, nil)
        }

        self.lock.lock()
        self.sessions[key] = ActiveSession(peerId: peerId, mode: mode, timer: timer, disposable: disposable)
        self.lock.unlock()
    }

    public func stop(peerId: PeerId) {
        let key = peerId.toInt64()
        self.lock.lock()
        let session = self.sessions.removeValue(forKey: key)
        self.lock.unlock()
        session?.disposable.dispose()
    }

    public func stopAll() {
        self.lock.lock()
        let all = self.sessions
        self.sessions.removeAll()
        self.lock.unlock()
        for (_, session) in all {
            session.disposable.dispose()
        }
    }

    public func isActive(peerId: PeerId) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.sessions[peerId.toInt64()] != nil
    }

    public func currentMode(peerId: PeerId) -> Mode? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.sessions[peerId.toInt64()]?.mode
    }

    public func activePeerIds() -> [PeerId] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.sessions.values.map { $0.peerId }
    }
}
