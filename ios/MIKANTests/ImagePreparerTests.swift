import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MIKAN

final class ImagePreparerTests: XCTestCase {
    private func pngData(width: Int, height: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(srgbRed: 1, green: 0.48, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output as CFMutableData, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func pixelSize(of data: Data) throws -> (width: Int, height: Int, type: String) {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let width = try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int)
        let height = try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int)
        let type = try XCTUnwrap(CGImageSourceGetType(source) as String?)
        return (width, height, type)
    }

    func testLargeImageIsDownscaledToJPEGWithin1600Pixels() throws {
        let jpeg = try ImagePreparer.jpeg(from: pngData(width: 3200, height: 2000))
        let size = try pixelSize(of: jpeg)
        XCTAssertEqual(size.type, UTType.jpeg.identifier)
        XCTAssertEqual(max(size.width, size.height), 1600)
        XCTAssertEqual(size.height, 1000)
    }

    func testSmallImageIsNotUpscaled() throws {
        let jpeg = try ImagePreparer.jpeg(from: pngData(width: 800, height: 600))
        let size = try pixelSize(of: jpeg)
        XCTAssertEqual(size.width, 800)
        XCTAssertEqual(size.height, 600)
    }

    func testGarbageDataThrows() {
        XCTAssertThrowsError(try ImagePreparer.jpeg(from: Data("not an image".utf8)))
    }
}
