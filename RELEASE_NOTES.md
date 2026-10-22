**New:** updates install themselves. When a newer version is found, choose **Install and Relaunch**:
DeepClean downloads the release, verifies the bundle (identifier, version, code signature), swaps it over
the running app and reopens. No more unzipping and dragging. If the app cannot replace itself, it falls
back to the download as before.

This is the first version that carries the in-app installer, so this one update is still a manual replace.
macOS may ask for Full Disk Access again after updating.

**Install:** `brew install --cask bunthondev/tap/deepclean`, or unzip, drag `DeepClean.app` to `/Applications`,
then run `xattr -d com.apple.quarantine /Applications/DeepClean.app` once (the build is not notarized).
Grant Full Disk Access when asked. Apple silicon, macOS 14 or newer.
