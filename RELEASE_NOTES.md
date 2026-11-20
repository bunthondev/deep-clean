**Unused tool.** A new Unused view under Tools lists projects, apps, local Postgres databases and large files you have not used in a while, each with its size, the date it was last used and how that date is measured. Pick 1 month to 2 years; the list updates instantly. Projects, apps and files can be revealed or moved to the Trash after confirmation. Databases are read-only: their names come from the Postgres catalog on disk without connecting to the server, and DeepClean shows the `DROP DATABASE` command instead of deleting files.

**System Data filter.** A new System Data entry under Junk shows the items macOS counts as "System Data" in Storage settings.

**More known locations.** Gradle wrapper distributions, pnpm metadata cache, Go build cache, Rust toolchains, headless Chrome, Codex app data, VS Code extensions, a second TikTok automation profile, and Postman, Warp and Whisky app data.

**Install:** `brew install --cask bunthondev/tap/deepclean`, or unzip, drag `DeepClean.app` to `/Applications`,
then run `xattr -d com.apple.quarantine /Applications/DeepClean.app` once (the build is not notarized).
Grant Full Disk Access when asked. Apple silicon, macOS 14 or newer. From 0.2.2 on, updates install
themselves via DeepClean > Check for Updates.
