import Foundation

/// A known location that is commonly junk. Paths are relative to home unless absolute.
struct CatalogEntry: Sendable {
    let name: String
    let path: String
    let tier: Tier
    let group: String
    let what: String
    let afterDelete: String
}

enum Catalog {
    static let regen = "Comes back automatically the next time the tool needs it."
    static let reinstall = "Re-created the next time you install or build the project."

    static let entries: [CatalogEntry] = [
        // MARK: Package manager caches
        .init(name: "npm cache", path: "~/.npm/_cacache", tier: .safe, group: "Package manager caches",
              what: "Downloaded npm packages kept so future installs are faster.", afterDelete: regen),
        .init(name: "npx cache", path: "~/.npm/_npx", tier: .safe, group: "Package manager caches",
              what: "Packages fetched by one-off `npx` commands. Each run leaves a copy behind.", afterDelete: regen),
        .init(name: "pnpm store", path: "~/Library/pnpm", tier: .safe, group: "Package manager caches",
              what: "pnpm's content-addressable store. Projects hard-link into it, so unused parts are junk.", afterDelete: "Run `pnpm store prune` for a gentler cleanup. Deleting all forces re-download on next install."),
        .init(name: "Yarn cache", path: "~/Library/Caches/Yarn", tier: .safe, group: "Package manager caches",
              what: "Yarn 1 package download cache.", afterDelete: regen),
        .init(name: "Yarn Berry cache", path: "~/.yarn/berry", tier: .safe, group: "Package manager caches",
              what: "Yarn 2+ global package cache and release binaries.", afterDelete: regen),
        .init(name: "Bun cache", path: "~/.bun/install/cache", tier: .safe, group: "Package manager caches",
              what: "Bun package download cache.", afterDelete: regen),
        .init(name: "Deno cache", path: "~/Library/Caches/deno", tier: .safe, group: "Package manager caches",
              what: "Deno module cache.", afterDelete: regen),
        .init(name: "pip cache", path: "~/Library/Caches/pip", tier: .safe, group: "Package manager caches",
              what: "Python wheel and HTTP download cache used by pip.", afterDelete: regen),
        .init(name: "uv cache", path: "~/.cache/uv", tier: .safe, group: "Package manager caches",
              what: "Python package cache used by uv. Grows fast because every project version is kept.", afterDelete: "Run `uv cache clean` or delete. " + regen),
        .init(name: "Cargo registry", path: "~/.cargo/registry", tier: .safe, group: "Package manager caches",
              what: "Downloaded Rust crate sources and index.", afterDelete: regen),
        .init(name: "Go module cache", path: "~/go/pkg/mod", tier: .safe, group: "Package manager caches",
              what: "Downloaded Go modules.", afterDelete: regen),
        .init(name: "Gradle caches", path: "~/.gradle/caches", tier: .safe, group: "Package manager caches",
              what: "Gradle dependency jars and build cache for Android/Java projects.", afterDelete: regen),
        .init(name: "Composer cache", path: "~/Library/Caches/composer", tier: .safe, group: "Package manager caches",
              what: "PHP Composer package download cache.", afterDelete: regen),
        .init(name: "CocoaPods cache", path: "~/Library/Caches/CocoaPods", tier: .safe, group: "Package manager caches",
              what: "Downloaded iOS pod sources.", afterDelete: regen),
        .init(name: "Flutter pub cache", path: "~/.pub-cache", tier: .safe, group: "Package manager caches",
              what: "Dart/Flutter package cache.", afterDelete: regen),
        .init(name: "Homebrew downloads", path: "~/Library/Caches/Homebrew", tier: .safe, group: "Package manager caches",
              what: "Bottles and installers Homebrew downloaded. Old versions are never used again.", afterDelete: "Run `brew cleanup` for the thorough version. " + regen),

        // MARK: Dev tool caches
        .init(name: "Puppeteer browsers", path: "~/.cache/puppeteer", tier: .safe, group: "Dev tool caches",
              what: "Headless Chrome builds downloaded by Puppeteer. Each version is 200-400 MB.", afterDelete: regen),
        .init(name: "Playwright browsers", path: "~/Library/Caches/ms-playwright", tier: .safe, group: "Dev tool caches",
              what: "Chromium, Firefox and WebKit builds for Playwright tests.", afterDelete: "Run `npx playwright install` to get them back."),
        .init(name: "Prisma engines", path: "~/.cache/prisma", tier: .safe, group: "Dev tool caches",
              what: "Downloaded Prisma query engine binaries.", afterDelete: regen),
        .init(name: "node-gyp headers", path: "~/Library/Caches/node-gyp", tier: .safe, group: "Dev tool caches",
              what: "Node headers used to compile native addons.", afterDelete: regen),
        .init(name: "PHP language server index", path: "~/.phpls", tier: .review, group: "Dev tool caches",
              what: "Package index built by the PHP language server (Intelephense/Phpactor) for every vendor version it saw.", afterDelete: "Rebuilt when you next open a PHP project. First open is slower."),
        .init(name: "JetBrains caches", path: "~/Library/Caches/JetBrains", tier: .safe, group: "Dev tool caches",
              what: "Index and compile caches for IntelliJ, DataGrip, WebStorm etc.", afterDelete: "IDE re-indexes projects on next open."),
        .init(name: "Xcode DerivedData", path: "~/Library/Developer/Xcode/DerivedData", tier: .safe, group: "Dev tool caches",
              what: "Xcode build intermediates and indexes for every project you opened.", afterDelete: "Next build is a full rebuild."),
        .init(name: "Xcode Archives", path: "~/Library/Developer/Xcode/Archives", tier: .review, group: "Dev tool caches",
              what: "App archives from App Store / ad-hoc exports. Old ones are rarely needed.", afterDelete: "Gone for good. Keep any you still need for crash symbolication."),
        .init(name: "iOS device support", path: "~/Library/Developer/Xcode/iOS DeviceSupport", tier: .safe, group: "Dev tool caches",
              what: "Debug symbols for every iOS version you ever plugged in.", afterDelete: "Re-copied from the device next time you debug on it."),
        .init(name: "iOS Simulators", path: "~/Library/Developer/CoreSimulator", tier: .review, group: "Dev tool caches",
              what: "Simulator runtimes and device data.", afterDelete: "Run `xcrun simctl delete unavailable` for a safe partial clean."),
        .init(name: "Android NDK", path: "~/Library/Android/sdk/ndk", tier: .review, group: "Dev tool caches",
              what: "Native Development Kit. Only needed to compile C/C++ Android code. Often installed by accident.", afterDelete: "Reinstall from Android Studio SDK Manager if needed."),
        .init(name: "Android emulator images", path: "~/Library/Android/sdk/system-images", tier: .review, group: "Dev tool caches",
              what: "Android OS images for emulators. Each one is 1-3 GB.", afterDelete: "Reinstall from the SDK Manager."),
        .init(name: "Android AVDs", path: "~/.android/avd", tier: .review, group: "Dev tool caches",
              what: "Emulated device disks.", afterDelete: "Re-create the device in Android Studio."),

        // MARK: AI / agent tools
        .init(name: "Antigravity IDE data", path: "~/.gemini", tier: .review, group: "AI and agent tools",
              what: "Google Antigravity IDE binaries, browser profiles and agent workspaces.", afterDelete: "Junk if you stopped using Antigravity. Otherwise settings and history are lost."),
        .init(name: "Claude Code versions", path: "~/.local/share/claude", tier: .review, group: "AI and agent tools",
              what: "Downloaded Claude Code binaries. Old versions stay after updates.", afterDelete: "Current version re-downloads on next launch."),
        .init(name: "Cursor agent", path: "~/.local/share/cursor-agent", tier: .review, group: "AI and agent tools",
              what: "Cursor CLI agent binaries and cache.", afterDelete: "Re-downloads on next use."),
        .init(name: "OpenCode data", path: "~/.local/share/opencode", tier: .review, group: "AI and agent tools",
              what: "OpenCode sessions, binaries and cache.", afterDelete: "Session history is lost."),
        .init(name: "Codex data", path: "~/.codex", tier: .review, group: "AI and agent tools",
              what: "OpenAI Codex CLI sessions and cache.", afterDelete: "Session history is lost."),
        .init(name: "Ollama models", path: "~/.ollama/models", tier: .review, group: "AI and agent tools",
              what: "Downloaded local LLM weights.", afterDelete: "Re-pull with `ollama pull`."),
        .init(name: "Hugging Face cache", path: "~/.cache/huggingface", tier: .review, group: "AI and agent tools",
              what: "Downloaded model weights and datasets.", afterDelete: "Re-download on next use."),
        .init(name: "Torch cache", path: "~/.cache/torch", tier: .safe, group: "AI and agent tools",
              what: "PyTorch hub model downloads.", afterDelete: regen),
        .init(name: "Whisper models", path: "~/.cache/whisper", tier: .safe, group: "AI and agent tools",
              what: "OpenAI Whisper speech models.", afterDelete: regen),

        // MARK: Editors
        .init(name: "VS Code updater leftovers", path: "~/Library/Caches/com.microsoft.VSCode.ShipIt", tier: .safe, group: "Editors",
              what: "Downloaded VS Code updates that were already applied. Pure leftovers.", afterDelete: "Nothing. Already installed."),
        .init(name: "VS Code workspace storage", path: "~/Library/Application Support/Code/User/workspaceStorage", tier: .safe, group: "Editors",
              what: "Per-folder state (open tabs, history) for every folder you ever opened.", afterDelete: "Open editors and undo history reset per folder."),
        .init(name: "VS Code cached extensions", path: "~/Library/Application Support/Code/CachedExtensionVSIXs", tier: .safe, group: "Editors",
              what: "Extension installers kept after install.", afterDelete: "Nothing. Already installed."),
        .init(name: "Cursor workspace storage", path: "~/Library/Application Support/Cursor/User/workspaceStorage", tier: .safe, group: "Editors",
              what: "Per-folder state and AI chat history for every folder opened in Cursor.", afterDelete: "Chat history per folder is lost."),
        .init(name: "Cursor cache", path: "~/Library/Application Support/Cursor/Cache", tier: .safe, group: "Editors",
              what: "Chromium-style web cache inside Cursor.", afterDelete: regen),
        .init(name: "Antigravity IDE support", path: "~/Library/Application Support/Antigravity IDE", tier: .review, group: "Editors",
              what: "Antigravity IDE settings, extensions and caches.", afterDelete: "Junk if you stopped using Antigravity."),
        .init(name: "Trae IDE", path: "~/Library/Application Support/Trae", tier: .review, group: "Editors",
              what: "Trae IDE settings and caches.", afterDelete: "Junk if you stopped using Trae."),

        // MARK: Browsers
        .init(name: "Brave cache", path: "~/Library/Caches/BraveSoftware", tier: .safe, group: "Browser caches",
              what: "Web page cache for every Brave profile.", afterDelete: "Pages load slightly slower the first time."),
        .init(name: "Chrome cache", path: "~/Library/Caches/Google", tier: .safe, group: "Browser caches",
              what: "Web page cache for Chrome profiles.", afterDelete: "Pages load slightly slower the first time."),
        .init(name: "Firefox cache", path: "~/Library/Caches/Firefox", tier: .safe, group: "Browser caches",
              what: "Firefox page cache.", afterDelete: "Pages load slightly slower the first time."),
        .init(name: "Arc cache", path: "~/Library/Caches/company.thebrowser.Browser", tier: .safe, group: "Browser caches",
              what: "Arc page cache.", afterDelete: "Pages load slightly slower the first time."),
        .init(name: "TikTok automation profile", path: "~/.tiktok-browser-profile", tier: .review, group: "Browser caches",
              what: "A scripted browser profile created by an automation project.", afterDelete: "Junk if that project is done. Logged-in session is lost."),

        // MARK: App caches
        .init(name: "Notion offline cache", path: "~/Library/Application Support/Notion", tier: .review, group: "App data",
              what: "Offline copy of your Notion pages and media.", afterDelete: "Re-syncs from the cloud on next launch."),
        .init(name: "Notion updater", path: "~/Library/Caches/notion-updater", tier: .safe, group: "App data",
              what: "Downloaded Notion updates already applied.", afterDelete: "Nothing."),
        .init(name: "Notion ShipIt", path: "~/Library/Caches/notion.id.ShipIt", tier: .safe, group: "App data",
              what: "Downloaded Notion updates already applied.", afterDelete: "Nothing."),
        .init(name: "Figma updater", path: "~/Library/Caches/com.figma.Desktop.ShipIt", tier: .safe, group: "App data",
              what: "Downloaded Figma updates already applied.", afterDelete: "Nothing."),
        .init(name: "Wallpaper cache", path: "~/Library/Application Support/com.apple.wallpaper", tier: .safe, group: "App data",
              what: "Cached aerial and dynamic wallpaper videos.", afterDelete: "macOS re-downloads the wallpaper you use."),
        .init(name: "Slack cache", path: "~/Library/Application Support/Slack/Cache", tier: .safe, group: "App data",
              what: "Slack media and page cache.", afterDelete: regen),
        .init(name: "Discord cache", path: "~/Library/Application Support/discord/Cache", tier: .safe, group: "App data",
              what: "Discord media cache.", afterDelete: regen),
        .init(name: "Spotify cache", path: "~/Library/Caches/com.spotify.client", tier: .safe, group: "App data",
              what: "Streamed song cache.", afterDelete: regen),
        .init(name: "Wondershare installer", path: "~/Library/Application Support/com.wondershare.Installer", tier: .safe, group: "App data",
              what: "Leftover installer packages.", afterDelete: "Nothing."),
        .init(name: "Postgres data", path: "~/Library/Application Support/Postgres", tier: .personal, group: "App data",
              what: "Databases created by Postgres.app. Only old unused databases are junk.", afterDelete: "All local databases are lost. Drop individual databases instead."),

        // MARK: System
        .init(name: "User logs", path: "~/Library/Logs", tier: .safe, group: "System",
              what: "Log files written by apps.", afterDelete: regen),
        .init(name: "Saved application state", path: "~/Library/Saved Application State", tier: .safe, group: "System",
              what: "Window positions and reopen state per app.", afterDelete: "Apps open with default windows next time."),
        .init(name: "Mail downloads", path: "~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads", tier: .safe, group: "System",
              what: "Attachments you opened from Mail. Originals stay in the email.", afterDelete: "Nothing."),
        .init(name: "iOS device backups", path: "~/Library/Application Support/MobileSync/Backup", tier: .review, group: "System",
              what: "Full iPhone/iPad backups made by Finder.", afterDelete: "Old device backups are gone. Keep the latest for each device you own."),
    ]
}

/// Folder names inside projects that are generated output.
struct ArtifactRule: Sendable {
    let name: String
    let what: String
    let afterDelete: String
    let tier: Tier
    /// If non-empty, the folder only counts when one of these files exists next to it.
    let requiresSibling: [String]
}

extension Catalog {
    static let artifactRules: [ArtifactRule] = [
        .init(name: "node_modules", what: "Installed JavaScript dependencies for this project.", afterDelete: "Run `npm install` (or pnpm/yarn/bun) to restore.", tier: .safe, requiresSibling: []),
        .init(name: ".next", what: "Next.js build output and cache.", afterDelete: "Rebuilt by `next build` / `next dev`.", tier: .safe, requiresSibling: []),
        .init(name: ".nuxt", what: "Nuxt build output.", afterDelete: "Rebuilt on next build.", tier: .safe, requiresSibling: []),
        .init(name: ".output", what: "Nitro/Nuxt production output.", afterDelete: "Rebuilt on next build.", tier: .safe, requiresSibling: ["nuxt.config.ts", "nuxt.config.js", "package.json"]),
        .init(name: ".turbo", what: "Turborepo task cache.", afterDelete: "Rebuilt on next run.", tier: .safe, requiresSibling: []),
        .init(name: ".svelte-kit", what: "SvelteKit generated files.", afterDelete: "Rebuilt on next dev/build.", tier: .safe, requiresSibling: []),
        .init(name: ".angular", what: "Angular CLI build cache.", afterDelete: "Rebuilt on next build.", tier: .safe, requiresSibling: []),
        .init(name: ".parcel-cache", what: "Parcel bundler cache.", afterDelete: "Rebuilt on next build.", tier: .safe, requiresSibling: []),
        .init(name: ".vite", what: "Vite dependency pre-bundle cache.", afterDelete: "Rebuilt on next dev.", tier: .safe, requiresSibling: []),
        .init(name: "dist", what: "Bundled production build output.", afterDelete: "Rebuilt by the project's build command.", tier: .safe, requiresSibling: ["package.json", "tsconfig.json", "vite.config.ts", "vite.config.js"]),
        .init(name: "build", what: "Compiled build output.", afterDelete: "Rebuilt by the project's build command.", tier: .safe, requiresSibling: ["package.json", "build.gradle", "build.gradle.kts", "CMakeLists.txt", "setup.py", "pyproject.toml"]),
        .init(name: "target", what: "Rust (Cargo) or Java (Maven) compiled output. Rust targets are often multiple GB.", afterDelete: "Rebuilt by `cargo build` / `mvn package`.", tier: .safe, requiresSibling: ["Cargo.toml", "pom.xml"]),
        .init(name: "coverage", what: "Test coverage reports.", afterDelete: "Rebuilt by the next test run.", tier: .safe, requiresSibling: []),
        .init(name: ".venv", what: "Python virtual environment with installed packages.", afterDelete: "Re-create with `python -m venv .venv` and reinstall requirements.", tier: .safe, requiresSibling: []),
        .init(name: "venv", what: "Python virtual environment with installed packages.", afterDelete: "Re-create and reinstall requirements.", tier: .safe, requiresSibling: []),
        .init(name: "__pycache__", what: "Compiled Python bytecode.", afterDelete: "Regenerated on next run.", tier: .safe, requiresSibling: []),
        .init(name: ".pytest_cache", what: "pytest state cache.", afterDelete: "Regenerated on next test run.", tier: .safe, requiresSibling: []),
        .init(name: ".mypy_cache", what: "mypy type-check cache.", afterDelete: "Regenerated on next check.", tier: .safe, requiresSibling: []),
        .init(name: ".ruff_cache", what: "Ruff linter cache.", afterDelete: "Regenerated on next lint.", tier: .safe, requiresSibling: []),
        .init(name: ".gradle", what: "Project-local Gradle cache.", afterDelete: "Rebuilt on next Gradle run.", tier: .safe, requiresSibling: ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"]),
        .init(name: "Pods", what: "Installed CocoaPods for an iOS project.", afterDelete: "Run `pod install`.", tier: .safe, requiresSibling: ["Podfile"]),
        .init(name: "DerivedData", what: "Xcode build intermediates stored inside the project.", afterDelete: "Next build is a full rebuild.", tier: .safe, requiresSibling: []),
        .init(name: ".dart_tool", what: "Dart/Flutter tool cache.", afterDelete: "Rebuilt by `flutter pub get`.", tier: .safe, requiresSibling: []),
        .init(name: ".cache", what: "Project-local tool cache.", afterDelete: "Regenerated on next run.", tier: .safe, requiresSibling: ["package.json", "pyproject.toml", "requirements.txt"]),
    ]

    static let artifactNames: Set<String> = Set(artifactRules.map(\.name))

    /// Small, numerous folders that are shown as one row per kind instead of one row each.
    static let aggregatedArtifacts: Set<String> = ["__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache", "coverage"]
}
