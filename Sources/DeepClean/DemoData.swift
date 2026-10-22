import Foundation

/// Fixed, realistic sample data for screenshots (DEEPCLEAN_DEBUG=demo). Nothing here is read
/// from disk, so screenshots never show the machine's real project names.
enum DemoData {
    private static let home = NSHomeDirectory()
    private static func ago(_ days: Int) -> Date { Date().addingTimeInterval(-Double(days) * 86_400) }
    private static func gb(_ v: Double) -> Int64 { Int64(v * 1_073_741_824) }
    private static func mb(_ v: Double) -> Int64 { Int64(v * 1_048_576) }

    private static func item(_ name: String, _ path: String, _ tier: Tier, _ group: String,
                             what: String, after: String, bytes: Int64, files: Int, days: Int) -> CleanItem {
        CleanItem(id: "demo:" + path, name: name, paths: [home + path], tier: tier, group: group,
                  what: what, afterDelete: after, bytes: bytes, fileCount: files, modified: ago(days))
    }

    static let selectedID = "demo:/Library/Developer/Xcode/DerivedData"
    private static let staleNames = ["invoice-data-2025-09-11.json", "download (1).png", "anydesk.dmg", "book.pdf", "result (27).xlsx",
                                     "Style_official_3_Noir.zip", "screenshot 2025-03-02.png", "slides-final-v2.key", "logo.svg", "notes.txt"]
    private static let stalePaths: [String] = (0..<40).map { i in
        let sub = i < 10 ? "" : i < 22 ? "Telegram Desktop/" : i < 30 ? "old-project/assets/" : i < 34 ? "old-project/" : ""
        return home + "/Downloads/" + sub + (i < 10 ? staleNames[i] : "report-\(i).pdf")
    }

    static let items: [CleanItem] = [
        CleanItem(id: "demo:downloads-stale", name: "Downloads untouched for 180 days",
                  paths: stalePaths, tier: .review, group: "Downloads",
                  what: "40 files not modified in the last 180 days.",
                  afterDelete: "Moved to Trash, so you can still recover them until you empty it.",
                  bytes: gb(1.9), fileCount: 40, modified: ago(200),
                  pathInfo: Dictionary(uniqueKeysWithValues: stalePaths.enumerated().map { i, p in
                      (p, PathInfo(bytes: mb(Double(3 + (i * 37) % 160)), modified: ago(181 + (i * 23) % 500)))
                  })),
        item("Xcode DerivedData", "/Library/Developer/Xcode/DerivedData", .safe, "Dev tool caches",
             what: "Intermediate build products and indexes for every Xcode project you have opened.",
             after: Catalog.reinstall, bytes: gb(12.4), files: 184_302, days: 1),
        item("Ollama models", "/.ollama/models", .review, "AI and agent tools",
             what: "Downloaded language models for Ollama.",
             after: "Each model is downloaded again the next time you run it.", bytes: gb(14.2), files: 23, days: 12),
        item("iOS Simulators", "/Library/Developer/CoreSimulator", .review, "Dev tool caches",
             what: "Simulator runtimes and the apps installed inside each simulated device.",
             after: "Xcode re-downloads runtimes you still use; simulator app data is gone.", bytes: gb(9.8), files: 61_540, days: 9),
        item("Hugging Face cache", "/.cache/huggingface", .review, "AI and agent tools",
             what: "Model weights and datasets pulled by the transformers and datasets libraries.",
             after: "Re-downloaded on first use.", bytes: gb(6.3), files: 412, days: 30),
        item("api-server/target", "/dev/api-server/target", .safe, "target",
             what: "Cargo build output for this project.", after: Catalog.reinstall, bytes: gb(4.6), files: 29_118, days: 2),
        item("Android emulator images", "/Library/Android/sdk/system-images", .review, "Dev tool caches",
             what: "System images used by Android virtual devices.",
             after: "Re-downloaded from the SDK manager when you create an emulator.", bytes: gb(5.1), files: 38, days: 120),
        item("pnpm store", "/Library/pnpm", .safe, "Package manager caches",
             what: "Content-addressable store that pnpm links node_modules from.", after: Catalog.regen, bytes: gb(3.2), files: 210_664, days: 0),
        item("Cargo registry", "/.cargo/registry", .safe, "Package manager caches",
             what: "Downloaded Rust crates and their extracted sources.", after: Catalog.regen, bytes: gb(2.9), files: 58_020, days: 3),
        item("Gradle caches", "/.gradle/caches", .safe, "Package manager caches",
             what: "Downloaded JVM dependencies and Gradle's build cache.", after: Catalog.regen, bytes: gb(2.2), files: 14_331, days: 5),
        item("npm cache", "/.npm/_cacache", .safe, "Package manager caches",
             what: "Packages npm has downloaded, kept for offline installs.", after: Catalog.regen, bytes: gb(2.1), files: 96_204, days: 0),
        item("shop-web/node_modules", "/dev/shop-web/node_modules", .safe, "node_modules",
             what: "JavaScript dependencies installed for this project.", after: Catalog.reinstall, bytes: gb(1.8), files: 74_911, days: 1),
        item("Go module cache", "/go/pkg/mod", .safe, "Package manager caches",
             what: "Downloaded Go modules.", after: Catalog.regen, bytes: gb(1.7), files: 40_218, days: 7),
        item("Chrome cache", "/Library/Caches/Google/Chrome", .safe, "Browser caches",
             what: "Web pages, images and scripts Chrome keeps to load sites faster.", after: Catalog.regen, bytes: gb(1.46), files: 31_002, days: 0),
        item("JetBrains caches", "/Library/Caches/JetBrains", .safe, "Dev tool caches",
             what: "Indexes and local history for IntelliJ, WebStorm and friends.", after: Catalog.regen, bytes: gb(1.3), files: 12_770, days: 4),
        item("Playwright browsers", "/Library/Caches/ms-playwright", .safe, "Dev tool caches",
             what: "Browser builds Playwright downloads for testing.", after: Catalog.regen, bytes: gb(1.1), files: 2_488, days: 20),
        item("CocoaPods cache", "/Library/Caches/CocoaPods", .safe, "Package manager caches",
             what: "Downloaded pod specs and sources.", after: Catalog.regen, bytes: mb(710), files: 9_300, days: 40),
        item("Homebrew downloads", "/Library/Caches/Homebrew", .safe, "Package manager caches",
             what: "Bottles and casks Homebrew has downloaded.", after: Catalog.regen, bytes: mb(640), files: 118, days: 2),
        item("uv cache", "/.cache/uv", .safe, "Package manager caches",
             what: "Python wheels and sources cached by uv.", after: Catalog.regen, bytes: mb(530), files: 8_204, days: 1),
        item("shop-web/.next", "/dev/shop-web/.next", .safe, ".next",
             what: "Next.js build output for this project.", after: Catalog.reinstall, bytes: mb(420), files: 3_180, days: 1),
        item("Installers in Downloads", "/Downloads", .review, "Downloads",
             what: "Disk images and archives you already installed from.",
             after: "Nothing comes back. Download again from the vendor if needed.", bytes: gb(3.4), files: 14, days: 45),
        item("Postgres data", "/Library/Application Support/Postgres", .personal, "App data",
             what: "Databases created by Postgres.app. Only old or unused databases are junk.",
             after: "All local databases are lost. Drop individual databases instead.", bytes: gb(2.4), files: 5_120, days: 15),
        item("Large files in Downloads", "/Downloads/macOS Sequoia.iso", .personal, "Large files in Downloads",
             what: "Single files over 200 MB.", after: "Nothing comes back.", bytes: gb(7.9), files: 1, days: 200),
    ]

    static let children: [ChildStat] = [
        ("shop-web-dhsmxnfuwqlpkycsgnuaztkbnetm", gb(4.1)),
        ("api-ios-fvqnhzcqpxkruqcicbzqemhqwbbq", gb(3.3)),
        ("ModuleCache.noindex", gb(2.6)),
        ("Notes-aqkoqoelxoqfkebgbrpnmydujejz", gb(1.4)),
        ("SymbolCache.noindex", mb(680)),
        ("Widgets-bjzhbqjqtmxwkdbtkbnyafxbrrao", mb(310)),
    ].map { ChildStat(path: home + "/Library/Developer/Xcode/DerivedData/" + $0.0, name: $0.0, bytes: $0.1, isDirectory: true) }
}
