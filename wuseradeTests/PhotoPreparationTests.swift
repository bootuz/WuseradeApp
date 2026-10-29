import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Wuserade

final class PhotoPreparationTests: XCTestCase {
    // MARK: Fixtures

    private static let colorSpace = CGColorSpaceCreateDeviceRGB()

    /// A flat, opaque image. The content does not matter for the checks; only the size does.
    private func makeImage(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: Self.colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.7, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
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
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        return try XCTUnwrap(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: Self.colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
    }

    private func encode(_ image: CGImage, as type: UTType, properties: [CFString: Any] = [:]) throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
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
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        return try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    private func size(of data: Data) throws -> (width: Int, height: Int) {
        let properties = try properties(of: data)
        return (
            try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int),
            try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int)
        )
    }

    // MARK: Size

    func testLongSideIsAtMost2000() throws {
        let photo = try PhotoPreparation.prepare(makeJPEG(width: 4000, height: 3000))

        let size = try size(of: photo.jpeg)
        XCTAssertEqual(size.width, 2000)
        XCTAssertEqual(size.height, 1500)
        XCTAssertEqual(photo.image.width, 2000, "the image shown is the one uploaded")
        XCTAssertEqual(photo.image.height, 1500)
    }

    func testPanoramaKeepsItsShape() throws {
        let photo = try PhotoPreparation.prepare(makeJPEG(width: 12000, height: 1000))

        let size = try size(of: photo.jpeg)
        XCTAssertEqual(size.width, 2000)
        XCTAssertTrue((166...167).contains(size.height), "got \(size.height)")
    }

    func testSmallPhotoIsNotEnlarged() throws {
        let photo = try PhotoPreparation.prepare(makeJPEG(width: 300, height: 200))

        let size = try size(of: photo.jpeg)
        XCTAssertEqual(size.width, 300)
        XCTAssertEqual(size.height, 200)
    }

    // MARK: Orientation

    func testOrientationIsApplied() throws {
        let photo = try PhotoPreparation.prepare(makeJPEG(width: 400, height: 200, orientation: 6, withMetadata: true))

        let size = try size(of: photo.jpeg)
        XCTAssertEqual(size.width, 200, "turned upright")
        XCTAssertEqual(size.height, 400)
        XCTAssertEqual(photo.image.width, 200)
        XCTAssertEqual(photo.image.height, 400)
        let orientation = try properties(of: photo.jpeg)[kCGImagePropertyOrientation] as? Int
        XCTAssertTrue(orientation == nil || orientation == 1, "got \(String(describing: orientation))")
    }

    // MARK: Metadata

    func testNoMetadataSurvives() throws {
        let source = try makeJPEG(width: 400, height: 300, orientation: 3, withMetadata: true)
        // The fixture really carries what must go, or the checks below prove nothing.
        let before = try properties(of: source)
        XCTAssertNotNil(before[kCGImagePropertyGPSDictionary])
        XCTAssertNotNil((before[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFMake])
        XCTAssertNotNil((before[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifDateTimeOriginal])

        let after = try properties(of: PhotoPreparation.prepare(source).jpeg)

        XCTAssertNil(after[kCGImagePropertyGPSDictionary], "location")
        XCTAssertNil((after[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFMake], "camera")
        XCTAssertNil((after[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifDateTimeOriginal], "date")
    }

    // MARK: Format

    func testOutputIsJPEG() throws {
        let png = try encode(makeImage(width: 100, height: 100), as: .png)

        let photo = try PhotoPreparation.prepare(png)

        let source = try XCTUnwrap(CGImageSourceCreateWithData(photo.jpeg as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.jpeg.identifier)
    }

    // MARK: Size in bytes

    func testBinaryNoiseStaysUnder5MB() throws {
        // Lossless input, so the only compression is the one under test. On the iOS 27.2 simulator it
        // comes to about 5.54 MB at 0.85, over the limit, and 4.49 MB at 0.7, which is what prepare returns.
        let noise = try encode(makeBinaryNoiseImage(width: 2000, height: 2000), as: .png)

        let photo = try PhotoPreparation.prepare(noise)

        XCTAssertLessThanOrEqual(photo.jpeg.count, 5 * 1024 * 1024, "the Storage rules refuse more")
        let size = try size(of: photo.jpeg)
        XCTAssertEqual(size.width, 2000, "smaller in bytes, not in pixels")
        XCTAssertEqual(size.height, 2000)
    }

    /// JPEG of `image` as the quality ladder is meant to make it.
    private func reference(_ image: CGImage, quality: Double) throws -> Data {
        try encode(image, as: .jpeg, properties: [kCGImageDestinationLossyCompressionQuality: quality])
    }

    func testKeepsQuality085WhenItFits() throws {
        let image = try makeBinaryNoiseImage(width: 400, height: 300)

        let jpeg = try PhotoPreparation.encodeJPEG(image, maxBytes: .max)

        XCTAssertEqual(jpeg, try reference(image, quality: 0.85))
    }

    func testStepsDownTo07ThenTo05UntilItFits() throws {
        let image = try makeBinaryNoiseImage(width: 400, height: 300)
        let at085 = try reference(image, quality: 0.85)
        let at07 = try reference(image, quality: 0.7)
        let at05 = try reference(image, quality: 0.5)
        XCTAssertGreaterThan(at085.count, at07.count, "the fixture shrinks with quality")
        XCTAssertGreaterThan(at07.count, at05.count)

        XCTAssertEqual(try PhotoPreparation.encodeJPEG(image, maxBytes: at085.count - 1), at07)
        XCTAssertEqual(try PhotoPreparation.encodeJPEG(image, maxBytes: at07.count - 1), at05)
        XCTAssertEqual(try PhotoPreparation.encodeJPEG(image, maxBytes: at05.count), at05, "the limit itself fits")
    }

    func testThrowsWhenEvenQuality05IsTooBig() throws {
        let image = try makeBinaryNoiseImage(width: 400, height: 300)
        let at05 = try reference(image, quality: 0.5)

        XCTAssertThrowsError(try PhotoPreparation.encodeJPEG(image, maxBytes: at05.count - 1)) {
            XCTAssertEqual($0 as? PhotoPreparation.Failure, .unencodable)
        }
    }

    // MARK: Failure

    func testUnreadableDataThrows() {
        XCTAssertThrowsError(try PhotoPreparation.prepare(Data("not an image".utf8))) {
            XCTAssertEqual($0 as? PhotoPreparation.Failure, .unreadable)
        }
    }

    func testEmptyDataThrows() {
        XCTAssertThrowsError(try PhotoPreparation.prepare(Data())) {
            XCTAssertEqual($0 as? PhotoPreparation.Failure, .unreadable)
        }
    }

    func testJPEGHeaderWithoutPixelsThrows() throws {
        let jpeg = try makeJPEG(width: 400, height: 300, orientation: 1, withMetadata: true)

        XCTAssertThrowsError(try PhotoPreparation.prepare(jpeg.prefix(300))) {
            XCTAssertEqual($0 as? PhotoPreparation.Failure, .unreadable)
        }
    }

    /// Documents what ImageIO does, so that `prepare` has no check for it: a JPEG cut short is reported
    /// complete, and the missing part is filled in. A check on `CGImageSourceGetStatusAtIndex` would
    /// never fire. Task 10 shows the result in a circle before the reader sends it.
    func testTruncatedJPEGIsDecodedAsIfComplete() throws {
        let image = try makeBinaryNoiseImage(width: 400, height: 300)
        let jpeg = try encode(image, as: .jpeg)
        let truncated = jpeg.prefix(jpeg.count / 3)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(truncated as CFData, nil))
        XCTAssertEqual(CGImageSourceGetStatusAtIndex(source, 0), .statusComplete)

        let photo = try PhotoPreparation.prepare(truncated)

        XCTAssertEqual(photo.image.width, 400)
        XCTAssertEqual(photo.image.height, 300)
    }
}
