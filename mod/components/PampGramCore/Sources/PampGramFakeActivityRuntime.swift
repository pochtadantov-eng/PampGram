import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import AccountContext

/// "Фейк набор текста" — непрерывная отправка статуса активности собеседнику.
///
/// Telegram показывает "печатает..." примерно 6 секунд после последнего `sendTypingActivity`.
/// Этот runtime шлёт `sendTypingActivity` каждые 4 секунды, поддерживая статус непрерывно.
///
/// Режимы:
/// - `.typing` — "печатает..."
/// - `.recordingVoice` — "записывает голосовое..."
/// - `.uploadingVideo` — "записывает видео..."
/// - `.recordingRound` — "записывает видеосообщение..."
///
/// Integration points (в патче):
///
/// 1. Контекстное меню чата (навбар или «⋯»): добавить пункт «Фейк печатает» /
///    «Фейк записывает ГС» — при нажатии вызывает:
///    ```swift
///    PampGramFakeActivityRuntime.shared.start(context: context, peerId: peerId, mode: .typing)
///    ```
///
/// 2. При выходе из чата или повторном нажатии:
///    ```swift
///    PampGramFakeActivityRuntime.shared.stop(peerId: peerId)
///    ```
///
/// 3. Индикатор в навбаре (опционально): если `isActive(peerId:)` — показать точку
///    или бейдж, чтобы пользователь помнил что фейк идёт.
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

    private init() {}

    /// Начать отправку фейковой активности собеседнику.
    /// Если уже есть активная сессия для этого peer — перезапускает с новым режимом.
    public func start(context: AccountContext, peerId: PeerId, threadId: Int64? = nil, mode: Mode) {
        let key = peerId.toInt64()

        stop(peerId: peerId)

        let sendActivity: () -> Void = { [weak self] in
            guard self != nil else { return }
            let activity: TelegramEngineInputActivity
            switch mode {
            case .typing:
                activity = .typingText
            case .recordingVoice:
                activity = .recordingVoice
            case .uploadingVideo:
                activity = .uploadingVideo
            case .recordingRound:
                activity = .recordingInstantVideo
            }

            let _ = context.engine.messages.updatePeerChatInputActivity(
                peerId: peerId,
                threadId: threadId,
                activity: activity
            ).startStandalone()
        }

        sendActivity()

        let timer = SwiftSignalKit.Timer(timeout: 4.0, repeat: true, completion: {
            sendActivity()
        }, queue: Queue.mainQueue())
        timer.start()

        let disposable = ActionDisposable {
            timer.invalidate()
            let _ = context.engine.messages.updatePeerChatInputActivity(
                peerId: peerId,
                threadId: threadId,
                activity: nil
            ).startStandalone()
        }

        self.lock.lock()
        self.sessions[key] = ActiveSession(peerId: peerId, mode: mode, timer: timer, disposable: disposable)
        self.lock.unlock()
    }

    /// Остановить фейковую активность для собеседника.
    public func stop(peerId: PeerId) {
        let key = peerId.toInt64()
        self.lock.lock()
        let session = self.sessions.removeValue(forKey: key)
        self.lock.unlock()
        session?.disposable.dispose()
    }

    /// Остановить все сессии (например при выходе из аккаунта).
    public func stopAll() {
        self.lock.lock()
        let all = self.sessions
        self.sessions.removeAll()
        self.lock.unlock()
        for (_, session) in all {
            session.disposable.dispose()
        }
    }

    /// Проверить, активен ли фейк для данного peer.
    public func isActive(peerId: PeerId) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.sessions[peerId.toInt64()] != nil
    }

    /// Получить текущий режим для peer (nil если не активен).
    public func currentMode(peerId: PeerId) -> Mode? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.sessions[peerId.toInt64()]?.mode
    }

    /// Все peer-ы с активным фейком.
    public func activePeerIds() -> [PeerId] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.sessions.values.map { $0.peerId }
    }
}
