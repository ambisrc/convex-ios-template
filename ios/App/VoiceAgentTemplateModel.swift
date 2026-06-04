import Foundation

enum JournalScreen: Equatable {
    case home
    case brainDump(prompt: TemplateReflectionPrompt?)
    case entryEditor(Entry)
}

@MainActor
final class VoiceAgentTemplateModel: ObservableObject {
    @Published var isSignedIn = false
    @Published var screen: JournalScreen = .home
    @Published var commandText = ""
    @Published var entries: [Entry] = []
    @Published var homeReflectionPrompts: [TemplateReflectionPrompt] = []
    @Published var voiceState = TemplateVoiceCaptureState.idle
    @Published var isSettingsPresented = false
    @Published var feedbackMessage: String?
    @Published var voiceTranscriptPreview: String?

    private let sessionService: TemplateSessionServicing
    private let commandService: TemplateCommandServicing
    private let voiceCapture: TemplateVoiceCapturing
    private let microphonePermission: TemplateMicrophonePermissionProviding
    private let analytics: TemplateProductAnalytics
    private let sentryScope: TemplateSentryUserScope
    private var activeReflectionPrompt: TemplateReflectionPrompt?

    init(
        sessionService: TemplateSessionServicing = TemplateRuntimeServices.makeSessionService(),
        commandService: TemplateCommandServicing = TemplateRuntimeServices.makeCommandService(),
        voiceCapture: TemplateVoiceCapturing = TemplateVoiceCaptureService(),
        microphonePermission: TemplateMicrophonePermissionProviding = TemplateAVAudioSessionPermissionService(),
        analytics: TemplateProductAnalytics = TemplateProductAnalytics(configuration: .fromBundle()),
        sentryScope: TemplateSentryUserScope = TemplateSentryUserScope(),
        launchArguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        self.sessionService = sessionService
        self.commandService = commandService
        self.voiceCapture = voiceCapture
        self.microphonePermission = microphonePermission
        self.analytics = analytics
        self.sentryScope = sentryScope
        applyLaunchFixture(arguments: launchArguments)
    }

    func signIn() async {
        do {
            let session = try await sessionService.signIn()
            isSignedIn = true
            screen = .home
            feedbackMessage = nil
            sentryScope.bind(ownerKey: session.ownerKey)
            analytics.capture("auth_signed_in", properties: ["provider": "apple"])
            await loadHome()
        } catch {
            feedbackMessage = displayMessage(for: error)
        }
    }

    func loadHome() async {
        do {
            async let listedEntries = commandService.listEntries()
            async let listedReflections = commandService.listReflections()
            let (entriesResult, reflectionsResult) = try await (listedEntries, listedReflections)
            entries = entriesResult.map(Entry.init(listedEntry:))
            homeReflectionPrompts = reflectionsResult.filter { $0.status == .open }
            screen = .home
        } catch {
            feedbackMessage = displayMessage(for: error)
        }
    }

    private func refreshReflectionPrompts() async {
        do {
            let reflections = try await commandService.listReflections()
            homeReflectionPrompts = reflections.filter { $0.status == .open }
        } catch {
            feedbackMessage = displayMessage(for: error)
        }
    }

    func openBrainDump() {
        openBrainDump(prompt: nil)
    }

    func openBrainDump(prompt: TemplateReflectionPrompt?) {
        activeReflectionPrompt = prompt
        voiceTranscriptPreview = nil
        screen = .brainDump(prompt: prompt)
    }

    func openEntryEditor(_ entry: Entry) {
        screen = .entryEditor(entry)
    }

    func goHome() {
        activeReflectionPrompt = nil
        screen = .home
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

    func startVoiceDump(from prompt: TemplateReflectionPrompt? = nil) async {
        activeReflectionPrompt = prompt
        await startVoiceCommand(promptId: prompt?.id)
    }

    func startVoiceCommand(
        permission overridePermission: TemplateMicrophonePermission? = nil,
        promptId: String? = nil
    ) async {
        voiceTranscriptPreview = nil
        let permission: TemplateMicrophonePermission
        if let overridePermission {
            permission = overridePermission
        } else {
            permission = await microphonePermission.requestPermission()
        }
        voiceState = TemplateVoiceCaptureState.start(permission: permission)
        guard case .recording = voiceState else {
            analytics.capture("voice_fallback_selected", properties: ["reason": voiceState.fallbackReason ?? "unknown"])
            return
        }
        feedbackMessage = "Recording..."

        let audio: TemplateVoiceAudio
        do {
            audio = try await voiceCapture.captureAudio(permission: permission)
        } catch {
            applyVoiceFallback(error, reason: "audio_capture_failed")
            return
        }
        feedbackMessage = "Transcribing..."

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
            voiceTranscriptPreview = value
            feedbackMessage = "Saving..."
        case .configurationMissing(let missing):
            applyVoiceFallback(
                TemplateServiceError.missingConfiguration("Configure \(missing) before transcribing voice commands."),
                reason: "config_missing"
            )
            return
        }

        let resolvedPromptId = promptId ?? activeReflectionPrompt?.id
        do {
            let result = try await commandService.submitCommand(
                TemplateConvexCommandRequest(text: transcript, source: .voice, promptId: resolvedPromptId)
            )
            apply(result)
            voiceState = .submitted
            feedbackMessage = result.summary
            analytics.capture("command_submitted", properties: ["source": "voice"])
            if case .brainDump = screen {
                goHome()
            }
            await refreshReflectionPrompts()
        } catch {
            applyVoiceFallback(error, reason: "command_submission_failed")
        }
    }

    func saveEntryEdit(id: String, body: String) async {
        do {
            let updated = try await commandService.updateEntry(id: id, body: body)
            if let index = entries.firstIndex(where: { $0.id == id }) {
                entries[index] = Entry(listedEntry: updated)
            }
            feedbackMessage = "Saved."
            goHome()
        } catch {
            feedbackMessage = displayMessage(for: error)
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
        homeReflectionPrompts.removeAll()
        commandText = ""
        isSignedIn = false
        isSettingsPresented = false
        screen = .home
        activeReflectionPrompt = nil
        voiceTranscriptPreview = nil
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
        if arguments.contains("--template-deletion-progress") {
            feedbackMessage = "Account deletion is in progress. Your data will be removed shortly."
            return
        }
        if arguments.contains("--journal-home") {
            applyJournalHomeFixture()
            return
        }
        if arguments.contains("--journal-brain-dump") {
            applyJournalBrainDumpFixture()
            return
        }
        if arguments.contains("--journal-reflections") {
            applyJournalReflectionsFixture()
            return
        }

        guard arguments.contains("--template-signed-in")
            || arguments.contains("--template-voice-fallback")
            || arguments.contains("--template-settings")
        else {
            return
        }

        isSignedIn = true
        screen = .home
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

    private func applyJournalHomeFixture() {
        isSignedIn = true
        screen = .home
        sentryScope.bind(ownerKey: "fixture-owner")
        homeReflectionPrompts = [
            TemplateReflectionPrompt.fixture,
            TemplateReflectionPrompt(
                id: "reflectionPromptFixture2",
                question: "Where was there energy?",
                status: .open,
                createdAt: 1_720_000_000_100
            ),
        ]
        entries = [
            Entry(id: "entry-fixture-1", body: "Morning walk cleared my head.", source: .voice),
            Entry(id: "entry-fixture-2", body: "Need to follow up with the team.", source: .typed),
        ]
    }

    private func applyJournalBrainDumpFixture() {
        isSignedIn = true
        screen = .brainDump(prompt: nil)
        sentryScope.bind(ownerKey: "fixture-owner")
        homeReflectionPrompts = []
        entries = []
    }

    private func applyJournalReflectionsFixture() {
        isSignedIn = true
        screen = .home
        sentryScope.bind(ownerKey: "fixture-owner")
        homeReflectionPrompts = [
            TemplateReflectionPrompt.fixture,
            TemplateReflectionPrompt(
                id: "reflectionPromptFixture2",
                question: "Where was there energy?",
                status: .open,
                createdAt: 1_720_000_000_100
            ),
            TemplateReflectionPrompt(
                id: "reflectionPromptFixture3",
                question: "Say the unpolished version.",
                status: .open,
                createdAt: 1_720_000_000_200
            ),
        ]
        entries = [
            Entry(id: "entry-fixture-1", body: "I felt scattered today but clearer after walking.", source: .voice),
        ]
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

    init(id: String = UUID().uuidString, body: String, source: Source) {
        self.id = id
        self.body = body
        self.source = source
    }

    init(listedEntry: TemplateListedEntry) {
        id = listedEntry.id
        body = listedEntry.body
        source = Source(rawValue: listedEntry.source.rawValue) ?? .typed
    }
}
