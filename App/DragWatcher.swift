import AppKit
import HoverboxCore

/// Watches for a shake, or for holding still, during a drag in any app, without asking
/// for any permission. Two signals do this:
/// - a global *mouse* monitor (only key monitoring needs Accessibility), used
///   just to learn that the left button went down, then a 60 Hz poll of the
///   pointer while it stays down, so nothing runs while the mouse is idle;
/// - the drag pasteboard's change count, which moves only when a real drag
///   starts, so selecting text or moving a window never opens a shelf.
@MainActor
final class DragWatcher {
    var onShake: ((NSPoint) -> Void)?
    var rules: () -> ShakeRules = { ShakeRules(isEnabled: true, excludedBundleIDs: []) }
    var sensitivity: () -> ShakeDetector.Sensitivity = { .medium }
    var trigger: () -> OpenTrigger = { .shake }
    var dwellDelay: () -> TimeInterval = { 1.0 }

    private var monitor: Any?
    private var timer: Timer?
    private var detector = ShakeDetector()
    private var dwell = DwellDetector()
    private var currentTrigger = OpenTrigger.shake
    private var dragChangeCount = 0
    private let dragPasteboard = NSPasteboard(name: .drag)

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDown() }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        stopPolling()
    }

    private func mouseDown() {
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard rules().shouldWatch(frontmostBundleID: frontmost) else { return }
        detector = ShakeDetector(sensitivity: sensitivity())
        dwell = DwellDetector(duration: dwellDelay())
        currentTrigger = trigger()
        dragChangeCount = dragPasteboard.changeCount
        stopPolling()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            stopPolling()
            return
        }
        guard dragPasteboard.changeCount != dragChangeCount else { return }
        let point = NSEvent.mouseLocation
        // Over a shelf (or the menu bar icon) you're about to drop, not asking for a new shelf.
        if isOverOwnWindow(point) {
            dwell.restart()
            return
        }
        let time = ProcessInfo.processInfo.systemUptime
        let shook = currentTrigger.usesShake && detector.add(x: point.x, y: point.y, time: time)
        let held = currentTrigger.usesDwell && dwell.add(x: point.x, y: point.y, time: time)
        if shook || held {
            onShake?(point)
            stopPolling()  // One shelf per drag.
        }
    }

    private func isOverOwnWindow(_ point: NSPoint) -> Bool {
        let number = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
        return NSApp.windows.contains { $0.windowNumber == number && $0.isVisible }
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }
}
