import Foundation

enum ScanEvent: Sendable {
    case status(String)
    case item(CleanItem)
    case done
}

/// Finds junk in three ways: known catalog paths, generated folders inside projects,
/// and large or stale files in Downloads/Desktop. Read-only.
struct Scanner: Sendable {
    let projectRoots: [URL]
    let largeFileThreshold: Int64 = 200_000_000
    let staleDays = 180
    let maxConcurrent = 6

    static let home = FileManager.default.homeDirectoryForCurrentUser

    static let defaultProjectRoots: [URL] = {
        ["dev", "Developer", "Projects", "projects", "Code", "code", "src", "work", "workspace", "repos"]
            .map { home.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }()

    static func expand(_ p: String) -> URL {
        if p.hasPrefix("~") { return home.appendingPathComponent(String(p.dropFirst(2))) }
        return URL(fileURLWithPath: p)
    }

    // MARK: Streaming entry point for the UI

    func run() -> AsyncStream<ScanEvent> {
        AsyncStream { cont in
            let task = Task.detached(priority: .userInitiated) {
                await self.scan { cont.yield($0) }
                cont.yield(.done)
                cont.finish()
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }

    private func scan(_ emit: @Sendable @escaping (ScanEvent) -> Void) async {
        emit(.status("Checking known cache locations…"))
        let known = Catalog.entries.filter { FileManager.default.fileExists(atPath: Self.expand($0.path).path) }
        await sizeConcurrently(known.map { e in
            { () -> CleanItem? in
                let url = Self.expand(e.path)
                let s = DiskSize.stats(of: url, isCancelled: { Task.isCancelled })
                guard s.bytes > 0 else { return nil }
                return CleanItem(id: "known:" + e.path, name: e.name, paths: [url.path], tier: e.tier, group: e.group,
                                 what: e.what, afterDelete: e.afterDelete, bytes: s.bytes, fileCount: s.files, modified: DiskSize.modified(url))
            }
        }, emit: emit)
        if Task.isCancelled { return }

        emit(.status("Looking for build folders in projects…"))
        var found: [(URL, ArtifactRule)] = []
        for root in projectRoots { findArtifacts(in: root, depth: 0, into: &found) }
        let (small, big) = (found.filter { Catalog.aggregatedArtifacts.contains($0.1.name) }, found.filter { !Catalog.aggregatedArtifacts.contains($0.1.name) })
        emit(.status("Sizing \(big.count) project folders…"))
        await sizeConcurrently(big.map { (url, rule) in
            { () -> CleanItem? in
                let s = DiskSize.stats(of: url, isCancelled: { Task.isCancelled })
                guard s.bytes > 0 else { return nil }
                let project = url.deletingLastPathComponent().lastPathComponent
                return CleanItem(id: "artifact:" + url.path, name: "\(project)/\(rule.name)", paths: [url.path], tier: rule.tier,
                                 group: Self.groupName(for: rule.name), what: rule.what, afterDelete: rule.afterDelete,
                                 bytes: s.bytes, fileCount: s.files, modified: DiskSize.modified(url))
            }
        }, emit: emit)
        if Task.isCancelled { return }

        // One row per kind for the many tiny folders (e.g. 90 __pycache__ dirs).
        for (name, entries) in Dictionary(grouping: small, by: { $0.1.name }) {
            if Task.isCancelled { return }
            var bytes: Int64 = 0, files = 0
            var info: [String: PathInfo] = [:]
            for (url, _) in entries {
                let s = DiskSize.stats(of: url, isCancelled: { Task.isCancelled })
                bytes += s.bytes; files += s.files
                let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                info[url.path] = PathInfo(bytes: s.bytes, modified: mod)
            }
            guard bytes > 0, let rule = entries.first?.1 else { continue }
            emit(.item(CleanItem(id: "artifact-agg:" + name, name: "\(name) (\(entries.count) folders)", paths: entries.map { $0.0.path },
                                 tier: rule.tier, group: Self.groupName(for: name), what: rule.what + " Found in \(entries.count) places under your project folders.",
                                 afterDelete: rule.afterDelete, bytes: bytes, fileCount: files, modified: nil, pathInfo: info)))
        }

        emit(.status("Checking Downloads and Desktop…"))
        for item in scanUserFolders() { emit(.item(item)) }
    }

    private func sizeConcurrently(_ jobs: [@Sendable () -> CleanItem?], emit: @Sendable @escaping (ScanEvent) -> Void) async {
        await withTaskGroup(of: CleanItem?.self) { group in
            var running = 0
            for job in jobs {
                if Task.isCancelled { break }
                if running >= maxConcurrent {
                    if let item = await group.next() ?? nil { emit(.item(item)) }
                    running -= 1
                }
                group.addTask { job() }
                running += 1
            }
            for await item in group { if let item { emit(.item(item)) } }
        }
    }

    /// Project artifacts are grouped by their folder name, so all `node_modules` land together.
    static func groupName(for artifact: String) -> String {
        switch artifact {
        case ".venv", "venv": return "venv"
        default: return artifact
        }
    }

    // MARK: Project walk

    private func findArtifacts(in dir: URL, depth: Int, into out: inout [(URL, ArtifactRule)]) {
        guard depth < 10, !Task.isCancelled else { return }
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let children = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: Array(keys), options: []) else { return }
        let siblings = Set(children.map(\.lastPathComponent))

        for child in children {
            guard let v = try? child.resourceValues(forKeys: keys), v.isDirectory == true, v.isSymbolicLink != true else { continue }
            let name = child.lastPathComponent
            if name == ".git" || name == "Library" { continue }
            if let rule = Catalog.artifactRules.first(where: { $0.name == name }) {
                if rule.requiresSibling.isEmpty || !siblings.isDisjoint(with: rule.requiresSibling) {
                    out.append((child, rule))
                    continue
                }
            }
            if name.hasPrefix(".") { continue }
            findArtifacts(in: child, depth: depth + 1, into: &out)
        }
    }

    // MARK: Downloads / Desktop

    private func scanUserFolders() -> [CleanItem] {
        var items: [CleanItem] = []
        let cutoff = Date().addingTimeInterval(-Double(staleDays) * 86400)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .contentModificationDateKey]
        let installerExt: Set<String> = ["dmg", "pkg", "zip", "iso", "ipa", "apk", "tar", "gz", "xz", "7z", "rar"]

        for folderName in ["Downloads", "Desktop"] {
            let folder = Self.home.appendingPathComponent(folderName)
            guard let e = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: Array(keys),
                                                         options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in true }) else { continue }
            var staleBytes: Int64 = 0, stalePaths: [String] = []
            var installerBytes: Int64 = 0, installerPaths: [String] = []
            var info: [String: PathInfo] = [:]

            for case let f as URL in e {
                if Task.isCancelled { return items }
                guard let v = try? f.resourceValues(forKeys: keys), v.isRegularFile == true else { continue }
                let bytes = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
                let mod = v.contentModificationDate

                if bytes >= largeFileThreshold {
                    items.append(CleanItem(id: "large:" + f.path, name: f.lastPathComponent, paths: [f.path], tier: .personal,
                                           group: "Large files in \(folderName)", what: "A single file over \(Format.size(largeFileThreshold)).",
                                           afterDelete: "Gone for good unless you have another copy.", bytes: bytes, fileCount: 1, modified: mod))
                }
                if folderName == "Downloads", installerExt.contains(f.pathExtension.lowercased()) {
                    installerBytes += bytes; installerPaths.append(f.path); info[f.path] = PathInfo(bytes: bytes, modified: mod)
                }
                if folderName == "Downloads", let mod, mod < cutoff {
                    staleBytes += bytes; stalePaths.append(f.path); info[f.path] = PathInfo(bytes: bytes, modified: mod)
                }
            }
            if installerBytes > 0 {
                items.append(CleanItem(id: "agg:installers", name: "Installers and archives in Downloads", paths: installerPaths, tier: .review,
                                       group: "Downloads", what: "\(installerPaths.count) .dmg, .pkg, .zip and similar files. Usually already installed or unpacked.",
                                       afterDelete: "Re-download from the source if you need them again.", bytes: installerBytes, fileCount: installerPaths.count, modified: nil,
                                       pathInfo: info.filter { installerPaths.contains($0.key) }))
            }
            if staleBytes > 0 {
                items.append(CleanItem(id: "agg:stale-downloads", name: "Downloads untouched for \(staleDays) days", paths: stalePaths, tier: .review,
                                       group: "Downloads", what: "\(stalePaths.count) files not modified in the last \(staleDays) days.",
                                       afterDelete: "Moved to Trash, so you can still recover them until you empty it.", bytes: staleBytes, fileCount: stalePaths.count, modified: nil,
                                       pathInfo: info.filter { stalePaths.contains($0.key) }))
            }
        }
        return items
    }
}
