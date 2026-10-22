**New:** file-level control inside grouped items such as "Downloads untouched for 180 days".
The detail pane now shows every file as a folder tree with a checkbox, size, and days inactive.
Tick single files or whole subfolders and use **Trash selected**; subfolders left empty are trashed too.

**Also:**
- The empty start screen has a Scan button.
- Multi-selection shows a Reveal in Finder button and a remove button on each selected item.
- Installers and project-artifact groups carry per-path sizes and dates as well.

**Install:** `brew install --cask bunthondev/tap/deepclean`, or unzip, drag `DeepClean.app` to `/Applications`,
then run `xattr -d com.apple.quarantine /Applications/DeepClean.app` once (the build is not notarized).
Grant Full Disk Access when asked. Apple silicon, macOS 14 or newer.
