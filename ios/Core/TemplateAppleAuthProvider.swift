import ConvexMobile
import Foundation

final class TemplateAppleAuthProvider: AuthProvider, @unchecked Sendable {
    typealias T = TemplateAppleSignInResult

    let appleSignIn: TemplateAppleSignInPerforming
    private var cachedIdTokenHandler: (@Sendable (String?) -> Void)?

    init(appleSignIn: TemplateAppleSignInPerforming) {
        self.appleSignIn = appleSignIn
    }

    func login(onIdToken: @Sendable @escaping (String?) -> Void) async throws -> TemplateAppleSignInResult {
        cachedIdTokenHandler = onIdToken
        let result = try await appleSignIn.signIn()
        onIdToken(result.identityToken)
        return result
    }

    func loginFromCache(onIdToken: @Sendable @escaping (String?) -> Void) async throws -> TemplateAppleSignInResult {
        cachedIdTokenHandler = onIdToken
        throw TemplateServiceError.failed("Cached Apple Sign In is not available.")
    }

    func logout() async throws {
        cachedIdTokenHandler?(nil)
        cachedIdTokenHandler = nil
    }

    func extractIdToken(from authResult: TemplateAppleSignInResult) -> String {
        authResult.identityToken
    }
}
