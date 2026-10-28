**New: Duplicates.** A Duplicates section under Tools finds files and folders of 1 MB or more that exist more than once, by content, not name. It searches the entire disk by default (skipping macOS system folders, other disks and app data in Library folders), or only folders you choose. A copied folder shows up once instead of as hundreds of files. Sort by space freed, size or name; each set lists its copies oldest first with all but one ticked, and moves the extras to the Trash after confirmation.

**Install:** `brew install --cask bunthondev/tap/deepclean`, or unzip, drag `DeepClean.app` to `/Applications`,
then run `xattr -d com.apple.quarantine /Applications/DeepClean.app` once (the build is not notarized).
Grant Full Disk Access when asked. Apple silicon, macOS 14 or newer. From 0.2.2 on, updates install
themselves via DeepClean > Check for Updates.
