// Minimum iOS 17.
//  A photo ready to send: the JPEG to upload and the very pixels it holds, to show first.

import CoreGraphics
import Foundation

/// `CGImage` is `Sendable` in the SDK, so this crosses from the detached task that prepares it
/// to the main actor that shows it without any `@unchecked`.
struct PreparedPhoto: Identifiable, Sendable {
    let id: UUID
    /// Upright, at most `PhotoPreparation.maxPixelSize` on the long side and `PhotoPreparation.maxBytes` big,
    /// and carrying no location, camera or date.
    let jpeg: Data
    /// The pixels `jpeg` was encoded from.
    let image: CGImage
}
