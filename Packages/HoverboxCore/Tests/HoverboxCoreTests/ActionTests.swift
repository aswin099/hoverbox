import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import HoverboxCore

final class ActionTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("HoverboxActions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Writes a test image: a half-transparent PNG or an opaque JPEG with noise (so it compresses realistically).
    private func makeImage(_ name: String, width: Int, height: Int, type: UTType, transparent: Bool = false) throws -> URL {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        var generator = SystemRandomNumberGenerator()
        for x in stride(from: 0, to: width, by: 4) {
            for y in stride(from: 0, to: height, by: 4) {
                let alpha: CGFloat = transparent && x < width / 2 ? 0 : 1
                context.setFillColor(CGColor(red: .random(in: 0...1, using: &generator), green: CGFloat(x) / CGFloat(width),
                                             blue: CGFloat(y) / CGFloat(height), alpha: alpha))
                context.fill(CGRect(x: x, y: y, width: 4, height: 4))
            }
        }
        let url = tempDir.appendingPathComponent(name)
        let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    private func typeOf(_ url: URL) -> String? {
        CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceGetType($0) as String? }
    }

    private func fileSize(_ url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }

    // MARK: Naming and sizes

    func testOutputNamingAddsSuffixAndAvoidsCollisions() throws {
        let first = OutputNaming.url(in: tempDir, for: "photo.jpeg", suffix: "50%", fileExtension: "png")
        XCTAssertEqual(first.lastPathComponent, "photo (50%).png")
        try Data().write(to: first)
        XCTAssertEqual(OutputNaming.url(in: tempDir, for: "photo.jpeg", suffix: "50%", fileExtension: "png").lastPathComponent,
                       "photo (50%) 2.png")
        XCTAssertEqual(OutputNaming.url(in: tempDir, for: "notes.txt", fileExtension: "zip").lastPathComponent, "notes.zip")
    }

    func testResizeTargetsNeverUpscale() {
        XCTAssertEqual(ResizeTarget.percent(50).longestSide(forOriginal: 4000), 2000)
        XCTAssertEqual(ResizeTarget.percent(25).longestSide(forOriginal: 3), 1)
        XCTAssertEqual(ResizeTarget.longestSide(1280).longestSide(forOriginal: 4000), 1280)
        XCTAssertEqual(ResizeTarget.longestSide(1280).longestSide(forOriginal: 800), 800)
    }

    func testFormatsFromFileNames() {
        XCTAssertEqual(ImageFormat(url: URL(fileURLWithPath: "/a/b.JPG")), .jpeg)
        XCTAssertEqual(ImageFormat(url: URL(fileURLWithPath: "/a/b.png")), .png)
        XCTAssertNil(ImageFormat(url: URL(fileURLWithPath: "/a/b.txt")))
        XCTAssertTrue(ImageFormat.writable.contains(.png))
        XCTAssertTrue(ImageFormat.writable.contains(.jpeg))
    }

    // MARK: Images

    func testConvertTransparentPNGToJPEG() throws {
        let png = try makeImage("logo.png", width: 400, height: 200, type: .png, transparent: true)
        XCTAssertTrue(ImageTool.hasTransparency(png))
        let output = tempDir.appendingPathComponent("logo.jpg")
        try ImageTool.write(png, to: output, format: .jpeg, quality: 0.9)
        XCTAssertEqual(typeOf(output), UTType.jpeg.identifier)
        XCTAssertEqual(ImageTool.pixelSize(of: output), CGSize(width: 400, height: 200))
    }

    func testResizeKeepsAspectRatio() throws {
        let jpeg = try makeImage("wide.jpg", width: 1000, height: 600, type: .jpeg)
        let output = tempDir.appendingPathComponent("wide-small.jpg")
        let side = ResizeTarget.percent(50).longestSide(forOriginal: 1000)
        try ImageTool.write(jpeg, to: output, format: .jpeg, longestSide: side, quality: 0.85)
        XCTAssertEqual(ImageTool.pixelSize(of: output), CGSize(width: 500, height: 300))
    }

    func testCompressMakesJPEGSmaller() throws {
        let jpeg = try makeImage("big.jpg", width: 800, height: 800, type: .jpeg)
        XCTAssertEqual(ImageTool.compressedFormat(for: jpeg), .jpeg)
        let output = tempDir.appendingPathComponent("big-compressed.jpg")
        try ImageTool.write(jpeg, to: output, format: .jpeg, quality: 0.5)
        XCTAssertLessThan(fileSize(output), fileSize(jpeg))
    }

    func testCompressedFormatForPNG() throws {
        let opaque = try makeImage("opaque.png", width: 50, height: 50, type: .png)
        XCTAssertEqual(ImageTool.compressedFormat(for: opaque), .jpeg)
        let clear = try makeImage("clear.png", width: 50, height: 50, type: .png, transparent: true)
        XCTAssertEqual(ImageTool.compressedFormat(for: clear), .heic)
    }

    func testUnreadableImageThrows() throws {
        let text = tempDir.appendingPathComponent("not-an-image.png")
        try Data("hello".utf8).write(to: text)
        XCTAssertThrowsError(try ImageTool.write(text, to: tempDir.appendingPathComponent("out.png"), format: .png))
    }

    // MARK: Archives

    func testZipAndUnzipSeveralItems() throws {
        let a = tempDir.appendingPathComponent("a.txt"), folder = tempDir.appendingPathComponent("Folder")
        try Data("first".utf8).write(to: a)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("inside".utf8).write(to: folder.appendingPathComponent("b.txt"))

        let archive = tempDir.appendingPathComponent("Archive.zip")
        try Archiver.zip([a, folder], to: archive)
        XCTAssertGreaterThan(fileSize(archive), 0)

        let extracted = try Archiver.unzip(archive, into: tempDir.appendingPathComponent("out"))
        XCTAssertEqual(extracted.map(\.lastPathComponent), ["a.txt", "Folder"])
        XCTAssertEqual(try String(contentsOf: extracted[1].appendingPathComponent("b.txt"), encoding: .utf8), "inside")
    }

    func testZipSingleFolderKeepsItsName() throws {
        let folder = tempDir.appendingPathComponent("Photos")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: folder.appendingPathComponent("1.txt"))
        let archive = tempDir.appendingPathComponent("Photos.zip")
        try Archiver.zip([folder], to: archive)
        XCTAssertEqual(try Archiver.unzip(archive, into: tempDir.appendingPathComponent("out")).map(\.lastPathComponent), ["Photos"])
    }

    func testUnzipOfNonArchiveThrows() throws {
        let fake = tempDir.appendingPathComponent("fake.zip")
        try Data("not a zip".utf8).write(to: fake)
        XCTAssertThrowsError(try Archiver.unzip(fake, into: tempDir.appendingPathComponent("out")))
    }

    // MARK: Text

    func testRecognizesTextInAnImage() throws {
        let width = 900, height = 200
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 72, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "HOVERBOX 2026",
                                                                       attributes: [.init(kCTFontAttributeName as String): font]))
        context.textPosition = CGPoint(x: 40, y: 70)
        CTLineDraw(line, context)
        let url = tempDir.appendingPathComponent("text.png")
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        XCTAssertTrue(TextRecognizer.canRead(url))
        let text = try TextRecognizer.text(in: url)
        XCTAssertTrue(text.uppercased().contains("HOVERBOX"), "Recognized: \(text)")
    }
}
