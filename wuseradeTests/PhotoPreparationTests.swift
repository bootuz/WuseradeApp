import ImageIO
import UniformTypeIdentifiers
import Foundation
import Testing
@testable import Wuserade

struct PhotoPreparationTests {
    // MARK: Fixtures

    private static let colorSpace = CGColorSpaceCreateDeviceRGB()

    /// A flat, opaque image. The content does not matter for the checks; only the size does.
    private func makeImage(width: Int, height: Int) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: Self.colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.7, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    /// The same numbers on every run.
    private struct SplitMix64: RandomNumberGenerator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// An opaque image whose every colour channel is 0 or 255 at random. It is not the same as uniform
    /// random bytes: the hard edges everywhere make the JPEG bigger (5.54 MB against 4.56 MB at
    /// 2000 x 2000 and quality 0.85 on the iOS 27.2 simulator), and no photo comes close to either.
    private func makeBinaryNoiseImage(width: Int, height: Int) throws -> CGImage {
        var generator = SplitMix64(state: 20_261_028)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for start in stride(from: 0, to: bytes.count, by: 64) {
            let bits = generator.next()
            for offset in 0..<min(64, bytes.count - start) where (bits >> UInt64(offset)) & 1 == 1 {
                bytes[start + offset] = 255
            }
        }
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        return try #require(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: Self.colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
    }

    private func encode(_ image: CGImage, as type: UTType, properties: [CFString: Any] = [:]) throws -> Data {
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    /// A JPEG of `width` x `height` stored pixels. With metadata it carries the orientation, a GPS
    /// position (43.5 N), the Exif capture date and the TIFF camera make.
    private func makeJPEG(
        width: Int, height: Int, orientation: Int = 1, withMetadata: Bool = false
    ) throws -> Data {
        var properties: [CFString: Any] = [:]
        if withMetadata {
            properties[kCGImagePropertyOrientation] = orientation
            properties[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: 43.5,
                kCGImagePropertyGPSLatitudeRef: "N",
            ]
            properties[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifDateTimeOriginal: "2024:05:17 10:30:00"]
            properties[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFMake: "TestCam"]
        }
        return try encode(makeImage(width: width, height: height), as: .jpeg, properties: properties)
    }

    private func properties(of data: Data) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    private func size(of data: Data) throws -> (width: Int, height: Int) {
        let properties = try properties(of: data)
        return (
            try #require(properties[kCGImagePropertyPixelWidth] as? Int),
            try #require(properties[kCGImagePropertyPixelHeight] as? Int)
        )
    }

    // MARK: Size

    @Test func `Long side is at most 2000`() throws {
        let photo = try PhotoPreparation.prepare(makeJPEG(width: 4000, height: 3000))

        let size = try size(of: photo.jpeg)
        #expect(size.width == 2000)
        #expect(size.height == 1500)
        #expect(photo.image.width == 2000, "the image shown is the one uploaded")
        #expect(photo.image.height == 1500)
    }

    @Test func `Panorama keeps its shape`() throws {
        let photo = try PhotoPreparation.prepare(makeJPEG(width: 12000, height: 1000))

        let size = try size(of: photo.jpeg)
        #expect(size.width == 2000)
        #expect((166...167).contains(size.height), "got \(size.height)")
    }

    @Test func `Small photo is not enlarged`() throws {
        let photo = try PhotoPreparation.prepare(makeJPEG(width: 300, height: 200))

        let size = try size(of: photo.jpeg)
        #expect(size.width == 300)
        #expect(size.height == 200)
    }

    // MARK: Orientation

    @Test func `Orientation is applied`() throws {
        let photo = try PhotoPreparation.prepare(makeJPEG(width: 400, height: 200, orientation: 6, withMetadata: true))

        let size = try size(of: photo.jpeg)
        #expect(size.width == 200, "turned upright")
        #expect(size.height == 400)
        #expect(photo.image.width == 200)
        #expect(photo.image.height == 400)
        let orientation = try properties(of: photo.jpeg)[kCGImagePropertyOrientation] as? Int
        #expect(orientation == nil || orientation == 1, "got \(String(describing: orientation))")
    }

    // MARK: Metadata

    @Test func `No metadata survives`() throws {
        let source = try makeJPEG(width: 400, height: 300, orientation: 3, withMetadata: true)
        // The fixture really carries what must go, or the checks below prove nothing.
        let before = try properties(of: source)
        #expect(before[kCGImagePropertyGPSDictionary] != nil)
        #expect((before[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFMake] != nil)
        #expect((before[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifDateTimeOriginal] != nil)

        let after = try properties(of: PhotoPreparation.prepare(source).jpeg)

        #expect(after[kCGImagePropertyGPSDictionary] == nil, "location")
        #expect((after[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFMake] == nil, "camera")
        #expect((after[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifDateTimeOriginal] == nil, "date")
    }

    // MARK: Format

    @Test func `Output is JPEG`() throws {
        let png = try encode(makeImage(width: 100, height: 100), as: .png)

        let photo = try PhotoPreparation.prepare(png)

        let source = try #require(CGImageSourceCreateWithData(photo.jpeg as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
    }

    // MARK: Size in bytes

    @Test func `Binary noise stays under 5 MB`() throws {
        // Lossless input, so the only compression is the one under test. On the iOS 27.2 simulator it
        // comes to about 5.54 MB at 0.85, over the limit, and 4.49 MB at 0.7, which is what prepare returns.
        let noise = try encode(makeBinaryNoiseImage(width: 2000, height: 2000), as: .png)

        let photo = try PhotoPreparation.prepare(noise)

        #expect(photo.jpeg.count <= 5 * 1024 * 1024, "the Storage rules refuse more")
        let size = try size(of: photo.jpeg)
        #expect(size.width == 2000, "smaller in bytes, not in pixels")
        #expect(size.height == 2000)
    }

    /// JPEG of `image` as the quality ladder is meant to make it.
    private func reference(_ image: CGImage, quality: Double) throws -> Data {
        try encode(image, as: .jpeg, properties: [kCGImageDestinationLossyCompressionQuality: quality])
    }

    @Test func `Keeps quality 0.85 when it fits`() throws {
        let image = try makeBinaryNoiseImage(width: 400, height: 300)

        let jpeg = try PhotoPreparation.encodeJPEG(image, maxBytes: .max)

        #expect(try jpeg == reference(image, quality: 0.85))
    }

    @Test func `Steps down to 0.7 then to 0.5 until it fits`() throws {
        let image = try makeBinaryNoiseImage(width: 400, height: 300)
        let at085 = try reference(image, quality: 0.85)
        let at07 = try reference(image, quality: 0.7)
        let at05 = try reference(image, quality: 0.5)
        #expect(at085.count > at07.count, "the fixture shrinks with quality")
        #expect(at07.count > at05.count)

        #expect(try PhotoPreparation.encodeJPEG(image, maxBytes: at085.count - 1) == at07)
        #expect(try PhotoPreparation.encodeJPEG(image, maxBytes: at07.count - 1) == at05)
        #expect(try PhotoPreparation.encodeJPEG(image, maxBytes: at05.count) == at05, "the limit itself fits")
    }

    @Test func `Throws when even quality 0.5 is too big`() throws {
        let image = try makeBinaryNoiseImage(width: 400, height: 300)
        let at05 = try reference(image, quality: 0.5)

        #expect(throws: PhotoPreparation.Failure.unencodable) {
            try PhotoPreparation.encodeJPEG(image, maxBytes: at05.count - 1)
        }
    }

    // MARK: Failure

    @Test(arguments: [Data("not an image".utf8), Data()])
    func `Unreadable or empty data throws`(data: Data) {
        #expect(throws: PhotoPreparation.Failure.unreadable) {
            try PhotoPreparation.prepare(data)
        }
    }

    @Test func `JPEG header without pixels throws`() throws {
        let jpeg = try makeJPEG(width: 400, height: 300, orientation: 1, withMetadata: true)

        #expect(throws: PhotoPreparation.Failure.unreadable) {
            try PhotoPreparation.prepare(jpeg.prefix(300))
        }
    }

    /// Documents what ImageIO does, so that `prepare` has no check for it: a JPEG cut short is reported
    /// complete, and the missing part is filled in. A check on `CGImageSourceGetStatusAtIndex` would
    /// never fire. Task 10 shows the result in a circle before the reader sends it.
    @Test func `Truncated JPEG is decoded as if complete`() throws {
        let image = try makeBinaryNoiseImage(width: 400, height: 300)
        let jpeg = try encode(image, as: .jpeg)
        let truncated = jpeg.prefix(jpeg.count / 3)
        let source = try #require(CGImageSourceCreateWithData(truncated as CFData, nil))
        #expect(CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete)

        let photo = try PhotoPreparation.prepare(truncated)

        #expect(photo.image.width == 400)
        #expect(photo.image.height == 300)
    }
}
