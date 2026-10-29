// Minimum iOS 17.
//  Where the end-of-poem suggestions come from: the `keepReading` callable, which skips what the signed-in
//  account has read. `FirebaseKeepReadingService` calls it; tests and previews use fakes.

import FirebaseFunctions
import Foundation
import SwiftUI

protocol KeepReadingService: Sendable {
    func suggestions(for poemId: Int) async throws -> KeepReading
}

struct FirebaseKeepReadingService: KeepReadingService {
    /// Resolved on every call rather than stored, so the service can be created before `FirebaseApp.configure()`
    /// has run.
    private var functions: Functions { Functions.functions(region: "europe-west3") }

    func suggestions(for poemId: Int) async throws -> KeepReading {
        let result = try await functions.httpsCallable("keepReading").call(["poemId": poemId])
        return try Self.decode(result.data)
    }

    /// Decodes the callable's result, which the SDK hands back as Foundation objects.
    static func decode(_ data: Any) throws -> KeepReading {
        let json = try JSONSerialization.data(withJSONObject: data)
        return try JSONDecoder().decode(KeepReading.self, from: json)
    }
}

extension EnvironmentValues {
    /// The app's one service. Nil in previews, where the end of a poem keeps the next row.
    @Entry var keepReading: (any KeepReadingService)?
}
