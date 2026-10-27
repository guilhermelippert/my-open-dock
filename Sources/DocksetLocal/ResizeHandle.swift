import AppKit
import SwiftUI

enum DockScaleAdjustment {
    static func scale(start: Double, movement: CGSize, edge: DockEdge) -> Double {
        let distance: Double
        switch edge {
        case .bottom: distance = movement.height
        case .left: distance = movement.width
        case .right: distance = -movement.width
        }
        return min(1.6, max(0.6, start + distance / 180))
    }
}

struct DockResizeHandle: NSViewRepresentable {
    let edge: DockEdge
    let scale: Double
    let onChange: (Double) -> Void
    var onDragStateChanged: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> DockResizeGripView {
        let view = DockResizeGripView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: DockResizeGripView, context: Context) {
        view.edge = edge
        view.currentScale = scale
        view.onChange = onChange
        view.onDragStateChanged = onDragStateChanged
        view.toolTip = edge == .bottom ? "Arraste para cima ou para baixo para redimensionar. Dois cliques restauram 100%." : "Arraste para os lados para redimensionar. Dois cliques restauram 100%."
        view.needsDisplay = true
        view.window?.invalidateCursorRects(for: view)
    }
}

final class DockResizeGripView: NSView {
    var edge: DockEdge = .bottom
    var currentScale = 1.0
    var onChange: ((Double) -> Void)?
    var onDragStateChanged: ((Bool) -> Void)?
    private var startingPoint: NSPoint?
    private var startingScale = 1.0

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: edge == .bottom ? .resizeUpDown : .resizeLeftRight)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.secondaryLabelColor.withAlphaComponent(0.45).setFill()
        let line = edge == .bottom ? NSRect(x: bounds.midX - 1.5, y: bounds.midY - 15, width: 3, height: 30) :
            NSRect(x: bounds.midX - 15, y: bounds.midY - 1.5, width: 30, height: 3)
        NSBezierPath(roundedRect: line, xRadius: 1.5, yRadius: 1.5).fill()
    }

    override func mouseDown(with event: NSEvent) {
        guard event.clickCount < 2 else {
            finishDrag()
            onChange?(1)
            return
        }
        startingPoint = window?.convertPoint(toScreen: event.locationInWindow)
        startingScale = currentScale
        if startingPoint != nil { onDragStateChanged?(true) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startingPoint, let point = window?.convertPoint(toScreen: event.locationInWindow) else { return }
        let movement = CGSize(width: point.x - start.x, height: point.y - start.y)
        onChange?(DockScaleAdjustment.scale(start: startingScale, movement: movement, edge: edge))
    }

    override func mouseUp(with event: NSEvent) { finishDrag() }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { finishDrag() }
        super.viewWillMove(toWindow: newWindow)
    }

    private func finishDrag() {
        guard startingPoint != nil else { return }
        startingPoint = nil
        onDragStateChanged?(false)
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .slider }
    override func accessibilityLabel() -> String? { "Redimensionar a barra" }
    override func accessibilityValue() -> Any? { Int((currentScale * 100).rounded()) }
    override func accessibilityMinValue() -> Any? { 60 }
    override func accessibilityMaxValue() -> Any? { 160 }
    override func accessibilityPerformIncrement() -> Bool { onChange?(min(1.6, currentScale + 0.05)); return true }
    override func accessibilityPerformDecrement() -> Bool { onChange?(max(0.6, currentScale - 0.05)); return true }
}
