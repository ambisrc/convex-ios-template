import XCTest
@testable import VoiceAgentTemplate

final class TemplateVoiceCaptureServiceTests: XCTestCase {
    func testGrantedPermissionReturnsEncodedAudioFromFakeRecorder() async throws {
        let audioBytes = Data("fake-audio-bytes".utf8)
        let fileManager = FakeVoiceCaptureFileManager(initialData: audioBytes)
        let recorder = FakeVoiceRecorder()
        let session = FakeVoiceCaptureSession()
        let dependencies = makeDependencies(fileManager: fileManager, recorder: recorder, session: session)

        let audio = try await TemplateVoiceCaptureEngine.captureAudio(
            permission: .granted,
            dependencies: dependencies
        )

        XCTAssertFalse(audio.audioBase64.isEmpty)
        XCTAssertEqual(audio.mimeType, "audio/m4a")
        XCTAssertEqual(Data(base64Encoded: audio.audioBase64), audioBytes)
        XCTAssertTrue(recorder.stopCalled)
        XCTAssertTrue(session.deactivateCalled)
        XCTAssertFalse(fileManager.fileExists(at: fileManager.lastRecordingURL))
    }

    func testDeniedPermissionThrowsFallbackReasonWithoutRecording() async {
        let fileManager = FakeVoiceCaptureFileManager(initialData: Data())
        let recorder = FakeVoiceRecorder()
        let dependencies = makeDependencies(fileManager: fileManager, recorder: recorder)

        do {
            _ = try await TemplateVoiceCaptureEngine.captureAudio(
                permission: .denied,
                dependencies: dependencies
            )
            XCTFail("Expected permission_denied error")
        } catch TemplateServiceError.missingConfiguration(let reason) {
            XCTAssertEqual(reason, "permission_denied")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertFalse(recorder.prepareCalled)
        XCTAssertFalse(recorder.recordCalled)
    }

    func testRestrictedPermissionThrowsFallbackReasonWithoutRecording() async {
        let dependencies = makeDependencies(
            fileManager: FakeVoiceCaptureFileManager(initialData: Data()),
            recorder: FakeVoiceRecorder()
        )

        do {
            _ = try await TemplateVoiceCaptureEngine.captureAudio(
                permission: .restricted,
                dependencies: dependencies
            )
            XCTFail("Expected permission_restricted error")
        } catch TemplateServiceError.missingConfiguration(let reason) {
            XCTAssertEqual(reason, "permission_restricted")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUnavailablePermissionThrowsFallbackReasonWithoutRecording() async {
        let dependencies = makeDependencies(
            fileManager: FakeVoiceCaptureFileManager(initialData: Data()),
            recorder: FakeVoiceRecorder()
        )

        do {
            _ = try await TemplateVoiceCaptureEngine.captureAudio(
                permission: .unavailable,
                dependencies: dependencies
            )
            XCTFail("Expected audio_unavailable error")
        } catch TemplateServiceError.missingConfiguration(let reason) {
            XCTAssertEqual(reason, "audio_unavailable")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRecorderFailureRemovesTemporaryFile() async {
        let fileManager = FakeVoiceCaptureFileManager(initialData: Data("clip".utf8))
        let recorder = FakeVoiceRecorder(prepareResult: false)
        let dependencies = makeDependencies(fileManager: fileManager, recorder: recorder)

        do {
            _ = try await TemplateVoiceCaptureEngine.captureAudio(
                permission: .granted,
                dependencies: dependencies
            )
            XCTFail("Expected recorder preparation failure")
        } catch TemplateServiceError.failed(let message) {
            XCTAssertEqual(message, "Could not prepare the microphone for recording.")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(fileManager.removedURLs.contains(fileManager.lastRecordingURL))
    }

    func testRecorderFailureDeactivatesSession() async {
        let session = FakeVoiceCaptureSession()
        let dependencies = makeDependencies(
            fileManager: FakeVoiceCaptureFileManager(initialData: Data("clip".utf8)),
            recorder: FakeVoiceRecorder(prepareResult: false),
            session: session
        )

        do {
            _ = try await TemplateVoiceCaptureEngine.captureAudio(
                permission: .granted,
                dependencies: dependencies
            )
            XCTFail("Expected recorder preparation failure")
        } catch {
            XCTAssertTrue(session.deactivateCalled)
        }
    }

    func testEncodedAudioStaysWithinBackendRawByteCap() async throws {
        let audioBytes = Data(repeating: 0xAB, count: 512_000)
        let dependencies = makeDependencies(
            fileManager: FakeVoiceCaptureFileManager(initialData: audioBytes),
            recorder: FakeVoiceRecorder(),
            maxRawBytes: 512_000
        )

        let audio = try await TemplateVoiceCaptureEngine.captureAudio(
            permission: .granted,
            dependencies: dependencies
        )

        let decoded = try XCTUnwrap(Data(base64Encoded: audio.audioBase64))
        XCTAssertEqual(decoded.count, 512_000)
        XCTAssertLessThanOrEqual(audio.audioBase64.utf8.count, 700_000)
    }

    func testOversizedRecordingFailsBeforeEncoding() async {
        let audioBytes = Data(repeating: 0xCD, count: 600_000)
        let dependencies = makeDependencies(
            fileManager: FakeVoiceCaptureFileManager(initialData: audioBytes),
            recorder: FakeVoiceRecorder(),
            maxRawBytes: 512_000
        )

        do {
            _ = try await TemplateVoiceCaptureEngine.captureAudio(
                permission: .granted,
                dependencies: dependencies
            )
            XCTFail("Expected upload limit failure")
        } catch TemplateServiceError.failed(let message) {
            XCTAssertEqual(message, "Recorded audio exceeds the upload limit.")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeDependencies(
        fileManager: FakeVoiceCaptureFileManager,
        recorder: FakeVoiceRecorder,
        session: FakeVoiceCaptureSession = FakeVoiceCaptureSession(),
        maxRawBytes: Int = 512_000
    ) -> TemplateVoiceCaptureEngineDependencies {
        TemplateVoiceCaptureEngineDependencies(
            makeRecorder: { _, _ in recorder },
            configureSession: { session.configureCalled = true },
            deactivateSession: { session.deactivateCalled = true },
            fileManager: fileManager,
            delay: FakeVoiceCaptureDelay(),
            recordingDuration: 0.1,
            postStopFlushDelay: 0,
            maxRawBytes: maxRawBytes,
            mimeType: "audio/m4a",
            recorderSettings: [:]
        )
    }
}

private final class FakeVoiceRecorder: TemplateVoiceRecording {
    var isRecording = false
    var prepareResult: Bool
    var recordResult: Bool
    private(set) var prepareCalled = false
    private(set) var recordCalled = false
    private(set) var stopCalled = false

    init(prepareResult: Bool = true, recordResult: Bool = true) {
        self.prepareResult = prepareResult
        self.recordResult = recordResult
    }

    func prepareToRecord() -> Bool {
        prepareCalled = true
        return prepareResult
    }

    func record() -> Bool {
        recordCalled = true
        isRecording = recordResult
        return recordResult
    }

    func stop() {
        stopCalled = true
        isRecording = false
    }

    func deleteRecording() -> Bool { true }
}

private final class FakeVoiceCaptureSession {
    var configureCalled = false
    var deactivateCalled = false
}

private final class FakeVoiceCaptureFileManager: TemplateVoiceCaptureFileManaging {
    private var files: [URL: Data] = [:]
    private let payload: Data
    private(set) var removedURLs: [URL] = []
    private(set) var lastRecordingURL: URL = URL(fileURLWithPath: "/tmp/unused.m4a")

    init(initialData: Data) {
        payload = initialData
    }

    func makeTemporaryRecordingURL() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("voice-command-test-\(UUID().uuidString).m4a")
        lastRecordingURL = url
        files[url] = payload
        return url
    }

    func readData(at url: URL) throws -> Data {
        guard let data = files[url] else {
            throw TemplateServiceError.failed("Missing test recording file.")
        }
        return data
    }

    func removeItem(at url: URL) throws {
        removedURLs.append(url)
        files.removeValue(forKey: url)
    }

    func fileExists(at url: URL) -> Bool {
        files[url] != nil
    }
}

private struct FakeVoiceCaptureDelay: TemplateVoiceCaptureDelaying {
    func waitForRecording(duration: TimeInterval) async {}
}

final class TemplateMicrophonePermissionServiceTests: XCTestCase {
    func testMapperMapsGrantedDeniedAndUndetermined() {
        XCTAssertEqual(
            TemplateAVAudioSessionPermissionMapper.map(.granted),
            .granted
        )
        XCTAssertEqual(
            TemplateAVAudioSessionPermissionMapper.map(.denied),
            .denied
        )
        XCTAssertEqual(
            TemplateAVAudioSessionPermissionMapper.map(.undetermined),
            .unavailable
        )
    }
}
