import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import HoverboxCore

final class AutomationTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("HoverboxAuto-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makePNG(_ name: String, width: Int = 400, height: Int = 200) throws -> URL {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let url = tempDir.appendingPathComponent(name)
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    private func work(_ name: String = "work") -> URL { tempDir.appendingPathComponent(name) }

    // MARK: Pipeline

    func testStepsChainAndLeaveOriginalsAlone() throws {
        let png = try makePNG("photo.png")
        let before = try Data(contentsOf: png)
        let action = CustomAction(name: "Small JPEG ZIP", steps: [.resizePercent(50), .convert(.jpeg), .zip])
        let result = try ActionRunner.run(action, on: [png], in: work())

        XCTAssertEqual(result.files.count, 1)
        XCTAssertEqual(result.files[0].pathExtension, "zip")
        let extracted = try Archiver.unzip(result.files[0], into: work("out"))
        XCTAssertEqual(extracted.map(\.pathExtension), ["jpeg"])
        XCTAssertEqual(ImageTool.pixelSize(of: extracted[0]), CGSize(width: 200, height: 100))
        XCTAssertEqual(try Data(contentsOf: png), before)
    }

    func testImageStepsPassOtherFilesThrough() throws {
        let text = tempDir.appendingPathComponent("notes.txt")
        try Data("hi".utf8).write(to: text)
        let png = try makePNG("a.png")
        let result = try ActionRunner.run(CustomAction(name: "x", steps: [.resizeLongestSide(100)]), on: [text, png], in: work())
        XCTAssertEqual(result.files[0], text)
        XCTAssertEqual(ImageTool.pixelSize(of: result.files[1]), CGSize(width: 100, height: 50))
    }

    // MARK: Scripts

    func testScriptGetsFilesAndWritesOutput() throws {
        let png = try makePNG("a b.png")  // a space, to prove arguments stay whole
        let script = #"for f in "$@"; do cp "$f" "$HOVERBOX_OUTPUT/copy-$(basename "$f")"; done"#
        let result = try ActionRunner.run(CustomAction(name: "x", steps: [.script(script)]), on: [png], in: work())
        XCTAssertEqual(result.files.map(\.lastPathComponent), ["copy-a b.png"])
    }

    func testScriptWithoutOutputPassesFilesThroughAndKeepsText() throws {
        let png = try makePNG("a.png")
        let result = try ActionRunner.run(CustomAction(name: "x", steps: [.script(#"echo "got $# file""#)]), on: [png], in: work())
        XCTAssertEqual(result.files, [png])
        XCTAssertEqual(result.text, "got 1 file")
    }

    func testFailingScriptReportsItsError() throws {
        let action = CustomAction(name: "x", steps: [.script("echo nope >&2; exit 3")])
        XCTAssertThrowsError(try ActionRunner.run(action, on: [], in: work())) { error in
            XCTAssertEqual(error as? ActionError, .scriptFailed(status: 3, message: "nope"))
        }
    }

    func testSlowScriptIsStopped() throws {
        let action = CustomAction(name: "x", steps: [.script("sleep 30")])
        XCTAssertThrowsError(try ActionRunner.run(action, on: [], in: work(), scriptTimeout: 0.3)) { error in
            XCTAssertEqual(error as? ActionError, .scriptTimedOut)
        }
    }

    func testActionsSurviveEncoding() throws {
        let action = CustomAction(name: "All", steps: [.resizeLongestSide(1280), .resizePercent(50), .convert(.heic), .compress, .zip, .script("echo hi")])
        let decoded = try JSONDecoder().decode(CustomAction.self, from: JSONEncoder().encode(action))
        XCTAssertEqual(decoded, action)
    }

    // MARK: Command line

    func testParsingCommands() throws {
        XCTAssertEqual(try CLIRequest.parse([], directory: "/x"), .help)
        XCTAssertEqual(try CLIRequest.parse(["list", "--json"], directory: "/x"), .list(json: true))
        XCTAssertEqual(try CLIRequest.parse(["new"], directory: "/x"), .send(.newShelf(paths: [])))
        XCTAssertEqual(try CLIRequest.parse(["add", "a.txt", "/b/c.txt", "--shelf", "2"], directory: "/x/y"),
                       .send(.add(paths: ["/x/y/a.txt", "/b/c.txt"], shelf: 2)))
        XCTAssertEqual(try CLIRequest.parse(["add", "../a.txt"], directory: "/x/y"), .send(.add(paths: ["/x/a.txt"], shelf: nil)))
        XCTAssertEqual(try CLIRequest.parse(["run", "Web", "Images", "--shelf", "1"], directory: "/x"),
                       .send(.runAction(name: "Web Images", shelf: 1)))
        XCTAssertEqual(try CLIRequest.parse(["close", "3"], directory: "/x"), .send(.close(shelf: 3)))
        XCTAssertEqual(try CLIRequest.parse(["paths"], directory: "/x"), .paths(shelf: nil))
    }

    func testParsingErrors() {
        for bad in [["add"], ["run"], ["close"], ["close", "x"], ["add", "a", "--shelf"], ["add", "a", "--shelf", "0"],
                    ["list", "--nope"], ["frobnicate"]] {
            XCTAssertThrowsError(try CLIRequest.parse(bad, directory: "/x"), "\(bad)")
        }
    }

    func testCommandsRoundTrip() throws {
        for command in [AppCommand.newShelf(paths: ["/a b"]), .add(paths: ["/c"], shelf: 2), .runAction(name: "Zip it", shelf: nil), .close(shelf: 1)] {
            XCTAssertEqual(AppCommand(encoded: try XCTUnwrap(command.encoded)), command)
        }
        XCTAssertNil(AppCommand(encoded: "not json"))
    }

    func testStatusSavesPrivately() throws {
        let shelf = Shelf(name: "Work", items: [.text("hello"), .link(URL(string: "https://example.com")!)], isPinned: true)
        let status = AppStatus(shelves: [.init(number: 1, shelf: shelf)], actions: ["Zip it"])
        let url = tempDir.appendingPathComponent("sub/status.json")
        try status.save(to: url)
        XCTAssertEqual(AppStatus.load(from: url), status)
        XCTAssertEqual(status.shelves[0].itemCount, 2)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
}
