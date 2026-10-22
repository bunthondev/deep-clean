# DeepClean

A small native macOS app that finds junk taking up disk space, explains what each item is,
and lets you move it to the Trash only after you confirm.

- Swift + SwiftUI, no dependencies, ~600 KB app
- Read-only scan; deletion is always an explicit second step and goes to Trash (recoverable)
- Works with Command Line Tools only (no full Xcode needed)

## Build and run

```sh
./build.sh          # builds DeepClean.app in this folder
./build.sh --run    # build and open it
```

Text-only mode, useful for scripts or quick checks:

```sh
.build/release/DeepClean --cli
```

## What it scans

1. **Known cache locations** (`Catalog.swift`): package manager caches (npm, pnpm, uv, pip, cargo…),
   dev tool caches (Puppeteer, Playwright, Xcode, Android NDK…), AI agent tools, editors, browsers,
   app data and system folders. Each entry carries a plain-language description, what happens
   after deleting it, and a safety tier.
2. **Generated folders inside projects**: walks your project roots (default `~/dev`, `~/Projects`,
   `~/Code`… whichever exist, add more via the toolbar) and lists `node_modules`, `target`, `.next`,
   `dist`, `build`, `.venv`, `Pods` and similar. Folders like `dist`/`build`/`target` only count when a
   matching manifest (`package.json`, `Cargo.toml`, `pom.xml`…) sits next to them.
3. **Downloads and Desktop**: single files over 200 MB, installers/archives in Downloads, and
   Downloads untouched for 180 days.

## Safety tiers

| Tier | Meaning | Trash button |
|---|---|---|
| Safe to delete | Regenerates itself when needed | enabled |
| Review first | Junk only if you stopped using the tool/project | enabled |
| Personal data | Your files, listed for awareness | disabled |

Select several rows with ⌘-click or shift-click (or "Select all" in a section header), then use
**Trash selected** in the toolbar or the right-click menu. One confirmation covers the whole batch;
personal items in the selection are skipped.

## Full Disk Access

Mail, Safari and Messages folders are protected by macOS. If the app cannot read them it shows a
banner with a button to the right System Settings pane. The app is ad-hoc signed by `build.sh`,
so macOS may ask you to grant access again after a rebuild. To make the grant stick, sign with a
stable certificate:

1. Keychain Access > Certificate Assistant > Create a Certificate…
   Name `DeepClean Dev`, Identity Type `Self Signed Root`, Certificate Type `Code Signing`.
2. `SIGN_IDENTITY="DeepClean Dev" ./build.sh`

A paid Developer ID certificate works the same way and is required only for distributing to other Macs.

## Storage, system, Applications and Processes

**Tools > Processes** lists every running process grouped by app (an app bundle and all its
helpers count as one row, so Chrome shows one line, not thirty) with CPU and memory, sorted by
either. Selecting a group shows each process with its PID, user, CPU and memory, the group's share
of used memory, and **Quit** (normal, like ⌘Q) or **Force Quit** (kills immediately, after
confirmation). Own processes are read through libproc: memory is the physical footprint that
Activity Monitor shows, CPU is the change in CPU time between samples. System processes owned by
root cannot be inspected that way, so their RSS and %CPU come from one `ps` call per sample.
Sampling runs every 3 s only while the view is open.

```sh
.build/release/DeepClean --procs    # text listing of the 15 biggest process groups
.build/release/DeepClean --system   # one CPU / memory / battery reading
```


Below the storage card a system card refreshes every two seconds: CPU load across all cores with
the chip name, memory used (app + wired + compressed, like Activity Monitor) with the kernel's
memory-pressure level, and on laptops the battery level, charging state, time to empty or full,
health (max vs design capacity), cycle count and temperature. Readings come from Mach host
statistics, sysctl and IOKit, so no helper process or elevated rights are needed.

The sidebar starts with a storage card for the boot volume: used, purgeable (space macOS holds in
snapshots and caches and frees on demand) and free. It refreshes after every scan and every trash.

**Tools > Applications** lists every app in `/Applications` and `~/Applications` with its size,
source (App Store receipt, Homebrew Caskroom, or downloaded), version, and last-used date from
Spotlight. Selecting an app finds its leftovers in `~/Library` (Application Support, Caches,
Preferences, Containers, Group Containers, HTTPStorages, WebKit, Logs, Saved state, Launch agents,
Cookies, Application Scripts) matched by bundle identifier and exact app name. Uncheck anything to
keep, then **Uninstall** moves the app and the checked leftovers to the Trash after one
confirmation, or **Remove leftovers only** keeps the app. Running apps cannot be uninstalled until
quit. Apps installed by a root-owned installer (Microsoft Office, Adobe, many `.pkg` installs) cannot
be moved by the app directly, so it asks Finder to do it. Finder shows the usual password prompt and
still moves the item to the Trash. The first time, macOS asks whether DeepClean may control Finder;
that choice lives in System Settings > Privacy & Security > Automation.

```sh
.build/release/DeepClean --apps   # text listing of storage and the 15 largest apps with leftovers
```

## Grouping

The toolbar picker switches the list between **Safety** (tiers) and **Kind**. In Kind mode every
project artifact is its own section named after the folder (`node_modules`, `target`, `.next`,
`venv`…) and catalog items keep their category (`Browser caches`, `Package manager caches`…).
Each section header shows the count, total size and a "Select all" link, so trashing every
`node_modules` on the machine is: Kind > Select all > Trash selected > confirm.
The sidebar "By kind" list shows the same groups with size badges, biggest first.

## Drill-down

The detail pane lists the ten largest items directly inside the selected folder, each with a
reveal button and, for non-personal tiers, a trash button. Useful for things like Postgres data
or a package cache where only one subfolder is worth removing.

Project folders added via the toolbar are remembered between launches (UserDefaults key
`projectRoots`). Remove one from the same menu.

## Layout

```
Sources/DeepClean/
  DeepCleanApp.swift   app entry + --cli mode
  Models.swift         Tier, CleanItem, formatters
  Catalog.swift        known junk paths and project artifact rules
  DiskSize.swift       fast allocated-size walker
  Scanner.swift        the three scan passes, streamed as AsyncStream
  Apps.swift           StorageInfo, InstalledApp, AppScanner (app list + leftovers)
  SystemStats.swift    CPU / memory / battery sampler (Mach, sysctl, IOKit)
  Processes.swift      per-process sampler (libproc + ps), grouping by app, quit / force quit
  ScanViewModel.swift  UI state, trash + reveal actions
  Views/               ContentView (sidebar, list, banner), DetailView, MultiDetailView, AppViews (storage card, app list, app detail), SystemCard, ProcessViews
Resources/Info.plist
Resources/make-icon.sh    regenerates AppIcon.icns (AppKit + sips + iconutil, no Xcode)
build.sh               swift build + wrap into DeepClean.app
```

## Debugging without screen recording

`DEEPCLEAN_DEBUG=procs-click DEEPCLEAN_SNAPSHOT=/path/out.png ./DeepClean.app/Contents/MacOS/DeepClean`
opens the Processes view, sends a synthetic click to a row through the window (a real AppKit event,
no Accessibility permission needed) and writes a rendering of the window from inside the app (no
Screen Recording permission needed). Other modes: `procs`, `procs-noselect`, `apps`, `junk`.
See `DebugHooks.swift`. This is how the blank-sidebar bug was bisected.

## Notes

- Some folders under `~/Library` (Mail, Safari, Messages) need Full Disk Access to be read.
  Grant it in System Settings > Privacy & Security if those show as missing.
- Sizes are allocated size on disk, matching Finder's "on disk" figure.
- Keep every detail pane inside a `ScrollView`. A wrapping `Text` placed directly in the split
  view's detail column sent SwiftUI into a layout loop that blanked the sidebar on selection.
- `@State` is a macro in recent SDKs and its plugin ships only with full Xcode, so the view model
  uses `ObservableObject`/`@StateObject`. Keep it that way if you build with Command Line Tools.
