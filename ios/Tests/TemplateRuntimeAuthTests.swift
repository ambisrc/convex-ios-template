import XCTest
@testable import VoiceAgentTemplate

final class TemplateConvexArgumentDecoderTests: XCTestCase {
    func testDecodeMapsCommandRequestFields() throws {
        let body = try TemplateConvexCommandRequest(text: "hello", source: .typed).encodedBody()

        let args = try TemplateConvexArgumentDecoder.decode(body)

        XCTAssertEqual(args["text"] as? String, "hello")
        XCTAssertEqual(args["source"] as? String, "typed")
    }

    func testDecodeEmptyBodyProducesEmptyArguments() throws {
        let args = try TemplateConvexArgumentDecoder.decode(Data())

        XCTAssertTrue(args.isEmpty)
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
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
