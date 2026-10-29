import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Image formats Hoverbox can write. Which ones work depends on the OS's ImageIO
/// encoders, so menus should offer `ImageFormat.writable`.
public enum ImageFormat: String, CaseIterable, Sendable {
    case png, jpeg, heic, webp, tiff

    public var type: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .heic: return .heic
        case .webp: return .webP
        case .tiff: return .tiff
        }
    }

    public var fileExtension: String { type.preferredFilenameExtension ?? rawValue }

    public var displayName: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        case .heic: return "HEIC"
        case .webp: return "WebP"
        case .tiff: return "TIFF"
        }
    }

    public var isLossy: Bool { self == .jpeg || self == .heic || self == .webp }
    public var supportsAlpha: Bool { self != .jpeg }

    public static var writable: [ImageFormat] {
        let identifiers = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
        return allCases.filter { identifiers.contains($0.type.identifier) }
    }

    public init?(url: URL) {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return nil }
        guard let match = Self.allCases.first(where: { type.conforms(to: $0.type) }) else { return nil }
        self = match
    }
}

/// How big a resized image should be. Resizing never makes an image larger.
public enum ResizeTarget: Equatable, Sendable {
    case percent(Int)
    case longestSide(Int)

    /// The longest side, in pixels, for an image whose longest side is `original`.
    public func longestSide(forOriginal original: Int) -> Int {
        switch self {
        case .percent(let percent):
            return max(1, min(original, Int((Double(original) * Double(percent) / 100).rounded())))
        case .longestSide(let side):
            return max(1, min(original, side))
        }
    }

    public var label: String {
        switch self {
        case .percent(let percent): return "\(percent)%"
        case .longestSide(let side): return "\(side) px"
        }
    }
}

public enum ImageToolError: LocalizedError, Equatable {
    case unreadable(String)
    case unsupported(String)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let name): return "“\(name)” isn't an image Hoverbox can read."
        case .unsupported(let format): return "This Mac can't write \(format) images."
        case .writeFailed(let name): return "Couldn't save “\(name)”."
        }
    }
}

/// Resizes, converts and recompresses images with ImageIO, entirely on this Mac.
/// The orientation is applied to the pixels; other metadata (camera, location) is not copied.
public enum ImageTool {
    public static func isImage(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
    }

    /// Pixel size with the EXIF orientation applied.
    public static func pixelSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    /// True when some pixels are actually see-through. Many opaque images (screenshots
    /// especially) carry an alpha channel they never use, so the channel alone isn't enough.
    public static func hasTransparency(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              properties[kCGImagePropertyHasAlpha] as? Bool == true else { return false }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 256]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return false }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return false }
        return stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] < 255 }
    }

    /// Reads `input` and writes it to `output` as `format`, optionally limiting the
    /// longest side and setting the quality (0...1) for lossy formats.
    public static func write(_ input: URL, to output: URL, format: ImageFormat,
                             longestSide: Int? = nil, quality: Double? = nil) throws {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              let size = pixelSize(of: input) else { throw ImageToolError.unreadable(input.lastPathComponent) }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: longestSide ?? Int(max(size.width, size.height)),
        ]
        guard var image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageToolError.unreadable(input.lastPathComponent)
        }
        if !format.supportsAlpha, let flattened = flattenOnWhite(image) { image = flattened }

        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, format.type.identifier as CFString, 1, nil) else {
            throw ImageToolError.unsupported(format.displayName)
        }
        var properties: [CFString: Any] = [:]
        if let quality, format.isLossy { properties[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageToolError.writeFailed(output.lastPathComponent) }
    }

    /// The format "Compress" writes for an image: lossy formats stay as they are; PNG, TIFF and
    /// others become JPEG, or HEIC when they have see-through pixels.
    public static func compressedFormat(for url: URL) -> ImageFormat {
        if let format = ImageFormat(url: url), format.isLossy { return format }
        return hasTransparency(url) ? .heic : .jpeg
    }

    /// JPEG has no transparency; without this, transparent areas would turn black.
    private static func flattenOnWhite(_ image: CGImage) -> CGImage? {
        guard image.alphaInfo != .none, image.alphaInfo != .noneSkipFirst, image.alphaInfo != .noneSkipLast,
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }
}

/// Names for files that actions create, so results never overwrite each other.
public enum OutputNaming {
    /// "photo.jpeg" with suffix "50%" and extension "png" becomes "photo (50%).png";
    /// " 2", " 3"… are added if that name is taken in `directory`.
    public static func url(in directory: URL, for original: String, suffix: String? = nil, fileExtension: String,
                           exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        let stem = (original as NSString).deletingPathExtension
        let base = suffix.map { "\(stem) (\($0))" } ?? stem
        let ext = fileExtension.isEmpty ? "" : "." + fileExtension
        var candidate = directory.appendingPathComponent(base + ext)
        var number = 2
        while exists(candidate) {
            candidate = directory.appendingPathComponent("\(base) \(number)\(ext)")
            number += 1
        }
        return candidate
    }
}
