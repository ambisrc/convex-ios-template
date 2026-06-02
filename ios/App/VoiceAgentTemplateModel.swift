import Foundation

@MainActor
final class VoiceAgentTemplateModel: ObservableObject {
    @Published var isSignedIn = false
    @Published var commandText = ""
    @Published var entries: [Entry] = []
    @Published var voiceState = TemplateVoiceCaptureState.idle
    @Published var isSettingsPresented = false
    @Published var feedbackMessage: String?

    private let sessionService: TemplateSessionServicing
    private let commandService: TemplateCommandServicing
    private let voiceCapture: TemplateVoiceCapturing
    private let analytics: TemplateProductAnalytics
    private let sentryScope: TemplateSentryUserScope

    init(
        sessionService: TemplateSessionServicing = TemplateRuntimeServices.makeSessionService(),
        commandService: TemplateCommandServicing = TemplateRuntimeServices.makeCommandService(),
        voiceCapture: TemplateVoiceCapturing = TemplateVoiceCaptureService(),
        analytics: TemplateProductAnalytics = TemplateProductAnalytics(configuration: .fromBundle()),
        sentryScope: TemplateSentryUserScope = TemplateSentryUserScope(),
        launchArguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        self.sessionService = sessionService
        self.commandService = commandService
        self.voiceCapture = voiceCapture
        self.analytics = analytics
        self.sentryScope = sentryScope
        applyLaunchFixture(arguments: launchArguments)
    }

    func signIn() async {
        do {
            let session = try await sessionService.signIn()
            isSignedIn = true
            feedbackMessage = nil
            sentryScope.bind(ownerKey: session.ownerKey)
            analytics.capture("auth_signed_in", properties: ["provider": "apple"])
        } catch {
            feedbackMessage = displayMessage(for: error)
        }
    }

    func submitTypedCommand() async {
        let body = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        do {
            let result = try await commandService.submitCommand(
                TemplateConvexCommandRequest(text: body, source: .typed)
            )
            apply(result)
            commandText = ""
            feedbackMessage = result.summary
            analytics.capture("command_submitted", properties: ["source": "typed"])
        } catch {
            feedbackMessage = displayMessage(for: error)
        }
    }

    func startVoiceCommand(permission: TemplateMicrophonePermission = .granted) async {
        voiceState = TemplateVoiceCaptureState.start(permission: permission)
        guard case .recording = voiceState else {
            analytics.capture("voice_fallback_selected", properties: ["reason": voiceState.fallbackReason ?? "unknown"])
            return
        }

        let audio: TemplateVoiceAudio
        do {
            audio = try await voiceCapture.captureAudio(permission: permission)
        } catch {
            applyVoiceFallback(error, reason: "audio_capture_failed")
            return
        }

        let transcription: TemplateVoiceTranscriptionResult
        do {
            transcription = try await commandService.transcribeVoice(
                TemplateVoiceTranscriptionRequest(audioBase64: audio.audioBase64, mimeType: audio.mimeType)
            )
        } catch {
            applyVoiceFallback(error, reason: "voice_transcription_failed")
            return
        }

        let transcript: String
        switch transcription {
        case .transcribed(let value):
            transcript = value
        case .configurationMissing(let missing):
            applyVoiceFallback(
                TemplateServiceError.missingConfiguration("Configure \(missing) before transcribing voice commands."),
                reason: "config_missing"
            )
            return
        }

        do {
            let result = try await commandService.submitCommand(
                TemplateConvexCommandRequest(text: transcript, source: .voice)
            )
            apply(result)
            voiceState = .submitted
            feedbackMessage = result.summary
            analytics.capture("command_submitted", properties: ["source": "voice"])
        } catch {
            applyVoiceFallback(error, reason: "command_submission_failed")
        }
    }

    func deleteAccount() async {
        do {
            switch try await commandService.deleteAccount() {
            case .deleted:
                clearLocalSession()
                analytics.capture("account_deleted", properties: [:])
            case .deletionInProgress:
                clearLocalSession()
                feedbackMessage = "Account deletion is in progress. Your data will be removed shortly."
                analytics.capture("account_deleted", properties: ["status": "deletion_in_progress"])
            }
        } catch {
            feedbackMessage = displayMessage(for: error)
        }
    }

    private func clearLocalSession() {
        entries.removeAll()
        commandText = ""
        isSignedIn = false
        isSettingsPresented = false
        feedbackMessage = nil
        sentryScope.clear()
    }

    private func apply(_ result: TemplateCommandResult) {
        let appliedEntries = result.entries.map {
            Entry(id: $0.id, body: $0.body, source: Entry.Source(rawValue: $0.source.rawValue) ?? .typed)
        }
        entries.insert(contentsOf: appliedEntries, at: 0)
    }

    private func applyLaunchFixture(arguments: [String]) {
        guard arguments.contains("--template-signed-in")
            || arguments.contains("--template-voice-fallback")
            || arguments.contains("--template-settings")
        else {
            return
        }

        isSignedIn = true
        sentryScope.bind(ownerKey: "fixture-owner")
        entries = [
            Entry(id: "fixture-typed", body: "Draft launch announcement", source: .typed),
            Entry(id: "fixture-voice", body: "Follow up from voice note", source: .voice),
        ]

        if arguments.contains("--template-voice-fallback") {
            voiceState = .typedFallback(reason: "permission_denied")
        }
        if arguments.contains("--template-settings") {
            isSettingsPresented = true
        }
    }

    private func displayMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return error.localizedDescription
    }

    private func applyVoiceFallback(_ error: Error, reason: String) {
        voiceState = .typedFallback(reason: reason)
        feedbackMessage = displayMessage(for: error)
    }
}

struct Entry: Identifiable, Equatable {
    enum Source: String, Decodable {
        case typed
        case voice
    }

    let id: String
    let body: String
    let source: Source
}
