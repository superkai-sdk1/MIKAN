import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum ImagePreparerError: LocalizedError, Sendable {
    case unreadable
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .unreadable: "Не удалось прочитать изображение."
        case .encodingFailed: "Не удалось подготовить изображение к загрузке."
        }
    }
}

/// Downscales any supported image (JPEG/PNG/HEIC…) to a JPEG no larger than `maxPixelSize` on the long side.
nonisolated enum ImagePreparer {
    static let defaultMaxPixelSize = 1600
    static let defaultQuality = 0.82

    /// Same as `jpeg(from:)`, but always runs off the main actor.
    @concurrent
    static func jpegInBackground(from data: Data) async throws -> Data {
        try jpeg(from: data)
    }

    static func jpeg(from data: Data, maxPixelSize: Int = defaultMaxPixelSize, quality: Double = defaultQuality) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImagePreparerError.unreadable
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImagePreparerError.unreadable
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            throw ImagePreparerError.encodingFailed
        }
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImagePreparerError.encodingFailed
        }
        return output as Data
    }
}
