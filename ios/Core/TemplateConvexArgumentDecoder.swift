import ConvexMobile
import Foundation

enum TemplateConvexArgumentDecoder {
    static func decode(_ requestBody: Data) throws -> [String: ConvexEncodable?] {
        guard !requestBody.isEmpty else {
            return [:]
        }

        let object = try JSONSerialization.jsonObject(with: requestBody)
        guard let dictionary = object as? [String: Any] else {
            throw TemplateServiceError.failed("Convex request body must be a JSON object.")
        }

        return try dictionary.mapValues { value in
            try convexValue(from: value)
        }
    }

    private static func convexValue(from value: Any) throws -> ConvexEncodable? {
        if value is NSNull {
            return nil
        }
        if let string = value as? String {
            return string
        }
        if let bool = value as? Bool {
            return bool
        }
        if let int = value as? Int {
            return int
        }
        if let double = value as? Double {
            return double
        }
        if let array = value as? [Any] {
            return try array.map { try convexValue(from: $0) }
        }
        if let dictionary = value as? [String: Any] {
            return try dictionary.mapValues { try convexValue(from: $0) }
        }

        throw TemplateServiceError.failed("Unsupported Convex request value type.")
    }
}
