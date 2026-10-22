**Fixed:** the same project folder could appear several times in the junk list when project roots overlapped
(for example a folder added twice through the picker, or a root nested inside another). Roots are now
normalized and deduplicated, nested roots are dropped, and the scanner never reports the same path twice.

**Also:** `DeepClean --cli` scans the same project roots the app uses.

**Install:** `brew install --cask bunthondev/tap/deepclean`, or unzip, drag `DeepClean.app` to `/Applications`,
then run `xattr -d com.apple.quarantine /Applications/DeepClean.app` once (the build is not notarized).
Grant Full Disk Access when asked. Apple silicon, macOS 14 or newer.
