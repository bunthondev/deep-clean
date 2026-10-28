**New: Battery.** A Battery section under Tools shows which apps use the most energy (the same Energy Impact figure as Activity Monitor, live and averaged since you opened the view, with each app's processes), plus about a week of battery history: a charge chart with time on power shaded, and a table of each stretch on battery or on power with its drain rate.

**Install:** `brew install --cask bunthondev/tap/deepclean`, or unzip, drag `DeepClean.app` to `/Applications`,
then run `xattr -d com.apple.quarantine /Applications/DeepClean.app` once (the build is not notarized).
Grant Full Disk Access when asked. Apple silicon, macOS 14 or newer. From 0.2.2 on, updates install
themselves via DeepClean > Check for Updates.
