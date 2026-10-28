import Foundation
import CryptoKit
import Darwin

/// Two or more files, or two or more folders, with identical contents.
struct DuplicateSet: Identifiable, Hashable, Sendable {
    let id: String              // content hash
    let isFolder: Bool
    var paths: [String]         // oldest first: the likely original
    let bytes: Int64            // size of one copy
    let fileCount: Int          // files inside one copy (1 for a file)
    var modified: [String: Date]
    var name: String { (paths.first.map { ($0 as NSString).lastPathComponent }) ?? "" }
    /// Space freed by keeping one copy.
    var wasted: Int64 { bytes * Int64(max(0, paths.count - 1)) }
    static func == (a: DuplicateSet, b: DuplicateSet) -> Bool { a.id == b.id && a.paths == b.paths }
    func hash(into h: inout Hasher) { h.combine(id) }
}

enum DuplicateEvent: Sendable {
    case status(String)
    case done([DuplicateSet])
}

/// Finds duplicate files and folders under the given roots. Read-only.
/// Files: same size, then same SHA-256 of the whole content. Folders: same tree of names and
/// sizes, then same content hash of every file inside. A folder set hides the sets of the
/// subfolders and files inside it, so one copied project shows up once, not a thousand times.
struct DuplicateFinder: Sendable {
    let roots: [URL]
    var minFileBytes: Int64 = 1_000_000
    var minFolderBytes: Int64 = 1_000_000

    static let entireDisk = URL(fileURLWithPath: "/")
    static let defaultRoots: [URL] = [entireDisk]

    /// Never walked into (unless chosen as a root): the OS, other disks, and app data. Copies in
    /// these places are kept on purpose and trashing one breaks the system or an app.
    static let skippedPaths: Set<String> = [
        "/System", "/Library", "/private", "/usr", "/bin", "/sbin", "/dev", "/cores", "/opt", "/Volumes",
        "/etc", "/var", "/tmp", "/Network",
    ]
    /// A folder named Library directly inside a home folder (~/Library, /Users/x/Library).
    static func isAppData(_ path: String) -> Bool {
        (path as NSString).lastPathComponent == "Library"
            && ((path as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent == "/Users"
    }

    /// "Macintosh HD" for the entire disk, the folder name otherwise.
    static func displayName(_ root: URL) -> String {
        guard root.path == "/" else { return root.lastPathComponent }
        return (try? root.resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? "Entire disk"
    }

    /// Generated folders that are identical across projects by design; the junk scan covers them.
    static let skippedFolders: Set<String> = ["node_modules", "Pods", "DerivedData", "venv", "__pycache__", "bower_components"]

    func run() -> AsyncStream<DuplicateEvent> {
        AsyncStream { cont in
            let flag = CancelFlag()
            let task = Task.detached(priority: .userInitiated) {
                let sets = self.find(isCancelled: { flag.isSet }) { cont.yield(.status($0)) }
                cont.yield(.done(sets))
                cont.finish()
            }
            cont.onTermination = { _ in flag.set(); task.cancel() }
        }
    }

    private struct FileEntry {
        let size: Int64
        let modified: Date?
        let inode: UInt64
    }

    /// `isCancelled` is checked from worker threads too, where `Task.isCancelled` is always false.
    func find(isCancelled: @escaping @Sendable () -> Bool = { false }, _ status: (String) -> Void) -> [DuplicateSet] {
        // 1. Walk, one folder level at a time with every folder of a level listed in parallel.
        // Hidden files and package contents (apps, Photos libraries) are skipped.
        var files: [String: FileEntry] = [:]
        var children: [String: [String]] = [:]     // folder -> immediate child paths
        var folderModified: [String: Date] = [:]
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey,
                                      .fileSizeKey, .contentModificationDateKey, .fileIdentifierKey]
        let lock = NSLock()
        var level = Scanner.normalizeRoots(roots)
        while !level.isEmpty {
            if isCancelled() { return [] }
            status("Listing files… \(files.count.formatted())")
            let dirs = level
            var next: [URL] = []
            DispatchQueue.concurrentPerform(iterations: dirs.count) { i in
                if isCancelled() { return }
                let kids = (try? FileManager.default.contentsOfDirectory(at: dirs[i], includingPropertiesForKeys: keys,
                                                                         options: [.skipsHiddenFiles])) ?? []
                var found: [String: FileEntry] = [:], mods: [String: Date] = [:], subdirs: [URL] = [], listed: [String] = []
                for url in kids {
                    guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isSymbolicLink != true else { continue }
                    let path = url.path
                    if v.isDirectory == true {
                        if v.isPackage == true || Self.skippedFolders.contains(url.lastPathComponent)
                            || Self.skippedPaths.contains(path) || Self.isAppData(path) { continue }
                        subdirs.append(url)
                        mods[path] = v.contentModificationDate
                    } else if v.isRegularFile == true {
                        // The file identifier is the inode: hard links share it.
                        found[path] = FileEntry(size: Int64(v.fileSize ?? 0), modified: v.contentModificationDate, inode: v.fileIdentifier ?? 0)
                    } else { continue }
                    listed.append(path)
                }
                lock.withLock {
                    files.merge(found) { a, _ in a }
                    folderModified.merge(mods) { a, _ in a }
                    children[dirs[i].path] = listed
                    next.append(contentsOf: subdirs)
                }
            }
            level = next
        }

        let hashes = HashCache(isCancelled: isCancelled)

        // 2. Folders: structure signature (relative names + sizes), bottom-up.
        status("Comparing folders…")
        var structSig: [String: String] = [:]
        var folderSize: [String: Int64] = [:]
        var folderFiles: [String: Int] = [:]
        func structure(_ dir: String) -> String {
            if let s = structSig[dir] { return s }
            var lines: [String] = [], size: Int64 = 0, count = 0
            for c in children[dir] ?? [] {
                let name = (c as NSString).lastPathComponent
                if let f = files[c] {
                    lines.append("f\t\(name)\t\(f.size)"); size += f.size; count += 1
                } else if children[c] != nil {
                    lines.append("d\t\(name)\t\(structure(c))"); size += folderSize[c] ?? 0; count += folderFiles[c] ?? 0
                }
            }
            let sig = Self.sha(lines.sorted().joined(separator: "\n"))
            structSig[dir] = sig; folderSize[dir] = size; folderFiles[dir] = count
            return sig
        }
        let rootPaths = Set(Scanner.normalizeRoots(roots).map(\.path))
        var byStructure: [String: [String]] = [:]
        for dir in children.keys {
            let sig = structure(dir)
            guard !rootPaths.contains(dir), (folderSize[dir] ?? 0) >= minFolderBytes else { continue }
            byStructure[sig, default: []].append(dir)
        }

        // Content signature of a folder; nil when a file cannot be read (or is only in iCloud).
        var contentSig: [String: String?] = [:]
        func content(_ dir: String) -> String? {
            if let s = contentSig[dir] { return s }
            var lines: [String] = []
            for c in children[dir] ?? [] {
                let name = (c as NSString).lastPathComponent
                if files[c] != nil {
                    guard let h = hashes.full(c) else { contentSig[dir] = .some(nil); return nil }
                    lines.append("f\t\(name)\t\(h)")
                } else if children[c] != nil {
                    guard let h = content(c) else { contentSig[dir] = .some(nil); return nil }
                    lines.append("d\t\(name)\t\(h)")
                }
            }
            let sig = Self.sha(lines.sorted().joined(separator: "\n"))
            contentSig[dir] = sig
            return sig
        }

        // Hash every file inside a candidate folder up front, in parallel. A folder inside another
        // candidate shares its files, so this is the same work the checks below would do one by one.
        let folderGroups = byStructure.values.filter { $0.count > 1 }
            .sorted { (folderSize[$0[0]] ?? 0, -$0[0].count) > (folderSize[$1[0]] ?? 0, -$1[0].count) }
        var toHash: Set<String> = []
        func collect(_ dir: String) {
            for c in children[dir] ?? [] {
                if files[c] != nil { toHash.insert(c) } else if children[c] != nil { collect(c) }
            }
        }
        var collected: Set<String> = []
        for dir in folderGroups.joined() where collected.insert(dir).inserted { collect(dir) }
        status("Checking the contents of \(toHash.count.formatted()) files in \(folderGroups.count) folder sets…")
        hashes.prefetch(Array(toHash), head: false)
        if isCancelled() { return [] }

        var sets: [DuplicateSet] = []
        var covered: [String] = []    // folders already reported; anything inside them is hidden
        func isCovered(_ p: String) -> Bool { covered.contains { p.hasPrefix($0 + "/") } }
        for group in folderGroups {
            if isCancelled() { return [] }
            let open = group.filter { !isCovered($0) }
            guard open.count > 1 else { continue }
            var byContent: [String: [String]] = [:]
            for dir in open { if let h = content(dir) { byContent[h, default: []].append(dir) } }
            for (h, dirs) in byContent where dirs.count > 1 {
                let sorted = dirs.sorted { (folderModified[$0] ?? .distantFuture) < (folderModified[$1] ?? .distantFuture) }
                sets.append(DuplicateSet(id: "d:" + h, isFolder: true, paths: sorted, bytes: folderSize[dirs[0]] ?? 0,
                                         fileCount: folderFiles[dirs[0]] ?? 0, modified: folderModified.filter { dirs.contains($0.key) }))
                covered.append(contentsOf: dirs)
            }
        }

        // A folder holding nothing but one subfolder matches wherever the subfolder does; keep the outer set.
        let folderSets = sets
        sets.removeAll { s in
            folderSets.contains { o in o.id != s.id && s.paths.allSatisfy { p in o.paths.contains { p.hasPrefix($0 + "/") } } }
        }

        // 3. Files: same size, then a hash of the first 64 KB, then the full hash.
        var bySize: [Int64: [String]] = [:]
        var seenInodes: Set<UInt64> = []
        for (path, f) in files where f.size >= minFileBytes {
            // Hard links are one file on disk; count each inode once.
            if f.inode != 0, !seenInodes.insert(f.inode).inserted { continue }
            bySize[f.size, default: []].append(path)
        }
        let sizeGroups = bySize.values.filter { $0.count > 1 }
        let sameSize = sizeGroups.flatMap { $0 }
        status("Comparing \(sameSize.count.formatted()) files of the same size…")
        hashes.prefetch(sameSize, head: true)
        let headGroups = sizeGroups.flatMap { g in Dictionary(grouping: g) { hashes.head($0) ?? "" }.filter { !$0.key.isEmpty && $0.value.count > 1 }.values }
        hashes.prefetch(headGroups.flatMap { $0 }, head: false)
        if isCancelled() { return [] }
        for group in sizeGroups {
            var byHead: [String: [String]] = [:]
            for p in group { if let h = hashes.head(p) { byHead[h, default: []].append(p) } }
            for candidates in byHead.values where candidates.count > 1 {
                var byFull: [String: [String]] = [:]
                for p in candidates { if let h = hashes.full(p) { byFull[h, default: []].append(p) } }
                for (h, found) in byFull where found.count > 1 {
                    let all = found.sorted { (files[$0]?.modified ?? .distantFuture) < (files[$1]?.modified ?? .distantFuture) }
                    // Copies inside a reported folder set stay there; one of them is kept as the reference.
                    let free = all.filter { !isCovered($0) }
                    let paths = free + all.filter(isCovered).prefix(1)
                    guard !free.isEmpty, paths.count > 1 else { continue }
                    let sorted = paths.sorted { (files[$0]?.modified ?? .distantFuture) < (files[$1]?.modified ?? .distantFuture) }
                    var mod: [String: Date] = [:]
                    for p in paths { mod[p] = files[p]?.modified }
                    sets.append(DuplicateSet(id: "f:" + h, isFolder: false, paths: sorted, bytes: files[paths[0]]?.size ?? 0,
                                             fileCount: 1, modified: mod))
                }
            }
        }
        return sets.sorted { $0.wasted > $1.wasted }
    }

    static func sha(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Content hashes, computed once per file. Files that exist only in iCloud (dataless) are never
/// read, since reading them would download them.
private final class HashCache: @unchecked Sendable {
    private var fullHashes: [String: String?] = [:]
    private var headHashes: [String: String?] = [:]
    private let lock = NSLock()
    private let isCancelled: @Sendable () -> Bool

    init(isCancelled: @escaping @Sendable () -> Bool) { self.isCancelled = isCancelled }

    func head(_ path: String) -> String? { get(path, head: true) }
    func full(_ path: String) -> String? { get(path, head: false) }

    private func get(_ path: String, head: Bool) -> String? {
        if let h = lock.withLock({ head ? headHashes[path] : fullHashes[path] }) { return h }
        let h = hash(path, limit: head ? 65_536 : nil)
        lock.withLock { if head { headHashes[path] = .some(h) } else { fullHashes[path] = .some(h) } }
        return h
    }

    /// Hashes the given files on all cores; SSDs read faster with several requests in flight.
    func prefetch(_ paths: [String], head: Bool) {
        DispatchQueue.concurrentPerform(iterations: paths.count) { i in
            if isCancelled() { return }
            _ = get(paths[i], head: head)
        }
    }

    private func hash(_ path: String, limit: Int?) -> String? {
        var st = stat()
        guard lstat(path, &st) == 0, st.st_flags & UInt32(SF_DATALESS) == 0,
              let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? fh.close() }
        var hasher = SHA256()
        var read = 0
        while limit.map({ read < $0 }) ?? true {
            if isCancelled() { return nil }
            // Each read returns an autoreleased buffer; drain it per chunk or a big file stays in memory.
            let n: Int = autoreleasepool {
                guard let chunk = try? fh.read(upToCount: min(1 << 20, limit.map { $0 - read } ?? 1 << 20)), !chunk.isEmpty else { return 0 }
                hasher.update(data: chunk)
                return chunk.count
            }
            if n == 0 { break }
            read += n
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Set when the search is cancelled; readable from any thread.
final class CancelFlag: @unchecked Sendable {
    private var value = false
    private let lock = NSLock()
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}
