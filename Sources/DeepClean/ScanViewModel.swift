import Foundation
import AppKit
import SwiftUI

enum Filter: Hashable {
    case all
    case apps
    case processes
    case tier(Tier)
    case group(String)
}

@MainActor
final class ScanViewModel: ObservableObject {
    @Published var items: [CleanItem] = []
    @Published var status = "Press Scan to look for junk. Nothing is deleted without asking."
    @Published var isScanning = false
    @Published var hasScanned = false
    @Published var selection: Set<CleanItem.ID> = []
    @Published var filter: Filter = .all
    @Published var grouping: Grouping = .tier
    @Published var search = ""
    @Published var projectRoots: [URL] = ScanViewModel.loadProjectRoots() {
        didSet { UserDefaults.standard.set(projectRoots.map(\.path), forKey: "projectRoots") }
    }
    /// Largest immediate children of an item, loaded on demand for the detail pane.
    @Published var children: [CleanItem.ID: [ChildStat]] = [:]
    /// Paths ticked in the detail pane's file list of the current aggregate item.
    @Published var pathSelection: Set<String> = []
    /// Folders opened in that tree.
    @Published var expandedFolders: Set<String> = []
    @Published var pendingTrash: [CleanItem]?
    @Published var errorMessage: String?
    @Published var fullDiskAccessMissing = FullDiskAccess.isMissing()
    @Published var storage = StorageInfo.current()
    @Published var system = SystemSnapshot()

    // Processes tool
    @Published var processGroups: [ProcessGroup] = []
    @Published var processSort: ProcessSort = .memory
    @Published var processSearch = ""
    @Published var selectedProcessGroupID: ProcessGroup.ID?
    @Published var pendingForceQuit: ProcessGroup?
    private let processSampler = ProcessSampler()
    private var processTimer: Task<Void, Never>?
    private let sampler = SystemSampler()
    private var systemTimer: Task<Void, Never>?

    init() {
        _ = sampler.sample()  // prime the CPU tick counter so the first visible reading is a real delta
        systemTimer = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let snap = await Task.detached { [sampler = self.sampler] in sampler.sample() }.value
                self.system = snap
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // Applications tool
    @Published var apps: [InstalledApp] = []
    @Published var isScanningApps = false
    @Published var selectedAppID: InstalledApp.ID?
    @Published var appSearch = ""
    @Published var leftovers: [InstalledApp.ID: [Leftover]] = [:]
    private var appTask: Task<Void, Never>?
    private var leftoverTasks: [InstalledApp.ID: Task<Void, Never>] = [:]

    private var task: Task<Void, Never>?
    private var childTasks: [CleanItem.ID: Task<Void, Never>] = [:]

    nonisolated static func loadProjectRoots() -> [URL] {
        if let saved = UserDefaults.standard.stringArray(forKey: "projectRoots") {
            let urls = Scanner.normalizeRoots(saved.map { URL(fileURLWithPath: $0) })
            if !urls.isEmpty { return urls }
        }
        return Scanner.defaultProjectRoots
    }

    // MARK: Selection

    var selectedItems: [CleanItem] {
        items.filter { selection.contains($0.id) }.sorted { $0.bytes > $1.bytes }
    }
    var selected: CleanItem? { selection.count == 1 ? selectedItems.first : nil }
    /// Selected items that may be trashed (personal data is report-only).
    var trashableSelection: [CleanItem] { selectedItems.filter { $0.tier != .personal } }

    func selectAllVisible(tier: Tier? = nil, group: String? = nil) {
        selection = Set(filtered.filter { (tier == nil || $0.tier == tier) && (group == nil || $0.group == group) && $0.tier != .personal }.map(\.id))
    }

    // MARK: Filtering

    /// Group names ordered by total size, biggest first.
    var groups: [String] {
        var totals: [String: Int64] = [:]
        for i in items { totals[i.group, default: 0] += i.bytes }
        return totals.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map(\.key)
    }
    func bytes(forGroup g: String) -> Int64 { items.filter { $0.group == g }.reduce(0) { $0 + $1.bytes } }

    var filtered: [CleanItem] {
        var list = items
        switch filter {
        case .all: break
        case .apps, .processes: return []
        case .tier(let t): list = list.filter { $0.tier == t }
        case .group(let g): list = list.filter { $0.group == g }
        }
        if !search.isEmpty {
            let q = search.lowercased()
            list = list.filter { $0.name.lowercased().contains(q) || $0.path.lowercased().contains(q) || $0.group.lowercased().contains(q) }
        }
        return list.sorted { $0.bytes > $1.bytes }
    }

    func bytes(for tier: Tier) -> Int64 { items.filter { $0.tier == tier }.reduce(0) { $0 + $1.bytes } }
    var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }

    // MARK: Scanning

    func scan() {
        guard !isScanning else { return }
        items = []
        selection = []
        children = [:]
        isScanning = true
        refreshStorage()
        fullDiskAccessMissing = FullDiskAccess.isMissing()
        let scanner = Scanner(projectRoots: projectRoots)
        task = Task {
            for await event in scanner.run() {
                switch event {
                case .status(let s): status = s
                case .item(let item): if !items.contains(where: { $0.id == item.id }) { items.append(item) }
                case .done: break
                }
            }
            isScanning = false
            hasScanned = true
            status = "\(items.count) items, \(Format.size(totalBytes)) found"
        }
    }

    func refreshStorage() { storage = StorageInfo.current() }

    func cancel() {
        task?.cancel()
        task = nil
        isScanning = false
        status = "Scan stopped"
    }

    // MARK: Actions

    func reveal(_ item: CleanItem) {
        let urls = item.paths.prefix(1).map { URL(fileURLWithPath: $0) }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func askToTrash(_ items: [CleanItem]) {
        let list = items.filter { $0.tier != .personal }
        guard !list.isEmpty else { return }
        pendingTrash = list
    }

    /// Moves every path of every item to Trash (recoverable). Called only after the user confirms.
    func trash(_ list: [CleanItem]) {
        let total = list.reduce(0) { $0 + $1.bytes }
        status = "Moving \(list.count == 1 ? list[0].name : "\(list.count) items") to Trash…"
        // Files picked out of an aggregate: remember the aggregate's root so subfolders they
        // leave empty can be trashed too (e.g. the user ticked a whole subfolder of Downloads).
        var cleanupRoot: [String: String] = [:]
        for child in list where child.id.hasPrefix("child:") {
            if let parent = items.first(where: { $0.isAggregate && $0.paths.contains(child.path) }) {
                cleanupRoot[child.path] = PathNode.commonRoot(of: parent.paths)
            }
        }
        Task.detached(priority: .userInitiated) {
            var done: [CleanItem.ID] = []
            var collected: [String] = []
            for item in list {
                var ok = true
                for p in item.paths {
                    do { try FileManager.default.trashItem(at: URL(fileURLWithPath: p), resultingItemURL: nil) }
                    catch let first as NSError where first.code == NSFileWriteNoPermissionError || first.code == NSFileReadNoPermissionError {
                        // Not ours to move directly (root-owned). Let Finder ask for an admin password.
                        await MainActor.run { self.status = "Finder is asking for permission to move \(item.name)…" }
                        do { try await MainActor.run { try FinderTrash.trash(p) } }
                        catch { ok = false; collected.append("\(p): \(error.localizedDescription)") }
                    }
                    catch { ok = false; collected.append("\(p): \(error.localizedDescription)") }
                }
                if ok { done.append(item.id) }
            }
            // Trash subfolders emptied by the moves above, innermost first, never the root itself.
            var emptied: Set<String> = []
            for (path, root) in cleanupRoot where done.contains("child:" + path) {
                var dir = (path as NSString).deletingLastPathComponent
                while dir.hasPrefix(root + "/"), !emptied.contains(dir) {
                    let left = (try? FileManager.default.contentsOfDirectory(atPath: dir))?.filter { $0 != ".DS_Store" } ?? ["?"]
                    guard left.isEmpty else { break }
                    if (try? FileManager.default.trashItem(at: URL(fileURLWithPath: dir), resultingItemURL: nil)) == nil { break }
                    emptied.insert(dir)
                    dir = (dir as NSString).deletingLastPathComponent
                }
            }
            let removed = Set(done), failures = collected
            await MainActor.run {
                self.items.removeAll { removed.contains($0.id) }
                self.apps.removeAll { removed.contains("app:" + $0.path) }
                for app in self.apps where self.leftovers[app.id] != nil {
                    self.leftovers[app.id]?.removeAll { removed.contains("leftover:" + $0.path) }
                }
                self.refreshStorage()
                for child in list where child.id.hasPrefix("child:") && removed.contains(child.id) {
                    for (parentID, kids) in self.children where kids.contains(where: { $0.path == child.path }) {
                        self.children[parentID] = kids.filter { $0.path != child.path }
                        if let i = self.items.firstIndex(where: { $0.id == parentID }) {
                            self.items[i].bytes = max(0, self.items[i].bytes - child.bytes)
                        }
                    }
                }
                // A single path trashed out of an aggregate: drop it from the parent's list too.
                let trashedPaths = Set(list.filter { $0.id.hasPrefix("child:") && removed.contains($0.id) }.flatMap(\.paths))
                if !trashedPaths.isEmpty {
                    for i in self.items.indices where self.items[i].isAggregate {
                        let before = self.items[i].paths.count
                        self.items[i].paths.removeAll { trashedPaths.contains($0) }
                        let gone = before - self.items[i].paths.count
                        if gone > 0 {
                            self.items[i].fileCount = max(0, self.items[i].fileCount - gone)
                            let freed = trashedPaths.reduce(Int64(0)) { $0 + (self.items[i].pathInfo[$1]?.bytes ?? 0) }
                            self.items[i].bytes = max(0, self.items[i].bytes - freed)
                            for p in trashedPaths { self.items[i].pathInfo[p] = nil }
                        }
                    }
                    self.items.removeAll { $0.paths.isEmpty }
                    self.pathSelection.subtract(trashedPaths)
                }
                self.selection.subtract(removed)
                for id in removed { self.children[id] = nil }
                if failures.isEmpty {
                    self.status = "Moved \(removed.count) item\(removed.count == 1 ? "" : "s") (\(Format.size(total))) to Trash"
                } else {
                    self.status = "\(removed.count) moved, \(failures.count) failed"
                    self.errorMessage = failures.prefix(5).joined(separator: "\n")
                }
            }
        }
    }

    func removeProjectRoot(_ url: URL) {
        projectRoots.removeAll { $0 == url }
    }

    /// Sizes the immediate children of a single-path item, biggest first. Cached per item.
    func loadChildren(for item: CleanItem) {
        guard !item.isAggregate, children[item.id] == nil, childTasks[item.id] == nil else { return }
        let url = URL(fileURLWithPath: item.path)
        childTasks[item.id] = Task.detached(priority: .userInitiated) {
            let stats = ChildStat.list(of: url)
            await MainActor.run {
                self.children[item.id] = stats
                self.childTasks[item.id] = nil
            }
        }
    }

    func chooseProjectRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.message = "Choose folders that contain your code projects"
        if panel.runModal() == .OK {
            projectRoots = Scanner.normalizeRoots(projectRoots + panel.urls)
        }
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Full Disk Access detection: a few folders under ~/Library are protected by macOS privacy
/// controls and fail to list with EPERM until the user grants access in System Settings.
enum FullDiskAccess {
    static let probes = ["Library/Mail", "Library/Safari", "Library/Messages"]

    static func isMissing() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        for p in probes {
            let url = home.appendingPathComponent(p)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do { _ = try FileManager.default.contentsOfDirectory(atPath: url.path); return false }
            catch let e as NSError where e.code == NSFileReadNoPermissionError || (e.underlyingErrors.first as NSError?)?.code == Int(EPERM) {
                return true
            } catch { continue }
        }
        return false
    }
}

enum Grouping: String, CaseIterable, Identifiable {
    case tier, kind
    var id: String { rawValue }
    var title: String { self == .tier ? "Safety" : "Kind" }
}

// MARK: - Applications tool

extension ScanViewModel {
    var selectedApp: InstalledApp? { apps.first { $0.id == selectedAppID } }

    var filteredApps: [InstalledApp] {
        let q = appSearch.lowercased()
        return apps
            .filter { q.isEmpty || $0.name.lowercased().contains(q) || ($0.bundleID?.lowercased().contains(q) ?? false) }
            .sorted { $0.bytes > $1.bytes }
    }

    var appsTotalBytes: Int64 { apps.reduce(0) { $0 + $1.bytes } }

    func scanApps() {
        guard !isScanningApps else { return }
        apps = []
        leftovers = [:]
        selectedAppID = nil
        isScanningApps = true
        appTask = Task {
            for await app in AppScanner.run() { apps.append(app) }
            isScanningApps = false
        }
    }

    func loadLeftovers(for app: InstalledApp) {
        guard leftovers[app.id] == nil, leftoverTasks[app.id] == nil else { return }
        leftoverTasks[app.id] = Task.detached(priority: .userInitiated) {
            let found = AppScanner.leftovers(for: app)
            await MainActor.run {
                self.leftovers[app.id] = found
                self.leftoverTasks[app.id] = nil
            }
        }
    }

    /// Asks to move the app bundle and the chosen leftovers to Trash. Goes through the same
    /// confirmation and trash path as everything else.
    func askToUninstall(_ app: InstalledApp, leftovers chosen: [Leftover], includeApp: Bool) {
        var list: [CleanItem] = []
        if includeApp {
            list.append(CleanItem(id: "app:" + app.path, name: app.name, paths: [app.path], tier: .review, group: "Applications",
                                  what: "The application bundle.", afterDelete: "Reinstall from \(app.source.rawValue.lowercased()) or the developer's site.",
                                  bytes: app.bytes, fileCount: 0, modified: app.lastUsed))
        }
        for l in chosen {
            list.append(CleanItem(id: "leftover:" + l.path, name: "\(app.name) \(l.kind)", paths: [l.path], tier: .review, group: "Applications",
                                  what: "\(l.kind) left behind by \(app.name).", afterDelete: "Settings or cached data for \(app.name) are gone.",
                                  bytes: l.bytes, fileCount: 0, modified: nil))
        }
        guard !list.isEmpty else { return }
        pendingTrash = list
    }
}

/// Fallback for files the current user cannot move (root-owned apps from pkg installers):
/// ask Finder to do it. Finder shows the standard admin-password prompt and still moves the
/// item to the Trash, so the result is just as reversible.
enum FinderTrash {
    @MainActor
    static func trash(_ path: String) throws {
        let escaped = path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = "tell application \"Finder\" to delete (POSIX file \"\(escaped)\" as alias)"
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw NSError(domain: "DeepClean.FinderTrash", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not build the Finder script."])
        }
        script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? -1
            var msg = errorInfo[NSAppleScript.errorMessage] as? String ?? "Finder refused."
            if code == -1743 { msg = "DeepClean is not allowed to control Finder. Allow it in System Settings > Privacy & Security > Automation." }
            if code == -128 { msg = "Cancelled." }
            throw NSError(domain: "DeepClean.FinderTrash", code: code, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }
}

enum ProcessSort: String, CaseIterable { case memory, cpu }

// MARK: - Processes tool

extension ScanViewModel {
    var sortedProcessGroups: [ProcessGroup] {
        let q = processSearch.lowercased()
        let list = processGroups.filter { q.isEmpty || $0.name.lowercased().contains(q) || $0.rows.contains { $0.name.lowercased().contains(q) } }
        switch processSort {
        case .memory: return list.sorted { $0.memory > $1.memory }
        case .cpu: return list.sorted { $0.cpuPercent == $1.cpuPercent ? $0.memory > $1.memory : $0.cpuPercent > $1.cpuPercent }
        }
    }

    var selectedProcessGroup: ProcessGroup? { processGroups.first { $0.id == selectedProcessGroupID } }

    var processCount: Int { processGroups.reduce(0) { $0 + $1.rows.count } }

    func memoryShare(of g: ProcessGroup) -> Double? {
        system.memoryUsed > 0 ? Double(g.memory) / Double(system.memoryUsed) : nil
    }

    /// Sampling runs only while the Processes view is showing, every 3 s.
    func setProcessSampling(active: Bool) {
        if active {
            guard processTimer == nil else { return }
            processTimer = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    let groups = await Task.detached { [sampler = self.processSampler] in sampler.sample() }.value
                    if Task.isCancelled { return }
                    self.processGroups = groups
                    try? await Task.sleep(for: .seconds(3))
                }
            }
        } else {
            processTimer?.cancel()
            processTimer = nil
        }
    }

    func sampleProcessesNow() {
        Task { [weak self] in
            guard let self else { return }
            let groups = await Task.detached { [sampler = self.processSampler] in sampler.sample() }.value
            self.processGroups = groups
        }
    }

    func quit(_ group: ProcessGroup, force: Bool) {
        let failures = ProcessSampler.quit(group, force: force)
        if failures.isEmpty {
            status = force ? "Force quit \(group.name)" : "Asked \(group.name) to quit"
        } else {
            errorMessage = failures.joined(separator: "\n")
        }
        Task { try? await Task.sleep(for: .seconds(1)); sampleProcessesNow() }
    }
}

extension ScanViewModel {
    /// Selection bindings that write on the next run-loop turn. Writing a published value
    /// synchronously inside a List selection callback re-enters NSTableView while it is still
    /// handling the click, which AppKit warns about and which can leave columns blank.
    var processSelection: Binding<ProcessGroup.ID?> {
        Binding(get: { self.selectedProcessGroupID }, set: { v in DispatchQueue.main.async { self.selectedProcessGroupID = v } })
    }
    var appSelection: Binding<InstalledApp.ID?> {
        Binding(get: { self.selectedAppID }, set: { v in DispatchQueue.main.async { self.selectedAppID = v } })
    }
    var itemSelection: Binding<Set<CleanItem.ID>> {
        Binding(get: { self.selection }, set: { v in DispatchQueue.main.async { self.selection = v } })
    }
}
