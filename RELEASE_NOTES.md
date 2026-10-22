**Fixed:** closing the window now quits DeepClean instead of leaving it in the Dock until force-quit.

**Install:** `brew install --cask bunthondev/tap/deepclean`, or unzip, drag `DeepClean.app` to `/Applications`,
then run `xattr -d com.apple.quarantine /Applications/DeepClean.app` once (the build is not notarized).
Grant Full Disk Access when asked. Apple silicon, macOS 14 or newer. From 0.2.2 on, updates install
themselves via DeepClean > Check for Updates.
