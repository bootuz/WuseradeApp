// Minimum iOS 17.
//  Fetches a poet's photo. Responses are cached on disk and in memory, and every approval has a new URL,
//  so a cached photo never goes stale.

import Foundation
import ImageIO

enum PortraitLoader {
    enum LoadError: Error {
        case badResponse
        case undecodable
    }

    private static let session: URLSession = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 4_000_000,
            diskCapacity: 50_000_000,
            directory: caches.appendingPathComponent("Portraits", isDirectory: true)
        )
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: configuration)
    }()

    static func image(at url: URL) async throws -> CGImage {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LoadError.badResponse
        }
        // `ShouldCacheImmediately` decodes here, off the main actor, and not when the image is first drawn.
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, options) else {
            throw LoadError.undecodable
        }
        return image
    }
}
