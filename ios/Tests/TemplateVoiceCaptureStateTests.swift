import XCTest
@testable import VoiceAgentTemplate

final class TemplateVoiceCaptureStateTests: XCTestCase {
    func testGrantedPermissionStartsRecording() {
        XCTAssertEqual(TemplateVoiceCaptureState.start(permission: .granted), .recording)
    }

    func testMicrophoneDeniedMapsToTypedFallback() {
        XCTAssertEqual(
            TemplateVoiceCaptureState.start(permission: .denied),
            .typedFallback(reason: "permission_denied")
        )
    }

    func testMicrophoneRestrictedMapsToTypedFallback() {
        XCTAssertEqual(
            TemplateVoiceCaptureState.start(permission: .restricted),
            .typedFallback(reason: "permission_restricted")
        )
    }

    func testMicrophoneUnavailableMapsToTypedFallback() {
        XCTAssertEqual(
            TemplateVoiceCaptureState.start(permission: .unavailable),
            .typedFallback(reason: "audio_unavailable")
        )
    }
}
