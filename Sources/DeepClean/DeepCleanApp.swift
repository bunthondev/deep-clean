import SwiftUI

@main
struct DeepCleanApp: App {
    init() {
        if CommandLine.arguments.contains("--cli") {
            CLI.run()
            exit(0)
        }
        if CommandLine.arguments.contains("--apps") {
            CLI.runApps()
            exit(0)
        }
        if CommandLine.arguments.contains("--system") {
            CLI.runSystem()
            exit(0)
        }
        if CommandLine.arguments.contains("--procs") {
            CLI.runProcs()
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup("DeepClean") {
            ContentView()
                .frame(minWidth: 900, minHeight: 540)
        }
        .windowResizability(.contentSize)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

/// `DeepClean --cli` prints the junk scan; `DeepClean --apps` prints storage and the app list. Handy for testing and scripts.
enum CLI {
    static func runProcs() {
        let sampler = ProcessSampler()
        _ = sampler.sample()
        Thread.sleep(forTimeInterval: 2)
        let groups = sampler.sample().sorted { $0.memory > $1.memory }
        let total = groups.reduce(0) { $0 + $1.rows.count }
        let own = groups.reduce(0) { $0 + $1.rows.filter(\.isOwn).count }
        print("\(total) processes (\(own) readable in detail) in \(groups.count) groups\n")
        print(String(format: "%9@  %6@  %4@  %@", "Memory", "CPU", "Procs", "Group"))
        for g in groups.prefix(15) {
            print(String(format: "%9@  %5.1f%%  %4d  %@%@", Format.size(g.memory), g.cpuPercent, g.rows.count, g.name, g.isApp ? "" : "  (not an app bundle)"))
        }
    }

    static func runSystem() {
        let sampler = SystemSampler()
        _ = sampler.sample()
        Thread.sleep(forTimeInterval: 1)
        let s = sampler.sample()
        print("CPU      \(Int(s.cpuPercent.rounded()))%  \(s.cpuName), \(s.cores) cores")
        print("Memory   \(Format.size(s.memoryUsed)) / \(Format.size(s.memoryTotal)), pressure \(s.memoryPressure)")
        if s.hasBattery {
            print("Battery  \(s.batteryPercent)%  charging=\(s.charging) onAC=\(s.onAC) remaining=\(s.minutesRemaining.map(String.init) ?? "-")min health=\(s.healthPercent.map(String.init) ?? "-")% cycles=\(s.cycleCount.map(String.init) ?? "-") temp=\(s.batteryTemperatureC.map { String(format: "%.1f", $0) } ?? "-")C")
        } else { print("Battery  none") }
    }

    static func runApps() {
        let s = StorageInfo.current()
        print("Storage: total \(Format.size(s.total)), used \(Format.size(s.used)), purgeable \(Format.size(s.purgeable)), free \(Format.size(s.available))\n")
        let sem = DispatchSemaphore(value: 0)
        Task.detached {
            var apps: [InstalledApp] = []
            for await a in AppScanner.run() { apps.append(a) }
            apps.sort { $0.bytes > $1.bytes }
            for a in apps.prefix(15) {
                let left = AppScanner.leftovers(for: a)
                let lb = left.reduce(0) { $0 + $1.bytes }
                print(String(format: "%10@  %-32@ %-14@ %@", Format.size(a.bytes), a.name, a.source.rawValue, a.bundleID ?? "-"))
                print("            leftovers: \(left.count) items, \(Format.size(lb))" + (left.isEmpty ? "" : " e.g. " + left.prefix(3).map { $0.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }.joined(separator: ", ")))
            }
            print("\n\(apps.count) apps, \(Format.size(apps.reduce(0) { $0 + $1.bytes }))")
            sem.signal()
        }
        sem.wait()
    }

    static func run() {
        let sem = DispatchSemaphore(value: 0)
        Task.detached {
            var items: [CleanItem] = []
            for await e in Scanner(projectRoots: Scanner.defaultProjectRoots).run() {
                switch e {
                case .status(let s): FileHandle.standardError.write(Data(("… " + s + "\n").utf8))
                case .item(let i): items.append(i)
                case .done: break
                }
            }
            for tier in Tier.allCases {
                let list = items.filter { $0.tier == tier }.sorted { $0.bytes > $1.bytes }
                guard !list.isEmpty else { continue }
                let total = list.reduce(0) { $0 + $1.bytes }
                print("\n== \(tier.title.uppercased()) (\(Format.size(total))) ==")
                for i in list {
                    print(String(format: "%10@  %-45@  %@", Format.size(i.bytes), i.name, i.displayPath))
                    print("            " + i.what)
                }
            }
            print("\nTotal: \(Format.size(items.reduce(0) { $0 + $1.bytes })) in \(items.count) items")
            sem.signal()
        }
        sem.wait()
    }
}
