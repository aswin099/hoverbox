import XCTest
@testable import HoverboxCore

final class WatchAndRecentTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("HoverboxWatch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: Recently closed

    func testRecentShelvesNewestFirstWithLimit() {
        var recents = RecentShelves(limit: 3)
        let shelves = (1...4).map { Shelf(name: "S\($0)", items: [.text("x\($0)")]) }
        shelves.forEach { recents.remember($0) }
        XCTAssertEqual(recents.shelves.map(\.name), ["S4", "S3", "S2"])
        XCTAssertNotNil(recents.shelves[0].closedAt)
    }

    func testRecentShelvesSkipEmptyAndDeduplicate() {
        var recents = RecentShelves()
        recents.remember(Shelf())
        XCTAssertTrue(recents.shelves.isEmpty)
        var shelf = Shelf(items: [.text("a")], isPinned: true)
        recents.remember(shelf)
        shelf.add([.text("b")])
        recents.remember(shelf)
        XCTAssertEqual(recents.shelves.count, 1)
        XCTAssertEqual(recents.shelves[0].items.count, 2)
        XCTAssertFalse(recents.shelves[0].isPinned)
    }

    func testTakeRemovesAndClearsClosedDate() {
        var recents = RecentShelves()
        let shelf = Shelf(items: [.text("a")])
        recents.remember(shelf)
        let reopened = recents.take(shelf.id)
        XCTAssertEqual(reopened?.id, shelf.id)
        XCTAssertNil(reopened?.closedAt)
        XCTAssertTrue(recents.shelves.isEmpty)
        XCTAssertNil(recents.take(shelf.id))
    }

    func testOlderArchivesWithoutNewFieldsStillLoad() throws {
        let json = #"[{"id":"7D1E2C55-6B8A-4C3F-9E2A-1F0B9C8D7E6A","items":[],"isPinned":true,"createdAt":0}]"#
        let url = tempDir.appendingPathComponent("old.json")
        try Data(json.utf8).write(to: url)
        let loaded = ShelfArchive(fileURL: url).load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertNil(loaded[0].color)
    }

    func testArchiveCanSaveUnpinnedShelves() throws {
        let archive = ShelfArchive(fileURL: tempDir.appendingPathComponent("recent.json"), pinnedOnly: false)
        let shelf = Shelf(items: [.text("a")], color: .mint)
        try archive.save([shelf])
        XCTAssertEqual(archive.load(), [shelf])
    }

    // MARK: Folder watching

    func testWatcherReportsOnlyNewFinishedVisibleItems() throws {
        try Data("old".utf8).write(to: tempDir.appendingPathComponent("existing.txt"))
        let reported = expectation(description: "new items reported")
        var received: [String] = []
        let watcher = FolderWatcher(folder: tempDir, debounce: 0.2) { urls in
            received += urls.map(\.lastPathComponent)
            reported.fulfill()
        }
        XCTAssertNotNil(watcher)
        try Data("new".utf8).write(to: tempDir.appendingPathComponent("new.pdf"))
        try Data("hidden".utf8).write(to: tempDir.appendingPathComponent(".hidden"))
        try Data("partial".utf8).write(to: tempDir.appendingPathComponent("movie.mp4.crdownload"))
        wait(for: [reported], timeout: 5)
        XCTAssertEqual(received, ["new.pdf"])
        watcher?.stop()
    }

    func testWatcherFilter() throws {
        let reported = expectation(description: "filtered items reported")
        var received: [String] = []
        let watcher = FolderWatcher(folder: tempDir, debounce: 0.2, filter: { $0.pathExtension == "png" }) { urls in
            received += urls.map(\.lastPathComponent)
            reported.fulfill()
        }
        try Data().write(to: tempDir.appendingPathComponent("a.txt"))
        try Data().write(to: tempDir.appendingPathComponent("b.png"))
        wait(for: [reported], timeout: 5)
        XCTAssertEqual(received, ["b.png"])
        watcher?.stop()
    }

    // MARK: Screenshots

    func testScreenshotMarker() throws {
        let shot = tempDir.appendingPathComponent("shot.png"), plain = tempDir.appendingPathComponent("plain.png")
        try Data().write(to: shot)
        try Data().write(to: plain)
        let value = try PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
        let result = value.withUnsafeBytes {
            setxattr(shot.path, "com.apple.metadata:kMDItemIsScreenCapture", $0.baseAddress, value.count, 0, 0)
        }
        XCTAssertEqual(result, 0)
        XCTAssertTrue(ScreenshotDetector.isScreenshot(shot))
        XCTAssertFalse(ScreenshotDetector.isScreenshot(plain))
    }
}
