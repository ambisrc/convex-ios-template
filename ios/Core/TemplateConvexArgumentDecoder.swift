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
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue
            }

            let doubleValue = number.doubleValue
            if doubleValue.rounded(.towardZero) == doubleValue,
               doubleValue >= Double(Int.min),
               doubleValue <= Double(Int.max) {
                return number.intValue
            }
            return doubleValue
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
