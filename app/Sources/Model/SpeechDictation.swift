import SwiftUI
import Speech
import AVFoundation

// Dutch voice dictation for the chat field, via Apple's Speech framework
// (server model when available for best quality). Live partial results.
@MainActor
final class SpeechDictation: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false
    @Published var denied = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "nl-NL"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()

    func toggle() {
        if isRecording { stop() } else { Task { await startFlow() } }
    }

    private func startFlow() async {
        guard await authorize() else { denied = true; return }
        do { try start() } catch { isRecording = false }
    }

    private func authorize() async -> Bool {
        let speech = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard speech == .authorized else { return false }
        #if os(iOS)
        return await AVAudioApplication.requestRecordPermission()
        #else
        return await withCheckedContinuation { c in
            AVCaptureDevice.requestAccess(for: .audio) { c.resume(returning: $0) }
        }
        #endif
    }

    private func start() throws {
        task?.cancel(); task = nil
        transcript = ""
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak req] buffer, _ in
            req?.append(buffer)
        }
        engine.prepare()
        try engine.start()
        isRecording = true

        task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor in self.transcript = text }
            }
            if error != nil || (result?.isFinal ?? false) {
                Task { @MainActor in self.stop() }
            }
        }
    }

    func stop() {
        guard isRecording || engine.isRunning else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        request = nil; task = nil
        isRecording = false
    }
}
