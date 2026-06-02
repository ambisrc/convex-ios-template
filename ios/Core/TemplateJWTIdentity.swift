import Foundation

enum TemplateJWTIdentity {
    static let appleIssuer = "https://appleid.apple.com"

    static func ownerKey(fromIdentityToken token: String) throws -> String {
        let payload = try payloadJSON(fromIdentityToken: token)
        guard let subject = payload["sub"] as? String, !subject.isEmpty else {
            throw TemplateServiceError.failed("Apple identity token is missing a subject.")
        }

        if let issuer = payload["iss"] as? String, !issuer.isEmpty {
            return "\(issuer)|\(subject)"
        }

        return "\(appleIssuer)|\(subject)"
    }

    static func payloadJSON(fromIdentityToken token: String) throws -> [String: Any] {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else {
            throw TemplateServiceError.failed("Apple identity token is invalid.")
        }

        let payloadData = try base64URLDecode(String(segments[1]))
        let object = try JSONSerialization.jsonObject(with: payloadData)
        guard let payload = object as? [String: Any] else {
            throw TemplateServiceError.failed("Apple identity token payload is invalid.")
        }
        return payload
    }

    private static func base64URLDecode(_ value: String) throws -> Data {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = 4 - (base64.count % 4)
        if padding < 4 {
            base64.append(String(repeating: "=", count: padding))
        }
        guard let data = Data(base64Encoded: base64) else {
            throw TemplateServiceError.failed("Apple identity token payload could not be decoded.")
        }
        return data
    }
}
