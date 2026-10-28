import Foundation

enum DockBarSizing {
    static let spacing: CGFloat = 3
    static let padding: CGFloat = 6
    static let handle: CGFloat = 12

    static func sections(_ items: [DockItem]) -> (apps: [DockItem], others: [DockItem]) {
        let split = items.firstIndex { $0.kind != .app && $0.kind != .spacer } ?? items.endIndex
        return (Array(items[..<split]), Array(items[split...]))
    }

    static func width(of item: DockItem, iconSize: Double) -> CGFloat {
        if item.kind == .spacer { return 16 }
        guard item.kind == .widget, let widget = WidgetKind(rawValue: item.target) else { return iconSize + 6 }
        switch widget {
        case .clock: return 146
        case .calendar: return 106
        case .focus: return 142
        case .battery: return 130
        case .note: return 156
        case .system: return 144
        case .stopwatch: return 144
        case .worldClock: return 152
        case .hydration: return 120
        }
    }

    static func size(pinned: [DockItem], running: [DockItem], iconSize: Double, edge: DockEdge, scale: Double) -> CGSize {
        let items = pinned + running
        let sections = sections(pinned)
        let dividerCount = (running.isEmpty ? 0 : 1) + (!sections.others.isEmpty && (!sections.apps.isEmpty || !running.isEmpty) ? 1 : 0)
        let totalGaps = CGFloat(items.count + dividerCount) * spacing
        let inset = padding * 2 + handle
        if edge == .bottom {
            let length = items.reduce(CGFloat(24)) { $0 + width(of: $1, iconSize: iconSize) }
            let contentHeight = max(iconSize + 7, items.contains { $0.kind == .widget } ? 64 : 0)
            return CGSize(width: (length + totalGaps + CGFloat(dividerCount) * 9 + inset) * scale,
                          height: (contentHeight + padding * 2) * scale)
        }
        let contentWidth = items.map { width(of: $0, iconSize: iconSize) }.max() ?? iconSize + 6
        let length = items.reduce(CGFloat(24)) { $0 + ($1.kind == .spacer ? 16 : ($1.kind == .widget ? 64 : iconSize + 7)) }
        return CGSize(width: (contentWidth + padding * 2) * scale,
                      height: (length + totalGaps + CGFloat(dividerCount) * 9 + inset) * scale)
    }
}
