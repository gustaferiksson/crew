import Accelerate
import AVFoundation
import Observation
import Speech

nonisolated private struct DictationError: LocalizedError {
    let errorDescription: String?
}

nonisolated private enum AudioSink: Sendable {
    case analyzer(AVAudioConverter, AsyncStream<AnalyzerInput>.Continuation)
    case file(AVAudioFile)
}

@Observable
final class Dictation {
    enum Phase: Equatable {
        case idle, starting, listening, transcribing
    }

    private(set) var phase = Phase.idle
    private(set) var text = ""
    private(set) var levels: [Double] = []
    private(set) var startedAt: Date?
    var failure: String?

    static let levelCount = 40

    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var inputs: AsyncStream<AnalyzerInput>.Continuation?
    private var results: Task<Void, Never>?
    private var levelUpdates: Task<Void, Never>?
    private var recording: (file: AVAudioFile, transcribe: (Data) async throws -> String)?

    init() {}

    init(fixture levels: [Double], startedAt: Date) {
        phase = .listening
        self.levels = levels
        self.startedAt = startedAt
    }

    func start(fallback transcribe: @escaping (Data) async throws -> String) async {
        guard phase == .idle else { return }
        phase = .starting
        text = ""
        failure = nil
        do {
            guard await AVAudioApplication.requestRecordPermission() else {
                throw DictationError(errorDescription: String(localized: "Allow Crew to use the microphone in Settings to dictate."))
            }
            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            let format = engine.inputNode.outputFormat(forBus: 0)
            guard format.channelCount > 0, format.sampleRate > 0 else {
                throw DictationError(errorDescription: String(localized: "No microphone is available."))
            }
            let sink = try await makeSink(for: format, fallback: transcribe)
            let (levelStream, levelContinuation) = AsyncStream.makeStream(of: Double.self, bufferingPolicy: .bufferingNewest(1))
            try engine.inputNode.installAudioTap(onBus: 0, bufferSize: 4096, format: format, tapProvider: audioTap(into: sink, levels: levelContinuation))
            engine.prepare()
            try engine.start()
            levels = []
            startedAt = .now
            levelUpdates = Task {
                for await value in levelStream { levels = Array((levels + [value]).suffix(Self.levelCount)) }
            }
            phase = .listening
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            inputs?.finish()
            await analyzer?.cancelAndFinishNow()
            reset()
            failure = error.localizedDescription
        }
    }

    func stop() async {
        guard phase == .listening else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        inputs?.finish()
        levelUpdates?.cancel()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await results?.value
        if let recording {
            phase = .transcribing
            let url = recording.file.url
            recording.file.close()
            do {
                text = try await recording.transcribe(Data(contentsOf: url))
            } catch {
                failure = error.localizedDescription
            }
            try? FileManager.default.removeItem(at: url)
        }
        reset()
    }

    func cancel() async {
        guard phase == .listening else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        inputs?.finish()
        levelUpdates?.cancel()
        await analyzer?.cancelAndFinishNow()
        await results?.value
        if let recording {
            recording.file.close()
            try? FileManager.default.removeItem(at: recording.file.url)
        }
        text = ""
        failure = nil
        reset()
    }

    private func makeSink(for format: AVAudioFormat, fallback transcribe: @escaping (Data) async throws -> String) async throws -> AudioSink {
        if let transcriber = await onDeviceTranscriber(),
           let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]),
           let converter = AVAudioConverter(from: format, to: analyzerFormat) {
            let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            try await analyzer.start(inputSequence: stream)
            self.analyzer = analyzer
            inputs = continuation
            results = Task { await collect(transcriber) }
            return .analyzer(converter, continuation)
        }
        let url = URL.temporaryDirectory.appending(path: "dictation-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: format.sampleRate, AVNumberOfChannelsKey: format.channelCount]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        recording = (file, transcribe)
        return .file(file)
    }

    private func onDeviceTranscriber() async -> SpeechTranscriber? {
        guard SpeechTranscriber.isAvailable, let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else { return nil }
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        do {
            try await AssetInventory.assetInstallationRequest(supporting: [transcriber])?.downloadAndInstall()
        } catch {
            return nil
        }
        return transcriber
    }

    private func collect(_ transcriber: SpeechTranscriber) async {
        var committed = ""
        do {
            for try await result in transcriber.results {
                let segment = String(result.text.characters)
                if result.isFinal { committed += segment }
                text = result.isFinal ? committed : committed + segment
            }
        } catch {
            failure = error.localizedDescription
        }
    }

    private func reset() {
        levelUpdates?.cancel()
        levelUpdates = nil
        levels = []
        startedAt = nil
        analyzer = nil
        inputs = nil
        results = nil
        recording = nil
        phase = .idle
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}

nonisolated private func audioTap(into sink: AudioSink, levels: AsyncStream<Double>.Continuation) -> @Sendable (AVReadOnlyAudioPCMBuffer, AVAudioTime) -> Void {
    { readOnly, _ in
        let buffer = AVAudioPCMBuffer(copying: readOnly)
        if let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 {
            let rms = vDSP.rootMeanSquare(UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength)))
            levels.yield(Double(min(1, max(0, (20 * log10(max(rms, 0.000_001)) + 50) / 50))))
        }
        if case .file(let file) = sink {
            try? file.write(from: readOnly)
        }
        guard case .analyzer(let converter, let inputs) = sink else { return }
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * converter.outputFormat.sampleRate / buffer.format.sampleRate).rounded(.up))
        guard let converted = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else { return }
        var supplied = false
        let status = converter.convert(to: converted, error: nil) { _, inputStatus in
            guard !supplied else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, converted.frameLength > 0 else { return }
        inputs.yield(AnalyzerInput(buffer: converted))
    }
}
