import Foundation
import Observation
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
import ImageIO
#endif

enum ArtworkOutputFormat: String, CaseIterable, Identifiable {
    case jpeg
    case png

    var id: String { rawValue }

    var title: String {
        switch self {
        case .jpeg: "JPEG"
        case .png: "PNG"
        }
    }

    var mimeType: String {
        switch self {
        case .jpeg: "image/jpeg"
        case .png: "image/png"
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        }
    }
}

struct ArtworkAdjustmentSnapshot {
    var cropToSquare: Bool
    var maxPixelSize: Double
    var outputFormat: ArtworkOutputFormat
    var jpegQuality: Double
}

@Observable
@MainActor
final class ArtworkAdjustmentOptions {
    var cropToSquare = true
    var maxPixelSize = 1200.0
    var outputFormat = ArtworkOutputFormat.jpeg
    var jpegQuality = 0.86

    func snapshot() -> ArtworkAdjustmentSnapshot {
        ArtworkAdjustmentSnapshot(
            cropToSquare: cropToSquare,
            maxPixelSize: maxPixelSize,
            outputFormat: outputFormat,
            jpegQuality: jpegQuality
        )
    }

    func restore(_ snapshot: ArtworkAdjustmentSnapshot) {
        cropToSquare = snapshot.cropToSquare
        maxPixelSize = snapshot.maxPixelSize
        outputFormat = snapshot.outputFormat
        jpegQuality = snapshot.jpegQuality
    }
}

enum ArtworkProcessingError: LocalizedError {
    case invalidImage
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            "The selected artwork could not be read as an image."
        case .encodingFailed:
            "The adjusted artwork could not be encoded."
        }
    }
}

enum ArtworkProcessor {
    static func loadAdjustedArtwork(from url: URL, options: ArtworkAdjustmentOptions) throws -> ShazamID3Identifier.Artwork {
        let data = try Data(contentsOf: url)
        return try adjustedArtwork(from: data, options: options)
    }

    static func adjustedArtwork(from data: Data, options: ArtworkAdjustmentOptions) throws -> ShazamID3Identifier.Artwork {
        #if os(macOS)
        guard let image = NSImage(data: data),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ArtworkProcessingError.invalidImage
        }

        let options = options.snapshot()
        let cropped = options.cropToSquare ? squareCropped(cgImage) : cgImage
        let resized = resizedImage(cropped, maxPixelSize: max(64, Int(options.maxPixelSize.rounded()))) ?? cropped
        let encoded = try encode(resized, format: options.outputFormat, jpegQuality: options.jpegQuality)
        return ShazamID3Identifier.Artwork(data: encoded, mimeType: options.outputFormat.mimeType)
        #else
        throw ArtworkProcessingError.invalidImage
        #endif
    }

    static func fileExtension(for mimeType: String) -> String {
        switch mimeType.lowercased() {
        case "image/png": "png"
        case "image/webp": "webp"
        default: "jpg"
        }
    }

    #if os(macOS)
    private static func squareCropped(_ image: CGImage) -> CGImage {
        let side = min(image.width, image.height)
        let rect = CGRect(
            x: (image.width - side) / 2,
            y: (image.height - side) / 2,
            width: side,
            height: side
        )
        return image.cropping(to: rect) ?? image
    }

    private static func resizedImage(_ image: CGImage, maxPixelSize: Int) -> CGImage? {
        let longestEdge = max(image.width, image.height)
        guard longestEdge > maxPixelSize else {
            return image
        }

        let scale = CGFloat(maxPixelSize) / CGFloat(longestEdge)
        let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func encode(_ image: CGImage, format: ArtworkOutputFormat, jpegQuality: Double) throws -> Data {
        let data = NSMutableData()
        let type: CFString = format == .png ? UTType.png.identifier as CFString : UTType.jpeg.identifier as CFString
        guard let destination = CGImageDestinationCreateWithData(data, type, 1, nil) else {
            throw ArtworkProcessingError.encodingFailed
        }

        var properties: [CFString: Any] = [:]
        if format == .jpeg {
            properties[kCGImageDestinationLossyCompressionQuality] = min(max(jpegQuality, 0.35), 1.0)
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ArtworkProcessingError.encodingFailed
        }
        return data as Data
    }
    #endif
}
