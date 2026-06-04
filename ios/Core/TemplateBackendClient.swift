import Foundation

protocol TemplateConvexCalling {
    func callAction<Response: Decodable>(
        _ action: String,
        requestBody: Data
    ) async throws -> Response

    func callQuery<Response: Decodable>(
        _ query: String,
        requestBody: Data
    ) async throws -> Response

    func callMutation<Response: Decodable>(
        _ mutation: String,
        requestBody: Data
    ) async throws -> Response
}

enum TemplateBackendEndpoints {
    static let submitCommand = "commands:submitCommand"
    static let transcribeVoiceCommand = "commands:transcribeVoiceCommand"
    static let deleteAccount = "commands:deleteAccount"
    static let listEntries = "entries:listEntries"
    static let listReflections = "reflections:listLatest"
    static let generateReflections = "reflections:generateNow"
    static let updateEntry = "entries:updateEntry"
}

protocol TemplateCommandServicing {
    func submitCommand(_ request: TemplateConvexCommandRequest) async throws -> TemplateCommandResult
    func transcribeVoice(_ request: TemplateVoiceTranscriptionRequest) async throws -> TemplateVoiceTranscriptionResult
    func listEntries() async throws -> [TemplateListedEntry]
    func listReflections() async throws -> [TemplateReflectionPrompt]
    func generateReflections() async throws -> TemplateGenerateReflectionsResult
    func updateEntry(id: String, body: String) async throws -> TemplateListedEntry
    func deleteAccount() async throws -> TemplateDeleteAccountResult
}

struct TemplateBackendClient: TemplateCommandServicing {
    let configuration: TemplateConvexClientConfiguration?
    let caller: TemplateConvexCalling?

    init(
        configuration: TemplateConvexClientConfiguration? = .fromInfoDictionary(Bundle.main.infoDictionary ?? [:]),
        caller: TemplateConvexCalling? = nil
    ) {
        self.configuration = configuration
        self.caller = caller
    }

    func submitCommand(_ request: TemplateConvexCommandRequest) async throws -> TemplateCommandResult {
        try await callAction(
            TemplateBackendEndpoints.submitCommand,
            request: request
        )
    }

    func transcribeVoice(_ request: TemplateVoiceTranscriptionRequest) async throws -> TemplateVoiceTranscriptionResult {
        try await callAction(
            TemplateBackendEndpoints.transcribeVoiceCommand,
            request: request
        )
    }

    func listEntries() async throws -> [TemplateListedEntry] {
        try await callQuery(
            TemplateBackendEndpoints.listEntries,
            request: EmptyConvexRequest()
        )
    }

    func listReflections() async throws -> [TemplateReflectionPrompt] {
        try await callQuery(
            TemplateBackendEndpoints.listReflections,
            request: EmptyConvexRequest()
        )
    }

    func generateReflections() async throws -> TemplateGenerateReflectionsResult {
        try await callAction(
            TemplateBackendEndpoints.generateReflections,
            request: EmptyConvexRequest()
        )
    }

    func updateEntry(id: String, body: String) async throws -> TemplateListedEntry {
        try await callMutation(
            TemplateBackendEndpoints.updateEntry,
            request: TemplateUpdateEntryRequest(id: id, body: body)
        )
    }

    func deleteAccount() async throws -> TemplateDeleteAccountResult {
        try await callAction(
            TemplateBackendEndpoints.deleteAccount,
            request: EmptyConvexRequest()
        )
    }

    private func callAction<Response: Decodable, Request: Encodable>(
        _ action: String,
        request: Request
    ) async throws -> Response {
        let caller = try requireCaller(for: action)
        let body = try JSONEncoder().encode(request)
        return try await caller.callAction(action, requestBody: body)
    }

    private func callQuery<Response: Decodable, Request: Encodable>(
        _ query: String,
        request: Request
    ) async throws -> Response {
        let caller = try requireCaller(for: query)
        let body = try JSONEncoder().encode(request)
        return try await caller.callQuery(query, requestBody: body)
    }

    private func callMutation<Response: Decodable, Request: Encodable>(
        _ mutation: String,
        request: Request
    ) async throws -> Response {
        let caller = try requireCaller(for: mutation)
        let body = try JSONEncoder().encode(request)
        return try await caller.callMutation(mutation, requestBody: body)
    }

    private func requireCaller(for endpoint: String) throws -> TemplateConvexCalling {
        guard let configuration, !configuration.isPlaceholder else {
            throw TemplateServiceError.missingConfiguration(
                "Configure CONVEX_DEPLOYMENT_URL before calling \(endpoint)."
            )
        }
        guard let caller else {
            throw TemplateServiceError.missingConfiguration(
                "Wire the Convex Swift client to \(endpoint) at \(configuration.deploymentURL.absoluteString)."
            )
        }
        return caller
    }
}

struct EmptyConvexRequest: Encodable, Equatable {}

struct PlaceholderTemplateBackendClient: TemplateCommandServicing {
    let configuration: TemplateConvexClientConfiguration?

    init(configuration: TemplateConvexClientConfiguration? = .fromInfoDictionary(Bundle.main.infoDictionary ?? [:])) {
        self.configuration = configuration
    }

    func submitCommand(_ request: TemplateConvexCommandRequest) async throws -> TemplateCommandResult {
        _ = request
        return try requireConfigured(action: TemplateBackendEndpoints.submitCommand)
    }

    func transcribeVoice(_ request: TemplateVoiceTranscriptionRequest) async throws -> TemplateVoiceTranscriptionResult {
        _ = request
        return try requireConfigured(action: TemplateBackendEndpoints.transcribeVoiceCommand)
    }

    func listEntries() async throws -> [TemplateListedEntry] {
        try requireConfigured(action: TemplateBackendEndpoints.listEntries)
    }

    func listReflections() async throws -> [TemplateReflectionPrompt] {
        try requireConfigured(action: TemplateBackendEndpoints.listReflections)
    }

    func generateReflections() async throws -> TemplateGenerateReflectionsResult {
        try requireConfigured(action: TemplateBackendEndpoints.generateReflections)
    }

    func updateEntry(id: String, body: String) async throws -> TemplateListedEntry {
        _ = id
        _ = body
        return try requireConfigured(action: TemplateBackendEndpoints.updateEntry)
    }

    func deleteAccount() async throws -> TemplateDeleteAccountResult {
        try requireConfigured(action: TemplateBackendEndpoints.deleteAccount)
    }

    private func requireConfigured<T>(action: String) throws -> T {
        guard let configuration, !configuration.isPlaceholder else {
            throw TemplateServiceError.missingConfiguration(
                "Configure CONVEX_DEPLOYMENT_URL before calling \(action)."
            )
        }
        throw TemplateServiceError.missingConfiguration(
            "Wire the Convex Swift client to \(action) at \(configuration.deploymentURL.absoluteString)."
        )
    }
}

typealias TemplateConvexCommandService = PlaceholderTemplateBackendClient
