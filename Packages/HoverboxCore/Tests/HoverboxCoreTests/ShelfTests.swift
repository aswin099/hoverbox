import XCTest
@testable import HoverboxCore

final class ShelfTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("HoverboxTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeFile(_ name: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try Data("hello".utf8).write(to: url)
        return url
    }

    func testAddSkipsDuplicates() throws {
        let file = try makeFile("a.txt")
        var shelf = Shelf()
        XCTAssertEqual(shelf.add([.file(file), .text("hi"), .link(URL(string: "https://example.com")!)]).count, 3)
        XCTAssertEqual(shelf.add([.file(file), .text("hi"), .text("new")]).count, 1)
        XCTAssertEqual(shelf.items.count, 4)
    }

    func testRemoveAndMove() {
        var shelf = Shelf(items: [.text("a"), .text("b"), .text("c")])
        let ids = shelf.items.map(\.id)
        shelf.move(ids[0], to: 3)
        XCTAssertEqual(shelf.items.map(\.displayName), ["b", "c", "a"])
        shelf.move(ids[2], to: 0)
        XCTAssertEqual(shelf.items.map(\.displayName), ["c", "b", "a"])
        shelf.remove(ids: [ids[1]])
        XCTAssertEqual(shelf.items.map(\.displayName), ["c", "a"])
    }

    func testMoveBlockKeepsOrder() {
        var shelf = Shelf(items: ["a", "b", "c", "d", "e"].map { ShelfItem.text($0) })
        let ids = shelf.items.map(\.id)
        shelf.move([ids[3], ids[1]], to: 0)
        XCTAssertEqual(shelf.items.map(\.displayName), ["b", "d", "a", "c", "e"])
        shelf.move([ids[0], ids[2]], to: 5)
        XCTAssertEqual(shelf.items.map(\.displayName), ["b", "d", "e", "a", "c"])
        // Dropping a block onto one of its own members leaves it in place.
        shelf.move([ids[1], ids[3]], to: 1)
        XCTAssertEqual(shelf.items.map(\.displayName), ["b", "d", "e", "a", "c"])
        shelf.move([ids[2]], to: 0)
        XCTAssertEqual(shelf.items.map(\.displayName), ["c", "b", "d", "e", "a"])
    }

    func testUpdateFileFollowsRename() throws {
        let original = try makeFile("draft.txt")
        var shelf = Shelf(items: [.file(original), .text("t")])
        let renamed = tempDir.appendingPathComponent("final.txt")
        try FileManager.default.moveItem(at: original, to: renamed)
        shelf.updateFile(shelf.items[0].id, to: renamed)
        shelf.updateFile(shelf.items[1].id, to: renamed)
        XCTAssertEqual(shelf.items[0].fileURL, renamed)
        XCTAssertEqual(shelf.items[1].content, .text("t"))
        XCTAssertFalse(shelf.items[0].refreshed().isMissing)
    }

    func testItemsInSelectionKeepShelfOrder() {
        let shelf = Shelf(items: [.text("a"), .text("b"), .text("c")])
        let picked: Set = [shelf.items[2].id, shelf.items[0].id]
        XCTAssertEqual(shelf.items(in: picked).map(\.displayName), ["a", "c"])
        XCTAssertEqual(shelf.items(in: []).count, 3)
    }

    func testTitles() throws {
        XCTAssertEqual(Shelf().title, "Empty shelf")
        let file = try makeFile("b.txt")
        XCTAssertEqual(Shelf(items: [.file(file)]).title, "1 file")
        XCTAssertEqual(Shelf(items: [.link(URL(string: "https://a.com")!), .link(URL(string: "https://b.com")!)]).title, "2 links")
        XCTAssertEqual(Shelf(items: [.file(file), .text("x")]).title, "2 items")
        XCTAssertEqual(Shelf(name: "Invoices", items: [.file(file)]).title, "Invoices")
    }

    func testDisplayNames() {
        XCTAssertEqual(ShelfItem.text("\n  first line \nsecond").displayName, "first line")
        XCTAssertEqual(ShelfItem.link(URL(string: "https://example.com/docs/page")!).displayName, "example.com/docs/page")
        XCTAssertEqual(ShelfItem.link(URL(string: "https://example.com/")!).displayName, "example.com")
    }

    func testBookmarkFollowsRenamedFile() throws {
        let original = try makeFile("report.pdf")
        let item = ShelfItem.file(original)
        let renamed = tempDir.appendingPathComponent("report-final.pdf")
        try FileManager.default.moveItem(at: original, to: renamed)

        let (refreshed, isMissing) = item.refreshed()
        XCTAssertFalse(isMissing)
        XCTAssertEqual(refreshed.fileURL?.lastPathComponent, "report-final.pdf")
        XCTAssertEqual(refreshed.id, item.id)
    }

    func testDeletedFileIsMissing() throws {
        let url = try makeFile("gone.txt")
        let item = ShelfItem.file(url)
        try FileManager.default.removeItem(at: url)
        XCTAssertTrue(item.refreshed().isMissing)
    }

    func testArchiveSavesOnlyPinnedShelves() throws {
        let archive = ShelfArchive(fileURL: tempDir.appendingPathComponent("sub/shelves.json"))
        let file = try makeFile("c.txt")
        let pinned = Shelf(name: "Keep", items: [.file(file), .text("note")], isPinned: true, origin: .init(x: 10, y: 20))
        let temporary = Shelf(items: [.text("temp")])
        try archive.save([pinned, temporary])

        let loaded = archive.load()
        XCTAssertEqual(loaded, [pinned])
        let attributes = try FileManager.default.attributesOfItem(atPath: archive.fileURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testArchiveLoadIsEmptyWhenMissingOrCorrupt() throws {
        let archive = ShelfArchive(fileURL: tempDir.appendingPathComponent("shelves.json"))
        XCTAssertEqual(archive.load(), [])
        try Data("not json".utf8).write(to: archive.fileURL)
        XCTAssertEqual(archive.load(), [])
    }

    func testShakeRules() {
        let rules = ShakeRules(isEnabled: true, excludedBundleIDs: ["com.adobe.Photoshop"])
        XCTAssertTrue(rules.shouldWatch(frontmostBundleID: "com.apple.finder"))
        XCTAssertTrue(rules.shouldWatch(frontmostBundleID: nil))
        XCTAssertFalse(rules.shouldWatch(frontmostBundleID: "com.adobe.Photoshop"))
        XCTAssertFalse(ShakeRules(isEnabled: false, excludedBundleIDs: []).shouldWatch(frontmostBundleID: "com.apple.finder"))
    }
}
