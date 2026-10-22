**New:** DeepClean > Check for Updates… looks up the latest GitHub release and offers the download.
The app also checks quietly once a day at launch and only shows a dialog when a newer version exists.
`DeepClean --update-check` does the same in text mode.

**Install:** unzip, drag `DeepClean.app` to `/Applications`, then run
`xattr -d com.apple.quarantine /Applications/DeepClean.app` once (the build is not notarized),
or use System Settings > Privacy & Security > Open Anyway. Grant Full Disk Access when asked.
Apple silicon, macOS 14 or newer.
