import AppKit
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
        let zip = assets.compactMap { $0["browser_download_url"] as? String }.first { $0.hasSuffix(".zip") }.flatMap(URL.init(string:))
        return Release(version: version, page: page, zip: zip, notes: json["body"] as? String ?? "")
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
        var text = "You have \(currentVersion). Download the new version, unzip it and replace the app in Applications."
        let notes = release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { text += "\n\n" + String(notes.prefix(600)) }
        a.informativeText = text
        a.addButton(withTitle: "Download")
        a.addButton(withTitle: "Later")
        if allowSkip { a.addButton(withTitle: "Skip This Version") }
        switch a.runModal() {
        case .alertFirstButtonReturn: NSWorkspace.shared.open(release.zip ?? release.page)
        case .alertThirdButtonReturn: UserDefaults.standard.set(release.version, forKey: skippedKey)
        default: break
        }
    }
}
