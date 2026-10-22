import Foundation

/// How safe it is to delete an item.
enum Tier: Int, CaseIterable, Identifiable, Sendable, Comparable {
    case safe = 0      // regenerates itself, delete anytime
    case review = 1    // probably junk, but depends on whether you still use the tool/project
    case personal = 2  // your data; the app only reports it

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .safe: return "Safe to delete"
        case .review: return "Review first"
        case .personal: return "Personal data"
        }
    }

    var subtitle: String {
        switch self {
        case .safe: return "Caches and build output. Comes back on its own when needed."
        case .review: return "Junk only if you no longer use the tool or project that made it."
        case .personal: return "Your files. Listed for awareness, consider moving to external storage."
        }
    }

    var symbol: String {
        switch self {
        case .safe: return "checkmark.shield.fill"
        case .review: return "questionmark.circle.fill"
        case .personal: return "person.crop.circle.fill"
        }
    }

    static func < (a: Tier, b: Tier) -> Bool { a.rawValue < b.rawValue }
}

/// A folder, file, or set of files the scanner found.
struct CleanItem: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /// All paths the item covers. Usually one; aggregates (e.g. "old downloads") have many.
    let paths: [String]
    let tier: Tier
    /// Section label, e.g. "Browser cache", "JavaScript dependencies".
    let group: String
    /// Plain-language explanation of what this is.
    let what: String
    /// What happens after deleting it: how (and whether) it comes back.
    let afterDelete: String
    var bytes: Int64
    var fileCount: Int
    var modified: Date?

    var path: String { paths.first ?? "" }
    var isAggregate: Bool { paths.count > 1 }

    var displayPath: String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    static func == (a: CleanItem, b: CleanItem) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

enum Format {
    static let bytes: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB]
        return f
    }()

    static func size(_ b: Int64) -> String { bytes.string(fromByteCount: b) }

    static let date: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()
}

/// One immediate child of a scanned folder, for the drill-down in the detail pane.
struct ChildStat: Identifiable, Hashable, Sendable {
    let path: String
    let name: String
    let bytes: Int64
    let isDirectory: Bool
    var id: String { path }

    /// Immediate children of `dir`, sized and sorted biggest first. Caps at `limit` entries.
    static func list(of dir: URL, limit: Int = 10) -> [ChildStat] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let kids = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: Array(keys), options: []) else { return [] }
        var out: [ChildStat] = []
        for k in kids {
            if Task.isCancelled { break }
            let v = try? k.resourceValues(forKeys: keys)
            if v?.isSymbolicLink == true { continue }
            let s = DiskSize.stats(of: k, isCancelled: { Task.isCancelled })
            out.append(ChildStat(path: k.path, name: k.lastPathComponent, bytes: s.bytes, isDirectory: v?.isDirectory == true))
        }
        return Array(out.sorted { $0.bytes > $1.bytes }.prefix(limit))
    }
}
