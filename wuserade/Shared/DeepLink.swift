// Minimum iOS 17.
//  The link that opens one poem, `wuserade://poem/{id}?source=widget|notification`, which the widget and the
//  morning notification open. The source says where the reader came from, for `daily_open`.

import Foundation

enum DeepLink {
    static let scheme = "wuserade"
    /// The sources analytics knows. Any other source opens the poem without one.
    static let sources: Set<String> = ["widget", "notification"]

    static func poemURL(_ id: Int, source: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "poem"
        components.path = "/\(id)"
        components.queryItems = [URLQueryItem(name: "source", value: source)]
        // Built from a scheme, a fixed host, digits and a query: never nil.
        return components.url!
    }

    /// The poem a link opens, or nil when it is not a poem link (such as Google sign-in's callback).
    static func poem(from url: URL) -> (id: Int, source: String?)? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == scheme,
              components.host?.lowercased() == "poem"
        else { return nil }
        let parts = components.path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].isEmpty,
              parts[1].allSatisfy({ $0.isASCII && $0.isNumber }), let id = Int(parts[1]), id > 0
        else { return nil }
        let source = components.queryItems?.first { $0.name == "source" }?.value
        return (id, source.flatMap { sources.contains($0) ? $0 : nil })
    }

    /// The link a tapped morning notification opens. The server sends the poem's id as a string under `poemId`, as
    /// every FCM data value is; a number is accepted too.
    static func notificationURL(userInfo: [AnyHashable: Any]) -> URL? {
        let id: Int?
        switch userInfo["poemId"] {
        case let string as String: id = Int(string)
        case let number as Int: id = number
        default: id = nil
        }
        guard let id, id > 0 else { return nil }
        return poemURL(id, source: "notification")
    }
}
