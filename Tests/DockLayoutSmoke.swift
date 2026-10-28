import Foundation

@main
struct DockLayoutSmoke {
    static func main() {
        let a = DockItem(name: "A", kind: .app, target: "/Applications/A.app")
        let b = DockItem(name: "B", kind: .app, target: "/Applications/B.app")
        let folder = DockItem(name: "Downloads", kind: .folder, target: "/tmp")
        let widget = DockItem(name: "Relógio", kind: .widget, target: "clock")
        let compact = DockBarSizing.size(pinned: [a, b], running: [], iconSize: 33, edge: .bottom, scale: 1)
        precondition(compact == CGSize(width: 132, height: 52), "33-point icons must produce a compact 52-point bar")
        let mixed = DockBarSizing.size(pinned: [a, widget], running: [], iconSize: 33, edge: .bottom, scale: 1)
        precondition(mixed.height == 76, "Widgets must retain a readable height")
        let scaled = DockBarSizing.size(pinned: [a, b], running: [], iconSize: 33, edge: .bottom, scale: 1.25)
        precondition(scaled == CGSize(width: 165, height: 65))
        let sections = DockBarSizing.sections([a, b, folder])
        precondition(sections.apps.map(\.id) == [a.id, b.id] && sections.others.map(\.id) == [folder.id])
        let vertical = DockBarSizing.size(pinned: [a, b], running: [], iconSize: 33, edge: .left, scale: 1)
        precondition(vertical == CGSize(width: 51, height: 134))
        print("PASS: native-sized compact bar, readable widgets, scale, vertical layout, and app/other ordering.")
    }
}
