// usage: swift frame.swift in.png out.png  — rounds window corners and adds a soft shadow on a transparent canvas (2x).
import AppKit
let args = CommandLine.arguments
guard args.count == 3, let src = NSImage(contentsOfFile: args[1]), let rep0 = src.representations.first as? NSBitmapImageRep else { exit(1) }
let w = rep0.pixelsWide, h = rep0.pixelsHigh
let pad = 80, radius: CGFloat = 24   // pixels at 2x
let cw = w + pad * 2, ch = h + pad * 2
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: cw, pixelsHigh: ch, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx
let rect = NSRect(x: pad, y: pad, width: w, height: h)
let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
let shadow = NSShadow(); shadow.shadowBlurRadius = 40; shadow.shadowOffset = NSSize(width: 0, height: -16); shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
ctx.cgContext.saveGState(); shadow.set(); NSColor.black.setFill(); path.fill(); ctx.cgContext.restoreGState()
path.addClip()
let cg = rep0.cgImage!
ctx.cgContext.draw(cg, in: rect)
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("wrote \(args[2]) \(cw)x\(ch)")
