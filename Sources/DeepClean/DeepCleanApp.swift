import SwiftUI

/// Quit when the window closes. A single-window utility has nothing to do in the Dock without it.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct DeepCleanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        if CommandLine.arguments.contains("--cli") {
            CLI.run()
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--self-update"), i + 1 < CommandLine.arguments.count {
            CLI.runSelfUpdate(CommandLine.arguments[i + 1])
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
        if CommandLine.arguments.contains("--update-check") {
            CLI.runUpdateCheck()
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup("DeepClean") {
            ContentView()
                .frame(minWidth: 900, minHeight: 540)
                .task {
                    guard ProcessInfo.processInfo.environment["DEEPCLEAN_DEBUG"] == nil else { return }
                    try? await Task.sleep(for: .seconds(5))
                    Updater.checkQuietlyIfDue()
                }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Updater.checkInteractively() }
            }
        }
    }
}

/// `DeepClean --cli` prints the junk scan; `DeepClean --apps` prints storage and the app list. Handy for testing and scripts.
enum CLI {
    /// `--self-update <zip url or path>`: installs that zip (its `.sig` must sit beside it) over this
    /// bundle and relaunches. For testing the installer.
    static func runSelfUpdate(_ arg: String) {
        setvbuf(stdout, nil, _IONBF, 0)
        let url = arg.hasPrefix("http") || arg.hasPrefix("file:") ? URL(string: arg)! : URL(fileURLWithPath: arg)
        let sig = URL(string: url.absoluteString + ".sig")!
        let sem = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                let app = try await Installer.install(zip: url, sig: sig, expectedVersion: nil) { print("… \($0)") }
                print("installed at \(app.path)")
                Installer.relaunch(app)
            } catch { print("install failed: \(error.localizedDescription)"); exit(1) }
            sem.signal()
        }
        sem.wait()
    }

    /// `--update-check`: prints the running and latest versions, exit code 1 when an update exists.
    static func runUpdateCheck() {
        let sem = DispatchSemaphore(value: 0)
        var newer = false
        Task.detached {
            do {
                let r = try await Updater.fetchLatest()
                newer = Updater.isNewer(r.version, than: Updater.currentVersion)
                print("installed \(Updater.currentVersion), latest \(r.version) -> \(newer ? "update available" : "up to date")")
                print("page: \(r.page)"); if let z = r.zip { print("zip:  \(z)") }
            } catch { print("check failed: \(error.localizedDescription)") }
            sem.signal()
        }
        sem.wait()
        if newer { exit(1) }
    }

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
            for await e in Scanner(projectRoots: ScanViewModel.loadProjectRoots()).run() {
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
