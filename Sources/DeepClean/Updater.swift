import AppKit
import CryptoKit
import Foundation

/// Checks GitHub Releases for a newer build. No framework, no background daemon: it asks the
/// releases API, compares the tag with the running version, and offers the download page.
enum Updater {
    static let repo = "bunthondev/deep-clean"
    static let releasesPage = URL(string: "https://github.com/\(repo)/releases/latest")!
    private static let api = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
    private static let lastCheckKey = "lastUpdateCheck"
    private static let skippedKey = "skippedUpdateVersion"

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    struct Release: Sendable {
        let version: String
        let page: URL
        let zip: URL?
        /// Detached Ed25519 signature of the zip (`<zip>.sig` asset), made by release.sh.
        let sig: URL?
        let notes: String
    }

    enum CheckError: LocalizedError {
        case badResponse(Int)
        case noRelease
        var errorDescription: String? {
            switch self {
            case .badResponse(let code): return "GitHub answered with status \(code)."
            case .noRelease: return "No release found."
            }
        }
    }

    /// Fetches the latest release. Throws on network or parse errors.
    static func fetchLatest() async throws -> Release {
        var req = URLRequest(url: api)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("DeepClean/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 { throw CheckError.badResponse(http.statusCode) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let pageString = json["html_url"] as? String, let page = URL(string: pageString) else { throw CheckError.noRelease }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let assets = json["assets"] as? [[String: Any]] ?? []
        let urls = assets.compactMap { $0["browser_download_url"] as? String }
        let zip = urls.first { $0.hasSuffix(".zip") }.flatMap(URL.init(string:))
        let sig = urls.first { $0.hasSuffix(".zip.sig") }.flatMap(URL.init(string:))
        return Release(version: version, page: page, zip: zip, sig: sig, notes: json["body"] as? String ?? "")
    }

    /// True when `a` is a newer semantic version than `b` (numeric, component-wise).
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Menu action: always reports the result, including "up to date" and errors.
    @MainActor static func checkInteractively() {
        Task {
            do {
                let release = try await fetchLatest()
                UserDefaults.standard.set(Date(), forKey: lastCheckKey)
                if isNewer(release.version, than: currentVersion) {
                    offer(release, allowSkip: false)
                } else {
                    let a = NSAlert()
                    a.messageText = "You're up to date"
                    a.informativeText = "DeepClean \(currentVersion) is the latest version."
                    a.runModal()
                }
            } catch {
                let a = NSAlert()
                a.alertStyle = .warning
                a.messageText = "Could not check for updates"
                a.informativeText = error.localizedDescription
                a.addButton(withTitle: "OK")
                a.addButton(withTitle: "Open Releases Page")
                if a.runModal() == .alertSecondButtonReturn { NSWorkspace.shared.open(releasesPage) }
            }
        }
    }

    /// Launch check: at most once a day, silent unless something newer exists and was not skipped.
    @MainActor static func checkQuietlyIfDue() {
        if let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date, Date().timeIntervalSince(last) < 86_400 { return }
        Task {
            guard let release = try? await fetchLatest() else { return }
            UserDefaults.standard.set(Date(), forKey: lastCheckKey)
            guard isNewer(release.version, than: currentVersion),
                  UserDefaults.standard.string(forKey: skippedKey) != release.version else { return }
            offer(release, allowSkip: true)
        }
    }

    @MainActor private static func offer(_ release: Release, allowSkip: Bool) {
        let a = NSAlert()
        a.messageText = "DeepClean \(release.version) is available"
        let canInstall = release.zip != nil && release.sig != nil && Installer.canReplaceRunningApp
        var text = canInstall
            ? "You have \(currentVersion). The update is installed in place and DeepClean reopens by itself."
            : "You have \(currentVersion). Download the new version, unzip it and replace the app in Applications."
        let notes = release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { text += "\n\n" + String(notes.prefix(600)) }
        a.informativeText = text
        a.addButton(withTitle: canInstall ? "Install and Relaunch" : "Download")
        a.addButton(withTitle: "Later")
        if allowSkip { a.addButton(withTitle: "Skip This Version") }
        switch a.runModal() {
        case .alertFirstButtonReturn:
            if canInstall, let zip = release.zip, let sig = release.sig { Installer.installAndRelaunch(zip: zip, sig: sig, version: release.version) }
            else { NSWorkspace.shared.open(release.zip ?? release.page) }
        case .alertThirdButtonReturn: UserDefaults.standard.set(release.version, forKey: skippedKey)
        default: break
        }
    }
}

/// Downloads a release zip, checks the bundle inside, swaps it over the running app and relaunches.
/// Plain file moves, no helper tool: it works wherever the user can already write (Applications
/// owned by them, or a Homebrew cask install).
enum Installer {
    /// Public half of the Ed25519 key that release.sh signs every zip with. Private key stays on
    /// the release machine (~/.config/deepclean/update-signing.pem). Builds are ad-hoc signed, so
    /// this is what proves a download really came from the project.
    static let updatePublicKey = "J88bI5lAX7cQzpSd3IKzc5TOdl8+syMjkKrTY8NpPFM="

    enum InstallError: LocalizedError {
        case badDownload(Int), noBundle, wrongBundle(String), wrongVersion(String, String), signature(String), translocated, notSigned
        var errorDescription: String? {
            switch self {
            case .notSigned: return "The download is not signed with the DeepClean release key, so it was not installed."
            case .badDownload(let c): return "Download failed with status \(c)."
            case .noBundle: return "The download did not contain DeepClean.app."
            case .wrongBundle(let id): return "The download contains a different app (\(id))."
            case .wrongVersion(let got, let want): return "The download is version \(got), expected \(want)."
            case .signature(let why): return "The downloaded app failed its signature check: \(why)"
            case .translocated: return "DeepClean is running from a temporary location. Move it to Applications first."
            }
        }
    }

    /// False when the running bundle cannot sensibly be replaced (Gatekeeper translocation, or a
    /// folder the user cannot write to).
    static var canReplaceRunningApp: Bool {
        let url = Bundle.main.bundleURL
        guard url.pathExtension == "app", !url.path.contains("/AppTranslocation/") else { return false }
        return FileManager.default.isWritableFile(atPath: url.deletingLastPathComponent().path)
    }

    @MainActor static func installAndRelaunch(zip: URL, sig: URL, version: String) {
        let progress = ProgressPanel(title: "Installing DeepClean \(version)…")
        progress.show("Downloading…")
        Task {
            do {
                let newApp = try await install(zip: zip, sig: sig, expectedVersion: version) { stage in
                    Task { @MainActor in progress.show(stage) }
                }
                progress.show("Relaunching…")
                relaunch(newApp)
            } catch {
                progress.close()
                let a = NSAlert()
                a.alertStyle = .warning
                a.messageText = "Could not install the update"
                a.informativeText = error.localizedDescription + "\n\nYou can download it and replace the app yourself."
                a.addButton(withTitle: "Download Manually")
                a.addButton(withTitle: "Cancel")
                if a.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(zip) }
            }
        }
    }

    /// Does the work and returns the path of the installed bundle (same place as the running one).
    /// `expectedVersion` nil skips the version check (used by `--self-update`).
    static func install(zip: URL, sig: URL, expectedVersion: String?, stage: @escaping @Sendable (String) -> Void) async throws -> URL {
        let fm = FileManager.default
        let current = Bundle.main.bundleURL
        guard !current.path.contains("/AppTranslocation/") else { throw InstallError.translocated }
        let work = fm.temporaryDirectory.appendingPathComponent("DeepClean-update-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let zipFile = work.appendingPathComponent("update.zip")
        try await fetch(zip, to: zipFile)
        let sigFile = work.appendingPathComponent("update.zip.sig")
        try await fetch(sig, to: sigFile)

        // Nothing is unpacked before the release key has vouched for the bytes.
        stage("Verifying…")
        guard let keyData = Data(base64Encoded: updatePublicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              key.isValidSignature(try Data(contentsOf: sigFile), for: try Data(contentsOf: zipFile)) else { throw InstallError.notSigned }

        stage("Unpacking…")
        let unpacked = work.appendingPathComponent("unpacked", isDirectory: true)
        try run("/usr/bin/ditto", ["-x", "-k", zipFile.path, unpacked.path])
        guard let newApp = (try? fm.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil))?
                .first(where: { $0.pathExtension == "app" }) else { throw InstallError.noBundle }

        stage("Checking…")
        let plist = newApp.appendingPathComponent("Contents/Info.plist")
        let info = NSDictionary(contentsOf: plist) as? [String: Any] ?? [:]
        let newID = info["CFBundleIdentifier"] as? String ?? "?"
        guard newID == Bundle.main.bundleIdentifier else { throw InstallError.wrongBundle(newID) }
        let newVersion = info["CFBundleShortVersionString"] as? String ?? "?"
        if let expectedVersion, newVersion != expectedVersion { throw InstallError.wrongVersion(newVersion, expectedVersion) }
        do { try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path]) }
        catch { throw InstallError.signature(error.localizedDescription) }
        try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])

        stage("Installing…")
        let dir = current.deletingLastPathComponent()
        let backup = dir.appendingPathComponent(".\(current.deletingPathExtension().lastPathComponent)-old-\(Updater.currentVersion).app")
        try? fm.removeItem(at: backup)
        try fm.moveItem(at: current, to: backup)
        do {
            try fm.moveItem(at: newApp, to: current)
        } catch {
            try? fm.moveItem(at: backup, to: current)   // put the old one back
            throw error
        }
        pendingCleanup = backup
        return current
    }

    /// Downloads a URL to `dest`, or copies it when it is a local file (tests).
    private static func fetch(_ url: URL, to dest: URL) async throws {
        if url.isFileURL { try FileManager.default.copyItem(at: url, to: dest); return }
        var req = URLRequest(url: url)
        req.setValue("DeepClean/\(Updater.currentVersion)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 60
        let (tmp, resp) = try await URLSession.shared.download(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 { throw InstallError.badDownload(http.statusCode) }
        try FileManager.default.moveItem(at: tmp, to: dest)
    }

    /// Old bundle to delete once the new one is running. Removed by the relaunch script.
    nonisolated(unsafe) private static var pendingCleanup: URL?

    /// Waits for this process to exit, opens the new bundle, deletes the old one, then quits the app.
    static func relaunch(_ app: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let cleanup = pendingCleanup.map { "/bin/rm -rf \(shellQuote($0.path))" } ?? "true"
        let script = "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \(shellQuote(app.path)); \(cleanup)"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script]
        try? p.run()
        if let app = NSApp, app.isRunning { DispatchQueue.main.async { app.terminate(nil) } } else { exit(0) }
    }

    private static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    private struct ToolError: LocalizedError {
        let output: String
        var errorDescription: String? { output }
    }

    private static func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardError = pipe; p.standardOutput = pipe
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            throw ToolError(output: String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "exit \(p.terminationStatus)")
        }
    }
}

/// Small floating panel with a spinner and a one-line status, shown while an update installs.
@MainActor final class ProgressPanel {
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")

    init(title: String) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 92),
                        styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = title
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        let spinner = NSProgressIndicator(frame: NSRect(x: 20, y: 36, width: 32, height: 32))
        spinner.style = .spinning
        spinner.startAnimation(nil)
        label.frame = NSRect(x: 64, y: 42, width: 276, height: 20)
        label.font = .systemFont(ofSize: 13)
        panel.contentView?.addSubview(spinner)
        panel.contentView?.addSubview(label)
        panel.center()
    }

    func show(_ text: String) {
        label.stringValue = text
        if !panel.isVisible { panel.orderFront(nil) }
    }

    func close() { panel.orderOut(nil) }
}
