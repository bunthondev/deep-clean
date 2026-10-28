**Safer duplicate removal.** Before moving duplicates to the Trash, DeepClean now re-reads every copy from disk and refuses if the kept copy was changed or deleted since the search. Folders that hold items the search does not compare (hidden files such as a `.git` history, packages such as Keynote documents or apps, symlinks) are no longer reported as identical folders; duplicate files inside them are still found.

**Install:** `brew install --cask bunthondev/tap/deepclean`, or unzip, drag `DeepClean.app` to `/Applications`,
then run `xattr -d com.apple.quarantine /Applications/DeepClean.app` once (the build is not notarized).
Grant Full Disk Access when asked. Apple silicon, macOS 14 or newer. From 0.2.2 on, updates install
themselves via DeepClean > Check for Updates.
