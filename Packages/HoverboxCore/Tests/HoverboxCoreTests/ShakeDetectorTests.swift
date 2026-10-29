import XCTest
@testable import HoverboxCore

final class ShakeDetectorTests: XCTestCase {
    /// Feeds a zig-zag along x: `legs` swings of `amplitude` points, each taking `legDuration` seconds.
    private func zigzag(_ detector: inout ShakeDetector, amplitude: Double, legs: Int,
                        legDuration: TimeInterval, vertical: Bool = false) -> Int {
        var fired = 0
        var time: TimeInterval = 0
        var from = 0.0
        let steps = 10
        for leg in 0..<legs {
            let to = leg.isMultiple(of: 2) ? amplitude : 0
            for step in 1...steps {
                let value = from + (to - from) * Double(step) / Double(steps)
                time += legDuration / Double(steps)
                let hit = vertical
                    ? detector.add(x: 500, y: value, time: time)
                    : detector.add(x: value, y: 500, time: time)
                if hit { fired += 1 }
            }
            from = to
        }
        return fired
    }

    func testQuickHorizontalShakeFiresOnce() {
        var detector = ShakeDetector(sensitivity: .medium)
        XCTAssertEqual(zigzag(&detector, amplitude: 80, legs: 8, legDuration: 0.06), 1)
        XCTAssertTrue(detector.hasFired)
    }

    func testVerticalShakeFires() {
        var detector = ShakeDetector(sensitivity: .medium)
        XCTAssertEqual(zigzag(&detector, amplitude: 80, legs: 4, legDuration: 0.06, vertical: true), 1)
    }

    func testStraightDragNeverFires() {
        var detector = ShakeDetector(sensitivity: .high)
        for step in 0..<200 {
            XCTAssertFalse(detector.add(x: Double(step) * 5, y: Double(step) * 2, time: Double(step) * 0.016))
        }
    }

    func testSlowBackAndForthDoesNotFire() {
        var detector = ShakeDetector(sensitivity: .medium)
        XCTAssertEqual(zigzag(&detector, amplitude: 200, legs: 8, legDuration: 1.0), 0)
    }

    func testSmallJitterDoesNotFire() {
        var detector = ShakeDetector(sensitivity: .medium)
        XCTAssertEqual(zigzag(&detector, amplitude: 15, legs: 12, legDuration: 0.04), 0)
    }

    func testHighSensitivityCatchesSmallerSwings() {
        var medium = ShakeDetector(sensitivity: .medium)
        var high = ShakeDetector(sensitivity: .high)
        XCTAssertEqual(zigzag(&medium, amplitude: 40, legs: 6, legDuration: 0.06), 0)
        XCTAssertEqual(zigzag(&high, amplitude: 40, legs: 6, legDuration: 0.06), 1)
    }

    func testResetAllowsAnotherShake() {
        var detector = ShakeDetector(sensitivity: .medium)
        XCTAssertEqual(zigzag(&detector, amplitude: 80, legs: 4, legDuration: 0.06), 1)
        detector.reset()
        XCTAssertFalse(detector.hasFired)
        XCTAssertEqual(zigzag(&detector, amplitude: 80, legs: 4, legDuration: 0.06), 1)
    }
}
