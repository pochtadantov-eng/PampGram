import Foundation
import UIKit
import SwiftSignalKit

/// «Фейк входящий звонок» — полноэкранный экран входящего звонка от любого контакта.
///
/// Вибрация, звук, аватарка, кнопки «Принять/Отклонить». Можно «принять» — таймер тикает
/// как при настоящем разговоре. Для алиби: «Видишь, мне звонят, надо ответить».
///
/// Архитектура:
/// - Этот runtime управляет состоянием звонка (ringing → active → ended)
/// - Реальный UI-контроллер (`PampGramFakeCallViewController`) живёт в PampGramSettingsUI,
///   так как использует UIKit/экран целиком
/// - Runtime только хранит состояние и предоставляет API; UI подписывается на изменения
///
/// Integration points (в патче):
///
/// 1. Долгое нажатие на контакт в списке чатов → «Фейк звонок»:
///
///    ```swift
///    items.append(.action(ContextMenuActionItem(
///        text: "Фейк звонок",
///        icon: { theme in generateTintedImage(image: UIImage(bundleImageName: "Call/CallPhone"), color: theme.contextMenu.primaryColor) },
///        action: { c, _ in
///            c?.dismiss(completion: {
///                PampGramFakeIncomingCallRuntime.shared.triggerFakeCall(
///                    peerName: peer.displayTitle,
///                    avatarImage: avatarImage
///                )
///                let callVC = PampGramFakeCallViewController()
///                present(callVC, animated: true)
///            })
///        }
///    )))
///    ```
///
/// 2. UI-контроллер читает состояние из `PampGramFakeIncomingCallRuntime.shared.state`
///    и вызывает `acceptCall()` / `endCall()` по кнопкам.
///
/// 3. Для вибрации при входящем: `AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)`
///    каждые 2 секунды пока `state == .ringing`.
public final class PampGramFakeIncomingCallRuntime {
    public static let shared = PampGramFakeIncomingCallRuntime()

    public enum FakeCallState: Equatable {
        case idle
        case ringing
        case active(duration: TimeInterval)
        case ended

        public static func == (lhs: FakeCallState, rhs: FakeCallState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.ringing, .ringing), (.ended, .ended):
                return true
            case let (.active(d1), .active(d2)):
                return d1 == d2
            default:
                return false
            }
        }
    }

    public struct CallInfo {
        public let peerName: String
        public let avatarImage: UIImage?
        public let startTime: Date
    }

    private let lock = NSLock()
    private var _state: FakeCallState = .idle
    private var _callInfo: CallInfo?
    private var callTimer: SwiftSignalKit.Timer?
    private var callStartTime: Date?
    private var vibrationTimer: SwiftSignalKit.Timer?

    /// Колбэк на изменение состояния — UI подписывается на него.
    public var onStateChanged: ((FakeCallState, CallInfo?) -> Void)?

    private init() {}

    public var state: FakeCallState {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self._state
    }

    public var callInfo: CallInfo? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self._callInfo
    }

    /// Запускает фейковый входящий звонок.
    public func triggerFakeCall(peerName: String, avatarImage: UIImage?) {
        endCall()

        let info = CallInfo(peerName: peerName, avatarImage: avatarImage, startTime: Date())

        self.lock.lock()
        self._state = .ringing
        self._callInfo = info
        self.lock.unlock()

        startVibration()
        notifyStateChanged()
    }

    /// «Принять» фейковый звонок — таймер начинает тикать.
    public func acceptCall() {
        self.lock.lock()
        guard self._state == .ringing else {
            self.lock.unlock()
            return
        }
        self._state = .active(duration: 0)
        self.callStartTime = Date()
        self.lock.unlock()

        stopVibration()

        let timer = SwiftSignalKit.Timer(timeout: 1.0, repeat: true, completion: { [weak self] in
            guard let self else { return }
            self.lock.lock()
            guard let start = self.callStartTime else {
                self.lock.unlock()
                return
            }
            let duration = Date().timeIntervalSince(start)
            self._state = .active(duration: duration)
            self.lock.unlock()
            self.notifyStateChanged()
        }, queue: Queue.mainQueue())
        timer.start()

        self.lock.lock()
        self.callTimer = timer
        self.lock.unlock()

        notifyStateChanged()
    }

    /// Завершить фейковый звонок (отклонить или положить трубку).
    public func endCall() {
        self.lock.lock()
        let wasActive = self._state != .idle
        self._state = wasActive ? .ended : .idle
        self._callInfo = nil
        self.callStartTime = nil
        let timer = self.callTimer
        self.callTimer = nil
        self.lock.unlock()

        timer?.invalidate()
        stopVibration()

        if wasActive {
            notifyStateChanged()

            // Через 2 секунды сбросить в idle
            let resetTimer = SwiftSignalKit.Timer(timeout: 2.0, repeat: false, completion: { [weak self] in
                self?.lock.lock()
                self?._state = .idle
                self?.lock.unlock()
                self?.notifyStateChanged()
            }, queue: Queue.mainQueue())
            resetTimer.start()
        }
    }

    /// Форматирует длительность звонка для отображения: "0:05", "1:23:45"
    public static func formatDuration(_ duration: TimeInterval) -> String {
        let total = Int(duration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    private func startVibration() {
        stopVibration()
        let timer = SwiftSignalKit.Timer(timeout: 2.0, repeat: true, completion: {
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        }, queue: Queue.mainQueue())
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        timer.start()
        self.lock.lock()
        self.vibrationTimer = timer
        self.lock.unlock()
    }

    private func stopVibration() {
        self.lock.lock()
        let timer = self.vibrationTimer
        self.vibrationTimer = nil
        self.lock.unlock()
        timer?.invalidate()
    }

    private func notifyStateChanged() {
        let state = self.state
        let info = self.callInfo
        Queue.mainQueue().async {
            self.onStateChanged?(state, info)
        }
    }
}
