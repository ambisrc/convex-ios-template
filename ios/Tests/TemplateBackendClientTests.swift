import XCTest
@testable import VoiceAgentTemplate

final class TemplateBackendClientTests: XCTestCase {
    func testBackendClientRoutesSubmitCommandThroughInjectedCaller() async throws {
        let fixture = try PublicActionContractFixture.load()
            .requiredAction(TemplateBackendEndpoints.submitCommand)
        let caller = ConvexCallerSpy()
        caller.actionResponses[TemplateBackendEndpoints.submitCommand] = try fixture.successData()
        let client = TemplateBackendClient(
            configuration: TemplateConvexClientConfiguration(deploymentURL: URL(string: "https://live.convex.cloud")!),
            caller: caller
        )

        let result = try await client.submitCommand(
            TemplateConvexCommandRequest(text: "Create a note saying hello", source: .typed)
        )

        XCTAssertEqual(caller.actionCalls.map(\.name), [TemplateBackendEndpoints.submitCommand])
        XCTAssertEqual(
            caller.actionCalls.first?.body,
            try TemplateConvexCommandRequest(text: "Create a note saying hello", source: .typed).encodedBody()
        )
        XCTAssertEqual(result.status, .applied)
        XCTAssertEqual(result.summary, "Created entry: hello.")
    }

    func testBackendClientRoutesListEntriesThroughInjectedQueryCaller() async throws {
        let fixture = try PublicActionContractFixture.load()
            .requiredQuery(TemplateBackendEndpoints.listEntries)
        let caller = ConvexCallerSpy()
        caller.queryResponses[TemplateBackendEndpoints.listEntries] = try fixture.successData()
        let client = TemplateBackendClient(
            configuration: TemplateConvexClientConfiguration(deploymentURL: URL(string: "https://live.convex.cloud")!),
            caller: caller
        )

        let entries = try await client.listEntries()

        XCTAssertEqual(caller.queryCalls.map(\.name), [TemplateBackendEndpoints.listEntries])
        XCTAssertEqual(caller.queryCalls.first?.body, try JSONEncoder().encode(EmptyConvexRequest()))
        XCTAssertEqual(entries, [TemplateListedEntry(body: "hello", source: .typed)])
    }

    func testBackendClientRoutesDeleteAccountThroughInjectedCaller() async throws {
        let fixture = try PublicActionContractFixture.load()
            .requiredAction(TemplateBackendEndpoints.deleteAccount)
        let caller = ConvexCallerSpy()
        caller.actionResponses[TemplateBackendEndpoints.deleteAccount] = try fixture.successData()
        let client = TemplateBackendClient(
            configuration: TemplateConvexClientConfiguration(deploymentURL: URL(string: "https://live.convex.cloud")!),
            caller: caller
        )

        let result = try await client.deleteAccount()

        XCTAssertEqual(caller.actionCalls.map(\.name), [TemplateBackendEndpoints.deleteAccount])
        guard case .deleted = result else {
            return XCTFail("Expected deleted status")
        }
    }

    func testPlaceholderBackendClientFailsSafelyWithoutCaller() async {
        let client = PlaceholderTemplateBackendClient(
            configuration: TemplateConvexClientConfiguration(deploymentURL: URL(string: "https://live.convex.cloud")!)
        )

        do {
            _ = try await client.submitCommand(
                TemplateConvexCommandRequest(text: "Create a note saying hello", source: .typed)
            )
            XCTFail("Expected missing configuration error")
        } catch let error as TemplateServiceError {
            XCTAssertEqual(
                error.errorDescription,
                "Wire the Convex Swift client to commands:submitCommand at https://live.convex.cloud."
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private final class ConvexCallerSpy: TemplateConvexCalling {
    struct Call {
        let name: String
        let body: Data
    }

    var actionCalls: [Call] = []
    var queryCalls: [Call] = []
    var actionResponses: [String: Data] = [:]
    var queryResponses: [String: Data] = [:]

    func callAction<Response>(
        _ action: String,
        requestBody: Data
    ) async throws -> Response where Response: Decodable {
        actionCalls.append(Call(name: action, body: requestBody))
        guard let responseData = actionResponses[action] else {
            throw TemplateServiceError.failed("Missing spy response for \(action)")
        }
        return try JSONDecoder().decode(Response.self, from: responseData)
    }

    func callQuery<Response>(
        _ query: String,
        requestBody: Data
    ) async throws -> Response where Response: Decodable {
        queryCalls.append(Call(name: query, body: requestBody))
        guard let responseData = queryResponses[query] else {
            throw TemplateServiceError.failed("Missing spy response for \(query)")
        }
        return try JSONDecoder().decode(Response.self, from: responseData)
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

    func successData() throws -> Data {
        try JSONEncoder().encode(success)
    }
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
