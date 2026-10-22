// Renders AppIcon.icns without Xcode. Run: ./Resources/make-icon.sh
import AppKit

let px = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: px, height: px)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let s = CGFloat(px)
let rect = NSRect(x: 0, y: 0, width: s, height: s).insetBy(dx: s * 0.1, dy: s * 0.1)
let squircle = NSBezierPath(roundedRect: rect, xRadius: s * 0.18, yRadius: s * 0.18)
NSGradient(starting: NSColor(red: 0.16, green: 0.62, blue: 0.98, alpha: 1),
           ending: NSColor(red: 0.04, green: 0.24, blue: 0.62, alpha: 1))!.draw(in: squircle, angle: -70)

// subtle inner highlight
NSColor.white.withAlphaComponent(0.12).setStroke()
squircle.lineWidth = s * 0.012
squircle.stroke()

func whiteSymbol(_ name: String, size: CGFloat, weight: NSFont.Weight) -> NSImage? {
    let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
    guard let sym = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) else { return nil }
    let out = NSImage(size: sym.size, flipped: false) { r in
        sym.draw(in: r)
        NSColor.white.set()
        r.fill(using: .sourceAtop)
        return true
    }
    return out
}

if let broom = whiteSymbol("sparkles", size: s * 0.42, weight: .semibold) {
    let sz = broom.size
    let origin = NSPoint(x: (s - sz.width) / 2, y: (s - sz.height) / 2 + s * 0.02)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowBlurRadius = s * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
    shadow.set()
    broom.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
}

NSGraphicsContext.restoreGraphicsState()
let png = rep.representation(using: .png, properties: [:])!
let out = CommandLine.arguments.dropFirst().first ?? "icon_1024.png"
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
