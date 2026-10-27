import AppKit
import Foundation

@main
struct ResizeSmoke {
    @MainActor static func main() {
        func check(_ actual: Double, _ expected: Double) { precondition(abs(actual - expected) < 0.0001) }
        check(DockScaleAdjustment.scale(start: 1, movement: CGSize(width: 0, height: 45), edge: .bottom), 1.25)
        check(DockScaleAdjustment.scale(start: 1, movement: CGSize(width: 45, height: 0), edge: .left), 1.25)
        check(DockScaleAdjustment.scale(start: 1, movement: CGSize(width: -45, height: 0), edge: .right), 1.25)
        check(DockScaleAdjustment.scale(start: 1, movement: CGSize(width: 0, height: -500), edge: .bottom), 0.6)
        check(DockScaleAdjustment.scale(start: 1, movement: CGSize(width: 0, height: 500), edge: .bottom), 1.6)
        check(DockScaleAdjustment.scale(start: 1.25, movement: .zero, edge: .bottom), 1.25)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 300, height: 90), styleMask: .borderless, backing: .buffered, defer: false)
        let grip = DockResizeGripView(frame: NSRect(x: 270, y: 0, width: 18, height: 90))
        window.contentView?.addSubview(grip)
        var observed = 1.0
        var dragStates: [Bool] = []
        grip.onChange = { observed = $0; grip.currentScale = $0 }
        grip.onDragStateChanged = { dragStates.append($0) }
        func mouse(_ type: NSEvent.EventType, _ point: NSPoint, clicks: Int = 1) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
        }
        grip.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 280, y: 20)))
        grip.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: 280, y: 65)))
        check(observed, 1.25)
        // Moving the panel while dragging must not change the global drag origin.
        window.setFrameOrigin(NSPoint(x: 50, y: 100))
        grip.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: 330, y: 65)))
        check(observed, 1.25)
        grip.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 330, y: 65)))
        precondition(dragStates == [true, false])
        grip.mouseDown(with: mouse(.leftMouseDown, .zero, clicks: 2))
        check(observed, 1)
        _ = grip.accessibilityPerformIncrement()
        check(observed, 1.05)
        _ = grip.accessibilityPerformDecrement()
        check(observed, 1)
        grip.mouseDown(with: mouse(.leftMouseDown, .zero))
        grip.removeFromSuperview()
        precondition(dragStates == [true, false, true, false], "Removing a grip must end resizing so auto-hide can resume")
        precondition(!window.isVisible, "Resize tests must never show the disabled dock")
        print("PASS: all screen edges, scale limits, native grip drag, panel movement, double-click reset and accessibility. No window displayed.")
    }
}
