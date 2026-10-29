// Minimum iOS 17.
//  Shrinks a picked photo, turns it upright and strips its metadata before it is sent.

import Foundation
import ImageIO
import UniformTypeIdentifiers

enum PhotoPreparation {
    enum Failure: Error, Equatable {
        /// The data is not an image the system can read.
        case unreadable
        /// The image was read but could not be written back as a JPEG.
        case unencodable
    }

    /// The longest side of the result, in pixels. Smaller photos are not enlarged.
    static let maxPixelSize = 2000
    static let quality = 0.85
    /// The size of the result, in bytes. The Storage rules refuse an upload over 5 MiB, and the app shows
    /// a refused upload as "this account can't send photos".
    static let maxBytes = 5 * 1024 * 1024
    /// Tried in this order when the encode at `quality` is over `maxBytes`. Only noise-like pictures need them.
    private static let fallbackQualities = [0.7, 0.5]

    /// Decodes, shrinks and re-encodes `data`, which takes a moment: call it off the main actor.
    ///
    /// The result is rebuilt from the pixels alone. The encoder is given only the quality, never the
    /// source's properties, so no location, camera or date is written. It fits in `maxBytes` or this throws.
    nonisolated static func prepare(_ data: Data) throws -> PreparedPhoto {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw Failure.unreadable }

        // `FromImageAlways` renders from the full image, never from a small preview embedded in the file.
        // `WithTransform` turns the pixels upright, so the orientation tag is not needed again.
        // `ShouldCacheImmediately` decodes here, off the main actor, and not when the image is first drawn.
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            throw Failure.unreadable
        }

        return PreparedPhoto(id: UUID(), jpeg: try encodeJPEG(image, maxBytes: maxBytes), image: image)
    }

    /// The JPEG of `image` at `quality`, or at the first lower quality in `fallbackQualities` that fits
    /// in `maxBytes`. Throws `.unencodable` when none does.
    nonisolated static func encodeJPEG(_ image: CGImage, maxBytes: Int) throws -> Data {
        for quality in [Self.quality] + fallbackQualities {
            let jpeg = try encodeJPEG(image, quality: quality)
            if jpeg.count <= maxBytes { return jpeg }
        }
        throw Failure.unencodable
    }

    private nonisolated static func encodeJPEG(_ image: CGImage, quality: Double) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw Failure.unencodable
        }
        CGImageDestinationAddImage(
            destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { throw Failure.unencodable }
        return output as Data
    }
}
