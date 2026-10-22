import Foundation

struct DirStats: Sendable {
    var bytes: Int64 = 0
    var files: Int = 0
}

/// Sizes a file or directory tree using allocated size on disk (what Finder's "on disk" shows).
/// Does not follow symlinks. Hard links are counted each time they appear.
enum DiskSize {
    private static let keys: Set<URLResourceKey> = [
        .isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
    ]

    static func stats(of url: URL, isCancelled: () -> Bool = { false }) -> DirStats {
        var s = DirStats()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return s }

        if !isDir.boolValue {
            if let v = try? url.resourceValues(forKeys: keys) {
                s.bytes = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
                s.files = 1
            }
            return s
        }

        guard let e = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(keys),
            options: [], errorHandler: { _, _ in true }
        ) else { return s }

        var n = 0
        for case let f as URL in e {
            n += 1
            if n & 0x3FF == 0, isCancelled() { break }
            guard let v = try? f.resourceValues(forKeys: keys), v.isRegularFile == true else { continue }
            s.bytes += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            s.files += 1
        }
        return s
    }

    static func modified(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}
