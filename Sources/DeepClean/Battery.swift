import Foundation

struct EnergyRow: Identifiable, Hashable, Sendable {
    let pid: Int32
    let name: String
    let path: String
    let power: Double         // Energy Impact, the same figure as Activity Monitor's Energy tab
    var id: Int32 { pid }
}

/// An app bundle and its helpers (or a bare executable) with their combined energy impact.
struct EnergyGroup: Identifiable, Hashable, Sendable {
    static let historyID = "#history"   // list row that shows the battery history instead of an app
    let id: String
    let name: String
    let bundlePath: String?
    var rows: [EnergyRow]
    var power: Double { rows.reduce(0) { $0 + $1.power } }
    static func == (a: EnergyGroup, b: EnergyGroup) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// Energy impact per process from `top` (covers every user's processes without root),
/// grouped by app the same way as the Processes tool. One sample takes about 2 s.
enum EnergySampler {
    static func sample() -> [EnergyGroup] {
        // pid -> full executable path; top truncates names to 16 characters.
        var paths: [Int32: String] = [:]
        for line in run("/bin/ps", ["-axo", "pid=,comm="]).split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            if parts.count == 2, let pid = Int32(parts[0]) { paths[pid] = String(parts[1]) }
        }

        // Two samples one second apart; the first has no delta, so only the second counts.
        let out = run("/usr/bin/top", ["-l", "2", "-s", "1", "-n", "400", "-o", "power", "-stats", "pid,power"])
        guard let last = out.range(of: "PID", options: .backwards) else { return [] }
        var groups: [String: EnergyGroup] = [:]
        for line in out[last.upperBound...].split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2, let pid = Int32(parts[0]), let power = Double(parts[1]), power > 0,
                  let path = paths[pid] else { continue }
            let (key, bundle) = ProcessSampler.groupKey(for: path)
            if groups[key] == nil { groups[key] = EnergyGroup(id: key, name: key, bundlePath: bundle, rows: []) }
            groups[key]!.rows.append(EnergyRow(pid: pid, name: (path as NSString).lastPathComponent, path: path, power: power))
        }
        return groups.values.map { g in
            var g = g
            g.rows.sort { $0.power > $1.power }
            return g
        }
    }

    static func run(_ tool: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

/// One battery reading from the power management log.
struct BatteryReading: Hashable, Sendable {
    let date: Date
    let percent: Int
    let onAC: Bool
}

/// A stretch of time on battery or on power, between two changes of power source.
struct BatterySession: Identifiable, Hashable, Sendable {
    let start: Date
    let end: Date
    let fromPercent: Int
    let toPercent: Int
    let onAC: Bool
    var id: Date { start }
    var hours: Double { end.timeIntervalSince(start) / 3600 }
    /// Percentage points lost per hour; nil for short stretches where the rate is noise.
    var drainPerHour: Double? {
        guard !onAC, hours >= 0.25 else { return nil }
        return Double(fromPercent - toPercent) / hours
    }
}

/// Battery history from `pmset -g log`, which macOS keeps for several days. Every sleep, wake and
/// assertion summary line records the charge and the power source ("Using Batt (Charge:80%)").
enum BatteryHistory {
    static func load() -> [BatteryReading] {
        parse(EnergySampler.run("/usr/bin/pmset", ["-g", "log"]))
    }

    static func parse(_ log: String) -> [BatteryReading] {
        let regex = try! NSRegularExpression(pattern: #"Using (AC|Batt)\s*\(Charge:\s*(\d+)"#, options: .caseInsensitive)
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        var out: [BatteryReading] = []
        for line in log.split(separator: "\n") where line.contains("Charge:") {
            let s = String(line)
            guard s.count > 25, let date = fmt.date(from: String(s.prefix(25))),
                  let m = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                  let src = Range(m.range(at: 1), in: s), let pct = Range(m.range(at: 2), in: s),
                  let percent = Int(s[pct]) else { continue }
            let r = BatteryReading(date: date, percent: percent, onAC: s[src].uppercased() == "AC")
            // Skip repeats so the chart and sessions stay light.
            if let prev = out.last, prev.percent == r.percent, prev.onAC == r.onAC, r.date.timeIntervalSince(prev.date) < 1800 { continue }
            out.append(r)
        }
        return out.sorted { $0.date < $1.date }
    }

    /// Splits readings into stretches on battery and on power, newest first.
    static func sessions(_ readings: [BatteryReading]) -> [BatterySession] {
        var out: [BatterySession] = []
        var i = 0
        while i < readings.count {
            var j = i
            while j + 1 < readings.count, readings[j + 1].onAC == readings[i].onAC { j += 1 }
            // A stretch ends where the next one begins.
            let end = j + 1 < readings.count ? readings[j + 1] : readings[j]
            out.append(BatterySession(start: readings[i].date, end: end.date, fromPercent: readings[i].percent,
                                      toPercent: end.percent, onAC: readings[i].onAC))
            i = j + 1
        }
        return out.reversed()
    }
}
