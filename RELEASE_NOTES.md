First public build.

**Install:** unzip, drag `DeepClean.app` to `/Applications`, then run
`xattr -d com.apple.quarantine /Applications/DeepClean.app` once (the build is not notarized),
or use System Settings > Privacy & Security > Open Anyway. Grant Full Disk Access when asked.
Apple silicon, macOS 14 or newer.

**What's inside**
- Junk scan: package manager and dev tool caches, AI tool caches, project build folders (`node_modules`, `target`, `.next`, `.venv`…), large and stale Downloads
- Every item explained, with a safety tier; deletion is a separate confirmed step and goes to the Trash
- Group by safety or by kind, multi-select, drill-down into the ten largest children
- Storage, CPU, memory and battery cards
- Applications: size, source, last used, leftovers in `~/Library`, one-click uninstall
- Processes: grouped by app with CPU and memory, quit or force quit
- Text modes: `--cli`, `--apps`, `--procs`, `--system`
