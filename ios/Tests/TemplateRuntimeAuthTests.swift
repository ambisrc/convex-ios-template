import XCTest
@testable import VoiceAgentTemplate

final class TemplateConvexArgumentDecoderTests: XCTestCase {
    func testDecodeMapsCommandRequestFields() throws {
        let body = try TemplateConvexCommandRequest(text: "hello", source: .typed).encodedBody()

        let args = try TemplateConvexArgumentDecoder.decode(body)

        XCTAssertEqual(args["text"] as? String, "hello")
        XCTAssertEqual(args["source"] as? String, "typed")
        XCTAssertNil(args["promptId"] as? String)
    }

    func testDecodeEmptyBodyProducesEmptyArguments() throws {
        let args = try TemplateConvexArgumentDecoder.decode(Data())

        XCTAssertTrue(args.isEmpty)
    }

    func testDecodePreservesNumbersAndBooleansFromJSONSerializationBridge() throws {
        let body = Data(#"{"count":1,"enabled":true,"ratio":1.5}"#.utf8)

        let args = try TemplateConvexArgumentDecoder.decode(body)

        XCTAssertEqual(args["count"] as? Int, 1)
        XCTAssertEqual(args["enabled"] as? Bool, true)
        XCTAssertEqual(args["ratio"] as? Double, 1.5)
    }
}

final class TemplateJWTIdentityTests: XCTestCase {
    func testOwnerKeyUsesIssuerAndSubjectFromTokenPayload() throws {
        let payload = #"{"iss":"https://appleid.apple.com","sub":"001234.abc"}"#
        let token = makeJWT(payload: payload)

        let ownerKey = try TemplateJWTIdentity.ownerKey(fromIdentityToken: token)

        XCTAssertEqual(ownerKey, "https://appleid.apple.com|001234.abc")
    }

    func testOwnerKeyFailsWhenSubjectMissing() {
        let payload = #"{"iss":"https://appleid.apple.com"}"#
        let token = makeJWT(payload: payload)

        XCTAssertThrowsError(try TemplateJWTIdentity.ownerKey(fromIdentityToken: token)) { error in
            XCTAssertEqual(
                (error as? TemplateServiceError)?.errorDescription,
                "Apple identity token is missing a subject."
            )
        }
    }

    private func makeJWT(payload: String) -> String {
        let header = Data(#"{"alg":"none"}"#.utf8).base64URLEncodedString()
        let body = Data(payload.utf8).base64URLEncodedString()
        return "\(header).\(body).signature"
    }
}

final class TemplateAppleSignInCredentialParserTests: XCTestCase {
    func testParseReturnsIdentityTokenWhenPresent() throws {
        let token = "header.payload.signature"
        let result = try TemplateAppleSignInCredentialParser.parse(
            user: "apple-user",
            identityTokenData: Data(token.utf8),
            clientId: "com.example.app"
        )

        XCTAssertEqual(result.user, "apple-user")
        XCTAssertEqual(result.clientId, "com.example.app")
        XCTAssertEqual(result.identityToken, token)
    }

    func testParseFailsWhenIdentityTokenMissing() {
        XCTAssertThrowsError(
            try TemplateAppleSignInCredentialParser.parse(
                user: "apple-user",
                identityTokenData: nil,
                clientId: "com.example.app"
            )
        ) { error in
            XCTAssertEqual(
                (error as? TemplateAppleSignInError)?.errorDescription,
                "Apple did not return an identity token."
            )
        }
    }

    func testParseFailsWhenIdentityTokenIsNotUTF8() {
        let invalidData = Data([0xFF, 0xFE, 0xFD])

        XCTAssertThrowsError(
            try TemplateAppleSignInCredentialParser.parse(
                user: "apple-user",
                identityTokenData: invalidData,
                clientId: "com.example.app"
            )
        ) { error in
            XCTAssertEqual(
                (error as? TemplateAppleSignInError)?.errorDescription,
                "Apple returned an identity token that is not valid UTF-8."
            )
        }
    }

    func testAlreadyInProgressErrorHasDisplayMessage() {
        XCTAssertEqual(
            TemplateAppleSignInError.alreadyInProgress.errorDescription,
            "Sign in with Apple is already in progress."
        )
    }
}

final class TemplateAppleAuthProviderTests: XCTestCase {
    func testLogoutDuringLoginPreventsStaleTokenNotification() async {
        let appleSignIn = ControlledAppleSignIn()
        let provider = TemplateAppleAuthProvider(appleSignIn: appleSignIn)
        let recorder = TokenRecorder()
        let loginTask = Task {
            try await provider.login { token in
                recorder.append(token)
            }
        }

        await appleSignIn.waitUntilStarted()
        try? await provider.logout()
        appleSignIn.complete(
            .success(
                TemplateAppleSignInResult(
                    user: "apple-user",
                    clientId: "com.example.app",
                    identityToken: "header.payload.signature"
                )
            )
        )

        do {
            _ = try await loginTask.value
            XCTFail("Expected login to fail after logout invalidates the in-flight token handler.")
        } catch {
            XCTAssertEqual(
                (error as? TemplateAppleSignInError)?.errorDescription,
                "Sign in with Apple was canceled."
            )
        }
        XCTAssertEqual(recorder.values, [nil])
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private final class TokenRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String?] = []

    var values: [String?] {
        lock.withLock { storage }
    }

    func append(_ value: String?) {
        lock.withLock {
            storage.append(value)
        }
    }
}

private final class ControlledAppleSignIn: TemplateAppleSignInPerforming, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<TemplateAppleSignInResult, Error>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func signIn() async throws -> TemplateAppleSignInResult {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                self.continuation = continuation
                startWaiters.forEach { $0.resume() }
                startWaiters.removeAll()
            }
        }
    }

    func waitUntilStarted() async {
        await withCheckedContinuation { continuation in
            lock.withLock {
                if self.continuation != nil {
                    continuation.resume()
                } else {
                    startWaiters.append(continuation)
                }
            }
        }
    }

    func complete(_ result: Result<TemplateAppleSignInResult, Error>) {
        let continuation = lock.withLock {
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.resume(with: result)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
