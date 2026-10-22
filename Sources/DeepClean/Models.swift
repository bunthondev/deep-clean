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
    var paths: [String]
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
    /// Per-path size and last-change date for aggregates, keyed by path. Empty for single items.
    var pathInfo: [String: PathInfo] = [:]

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
/// What the scanner knows about one file inside an aggregate item.
struct PathInfo: Hashable, Sendable {
    var bytes: Int64
    var modified: Date?

    /// Whole days since the file last changed, nil when unknown.
    var daysInactive: Int? {
        modified.map { max(0, Int(Date().timeIntervalSince($0) / 86_400)) }
    }
}

/// A folder or file in the detail pane's tree of an aggregate item's paths.
struct PathNode: Identifiable {
    let path: String
    let name: String
    let depth: Int
    let isDirectory: Bool
    var children: [PathNode] = []
    var bytes: Int64 = 0
    /// Days since the most recently changed file inside (or the file itself). nil when unknown.
    var daysInactive: Int?
    /// Every file path under this node (just itself for a file).
    var leaves: [String] = []
    var id: String { path }

    /// Builds a tree of `paths` relative to their common parent folder. Folders come first, then
    /// files, each sorted longest-untouched first.
    static func tree(of paths: [String], info: [String: PathInfo]) -> [PathNode] {
        let root = commonRoot(of: paths)
        var top: [String: PathNode] = [:]
        var order: [String] = []

        func insert(_ comps: ArraySlice<String>, into nodes: inout [String: PathNode], order: inout [String], prefix: String, depth: Int, leaf: String) {
            guard let head = comps.first else { return }
            let path = prefix + "/" + head
            if nodes[head] == nil {
                nodes[head] = PathNode(path: path, name: head, depth: depth, isDirectory: comps.count > 1)
                order.append(head)
            }
            var node = nodes[head]!
            node.leaves.append(leaf)
            let i = info[leaf]
            node.bytes += i?.bytes ?? 0
            if let d = i?.daysInactive { node.daysInactive = min(node.daysInactive ?? .max, d) }
            if comps.count > 1 {
                var kids = Dictionary(uniqueKeysWithValues: node.children.map { ($0.name, $0) })
                var kidOrder = node.children.map(\.name)
                insert(comps.dropFirst(), into: &kids, order: &kidOrder, prefix: path, depth: depth + 1, leaf: leaf)
                node.children = kidOrder.compactMap { kids[$0] }
            }
            nodes[head] = node
        }

        for p in paths {
            let rel = p.hasPrefix(root + "/") ? String(p.dropFirst(root.count + 1)) : (p as NSString).lastPathComponent
            insert(ArraySlice(rel.split(separator: "/").map(String.init)), into: &top, order: &order, prefix: root, depth: 0, leaf: p)
        }
        return sorted(order.compactMap { top[$0] })
    }

    private static func sorted(_ nodes: [PathNode]) -> [PathNode] {
        nodes.map { n in var n = n; n.children = sorted(n.children); return n }
            .sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                return (a.daysInactive ?? -1) > (b.daysInactive ?? -1)
            }
    }

    /// Longest directory shared by every path ("/" when nothing is shared).
    static func commonRoot(of paths: [String]) -> String {
        guard var common = paths.first.map({ ($0 as NSString).deletingLastPathComponent }) else { return "/" }
        for p in paths.dropFirst() {
            while !common.isEmpty, common != "/", !p.hasPrefix(common + "/") {
                common = (common as NSString).deletingLastPathComponent
            }
        }
        return common.isEmpty ? "/" : common
    }
}

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
