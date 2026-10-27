import AppKit

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
let base = NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 198, yRadius: 198)
NSGradient(starting: NSColor(red: 0.56, green: 0.39, blue: 0.98, alpha: 1), ending: NSColor(red: 0.26, green: 0.15, blue: 0.64, alpha: 1))!.draw(in: base, angle: -70)
NSColor.white.withAlphaComponent(0.22).setFill()
NSBezierPath(roundedRect: NSRect(x: 164, y: 284, width: 696, height: 374), xRadius: 94, yRadius: 94).fill()
NSColor.white.withAlphaComponent(0.50).setStroke()
let outline = NSBezierPath(roundedRect: NSRect(x: 164, y: 284, width: 696, height: 374), xRadius: 94, yRadius: 94)
outline.lineWidth = 3
outline.stroke()
for (index, height) in [178.0, 252.0, 178.0].enumerated() {
    NSColor.white.withAlphaComponent(index == 1 ? 1 : 0.78).setFill()
    NSBezierPath(roundedRect: NSRect(x: 244 + Double(index) * 190, y: 471 - height / 2, width: 156, height: height), xRadius: 34, yRadius: 34).fill()
}
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
