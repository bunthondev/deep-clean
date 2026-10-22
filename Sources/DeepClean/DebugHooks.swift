import AppKit

/// Only used when DEEPCLEAN_DEBUG is set: lets a terminal session click rows and save a
/// rendering of the window without screen-recording permission.
enum DebugHooks {
    static func tableViews(in view: NSView) -> [NSTableView] {
        var out: [NSTableView] = []
        if let t = view as? NSTableView { out.append(t) }
        for sub in view.subviews { out.append(contentsOf: tableViews(in: sub)) }
        return out
    }

    /// Sends a synthetic left click to `row` of `table` through the window, like a real click.
    static func click(_ table: NSTableView, row: Int) {
        guard let window = table.window, row < table.numberOfRows else { return }
        let rect = table.rect(ofRow: row)
        let pointInTable = NSPoint(x: rect.midX, y: rect.midY)
        let pointInWindow = table.convert(pointInTable, to: nil)
        for (type, count) in [(NSEvent.EventType.leftMouseDown, 1), (.leftMouseUp, 1)] {
            if let e = NSEvent.mouseEvent(with: type, location: pointInWindow, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: count, pressure: 1) {
                window.sendEvent(e)
            }
        }
    }

    /// Renders the whole window frame (title bar and toolbar included) from inside the app.
    static func snapshot(_ window: NSWindow, to path: String) {
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }

    static var window: NSWindow? { NSApp.windows.first { $0.isVisible } }
}
