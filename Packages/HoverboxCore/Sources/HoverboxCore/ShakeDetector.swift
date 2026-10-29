import Foundation

/// Recognises a "shake": the pointer swinging back and forth several times in
/// quick succession while something is being dragged. It only sees numbers, so
/// it runs and tests without AppKit; the app feeds it pointer samples.
public struct ShakeDetector {
    public enum Sensitivity: String, CaseIterable, Codable, Sendable {
        case low, medium, high
    }

    /// Direction changes needed inside `window` to count as a shake.
    public let reversalsNeeded: Int
    /// Travel, in points, before a swing counts.
    public let minSwing: Double
    /// Seconds within which the reversals must happen.
    public let window: TimeInterval

    private var xAxis = AxisTracker()
    private var yAxis = AxisTracker()
    public private(set) var hasFired = false

    public init(sensitivity: Sensitivity = .medium) {
        switch sensitivity {
        case .low: self.init(reversalsNeeded: 4, minSwing: 70, window: 0.8)
        case .medium: self.init(reversalsNeeded: 3, minSwing: 50, window: 0.7)
        case .high: self.init(reversalsNeeded: 3, minSwing: 30, window: 0.9)
        }
    }

    public init(reversalsNeeded: Int, minSwing: Double, window: TimeInterval) {
        self.reversalsNeeded = reversalsNeeded
        self.minSwing = minSwing
        self.window = window
    }

    public mutating func reset() {
        xAxis = AxisTracker()
        yAxis = AxisTracker()
        hasFired = false
    }

    /// Adds a pointer sample. Returns `true` exactly once per gesture, on the
    /// sample that completes the shake; call `reset()` before the next drag.
    public mutating func add(x: Double, y: Double, time: TimeInterval) -> Bool {
        guard !hasFired else { return false }
        let horizontal = xAxis.add(x, time: time, minSwing: minSwing, window: window)
        let vertical = yAxis.add(y, time: time, minSwing: minSwing, window: window)
        guard max(horizontal, vertical) >= reversalsNeeded else { return false }
        hasFired = true
        return true
    }
}

/// Follows one axis and reports how many direction changes happened within the window.
struct AxisTracker {
    private var extreme: Double?
    private var direction = 0
    private var reversals: [TimeInterval] = []

    mutating func add(_ value: Double, time: TimeInterval, minSwing: Double, window: TimeInterval) -> Int {
        guard let current = extreme else {
            extreme = value
            return 0
        }
        if direction == 0 {
            if abs(value - current) >= minSwing {
                direction = value > current ? 1 : -1
                extreme = value
            }
        } else if (value - current) * Double(direction) > 0 {
            extreme = value
        } else if (current - value) * Double(direction) >= minSwing {
            direction = -direction
            extreme = value
            reversals.append(time)
        }
        reversals.removeAll { time - $0 > window }
        return reversals.count
    }
}
