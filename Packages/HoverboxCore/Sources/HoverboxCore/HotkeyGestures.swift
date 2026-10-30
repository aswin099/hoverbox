import Foundation

/// Turns presses of the New Shelf shortcut into gestures:
/// - a short press opens a shelf;
/// - pressing again quickly (a double press) also pastes the clipboard onto it;
/// - holding it down brings back what you last dragged out of a shelf.
/// The first press acts at once, so the plain shortcut never feels slower.
public struct HotkeyGestures {
    public enum Gesture: Equatable, Sendable {
        case newShelf
        case pasteIntoNewShelf
        case recallDraggedOut
    }

    public let longPress: TimeInterval
    public let doublePressWindow: TimeInterval
    private var downAt: TimeInterval?
    private var lastShortPress: TimeInterval?

    public init(longPress: TimeInterval = 0.5, doublePressWindow: TimeInterval = 0.4) {
        self.longPress = longPress
        self.doublePressWindow = doublePressWindow
    }

    public mutating func keyDown(at time: TimeInterval) {
        if downAt == nil { downAt = time }
    }

    /// The gesture a key release completes.
    public mutating func keyUp(at time: TimeInterval) -> Gesture {
        defer { downAt = nil }
        if let downAt, time - downAt >= longPress {
            lastShortPress = nil
            return .recallDraggedOut
        }
        if let last = lastShortPress, time - last <= doublePressWindow {
            lastShortPress = nil
            return .pasteIntoNewShelf
        }
        lastShortPress = time
        return .newShelf
    }
}
