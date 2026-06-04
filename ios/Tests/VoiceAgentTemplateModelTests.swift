import XCTest
@testable import VoiceAgentTemplate

@MainActor
final class VoiceAgentTemplateModelTests: XCTestCase {
    func testSignedInLaunchFixtureBuildsDeterministicSmokeState() {
        let sentryScope = TemplateSentryUserScope()
        let model = VoiceAgentTemplateModel(
            sessionService: StubSessionService(result: .success(TemplateSession(ownerKey: "test|owner"))),
            commandService: StubCommandService(),
            voiceCapture: StubVoiceCapture(),
            analytics: TemplateProductAnalytics(configuration: nil),
            sentryScope: sentryScope,
            launchArguments: ["VoiceAgentTemplate", "--template-signed-in"]
        )

        XCTAssertTrue(model.isSignedIn)
        XCTAssertEqual(sentryScope.ownerKey, "fixture-owner")
        XCTAssertEqual(model.entries, [
            Entry(id: "fixture-typed", body: "Draft launch announcement", source: .typed),
            Entry(id: "fixture-voice", body: "Follow up from voice note", source: .voice),
        ])
    }

    func testDeletionProgressLaunchFixtureBuildsSignedOutFeedbackState() {
        let model = VoiceAgentTemplateModel(
            sessionService: StubSessionService(result: .success(TemplateSession(ownerKey: "test|owner"))),
            commandService: StubCommandService(),
            voiceCapture: StubVoiceCapture(),
            analytics: TemplateProductAnalytics(configuration: nil),
            sentryScope: TemplateSentryUserScope(),
            launchArguments: ["VoiceAgentTemplate", "--template-deletion-progress"]
        )

        XCTAssertFalse(model.isSignedIn)
        XCTAssertTrue(model.entries.isEmpty)
        XCTAssertEqual(
            model.feedbackMessage,
            "Account deletion is in progress. Your data will be removed shortly."
        )
    }

    func testSignInBindsSessionScopeAndCapturesAnalytics() async {
        let sentryScope = TemplateSentryUserScope()
        let analytics = AnalyticsSpy()
        let model = VoiceAgentTemplateModel(
            sessionService: StubSessionService(result: .success(TemplateSession(ownerKey: "test|owner"))),
            commandService: StubCommandService(),
            voiceCapture: StubVoiceCapture(),
            analytics: analytics.tracker,
            sentryScope: sentryScope,
            launchArguments: []
        )

        await model.signIn()

        XCTAssertTrue(model.isSignedIn)
        XCTAssertEqual(sentryScope.ownerKey, "test|owner")
        XCTAssertEqual(analytics.events, ["auth_signed_in"])
    }

    func testMissingSessionConfigurationDoesNotFakeSignIn() async {
        let model = VoiceAgentTemplateModel(
            sessionService: StubSessionService(result: .failure(.missingConfiguration("Configure Apple Sign In."))),
            commandService: StubCommandService(),
            voiceCapture: StubVoiceCapture(),
            analytics: TemplateProductAnalytics(configuration: nil),
            sentryScope: TemplateSentryUserScope(),
            launchArguments: []
        )

        await model.signIn()

        XCTAssertFalse(model.isSignedIn)
        XCTAssertEqual(model.feedbackMessage, "Configure Apple Sign In.")
    }

    func testFailedConvexAuthDoesNotFakeSignIn() async {
        let model = VoiceAgentTemplateModel(
            sessionService: StubSessionService(result: .failure(.failed("Sign in with Apple was canceled."))),
            commandService: StubCommandService(),
            voiceCapture: StubVoiceCapture(),
            analytics: TemplateProductAnalytics(configuration: nil),
            sentryScope: TemplateSentryUserScope(),
            launchArguments: []
        )

        await model.signIn()

        XCTAssertFalse(model.isSignedIn)
        XCTAssertEqual(model.feedbackMessage, "Sign in with Apple was canceled.")
    }

    func testTypedCommandSubmitsThroughConvexCommandSeamAndUsesAppliedResult() async {
        let commandService = StubCommandService()
        commandService.submitResult = TemplateCommandResult(
            summary: "Created entry: backend value.",
            operations: [.createEntry(body: "backend value")],
            entries: [TemplateAppliedEntry(id: "entry-typed", body: "backend value", source: .typed)]
        )
        let model = VoiceAgentTemplateModel(
            sessionService: StubSessionService(result: .success(TemplateSession(ownerKey: "test|owner"))),
            commandService: commandService,
            voiceCapture: StubVoiceCapture(),
            analytics: TemplateProductAnalytics(configuration: nil),
            sentryScope: TemplateSentryUserScope(),
            launchArguments: []
        )
        model.commandText = "Create a note saying local input"

        await model.submitTypedCommand()

        XCTAssertEqual(commandService.submittedCommands, [
            TemplateConvexCommandRequest(text: "Create a note saying local input", source: .typed),
        ])
        XCTAssertEqual(model.entries.map(\.body), ["backend value"])
        XCTAssertEqual(model.entries.map(\.source), [.typed])
        XCTAssertEqual(model.entries.map(\.id), ["entry-typed"])
        XCTAssertEqual(model.commandText, "")
    }

    func testVoiceCommandTranscribesAudioBeforeSubmittingVoiceCommand() async {
        let commandService = StubCommandService()
        commandService.transcriptionResult = TemplateVoiceTranscriptionResult(transcript: "Create a note saying voice result")
        commandService.submitResult = TemplateCommandResult(
            summary: "Created entry: voice result.",
            operations: [.createEntry(body: "voice result")],
            entries: [TemplateAppliedEntry(id: "entry-voice", body: "voice result", source: .voice)]
        )
        let voiceCapture = StubVoiceCapture(audio: TemplateVoiceAudio(audioBase64: "dGVzdA==", mimeType: "audio/m4a"))
        let model = VoiceAgentTemplateModel(
            sessionService: StubSessionService(result: .success(TemplateSession(ownerKey: "test|owner"))),
            commandService: commandService,
            voiceCapture: voiceCapture,
            analytics: TemplateProductAnalytics(configuration: nil),
            sentryScope: TemplateSentryUserScope(),
            launchArguments: []
        )

        await model.startVoiceCommand(permission: .granted)

        XCTAssertEqual(commandService.transcriptionRequests, [
            TemplateVoiceTranscriptionRequest(audioBase64: "dGVzdA==", mimeType: "audio/m4a"),
        ])
        XCTAssertEqual(commandService.submittedCommands, [
            TemplateConvexCommandRequest(text: "Create a note saying voice result", source: .voice),
        ])
        XCTAssertEqual(model.entries.map(\.body), ["voice result"])
        XCTAssertEqual(model.entries.map(\.source), [.voice])
        XCTAssertEqual(model.entries.map(\.id), ["entry-voice"])
    }

    func testVoiceCommandFallsBackWhenMicrophonePermissionDenied() async {
        let commandService = StubCommandService()
        let voiceCapture = StubVoiceCapture(audio: TemplateVoiceAudio(audioBase64: "dGVzdA==", mimeType: "audio/m4a"))
        let model = VoiceAgentTemplateModel(
            sessionService: StubSessionService(result: .success(TemplateSession(ownerKey: "test|owner"))),
            commandService: commandService,
            voiceCapture: voiceCapture,
            analytics: TemplateProductAnalytics(configuration: nil),
            sentryScope: TemplateSentryUserScope(),
            launchArguments: []
        )

        await model.startVoiceCommand(permission: .denied)

        XCTAssertEqual(model.voiceState, .typedFallback(reason: "permission_denied"))
        XCTAssertEqual(voiceCapture.captureCallCount, 0)
        XCTAssertEqual(commandService.transcriptionRequests, [])
        XCTAssertEqual(commandService.submittedCommands, [])
    }

    func testVoiceCommandUsesSpecificTypedFallbackReasonForCaptureFailures() async {
        let model = VoiceAgentTemplateModel(
            sessionService: StubSessionService(result: .success(TemplateSession(ownerKey: "test|owner"))),
            commandService: StubCommandService(),
            voiceCapture: StubVoiceCapture(result: .failure(.failed("Audio unavailable."))),
            analytics: TemplateProductAnalytics(configuration: nil),
            sentryScope: TemplateSentryUserScope(),
            launchArguments: []
        )

        await model.startVoiceCommand(permission: .granted)

        XCTAssertEqual(model.voiceState.fallbackReason, "audio_capture_failed")
    }

    func testVoiceCommandUsesConfigFallbackReasonForMissingTranscriptionConfig() async {
        let commandService = StubCommandService()
        commandService.transcriptionResult = .configurationMissing(missing: "GROQ_API_KEY")
        let voiceCapture = StubVoiceCapture(audio: TemplateVoiceAudio(audioBase64: "dGVzdA==", mimeType: "audio/m4a"))
        let model = VoiceAgentTemplateModel(
            sessionService: StubSessionService(result: .success(TemplateSession(ownerKey: "test|owner"))),
            commandService: commandService,
            voiceCapture: voiceCapture,
            analytics: TemplateProductAnalytics(configuration: nil),
            sentryScope: TemplateSentryUserScope(),
            launchArguments: []
        )

        await model.startVoiceCommand(permission: .granted)

        XCTAssertEqual(model.voiceState.fallbackReason, "config_missing")
    }

    func testVoiceCommandUsesSpecificTypedFallbackReasonForSubmitFailures() async {
        let commandService = StubCommandService()
        commandService.transcriptionResult = TemplateVoiceTranscriptionResult(transcript: "Create a note saying voice result")
        commandService.submitError = .failed("Command submit failed.")
        let voiceCapture = StubVoiceCapture(audio: TemplateVoiceAudio(audioBase64: "dGVzdA==", mimeType: "audio/m4a"))
        let model = VoiceAgentTemplateModel(
            sessionService: StubSessionService(result: .success(TemplateSession(ownerKey: "test|owner"))),
            commandService: commandService,
            voiceCapture: voiceCapture,
            analytics: TemplateProductAnalytics(configuration: nil),
            sentryScope: TemplateSentryUserScope(),
            launchArguments: []
        )

        await model.startVoiceCommand(permission: .granted)

        XCTAssertEqual(model.voiceState.fallbackReason, "command_submission_failed")
    }

    func testDeleteAccountCallsBackendDeletionBeforeClearingLocalSession() async {
        let sentryScope = TemplateSentryUserScope()
        sentryScope.bind(ownerKey: "test|owner")
        let commandService = StubCommandService()
        let model = VoiceAgentTemplateModel(
            sessionService: StubSessionService(result: .success(TemplateSession(ownerKey: "test|owner"))),
            commandService: commandService,
            voiceCapture: StubVoiceCapture(),
            analytics: TemplateProductAnalytics(configuration: nil),
            sentryScope: sentryScope,
            launchArguments: []
        )
        model.isSignedIn = true
        model.entries = [Entry(id: "existing", body: "Existing", source: .typed)]

        await model.deleteAccount()

        XCTAssertEqual(commandService.deleteAccountCallCount, 1)
        XCTAssertFalse(model.isSignedIn)
        XCTAssertTrue(model.entries.isEmpty)
        XCTAssertNil(sentryScope.ownerKey)
    }

    func testDeleteAccountClearsWritableLocalStateWhenDeletionIsInProgress() async {
        let sentryScope = TemplateSentryUserScope()
        sentryScope.bind(ownerKey: "test|owner")
        let analytics = AnalyticsSpy()
        let commandService = StubCommandService()
        commandService.deleteAccountResult = .deletionInProgress(
            deleted: .init(
                profiles: 0,
                entries: 1000,
                commandHistory: 1000,
                appleSignInCredentials: 0,
                usageEvents: 1000
            ),
            batches: 20,
            jobStatus: .deleting
        )
        let model = VoiceAgentTemplateModel(
            sessionService: StubSessionService(result: .success(TemplateSession(ownerKey: "test|owner"))),
            commandService: commandService,
            voiceCapture: StubVoiceCapture(),
            analytics: analytics.tracker,
            sentryScope: sentryScope,
            launchArguments: []
        )
        model.isSignedIn = true
        model.commandText = "draft command"
        model.entries = [Entry(id: "existing", body: "Existing", source: .typed)]

        await model.deleteAccount()

        XCTAssertEqual(commandService.deleteAccountCallCount, 1)
        XCTAssertFalse(model.isSignedIn)
        XCTAssertTrue(model.entries.isEmpty)
        XCTAssertEqual(model.commandText, "")
        XCTAssertNil(sentryScope.ownerKey)
        XCTAssertEqual(model.feedbackMessage?.isEmpty, false)
        XCTAssertEqual(analytics.events, ["account_deleted"])
        XCTAssertEqual(analytics.properties.first?["status"], "deletion_in_progress")
    }
}

private final class AnalyticsSpy {
    private(set) var events: [String] = []
    private(set) var properties: [[String: String]] = []

    lazy var tracker = TemplateProductAnalytics(
        configuration: TemplatePostHogConfiguration(
            apiKey: "ph_test",
            host: URL(string: "https://app.posthog.com")!
        )
    ) { [weak self] event, properties in
        self?.events.append(event)
        self?.properties.append(properties)
    }
}

private final class StubSessionService: TemplateSessionServicing {
    let result: Result<TemplateSession, TemplateServiceError>

    init(result: Result<TemplateSession, TemplateServiceError>) {
        self.result = result
    }

    func signIn() async throws -> TemplateSession {
        try result.get()
    }
}

private final class StubCommandService: TemplateCommandServicing {
    var submittedCommands: [TemplateConvexCommandRequest] = []
    var transcriptionRequests: [TemplateVoiceTranscriptionRequest] = []
    var deleteAccountCallCount = 0
    var deleteAccountResult: TemplateDeleteAccountResult?
    var submitResult = TemplateCommandResult(summary: "Created entry.", entries: [])
    var submitError: TemplateServiceError?
    var transcriptionResult = TemplateVoiceTranscriptionResult(transcript: "")

    func submitCommand(_ request: TemplateConvexCommandRequest) async throws -> TemplateCommandResult {
        submittedCommands.append(request)
        if let submitError {
            throw submitError
        }
        return submitResult
    }

    func transcribeVoice(_ request: TemplateVoiceTranscriptionRequest) async throws -> TemplateVoiceTranscriptionResult {
        transcriptionRequests.append(request)
        return transcriptionResult
    }

    func listEntries() async throws -> [TemplateListedEntry] {
        []
    }

    func updateEntry(id: String, body: String) async throws -> TemplateListedEntry {
        TemplateListedEntry(id: id, body: body, source: .typed)
    }

    func deleteAccount() async throws -> TemplateDeleteAccountResult {
        deleteAccountCallCount += 1
        if let deleteAccountResult {
            return deleteAccountResult
        }
        return .deleted(
            deleted: .init(
                profiles: 0,
                entries: 0,
                commandHistory: 0,
                appleSignInCredentials: 0,
                usageEvents: 0
            ),
            batches: 1,
            cleanup: .init(posthog: .init(status: "skipped"), sentry: .init(status: "skipped"))
        )
    }
}

private final class StubVoiceCapture: TemplateVoiceCapturing {
    let result: Result<TemplateVoiceAudio, TemplateServiceError>
    private(set) var captureCallCount = 0

    init(audio: TemplateVoiceAudio? = nil) {
        if let audio {
            result = .success(audio)
        } else {
            result = .failure(.missingConfiguration("Configure microphone capture."))
        }
    }

    init(result: Result<TemplateVoiceAudio, TemplateServiceError>) {
        self.result = result
    }

    func captureAudio(permission: TemplateMicrophonePermission) async throws -> TemplateVoiceAudio {
        captureCallCount += 1
        return try result.get()
    }
}
