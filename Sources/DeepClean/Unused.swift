import Foundation
import CoreServices

/// The kinds of things the Unused tool lists.
enum UnusedKind: Int, CaseIterable, Identifiable, Sendable {
    case projects, apps, databases, files

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .projects: return "Projects"
        case .apps: return "Apps"
        case .databases: return "Databases"
        case .files: return "Large files"
        }
    }

    var symbol: String {
        switch self {
        case .projects: return "folder.fill"
        case .apps: return "app.fill"
        case .databases: return "cylinder.split.1x2.fill"
        case .files: return "doc.fill"
        }
    }

    /// How the "last used" date is measured, in plain words for the detail pane.
    var howMeasured: String {
        switch self {
        case .projects: return "The newest change to any file in the project. Dependencies, build output, .git and .DS_Store are ignored, so installing or browsing does not count."
        case .apps: return "When macOS last recorded the app being opened. Apps never opened count from the day they were installed."
        case .databases: return "The last time Postgres wrote to the database's files. Only reading data does not update it."
        case .files: return "The later of the last change and the last time macOS recorded the file being opened."
        }
    }
}

/// One project, app, database or file and when it was last used.
struct UnusedItem: Identifiable, Hashable, Sendable {
    let kind: UnusedKind
    let name: String
    /// Folder, file or app bundle. For a database, its folder inside the Postgres data directory.
    let path: String
    /// One line under the name, e.g. "Downloaded · v2.1" or "Postgres 15 · var-15".
    let detail: String
    let bytes: Int64
    /// The date the "unused for" check uses. nil when unknown.
    let lastUsed: Date?
    /// Label for `lastUsed`, e.g. "Last opened", "Never opened, installed".
    let dateLabel: String

    var id: String { "\(kind.rawValue):\(path)" }
    /// Databases are report-only: deleting their files would corrupt the Postgres cluster.
    var canTrash: Bool { kind != .databases }

    var daysUnused: Int? { lastUsed.map { max(0, Int(Date().timeIntervalSince($0) / 86_400)) } }
    /// Unknown dates count as unused, so nothing is hidden for lack of data.
    func isUnused(days: Int) -> Bool { daysUnused.map { $0 >= days } ?? true }

    var displayPath: String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    static func == (a: UnusedItem, b: UnusedItem) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

enum UnusedEvent: Sendable {
    case status(String)
    case item(UnusedItem)
}

/// Finds projects, apps, local databases and large files with the date each was last used.
/// Read-only: databases are read from Postgres's catalog file on disk, without connecting.
struct UnusedScanner: Sendable {
    let projectRoots: [URL]
    let largeFileThreshold: Int64 = 100_000_000
    let maxConcurrent = 6

    static let home = FileManager.default.homeDirectoryForCurrentUser

    func run() -> AsyncStream<UnusedEvent> {
        AsyncStream { cont in
            let task = Task.detached(priority: .userInitiated) {
                await self.scan { cont.yield($0) }
                cont.finish()
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }

    private func scan(_ emit: @Sendable @escaping (UnusedEvent) -> Void) async {
        emit(.status("Reading local databases…"))
        for item in Self.databases() {
            if Task.isCancelled { return }
            emit(.item(item))
        }

        emit(.status("Checking when apps were last opened…"))
        for await app in AppScanner.run() {
            if Task.isCancelled { return }
            emit(.item(Self.unusedApp(app)))
        }

        emit(.status("Finding projects…"))
        var projects: [URL] = []
        for root in Scanner.normalizeRoots(projectRoots) { Self.findProjects(in: root, depth: 0, into: &projects) }
        emit(.status("Sizing \(projects.count) projects…"))
        await withTaskGroup(of: UnusedItem?.self) { group in
            var running = 0
            for p in projects {
                if Task.isCancelled { break }
                if running >= maxConcurrent { if let i = await group.next() ?? nil { emit(.item(i)) }; running -= 1 }
                group.addTask { Self.project(p) }
                running += 1
            }
            for await i in group { if let i { emit(.item(i)) } }
        }
        if Task.isCancelled { return }

        emit(.status("Looking for large files in your home folder…"))
        for item in largeFiles() {
            if Task.isCancelled { return }
            emit(.item(item))
        }
    }

    // MARK: Apps

    static func unusedApp(_ app: InstalledApp) -> UnusedItem {
        var date = app.lastUsed
        var label = "Last opened"
        if date == nil {
            label = "Never opened, installed"
            if let md = MDItemCreate(kCFAllocatorDefault, app.path as CFString) {
                date = MDItemCopyAttribute(md, kMDItemDateAdded) as? Date
            }
            if date == nil { date = (try? URL(fileURLWithPath: app.path).resourceValues(forKeys: [.creationDateKey]))?.creationDate }
        }
        let detail = [app.source.rawValue, app.version.map { "v\($0)" }].compactMap { $0 }.joined(separator: " · ")
        return UnusedItem(kind: .apps, name: app.name, path: app.path, detail: detail, bytes: app.bytes, lastUsed: date, dateLabel: label)
    }

    // MARK: Projects

    static let projectMarkers: Set<String> = [
        ".git", "package.json", "Cargo.toml", "go.mod", "pyproject.toml", "requirements.txt", "setup.py",
        "composer.json", "Package.swift", "pom.xml", "build.gradle", "build.gradle.kts", "Gemfile",
        "pubspec.yaml", "CMakeLists.txt", "docker-compose.yml", "deno.json",
    ]

    /// Folders skipped when looking for the newest change: they change without you working on the project.
    static let generatedNames: Set<String> = Catalog.artifactNames.union(["node_modules", ".git", "vendor", "Pods"])

    /// A project is the first folder below a root that holds a project marker. The roots themselves
    /// are containers, never projects.
    static func findProjects(in dir: URL, depth: Int, into out: inout [URL]) {
        guard depth <= 4 else { return }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
        guard let kids = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: []) else { return }
        if depth > 0 {
            let names = Set(kids.map(\.lastPathComponent))
            if !names.isDisjoint(with: projectMarkers) || kids.contains(where: { $0.pathExtension == "xcodeproj" }) {
                out.append(dir)
                return
            }
        }
        for k in kids {
            let name = k.lastPathComponent
            guard !name.hasPrefix("."), name != "node_modules", name != "Library",
                  let v = try? k.resourceValues(forKeys: Set(keys)), v.isDirectory == true, v.isSymbolicLink != true, v.isPackage != true else { continue }
            findProjects(in: k, depth: depth + 1, into: &out)
        }
    }

    static func project(_ url: URL) -> UnusedItem? {
        let size = DiskSize.stats(of: url, isCancelled: { Task.isCancelled })
        guard size.bytes > 0 else { return nil }
        let newest = newestChange(in: url)
        let parent = url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        return UnusedItem(kind: .projects, name: url.lastPathComponent, path: url.path, detail: "in \(parent)",
                          bytes: size.bytes, lastUsed: newest, dateLabel: "Last changed")
    }

    /// Newest modification date of any file in `url`, skipping generated and hidden folders and .DS_Store.
    static func newestChange(in url: URL) -> Date? {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .contentModificationDateKey]
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants],
                                                     errorHandler: { _, _ in true }) else { return nil }
        var newest: Date?
        var n = 0
        for case let f as URL in e {
            n += 1
            if n & 0x3FF == 0, Task.isCancelled { break }
            let name = f.lastPathComponent
            guard let v = try? f.resourceValues(forKeys: keys) else { continue }
            if v.isDirectory == true {
                if name.hasPrefix(".") || generatedNames.contains(name) { e.skipDescendants() }
                continue
            }
            guard v.isRegularFile == true, name != ".DS_Store", let d = v.contentModificationDate else { continue }
            if newest == nil || d > newest! { newest = d }
        }
        return newest
    }

    // MARK: Large files

    /// Files over the threshold anywhere in the home folder except Library, hidden folders and
    /// dependency or build folders (those are covered by the junk scan).
    func largeFiles() -> [UnusedItem] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .contentModificationDateKey]
        guard let e = FileManager.default.enumerator(at: Self.home, includingPropertiesForKeys: Array(keys),
                                                     options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in true }) else { return [] }
        var out: [UnusedItem] = []
        var n = 0
        for case let f as URL in e {
            n += 1
            if n & 0x3FF == 0, Task.isCancelled { break }
            guard let v = try? f.resourceValues(forKeys: keys) else { continue }
            let name = f.lastPathComponent
            if v.isDirectory == true {
                if (e.level == 1 && name == "Library") || Self.generatedNames.contains(name) { e.skipDescendants() }
                continue
            }
            guard v.isRegularFile == true else { continue }
            let bytes = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            guard bytes >= largeFileThreshold else { continue }
            var date = v.contentModificationDate
            if let md = MDItemCreate(kCFAllocatorDefault, f.path as CFString), let opened = MDItemCopyAttribute(md, kMDItemLastUsedDate) as? Date {
                date = max(date ?? opened, opened)
            }
            let folder = f.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
            out.append(UnusedItem(kind: .files, name: name, path: f.path, detail: "in \(folder)", bytes: bytes,
                                  lastUsed: date, dateLabel: "Last opened or changed"))
        }
        return out
    }

    // MARK: Databases

    /// Postgres data directories in the usual places (Postgres.app and Homebrew).
    static var postgresClusters: [URL] {
        var candidates: [URL] = []
        let fm = FileManager.default
        let pgApp = home.appendingPathComponent("Library/Application Support/Postgres")
        for name in (try? fm.contentsOfDirectory(atPath: pgApp.path)) ?? [] where name.hasPrefix("var-") {
            candidates.append(pgApp.appendingPathComponent(name))
        }
        for base in ["/opt/homebrew/var", "/usr/local/var"] {
            for name in (try? fm.contentsOfDirectory(atPath: base)) ?? [] where name.hasPrefix("postgres") {
                candidates.append(URL(fileURLWithPath: base).appendingPathComponent(name))
            }
        }
        return candidates.filter { fm.fileExists(atPath: $0.appendingPathComponent("PG_VERSION").path) }
    }

    static func databases() -> [UnusedItem] {
        var out: [UnusedItem] = []
        for cluster in postgresClusters {
            let version = (try? String(contentsOf: cluster.appendingPathComponent("PG_VERSION"), encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "?"
            let running = FileManager.default.fileExists(atPath: cluster.appendingPathComponent("postmaster.pid").path)
            let detail = "Postgres \(version) · \(cluster.lastPathComponent) · \(running ? "server running" : "server stopped")"
            for (oid, name) in PostgresCatalog.databases(in: cluster) where name != "template0" && name != "template1" {
                if Task.isCancelled { return out }
                let dir = cluster.appendingPathComponent("base/\(oid)")
                guard FileManager.default.fileExists(atPath: dir.path) else { continue }
                let size = DiskSize.stats(of: dir, isCancelled: { Task.isCancelled })
                out.append(UnusedItem(kind: .databases, name: name, path: dir.path, detail: detail, bytes: size.bytes,
                                      lastUsed: newestFile(in: dir), dateLabel: "Last written"))
            }
        }
        return out
    }

    private static func newestFile(in dir: URL) -> Date? {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [])) ?? []
        return files.compactMap { try? $0.resourceValues(forKeys: Set(keys)).contentModificationDate }.max()
    }
}

/// Reads database names from a Postgres cluster's `pg_database` catalog file (global/1262) without
/// a server connection. Only the first two columns are used (oid, datname), which keep the same
/// layout from Postgres 12 on.
enum PostgresCatalog {
    static func databases(in cluster: URL) -> [(oid: UInt32, name: String)] {
        guard let data = try? Data(contentsOf: cluster.appendingPathComponent("global/1262")) else { return [] }
        let page = 8192
        var live: [UInt32: String] = [:]
        var stale: [UInt32: String] = [:]
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            func u16(_ o: Int) -> Int { Int(raw.loadUnaligned(fromByteOffset: o, as: UInt16.self).littleEndian) }
            func u32(_ o: Int) -> UInt32 { raw.loadUnaligned(fromByteOffset: o, as: UInt32.self).littleEndian }
            var p = 0
            while p + page <= raw.count {
                let lower = u16(p + 12)
                var lp = p + 24
                while lp + 4 <= p + min(lower, page) {
                    let w = u32(lp)
                    lp += 4
                    let off = Int(w & 0x7FFF), flags = (w >> 15) & 3, len = Int(w >> 17)
                    guard flags == 1, len >= 24 + 68, off + len <= page else { continue }
                    let t = p + off
                    let xmax = u32(t + 4)
                    let infomask = u16(t + 20)
                    let hoff = Int(raw[t + 22])
                    guard hoff + 68 <= len else { continue }
                    let oid = u32(t + hoff)
                    let nameBytes = UnsafeRawBufferPointer(rebasing: raw[(t + hoff + 4)..<(t + hoff + 68)])
                    let name = String(decoding: nameBytes.prefix { $0 != 0 }, as: UTF8.self)
                    guard !name.isEmpty else { continue }
                    // xmax unset: the current row. Otherwise an old version left by a rename or drop.
                    if xmax == 0 || infomask & 0x0800 != 0 { live[oid] = name } else { stale[oid] = name }
                }
                p += page
            }
        }
        for (oid, name) in stale where live[oid] == nil { live[oid] = name }
        return live.map { (oid: $0.key, name: $0.value) }.sorted { $0.name < $1.name }
    }
}
