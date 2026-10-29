// Minimum iOS 17.
//  Decodes a document from Firestore's REST API, for the widget, which links no Firebase. The typed values
//  (`{"integerValue": "4130"}`, `{"mapValue": {"fields": …}}`) are unwrapped into plain JSON first.

import Foundation

enum FirestoreREST {
    /// The document, or one of its values, is not in the REST shape.
    struct Malformed: Error {}

    static func decode<T: Decodable>(_ type: T.Type, from documentJSON: Data) throws -> T {
        guard let document = try JSONSerialization.jsonObject(with: documentJSON) as? [String: Any] else {
            throw Malformed()
        }
        let plain = try unwrap(fields: document["fields"] as? [String: Any] ?? [:])
        return try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: plain))
    }

    private static func unwrap(fields: [String: Any]) throws -> [String: Any] {
        try fields.mapValues(unwrap(value:))
    }

    private static func unwrap(value: Any) throws -> Any {
        guard let typed = value as? [String: Any], typed.count == 1, let entry = typed.first else {
            throw Malformed()
        }
        let inner = entry.value
        switch entry.key {
        case "stringValue", "timestampValue", "referenceValue", "bytesValue":
            guard let string = inner as? String else { throw Malformed() }
            return string
        case "integerValue":
            // Sent as a string, since a JSON number cannot hold every 64-bit integer.
            if let string = inner as? String, let integer = Int64(string) { return integer }
            if let number = inner as? NSNumber { return number }
            throw Malformed()
        case "doubleValue":
            if let number = inner as? NSNumber { return number }
            if let string = inner as? String, let double = Double(string) { return double }
            throw Malformed()
        case "booleanValue":
            guard let bool = inner as? Bool else { throw Malformed() }
            return bool
        case "nullValue":
            return NSNull()
        case "mapValue":
            guard let map = inner as? [String: Any] else { throw Malformed() }
            return try unwrap(fields: map["fields"] as? [String: Any] ?? [:])
        case "arrayValue":
            guard let array = inner as? [String: Any] else { throw Malformed() }
            return try (array["values"] as? [Any] ?? []).map(unwrap(value:))
        case "geoPointValue":
            guard let point = inner as? [String: Any] else { throw Malformed() }
            return point
        default:
            throw Malformed()
        }
    }
}
