import AuthenticationServices
import Foundation
import UIKit

struct TemplateAppleSignInResult: Equatable, Sendable {
    let user: String
    let clientId: String
    let identityToken: String
}

enum TemplateAppleSignInError: Error, Equatable, LocalizedError {
    case canceled
    case missingIdentityToken
    case invalidIdentityTokenData
    case invalidCredential
    case alreadyInProgress
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .canceled:
            return "Sign in with Apple was canceled."
        case .missingIdentityToken:
            return "Apple did not return an identity token."
        case .invalidIdentityTokenData:
            return "Apple returned an identity token that is not valid UTF-8."
        case .invalidCredential:
            return "Apple returned an unexpected credential type."
        case .alreadyInProgress:
            return "Sign in with Apple is already in progress."
        case .failed(let message):
            return message
        }
    }
}

protocol TemplateAppleSignInPerforming: Sendable {
    func signIn() async throws -> TemplateAppleSignInResult
}

enum TemplateAppleSignInCredentialParser {
    static func parse(
        user: String,
        identityTokenData: Data?,
        clientId: String
    ) throws -> TemplateAppleSignInResult {
        guard let tokenData = identityTokenData else {
            throw TemplateAppleSignInError.missingIdentityToken
        }
        guard let identityToken = String(data: tokenData, encoding: .utf8), !identityToken.isEmpty else {
            throw TemplateAppleSignInError.invalidIdentityTokenData
        }

        return TemplateAppleSignInResult(
            user: user,
            clientId: clientId,
            identityToken: identityToken
        )
    }

    static func parse(
        _ credential: ASAuthorizationAppleIDCredential,
        fallbackClientId: String
    ) throws -> TemplateAppleSignInResult {
        try parse(
            user: credential.user,
            identityTokenData: credential.identityToken,
            clientId: Bundle.main.bundleIdentifier ?? fallbackClientId
        )
    }
}

final class TemplateAppleSignInService: NSObject, TemplateAppleSignInPerforming, @unchecked Sendable {
    private var continuation: CheckedContinuation<TemplateAppleSignInResult, Error>?

    @MainActor
    func signIn() async throws -> TemplateAppleSignInResult {
        guard continuation == nil else {
            throw TemplateAppleSignInError.alreadyInProgress
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    private func finish(with result: Result<TemplateAppleSignInResult, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}

extension TemplateAppleSignInService: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            finish(with: .failure(TemplateAppleSignInError.invalidCredential))
            return
        }

        do {
            let result = try TemplateAppleSignInCredentialParser.parse(
                credential,
                fallbackClientId: "com.example.voiceagent"
            )
            finish(with: .success(result))
        } catch {
            finish(with: .failure(error))
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        if let authorizationError = error as? ASAuthorizationError,
           authorizationError.code == .canceled {
            finish(with: .failure(TemplateAppleSignInError.canceled))
            return
        }

        finish(with: .failure(TemplateAppleSignInError.failed(error.localizedDescription)))
    }
}

extension TemplateAppleSignInService: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            if let window = scene.windows.first(where: { $0.isKeyWindow }) {
                return window
            }
        }
        if let window = scenes.first?.windows.first {
            return window
        }
        return ASPresentationAnchor()
    }
}
