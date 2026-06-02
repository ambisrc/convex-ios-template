import ConvexMobile
import Foundation

final class TemplateRuntimeServiceContainer {
    let configuration: TemplateConvexClientConfiguration
    let authClient: ConvexClientWithAuth<TemplateAppleSignInResult>
    let backendClient: TemplateBackendClient
    let sessionService: TemplateConfiguredSessionService

    init(
        configuration: TemplateConvexClientConfiguration,
        appleSignIn: TemplateAppleSignInPerforming = TemplateAppleSignInService()
    ) {
        self.configuration = configuration
        let authProvider = TemplateAppleAuthProvider(appleSignIn: appleSignIn)
        self.authClient = ConvexClientWithAuth(
            deploymentUrl: configuration.deploymentURL.absoluteString,
            authProvider: authProvider
        )
        let caller = TemplateConvexLiveCaller(client: authClient)
        self.backendClient = TemplateBackendClient(configuration: configuration, caller: caller)
        self.sessionService = TemplateConfiguredSessionService(
            configuration: configuration,
            authClient: authClient
        )
    }
}

enum TemplateRuntimeServices {
    private static let sharedContainer: TemplateRuntimeServiceContainer? = {
        guard
            let configuration = TemplateConvexClientConfiguration.fromInfoDictionary(
                Bundle.main.infoDictionary ?? [:]
            ),
            !configuration.isPlaceholder
        else {
            return nil
        }
        return TemplateRuntimeServiceContainer(configuration: configuration)
    }()

    static func makeSessionService() -> TemplateSessionServicing {
        sharedContainer?.sessionService ?? TemplateConfiguredSessionService()
    }

    static func makeCommandService() -> TemplateCommandServicing {
        sharedContainer?.backendClient ?? PlaceholderTemplateBackendClient()
    }

    static func sharedAuthClient() -> ConvexClientWithAuth<TemplateAppleSignInResult>? {
        sharedContainer?.authClient
    }
}
