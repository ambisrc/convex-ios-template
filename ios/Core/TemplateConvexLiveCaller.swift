import Combine
import ConvexMobile
import Foundation

struct TemplateConvexLiveCaller: TemplateConvexCalling {
    let client: ConvexClient

    func callAction<Response: Decodable>(
        _ action: String,
        requestBody: Data
    ) async throws -> Response {
        let args = try TemplateConvexArgumentDecoder.decode(requestBody)
        return try await client.action(action, with: args)
    }

    func callQuery<Response: Decodable>(
        _ query: String,
        requestBody: Data
    ) async throws -> Response {
        let args = try TemplateConvexArgumentDecoder.decode(requestBody)
        return try await fetchFirstValue(
            from: client.subscribe(to: query, with: args, yielding: Response.self)
        )
    }

    private func fetchFirstValue<Response: Decodable>(
        from publisher: AnyPublisher<Response, ClientError>
    ) async throws -> Response {
        for try await value in publisher.values {
            return value
        }
        throw TemplateServiceError.failed("Convex query returned no data.")
    }
}
