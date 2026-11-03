import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import AccountContext

/// «Клон голоса» — захватывает образец голоса из голосового сообщения собеседника,
/// затем генерирует новые голосовые сообщения этим голосом из текста.
///
/// ⚠️ ТЕКУЩАЯ РЕАЛИЗАЦИЯ — ЗАГЛУШКА.
/// Полноценный voice cloning требует ML-модели (например XTTS, Coqui TTS, или Apple's
/// Personal Voice API на iOS 17+). Эта заглушка реализует:
/// - Захват и хранение образца голоса (путь к аудиофайлу)
/// - Интерфейс генерации (вызов completion с nil пока нет бекенда)
/// - Все точки интеграции для подключения реального TTS-бекенда
///
/// Когда ML-бекенд будет готов, заменить тело `generateVoiceMessage` на вызов модели.
///
/// Integration points (в патче):
///
/// 1. Долгое нажатие на чужое голосовое сообщение → «Захватить голос»:
///
///    ```swift
///    items.append(.action(ContextMenuActionItem(
///        text: "Захватить голос",
///        icon: { theme in generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Microphone"), color: theme.contextMenu.primaryColor) },
///        action: { c, _ in
///            c?.dismiss(completion: {
///                if let file = message.media.compactMap({ $0 as? TelegramMediaFile }).first,
///                   file.isVoice || file.isInstantVideo {
///                    let path = context.account.postbox.mediaBox.resourcePath(file.resource)
///                    PampGramVoiceClonerRuntime.shared.captureVoiceSample(
///                        from: path,
///                        peerId: message.author?.id ?? message.id.peerId
///                    )
///                }
///            })
///        }
///    )))
///    ```
///
/// 2. В поле ввода → «Голосовое чужим голосом»:
///
///    ```swift
///    PampGramVoiceClonerRuntime.shared.generateVoiceMessage(
///        text: inputText,
///        samplePeerId: peerId
///    ) { audioPath in
///        guard let audioPath else { return } // ML-бекенд не подключён
///        // Отправить audioPath как голосовое сообщение
///    }
///    ```
public final class PampGramVoiceClonerRuntime {
    public static let shared = PampGramVoiceClonerRuntime()

    private let lock = NSLock()
    /// peerId → путь к аудиофайлу-образцу голоса
    private var samples: [Int64: String] = [:]

    private init() {}

    /// Сохраняет путь к аудиофайлу как образец голоса собеседника.
    /// Перезаписывает предыдущий образец для этого peer.
    public func captureVoiceSample(from audioPath: String, peerId: PeerId) {
        let key = peerId.toInt64()

        let sampleDir = PampGramVoiceClonerRuntime.samplesDirectory()
        let destPath = sampleDir.appendingPathComponent("voice_sample_\(key).ogg").path

        try? FileManager.default.createDirectory(at: sampleDir, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(atPath: destPath)
        try? FileManager.default.copyItem(atPath: audioPath, toPath: destPath)

        self.lock.lock()
        self.samples[key] = destPath
        self.lock.unlock()
    }

    /// Проверяет, есть ли сохранённый образец голоса для данного peer.
    public func hasSample(peerId: PeerId) -> Bool {
        let key = peerId.toInt64()
        self.lock.lock()
        defer { self.lock.unlock() }
        guard let path = self.samples[key] else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    /// Получить путь к образцу голоса.
    public func samplePath(peerId: PeerId) -> String? {
        let key = peerId.toInt64()
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.samples[key]
    }

    /// Генерирует голосовое сообщение из текста, используя образец голоса собеседника.
    ///
    /// ⚠️ ЗАГЛУШКА — всегда вызывает completion(nil).
    /// Замените тело этого метода на вызов ML-бекенда (XTTS, Coqui TTS, Apple Personal Voice)
    /// когда он будет готов. Бекенд должен:
    /// 1. Загрузить образец из `samplePath(peerId:)`
    /// 2. Синтезировать речь из `text` с тембром образца
    /// 3. Сохранить результат как .ogg и вернуть путь через `completion`
    public func generateVoiceMessage(text: String, samplePeerId: PeerId, completion: @escaping (String?) -> Void) {
        guard hasSample(peerId: samplePeerId) else {
            completion(nil)
            return
        }

        // TODO: подключить ML-бекенд для синтеза речи с клонированным голосом
        // let sample = samplePath(peerId: samplePeerId)!
        // MLVoiceCloner.synthesize(text: text, voiceSample: sample) { resultPath in
        //     completion(resultPath)
        // }

        completion(nil)
    }

    /// Удаляет образец голоса для данного peer.
    public func removeSample(peerId: PeerId) {
        let key = peerId.toInt64()
        self.lock.lock()
        let path = self.samples.removeValue(forKey: key)
        self.lock.unlock()
        if let path {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    /// Удаляет все образцы.
    public func removeAllSamples() {
        self.lock.lock()
        let all = self.samples
        self.samples.removeAll()
        self.lock.unlock()
        for (_, path) in all {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    /// Все peer-ы с захваченными образцами.
    public func capturedPeerKeys() -> [Int64] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return Array(self.samples.keys)
    }

    private static func samplesDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("PampGram/VoiceSamples", isDirectory: true)
    }
}
