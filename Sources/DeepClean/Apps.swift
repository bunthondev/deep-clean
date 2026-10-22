import Foundation
import AppKit
import CoreServices

/// Disk capacity of the boot volume. "Free" is what macOS would give an important write,
/// which includes purgeable space it can reclaim on demand.
struct StorageInfo: Sendable {
    var total: Int64 = 0
    var available: Int64 = 0       // free right now
    var importantFree: Int64 = 0   // free + purgeable
    var used: Int64 { max(0, total - importantFree) }
    var purgeable: Int64 { max(0, importantFree - available) }

    static func current() -> StorageInfo {
        var s = StorageInfo()
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        if let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys) {
            s.total = Int64(v.volumeTotalCapacity ?? 0)
            s.available = Int64(v.volumeAvailableCapacity ?? 0)
            s.importantFree = v.volumeAvailableCapacityForImportantUsage ?? s.available
        }
        return s
    }
}

struct InstalledApp: Identifiable, Hashable, Sendable {
    let path: String
    let name: String
    let bundleID: String?
    let version: String?
    let bytes: Int64
    let lastUsed: Date?
    let source: Source

    var id: String { path }

    enum Source: String, Sendable {
        case appStore = "App Store"
        case homebrew = "Homebrew cask"
        case other = "Downloaded"
    }

    var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.path == path }
    }

    static func == (a: InstalledApp, b: InstalledApp) -> Bool { a.path == b.path }
    func hash(into h: inout Hasher) { h.combine(path) }
}

/// A file or folder an app left in ~/Library.
struct Leftover: Identifiable, Hashable, Sendable {
    let path: String
    let kind: String
    let bytes: Int64
    var id: String { path }
}

enum AppScanner {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    static var folders: [URL] {
        [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Lists .app bundles in /Applications and ~/Applications (one level of subfolders too),
    /// sized concurrently and streamed as they finish.
    static func run() -> AsyncStream<InstalledApp> {
        AsyncStream { cont in
            let task = Task.detached(priority: .userInitiated) {
                var bundles: [URL] = []
                for folder in folders {
                    guard let kids = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
                    for k in kids {
                        if k.pathExtension == "app" { bundles.append(k) }
                        else if (try? k.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                                let sub = try? FileManager.default.contentsOfDirectory(at: k, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                            bundles.append(contentsOf: sub.filter { $0.pathExtension == "app" })
                        }
                    }
                }
                let casks = Set((try? FileManager.default.contentsOfDirectory(atPath: "/opt/homebrew/Caskroom")) ?? [])

                await withTaskGroup(of: InstalledApp?.self) { group in
                    var running = 0
                    for b in bundles {
                        if Task.isCancelled { break }
                        if running >= 6 { if let a = await group.next() ?? nil { cont.yield(a) }; running -= 1 }
                        group.addTask { inspect(b, casks: casks) }
                        running += 1
                    }
                    for await a in group { if let a { cont.yield(a) } }
                }
                cont.finish()
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }

    private static func inspect(_ url: URL, casks: Set<String>) -> InstalledApp? {
        let bundle = Bundle(url: url)
        let info = bundle?.infoDictionary ?? [:]
        let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent
        let bundleID = bundle?.bundleIdentifier
        let version = (info["CFBundleShortVersionString"] as? String) ?? (info["CFBundleVersion"] as? String)
        let stats = DiskSize.stats(of: url, isCancelled: { Task.isCancelled })

        var lastUsed: Date?
        if let md = MDItemCreate(kCFAllocatorDefault, url.path as CFString) {
            lastUsed = MDItemCopyAttribute(md, kMDItemLastUsedDate) as? Date
        }

        let source: InstalledApp.Source
        if FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/_MASReceipt/receipt").path) {
            source = .appStore
        } else if casks.contains(caskToken(for: url.deletingPathExtension().lastPathComponent)) || casks.contains(caskToken(for: name)) {
            source = .homebrew
        } else {
            source = .other
        }
        return InstalledApp(path: url.path, name: name, bundleID: bundleID, version: version, bytes: stats.bytes, lastUsed: lastUsed, source: source)
    }

    private static func caskToken(for name: String) -> String {
        name.lowercased().replacingOccurrences(of: " ", with: "-")
    }

    // MARK: Leftovers

    /// Files in ~/Library that belong to the app, matched by bundle identifier (exact, case-insensitive)
    /// and by exact app name. Name-only matches are limited to folders to avoid false positives.
    static func leftovers(for app: InstalledApp) -> [Leftover] {
        let lib = home.appendingPathComponent("Library")
        let id = app.bundleID?.lowercased()
        let name = app.name.lowercased()
        var out: [Leftover] = []
        var seen = Set<String>()

        func add(_ url: URL, _ kind: String) {
            let p = url.path
            guard !seen.contains(p), FileManager.default.fileExists(atPath: p) else { return }
            seen.insert(p)
            let s = DiskSize.stats(of: url, isCancelled: { Task.isCancelled })
            out.append(Leftover(path: p, kind: kind, bytes: s.bytes))
        }

        // Folders whose direct children are named after the app or its bundle id.
        let byName: [(String, String)] = [
            ("Application Support", "Application Support"), ("Caches", "Caches"), ("Logs", "Logs"),
            ("Containers", "Containers"), ("HTTPStorages", "HTTP storage"), ("WebKit", "WebKit data"),
            ("Application Scripts", "Application Scripts"), ("Saved Application State", "Saved state"),
            ("Preferences", "Preferences"), ("Cookies", "Cookies"), ("LaunchAgents", "Launch agents"),
            ("Group Containers", "Group Containers"),
        ]
        for (folder, kind) in byName {
            let dir = lib.appendingPathComponent(folder)
            guard let kids = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: []) else { continue }
            for k in kids {
                let base = k.deletingPathExtension().lastPathComponent.lowercased()
                let full = k.lastPathComponent.lowercased()
                let isDir = (try? k.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                var hit = false
                if let id {
                    // exact id, "id.savedState", "id.plist", "id.binarycookies", "id.helper", "TEAMID.id" (group containers)
                    if base == id || full == id || full.hasPrefix(id + ".") || full.hasSuffix("." + id) { hit = true }
                }
                if !hit, isDir, base == name { hit = true }
                if hit { add(k, kind) }
            }
        }
        return out.sorted { $0.bytes > $1.bytes }
    }
}
