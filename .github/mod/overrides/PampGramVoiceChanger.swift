import Foundation
import AVFoundation
import OpusBinding
import TelegramCore
import PampGramCore

/// Offline voice-note pitch shifter used only for newly recorded voice messages.
/// It intentionally keeps tempo at 1.0: changing the preset must never make the
/// recording play faster/slower. Any suspicious/near-silent render is rejected so
/// the caller falls back to the untouched original instead of sending broken audio.
public enum PampGramVoiceChanger {
    private static let sampleRate: Double = 16000
    private static let frameByteCount = 1920

    public static func apply(to compressedData: Data, preset: PampGramVoicePreset) -> Data? {
        guard let pcm = self.decode(compressedData), !pcm.isEmpty else {
            return nil
        }
        guard let shifted = self.pitchShiftPreservingTempo(pcm: pcm, pitchCents: preset.pitchCents) else {
            return nil
        }

        // Pitch-only processing should keep the recording length essentially unchanged.
        // If the render clock goes wrong, do not send accelerated/slowed audio.
        let ratio = Double(shifted.count) / Double(pcm.count)
        guard ratio >= 0.90 && ratio <= 1.10 else {
            return nil
        }

        guard let normalized = self.matchLoudness(samples: shifted, reference: pcm) else {
            return nil
        }
        return self.encode(pcm: normalized)
    }

    private static func decode(_ compressedData: Data) -> [Int16]? {
        let sourceFile = EngineTempBox.shared.tempFile(fileName: "pampgram_voice_in.ogg")
        defer {
            EngineTempBox.shared.dispose(sourceFile)
        }

        do {
            try compressedData.write(to: URL(fileURLWithPath: sourceFile.path))
        } catch {
            return nil
        }

        guard let reader = OggOpusReader(path: sourceFile.path) else {
            return nil
        }

        var samples: [Int16] = []
        let bufferByteCount = 65536
        var buffer = [UInt8](repeating: 0, count: bufferByteCount)

        while true {
            let bytesRead = buffer.withUnsafeMutableBytes { rawBuffer -> Int32 in
                guard let baseAddress = rawBuffer.baseAddress else {
                    return 0
                }
                return reader.read(baseAddress, bufSize: Int32(bufferByteCount))
            }
            if bytesRead <= 0 {
                break
            }

            // OggOpusReader's read API is byte-oriented here. Ignore an odd trailing byte
            // rather than ever inventing a partial Int16 sample.
            let validByteCount = Int(bytesRead) & ~1
            let sampleCount = validByteCount / MemoryLayout<Int16>.size
            if sampleCount == 0 {
                continue
            }
            buffer.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else {
                    return
                }
                let pointer = baseAddress.assumingMemoryBound(to: Int16.self)
                samples.append(contentsOf: UnsafeBufferPointer(start: pointer, count: sampleCount))
            }
        }

        return samples.isEmpty ? nil : samples
    }

    private static func encode(pcm: [Int16]) -> Data? {
        guard !pcm.isEmpty, let dataItem = TGDataItem(data: Data()) else {
            return nil
        }
        let writer = TGOggOpusWriter()
        guard writer.begin(with: dataItem) else {
            return nil
        }

        let samplesPerFrame = self.frameByteCount / MemoryLayout<Int16>.size
        var offset = 0
        var wroteAnyFrame = false

        while offset < pcm.count {
            let remaining = pcm.count - offset
            let thisFrameSamples = min(samplesPerFrame, remaining)
            var frameBytes = [UInt8](repeating: 0, count: thisFrameSamples * MemoryLayout<Int16>.size)

            pcm.withUnsafeBufferPointer { samplesPointer in
                frameBytes.withUnsafeMutableBytes { framePointer in
                    guard let sourceBase = samplesPointer.baseAddress, let destinationBase = framePointer.baseAddress else {
                        return
                    }
                    let source = UnsafeRawPointer(sourceBase.advanced(by: offset))
                    destinationBase.copyMemory(from: source, byteCount: framePointer.count)
                }
            }

            let ok = frameBytes.withUnsafeMutableBytes { framePointer -> Bool in
                return writer.writeFrame(framePointer.baseAddress?.assumingMemoryBound(to: UInt8.self), frameByteCount: UInt(framePointer.count))
            }
            if !ok {
                return nil
            }
            wroteAnyFrame = true
            offset += thisFrameSamples
        }

        _ = writer.writeFrame(nil, frameByteCount: 0)
        guard wroteAnyFrame else {
            return nil
        }
        return dataItem.data()
    }

    private static func pitchShiftPreservingTempo(pcm: [Int16], pitchCents: Float) -> [Int16]? {
        guard !pcm.isEmpty,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: self.sampleRate, channels: 1, interleaved: false),
              let inputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(pcm.count)) else {
            return nil
        }

        inputBuffer.frameLength = AVAudioFrameCount(pcm.count)
        guard let inputChannel = inputBuffer.floatChannelData?[0] else {
            return nil
        }
        for index in 0 ..< pcm.count {
            inputChannel[index] = Float(pcm[index]) / 32768.0
        }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let pitchUnit = AVAudioUnitTimePitch()
        pitchUnit.pitch = pitchCents
        pitchUnit.rate = 1.0

        engine.attach(player)
        engine.attach(pitchUnit)
        engine.connect(player, to: pitchUnit, format: format)
        engine.connect(pitchUnit, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1.0

        do {
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        } catch {
            return nil
        }

        // Scheduling before the engine starts avoids an initial offline-render underrun.
        player.scheduleBuffer(inputBuffer, at: nil, options: [], completionHandler: nil)
        do {
            try engine.start()
        } catch {
            return nil
        }
        player.play()

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: engine.manualRenderingMaximumFrameCount) else {
            engine.stop()
            return nil
        }

        var outputSamples: [Int16] = []
        outputSamples.reserveCapacity(pcm.count + 4096)

        // Pitch-only TimePitch should be close to the input duration. A little headroom is
        // allowed for unit latency/tail, while repeated dry renders are treated as EOF.
        let maxOutputFrames = pcm.count + Int(self.sampleRate * 0.5)
        var renderedFrames = 0
        var dryRenders = 0
        var contextRetries = 0

        renderLoop: while renderedFrames < maxOutputFrames && dryRenders < 4 && contextRetries < 64 {
            outputBuffer.frameLength = 0
            let status: AVAudioEngineManualRenderingStatus
            do {
                status = try engine.renderOffline(engine.manualRenderingMaximumFrameCount, to: outputBuffer)
            } catch {
                engine.stop()
                return nil
            }

            switch status {
            case .success:
                contextRetries = 0
                let length = Int(outputBuffer.frameLength)
                if length == 0 {
                    dryRenders += 1
                    continue renderLoop
                }
                dryRenders = 0
                guard let outputChannel = outputBuffer.floatChannelData?[0] else {
                    engine.stop()
                    return nil
                }
                for index in 0 ..< length {
                    let sample = max(-1.0, min(1.0, outputChannel[index]))
                    outputSamples.append(Int16(sample * 32767.0))
                }
                renderedFrames += length

            case .insufficientDataFromInputNode:
                dryRenders += 1

            case .cannotDoInCurrentContext:
                contextRetries += 1
                continue renderLoop

            case .error:
                engine.stop()
                return nil

            @unknown default:
                engine.stop()
                return nil
            }
        }

        engine.stop()
        guard !outputSamples.isEmpty else {
            return nil
        }

        // Remove only excess renderer tail. Never shorten below the original frame count.
        if outputSamples.count > pcm.count {
            outputSamples.removeLast(outputSamples.count - pcm.count)
        }
        return outputSamples
    }

    private static func matchLoudness(samples: [Int16], reference: [Int16]) -> [Int16]? {
        guard !samples.isEmpty, !reference.isEmpty else {
            return nil
        }

        func rms(_ values: [Int16]) -> Double {
            var sum = 0.0
            for value in values {
                let x = Double(value) / 32768.0
                sum += x * x
            }
            return sqrt(sum / Double(values.count))
        }

        let referenceRms = rms(reference)
        let outputRms = rms(samples)

        // Near-silence means the DSP render failed. Falling back to the original is much
        // better than sending an inaudible voice note.
        guard outputRms > 0.0005 else {
            return nil
        }

        var gain = referenceRms > 0.0005 ? referenceRms / outputRms : 1.0
        gain = min(4.0, max(0.50, gain))

        // Apply the RMS correction, then globally limit to avoid clipping.
        var peak = 0.0
        var floats = [Double]()
        floats.reserveCapacity(samples.count)
        for value in samples {
            let scaled = (Double(value) / 32768.0) * gain
            floats.append(scaled)
            peak = max(peak, abs(scaled))
        }
        if peak < 0.0005 {
            return nil
        }
        let limiter = peak > 0.96 ? (0.96 / peak) : 1.0

        return floats.map { value in
            let limited = max(-1.0, min(1.0, value * limiter))
            return Int16(limited * 32767.0)
        }
    }
}
