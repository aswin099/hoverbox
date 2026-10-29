import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Vision

/// Pulls text out of images and PDFs on this Mac. PDFs with a text layer are read
/// directly; scanned pages and images go through Vision's text recognition.
public enum TextRecognizer {
    public static func canRead(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "pdf" || ImageTool.isImage(url)
    }

    /// The text in a file, or an empty string when there is none. Blocks; call it off the main thread.
    public static func text(in url: URL) throws -> String {
        if url.pathExtension.lowercased() == "pdf" { return try pdfText(url) }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImageToolError.unreadable(url.lastPathComponent)
        }
        let orientation = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])?[kCGImagePropertyOrientation] as? UInt32
        return try recognize(image, orientation: orientation.flatMap(CGImagePropertyOrientation.init(rawValue:)) ?? .up)
    }

    public static func recognize(_ image: CGImage, orientation: CGImagePropertyOrientation = .up) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    private static func pdfText(_ url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else { throw ImageToolError.unreadable(url.lastPathComponent) }
        var pages: [String] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let layer = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !layer.isEmpty {
                pages.append(layer)
            } else if let image = render(page) {
                let recognized = try recognize(image)
                if !recognized.isEmpty { pages.append(recognized) }
            }
        }
        return pages.joined(separator: "\n\n")
    }

    /// Renders a page at twice its size on white, for recognising scanned PDFs.
    private static func render(_ page: PDFPage) -> CGImage? {
        guard let pageRef = page.pageRef else { return nil }
        let box = pageRef.getBoxRect(.mediaBox)
        let scale: CGFloat = 2
        guard let context = CGContext(data: nil, width: Int(box.width * scale), height: Int(box.height * scale),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: box.width * scale, height: box.height * scale))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -box.minX, y: -box.minY)
        context.drawPDFPage(pageRef)
        return context.makeImage()
    }
}
