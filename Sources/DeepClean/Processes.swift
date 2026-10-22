import Foundation
import AppKit
import Darwin

struct ProcessRow: Identifiable, Hashable, Sendable {
    let pid: Int32
    let ppid: Int32
    let user: String
    let name: String          // executable name
    let path: String
    var cpuPercent: Double    // of one core; 100 = one core fully busy
    var memory: Int64         // phys footprint for own processes, RSS for others
    let isOwn: Bool           // readable through libproc (same user)
    var id: Int32 { pid }
}

/// Processes that belong together: an app bundle and all its helpers, or a bare executable.
struct ProcessGroup: Identifiable, Hashable, Sendable {
    let id: String            // app name or executable name
    let name: String
    let bundlePath: String?   // for the icon
    var rows: [ProcessRow]
    var cpuPercent: Double { rows.reduce(0) { $0 + $1.cpuPercent } }
    var memory: Int64 { rows.reduce(0) { $0 + $1.memory } }
    var isApp: Bool { bundlePath != nil }
    static func == (a: ProcessGroup, b: ProcessGroup) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// Samples all processes. Own processes: libproc (footprint + CPU time deltas, like Activity Monitor).
/// Other users' processes (system daemons): one `ps` call per sample for RSS and %CPU.
final class ProcessSampler: @unchecked Sendable {
    private var lastCPUTime: [Int32: (ns: UInt64, at: TimeInterval)] = [:]

    func sample() -> [ProcessGroup] {
        let now = Date().timeIntervalSinceReferenceDate
        var rows: [Int32: ProcessRow] = [:]

        // 1. Everything from ps: pid, ppid, user, %cpu, rss, command path.
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-axo", "pid=,ppid=,user=,%cpu=,rss=,comm="]
        let pipe = Pipe()
        ps.standardOutput = pipe
        ps.standardError = FileHandle.nullDevice
        if (try? ps.run()) != nil {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            ps.waitUntilExit()
            for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                let parts = line.split(separator: " ", maxSplits: 5, omittingEmptySubsequences: true)
                guard parts.count == 6, let pid = Int32(parts[0]), let ppid = Int32(parts[1]),
                      let cpu = Double(parts[3]), let rssKB = Int64(parts[4]) else { continue }
                let path = String(parts[5])
                rows[pid] = ProcessRow(pid: pid, ppid: ppid, user: String(parts[2]), name: (path as NSString).lastPathComponent,
                                       path: path, cpuPercent: cpu, memory: rssKB * 1024, isOwn: false)
            }
        }

        // 2. Overlay accurate numbers for processes we may inspect.
        var seen = Set<Int32>()
        for pid in Array(rows.keys) {
            var ru = rusage_info_v4()
            let r = withUnsafeMutablePointer(to: &ru) { p in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, UnsafeMutableRawPointer(p).assumingMemoryBound(to: rusage_info_t?.self))
            }
            guard r == 0, var row = rows[pid] else { continue }
            seen.insert(pid)
            row.memory = Int64(ru.ri_phys_footprint)
            let cpuNS = ru.ri_user_time + ru.ri_system_time
            if let last = lastCPUTime[pid], now > last.at, cpuNS >= last.ns {
                row.cpuPercent = Double(cpuNS - last.ns) / ((now - last.at) * 1e9) * 100
            } else {
                row.cpuPercent = 0
            }
            lastCPUTime[pid] = (cpuNS, now)
            rows[pid] = ProcessRow(pid: row.pid, ppid: row.ppid, user: row.user, name: row.name, path: row.path,
                                   cpuPercent: row.cpuPercent, memory: row.memory, isOwn: true)
        }
        lastCPUTime = lastCPUTime.filter { seen.contains($0.key) }

        // 3. Group by app bundle (first ".app" path component) or executable name.
        var groups: [String: ProcessGroup] = [:]
        for row in rows.values {
            let (key, bundle) = Self.groupKey(for: row.path)
            if groups[key] == nil { groups[key] = ProcessGroup(id: key, name: key, bundlePath: bundle, rows: []) }
            groups[key]!.rows.append(row)
        }
        return groups.values.map { g in
            var g = g
            g.rows.sort { $0.memory > $1.memory }
            return g
        }
    }

    static func groupKey(for path: String) -> (String, String?) {
        let comps = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if let i = comps.firstIndex(where: { $0.hasSuffix(".app") }) {
            let name = String(comps[i].dropLast(4))
            let bundle = comps[0...i].joined(separator: "/")
            return (name, bundle)
        }
        // Some processes rewrite their title to a whole command line ("npm exec foo --bar"); keep the first word.
        let first = path.split(separator: " ", maxSplits: 1).first.map(String.init) ?? path
        return ((first as NSString).lastPathComponent, nil)
    }

    // MARK: Quitting

    /// Graceful quit: apps through AppKit, others with SIGTERM. Force: SIGKILL.
    static func quit(_ group: ProcessGroup, force: Bool) -> [String] {
        var failures: [String] = []
        let running = NSWorkspace.shared.runningApplications
        var handled = Set<Int32>()
        if let bundle = group.bundlePath {
            for app in running where app.bundleURL?.path == bundle {
                let ok = force ? app.forceTerminate() : app.terminate()
                if !ok { failures.append("\(app.localizedName ?? group.name) did not accept the request") }
                handled.insert(app.processIdentifier)
            }
        }
        // Helpers die with their parent; only signal what AppKit did not cover (and only our own).
        for row in group.rows where !handled.contains(row.pid) && row.isOwn && group.bundlePath == nil {
            if kill(row.pid, force ? SIGKILL : SIGTERM) != 0 {
                failures.append("\(row.name) (\(row.pid)): \(String(cString: strerror(errno)))")
            }
        }
        if group.bundlePath != nil && handled.isEmpty {
            // Bundle not registered with AppKit (e.g. a command-line tool inside a .app): signal directly.
            for row in group.rows where row.isOwn {
                if kill(row.pid, force ? SIGKILL : SIGTERM) != 0 {
                    failures.append("\(row.name) (\(row.pid)): \(String(cString: strerror(errno)))")
                }
            }
        }
        return failures
    }
}
