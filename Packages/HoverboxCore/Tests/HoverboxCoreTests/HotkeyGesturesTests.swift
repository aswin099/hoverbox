import XCTest
@testable import HoverboxCore

final class HotkeyGesturesTests: XCTestCase {
    private func press(_ gestures: inout HotkeyGestures, at time: TimeInterval, holding: TimeInterval = 0.08) -> HotkeyGestures.Gesture {
        gestures.keyDown(at: time)
        return gestures.keyUp(at: time + holding)
    }

    func testSinglePressOpensAShelf() {
        var gestures = HotkeyGestures()
        XCTAssertEqual(press(&gestures, at: 0), .newShelf)
        XCTAssertEqual(press(&gestures, at: 5), .newShelf)
    }

    func testDoublePressPastes() {
        var gestures = HotkeyGestures()
        XCTAssertEqual(press(&gestures, at: 0), .newShelf)
        XCTAssertEqual(press(&gestures, at: 0.25), .pasteIntoNewShelf)
        // A third quick press starts over rather than pasting again.
        XCTAssertEqual(press(&gestures, at: 0.5), .newShelf)
    }

    func testSlowSecondPressIsANewShelf() {
        var gestures = HotkeyGestures()
        XCTAssertEqual(press(&gestures, at: 0), .newShelf)
        XCTAssertEqual(press(&gestures, at: 1.0), .newShelf)
    }

    func testLongPressRecalls() {
        var gestures = HotkeyGestures()
        XCTAssertEqual(press(&gestures, at: 0, holding: 0.7), .recallDraggedOut)
        XCTAssertEqual(press(&gestures, at: 1.0), .newShelf)
    }

    func testKeyRepeatDoesNotRestartTheHold() {
        var gestures = HotkeyGestures()
        gestures.keyDown(at: 0)
        gestures.keyDown(at: 0.3)  // auto-repeat while held
        XCTAssertEqual(gestures.keyUp(at: 0.6), .recallDraggedOut)
    }
}
