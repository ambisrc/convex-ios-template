import XCTest
@testable import VoiceAgentTemplate

final class TemplateConvexCommandRequestTests: XCTestCase {
    func testTypedCommandRequestEncodesTextAndSource() throws {
        let request = TemplateConvexCommandRequest(text: "Create a note saying hello", source: .typed)
        let object = try JSONSerialization.jsonObject(with: request.encodedBody()) as? [String: String]

        XCTAssertEqual(object?["text"], "Create a note saying hello")
        XCTAssertEqual(object?["source"], "typed")
    }

    func testPublicActionNamesMatchSharedContractFixture() throws {
        let fixture = try PublicActionContractFixture.load()

        XCTAssertNotNil(fixture.actions[TemplateBackendEndpoints.submitCommand])
        XCTAssertNotNil(fixture.actions[TemplateBackendEndpoints.transcribeVoiceCommand])
        XCTAssertNotNil(fixture.actions[TemplateBackendEndpoints.deleteAccount])
        XCTAssertNotNil(fixture.queries[TemplateBackendEndpoints.listEntries])
    }

    func testTypedCommandRequestMatchesSharedContractFixture() throws {
        let contract = try PublicActionContractFixture.load()
            .requiredAction(TemplateBackendEndpoints.submitCommand)
        let request = TemplateConvexCommandRequest(text: "Create a note saying hello", source: .typed)

        let requestObject = try XCTUnwrap(JSONSerialization.jsonObject(with: request.encodedBody()) as? NSDictionary)

        XCTAssertEqual(requestObject, contract.request as NSDictionary)
    }

    func testConvexConfigurationParsesHTTPDeploymentURL() {
        let config = TemplateConvexClientConfiguration.fromInfoDictionary([
            "CONVEX_DEPLOYMENT_URL": "https://example.convex.cloud",
        ])

        XCTAssertEqual(config?.deploymentURL.absoluteString, "https://example.convex.cloud")
    }

    func testConvexConfigurationRejectsNonHTTPDeploymentURL() {
        let config = TemplateConvexClientConfiguration.fromInfoDictionary([
            "CONVEX_DEPLOYMENT_URL": "httpx://example.convex.cloud",
        ])

        XCTAssertNil(config)
    }

    func testConvexConfigurationRejectsHostlessHTTPDeploymentURL() {
        let config = TemplateConvexClientConfiguration.fromInfoDictionary([
            "CONVEX_DEPLOYMENT_URL": "https:broken-value",
        ])

        XCTAssertNil(config)
    }

    func testCommandResultDecodesPublicConvexResponseShape() throws {
        let json = try PublicActionContractFixture.load()
            .requiredAction(TemplateBackendEndpoints.submitCommand)
            .successData()

        let result = try JSONDecoder().decode(TemplateCommandResult.self, from: json)

        XCTAssertEqual(result.status, .applied)
        XCTAssertEqual(result.summary, "Created entry: hello.")
        XCTAssertEqual(result.operations, [.createEntry(body: "hello")])
        XCTAssertEqual(result.entries, [
            TemplateAppliedEntry(body: "hello", source: .typed),
        ])
    }

    func testVoiceTranscriptionResultDecodesPublicConvexResponseShape() throws {
        let json = try PublicActionContractFixture.load()
            .requiredAction(TemplateBackendEndpoints.transcribeVoiceCommand)
            .successData()

        let result = try JSONDecoder().decode(TemplateVoiceTranscriptionResult.self, from: json)

        XCTAssertEqual(result, .transcribed(transcript: "Create a note saying voice result"))
    }

    func testVoiceTranscriptionResultDecodesConfigurationMissingUnion() throws {
        let json = try PublicActionContractFixture.load()
            .requiredAction(TemplateBackendEndpoints.transcribeVoiceCommand)
            .configurationMissingData()

        let result = try JSONDecoder().decode(TemplateVoiceTranscriptionResult.self, from: json)

        XCTAssertEqual(result, .configurationMissing(missing: "GROQ_API_KEY"))
    }

    func testListEntriesResponseDecodesSharedReadSeamFixture() throws {
        let json = try PublicActionContractFixture.load()
            .requiredQuery(TemplateBackendEndpoints.listEntries)
            .successData()

        let entries = try JSONDecoder().decode([TemplateListedEntry].self, from: json)

        XCTAssertEqual(entries, [
            TemplateListedEntry(body: "hello", source: .typed),
        ])
    }

    func testDeleteAccountResponseDecodesSharedContractFixture() throws {
        let json = try PublicActionContractFixture.load()
            .requiredAction(TemplateBackendEndpoints.deleteAccount)
            .successData()

        let result = try JSONDecoder().decode(TemplateDeleteAccountResult.self, from: json)

        guard case let .deleted(deleted, batches, cleanup) = result else {
            return XCTFail("Expected deleted status")
        }
        XCTAssertEqual(deleted.entries, 1)
        XCTAssertEqual(deleted.commandHistory, 1)
        XCTAssertEqual(batches, 1)
        XCTAssertEqual(cleanup.posthog.status, "skipped")
        XCTAssertEqual(cleanup.sentry.status, "skipped")
    }

    func testDeleteAccountResponseDecodesDeletionInProgressFixture() throws {
        let json = try PublicActionContractFixture.load()
            .requiredAction(TemplateBackendEndpoints.deleteAccount)
            .namedResponseData("deletionInProgress")

        let result = try JSONDecoder().decode(TemplateDeleteAccountResult.self, from: json)

        guard case let .deletionInProgress(deleted, batches, jobStatus) = result else {
            return XCTFail("Expected deletion_in_progress status")
        }
        XCTAssertEqual(deleted.entries, 1000)
        XCTAssertEqual(batches, 20)
        XCTAssertEqual(jobStatus, .deleting)
    }

    func testDeleteAccountResponseDecodesCleanupFailedFixture() throws {
        let json = try PublicActionContractFixture.load()
            .requiredAction(TemplateBackendEndpoints.deleteAccount)
            .namedResponseData("cleanupFailed")

        let result = try JSONDecoder().decode(TemplateDeleteAccountResult.self, from: json)

        guard case let .deleted(_, _, cleanup) = result else {
            return XCTFail("Expected deleted status")
        }
        XCTAssertEqual(cleanup.posthog.status, "failed")
        XCTAssertEqual(cleanup.posthog.reason, "POSTHOG_DELETE_FAILED_500")
        XCTAssertEqual(cleanup.sentry.status, "reported")
        XCTAssertNil(cleanup.sentry.reason)
    }
}

private struct PublicActionContractFixture: Decodable {
    let actions: [String: PublicActionContract]
    let queries: [String: PublicQueryContract]

    static func load(file: StaticString = #filePath) throws -> PublicActionContractFixture {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let root = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureURL = root.appendingPathComponent("tests/fixtures/public-actions.json")
        let data = try Data(contentsOf: fixtureURL)
        return try JSONDecoder().decode(PublicActionContractFixture.self, from: data)
    }

    func requiredAction(_ name: String) throws -> PublicActionContract {
        try XCTUnwrap(actions[name], "Missing shared action contract for \(name)")
    }

    func requiredQuery(_ name: String) throws -> PublicQueryContract {
        try XCTUnwrap(queries[name], "Missing shared query contract for \(name)")
    }
}

private struct PublicActionContract: Decodable {
    let request: [String: String]
    let success: JSONValue
    let configurationMissing: JSONValue?
    let deletionInProgress: JSONValue?
    let cleanupFailed: JSONValue?

    func successData() throws -> Data {
        try JSONEncoder().encode(success)
    }

    func configurationMissingData() throws -> Data {
        try JSONEncoder().encode(XCTUnwrap(configurationMissing))
    }

    func namedResponseData(_ name: String) throws -> Data {
        switch name {
        case "deletionInProgress":
            return try JSONEncoder().encode(XCTUnwrap(deletionInProgress))
        case "cleanupFailed":
            return try JSONEncoder().encode(XCTUnwrap(cleanupFailed))
        default:
            throw PublicActionContractError.unsupportedNamedResponse(name)
        }
    }
}

private enum PublicActionContractError: Error {
    case unsupportedNamedResponse(String)
}

private struct PublicQueryContract: Decodable {
    let request: [String: String]
    let success: JSONValue

    func successData() throws -> Data {
        try JSONEncoder().encode(success)
    }
}

private enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Int)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        if let value = try? container.decode(Int.self) {
            self = .number(value)
            return
        }
        if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
            return
        }
        self = .object(try container.decode([String: JSONValue].self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}
