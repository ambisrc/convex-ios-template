import ConvexMobile
import Foundation

final class TemplateAppleAuthProvider: AuthProvider, @unchecked Sendable {
    typealias T = TemplateAppleSignInResult

    let appleSignIn: TemplateAppleSignInPerforming
    private let lock = NSLock()
    private var cachedIdTokenHandler: (@Sendable (String?) -> Void)?
    private var loginGeneration = 0

    init(appleSignIn: TemplateAppleSignInPerforming) {
        self.appleSignIn = appleSignIn
    }

    func login(onIdToken: @Sendable @escaping (String?) -> Void) async throws -> TemplateAppleSignInResult {
        let generation = beginLogin(onIdToken: onIdToken)
        let result: TemplateAppleSignInResult
        do {
            result = try await appleSignIn.signIn()
        } catch {
            clearLoginIfCurrent(generation: generation)
            throw error
        }
        try notifyLoginCompleted(generation: generation, identityToken: result.identityToken)
        return result
    }

    func loginFromCache(onIdToken: @Sendable @escaping (String?) -> Void) async throws -> TemplateAppleSignInResult {
        let generation = beginLogin(onIdToken: onIdToken)
        clearLoginIfCurrent(generation: generation)
        throw TemplateServiceError.failed("Cached Apple Sign In is not available.")
    }

    func logout() async throws {
        let handler = clearLogin()
        handler?(nil)
    }

    private func beginLogin(onIdToken: @Sendable @escaping (String?) -> Void) -> Int {
        lock.lock()
        loginGeneration += 1
        let generation = loginGeneration
        cachedIdTokenHandler = onIdToken
        lock.unlock()
        return generation
    }

    private func notifyLoginCompleted(generation: Int, identityToken: String) throws {
        lock.lock()
        let handler: (@Sendable (String?) -> Void)?
        if generation == loginGeneration {
            handler = cachedIdTokenHandler
        } else {
            handler = nil
        }
        lock.unlock()

        guard let handler else {
            throw TemplateAppleSignInError.canceled
        }
        handler(identityToken)
    }

    private func clearLoginIfCurrent(generation: Int) {
        lock.lock()
        if generation == loginGeneration {
            cachedIdTokenHandler = nil
        }
        lock.unlock()
    }

    private func clearLogin() -> (@Sendable (String?) -> Void)? {
        lock.lock()
        loginGeneration += 1
        let handler = cachedIdTokenHandler
        cachedIdTokenHandler = nil
        lock.unlock()
        return handler
    }

    func extractIdToken(from authResult: TemplateAppleSignInResult) -> String {
        authResult.identityToken
    }
}
