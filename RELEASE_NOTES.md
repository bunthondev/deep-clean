**Security:** in-app updates are now signed. Every release zip carries a detached Ed25519 signature made with
the project's release key, and the installer verifies it against the key built into the app before unpacking
anything. A download that is unsigned or signed by anyone else is refused and the installed app is left alone.

**Install:** `brew install --cask bunthondev/tap/deepclean`, or unzip, drag `DeepClean.app` to `/Applications`,
then run `xattr -d com.apple.quarantine /Applications/DeepClean.app` once (the build is not notarized).
Grant Full Disk Access when asked. Apple silicon, macOS 14 or newer. From 0.2.2 on, later updates install
themselves via DeepClean > Check for Updates.
