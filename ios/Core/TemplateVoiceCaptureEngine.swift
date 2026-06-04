import AVFoundation
import Foundation

enum TemplateVoiceCaptureConfiguration {
    static let recordingDuration: TimeInterval = 3
    static let maxRawBytes = 512_000
    static let mimeType = "audio/m4a"

    static var recorderSettings: [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
    }
}

protocol TemplateVoiceRecording: AnyObject {
    var isRecording: Bool { get }
    func prepareToRecord() -> Bool
    func record() -> Bool
    func stop()
    func deleteRecording() -> Bool
}

protocol TemplateVoiceCaptureSessionConfiguring {
    func configureForRecording() throws
}

protocol TemplateVoiceCaptureFileManaging {
    func makeTemporaryRecordingURL() -> URL
    func readData(at url: URL) throws -> Data
    func removeItem(at url: URL) throws
    func fileExists(at url: URL) -> Bool
}

protocol TemplateVoiceCaptureDelaying {
    func waitForRecording(duration: TimeInterval) async
}

struct TemplateVoiceCaptureEngineDependencies {
    var makeRecorder: (URL, [String: Any]) throws -> TemplateVoiceRecording
    var configureSession: () throws -> Void
    var fileManager: TemplateVoiceCaptureFileManaging
    var delay: TemplateVoiceCaptureDelaying
    var recordingDuration: TimeInterval
    var maxRawBytes: Int
    var mimeType: String
    var recorderSettings: [String: Any]
}

enum TemplateVoiceCaptureEngine {
    static func captureAudio(
        permission: TemplateMicrophonePermission,
        dependencies: TemplateVoiceCaptureEngineDependencies
    ) async throws -> TemplateVoiceAudio {
        switch TemplateVoiceCaptureState.start(permission: permission) {
        case .recording:
            break
        case .typedFallback(let reason):
            throw TemplateServiceError.missingConfiguration(reason)
        case .idle, .submitted:
            throw TemplateServiceError.failed("Voice capture is not ready.")
        }

        try dependencies.configureSession()

        let recordingURL = dependencies.fileManager.makeTemporaryRecordingURL()
        var recordingFileRemoved = false
        defer {
            if !recordingFileRemoved, dependencies.fileManager.fileExists(at: recordingURL) {
                try? dependencies.fileManager.removeItem(at: recordingURL)
            }
        }

        let recorder = try dependencies.makeRecorder(recordingURL, dependencies.recorderSettings)
        guard recorder.prepareToRecord() else {
            throw TemplateServiceError.failed("Could not prepare the microphone for recording.")
        }
        guard recorder.record() else {
            throw TemplateServiceError.failed("Could not start voice recording.")
        }

        await dependencies.delay.waitForRecording(duration: dependencies.recordingDuration)
        recorder.stop()

        let audioData = try dependencies.fileManager.readData(at: recordingURL)
        try dependencies.fileManager.removeItem(at: recordingURL)
        recordingFileRemoved = true

        guard !audioData.isEmpty else {
            throw TemplateServiceError.failed("Recorded audio was empty.")
        }
        guard audioData.count <= dependencies.maxRawBytes else {
            throw TemplateServiceError.failed("Recorded audio exceeds the upload limit.")
        }

        return TemplateVoiceAudio(
            audioBase64: audioData.base64EncodedString(),
            mimeType: dependencies.mimeType
        )
    }
}

struct TemplateVoiceCaptureSleepDelay: TemplateVoiceCaptureDelaying {
    func waitForRecording(duration: TimeInterval) async {
        let nanoseconds = UInt64(max(duration, 0) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds)
    }
}

struct TemplateAVAudioSessionConfigurator: TemplateVoiceCaptureSessionConfiguring {
    func configureForRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
    }
}

struct TemplateVoiceCaptureTemporaryFileManager: TemplateVoiceCaptureFileManaging {
    func makeTemporaryRecordingURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-command-\(UUID().uuidString).m4a")
    }

    func readData(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func removeItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}

final class TemplateAVAudioRecorderAdapter: NSObject, TemplateVoiceRecording {
    private let recorder: AVAudioRecorder

    init(url: URL, settings: [String: Any]) throws {
        recorder = try AVAudioRecorder(url: url, settings: settings)
        super.init()
    }

    var isRecording: Bool { recorder.isRecording }

    func prepareToRecord() -> Bool { recorder.prepareToRecord() }

    func record() -> Bool { recorder.record() }

    func stop() { recorder.stop() }

    func deleteRecording() -> Bool { recorder.deleteRecording() }
}

enum TemplateVoiceCaptureDependencies {
    static func live() -> TemplateVoiceCaptureEngineDependencies {
        TemplateVoiceCaptureEngineDependencies(
            makeRecorder: { url, settings in
                try TemplateAVAudioRecorderAdapter(url: url, settings: settings)
            },
            configureSession: {
                try TemplateAVAudioSessionConfigurator().configureForRecording()
            },
            fileManager: TemplateVoiceCaptureTemporaryFileManager(),
            delay: TemplateVoiceCaptureSleepDelay(),
            recordingDuration: TemplateVoiceCaptureConfiguration.recordingDuration,
            maxRawBytes: TemplateVoiceCaptureConfiguration.maxRawBytes,
            mimeType: TemplateVoiceCaptureConfiguration.mimeType,
            recorderSettings: TemplateVoiceCaptureConfiguration.recorderSettings
        )
    }
}
