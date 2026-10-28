import SwiftUI

struct DuplicateListView: View {
    @ObservedObject var vm: ScanViewModel

    var body: some View {
        List(vm.sortedDuplicateSets, selection: vm.duplicateSelection) { d in
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: d.paths[0])).resizable().frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.name).lineLimit(1).truncationMode(.middle)
                    Text("\(d.isFolder ? "Folder" : "File") · \(d.paths.count) copies of \(Format.size(d.bytes))")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(Format.size(d.wasted)).monospacedDigit().foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            .tag(d.id)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Picker("Search", selection: Binding(
                    get: { vm.searchesEntireDisk },
                    // The open panel runs modally; start it after the segmented control finishes its click.
                    set: { entire in DispatchQueue.main.async { entire ? vm.searchEntireDisk() : vm.chooseDuplicateRoots(replacing: true) } }
                )) {
                    Text("Entire disk").tag(true)
                    Text("Folders…").tag(false)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                .help("Search the whole disk, or only folders you choose")
                Text(vm.searchesEntireDisk ? DuplicateFinder.displayName(DuplicateFinder.entireDisk)
                     : vm.duplicateRoots.map(\.lastPathComponent).joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                    .help(vm.searchesEntireDisk ? "Everything except macOS system folders, other disks and app data in Library folders"
                          : vm.duplicateRoots.map { $0.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }.joined(separator: "\n"))
                Spacer()
                Picker("Sort", selection: $vm.duplicateSort) {
                    ForEach(DuplicateSort.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu).fixedSize()
                .help("Sort by space freed, size of one copy, or name")
                if !vm.searchesEntireDisk {
                    Menu {
                        Section("Searched for duplicates") {
                            ForEach(vm.duplicateRoots, id: \.self) { url in
                                Label(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"), systemImage: "folder")
                            }
                        }
                        Divider()
                        Button("Add folder…") { vm.chooseDuplicateRoots(replacing: false) }
                        Menu("Remove folder") {
                            ForEach(vm.duplicateRoots, id: \.self) { url in
                                Button(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) { vm.duplicateRoots.removeAll { $0 == url } }
                            }
                        }
                        .disabled(vm.duplicateRoots.count < 2)
                    } label: {
                        Image(systemName: "folder.badge.gearshape")
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                    .help("Add or remove folders")
                }
            }
            .disabled(vm.isFindingDuplicates)
            .padding(8)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
        }
        .overlay {
            if vm.isFindingDuplicates && vm.duplicateSets.isEmpty {
                ProgressView(vm.duplicateStatus)
            } else if vm.duplicateSets.isEmpty {
                ContentUnavailableView {
                    Label(vm.hasFoundDuplicates ? "No duplicates" : "No search yet",
                          systemImage: vm.hasFoundDuplicates ? "sparkles" : "doc.on.doc")
                } description: {
                    Text(vm.hasFoundDuplicates ? "No file or folder of 1 MB or more exists twice \(vm.searchesEntireDisk ? "on this disk" : "in these folders")."
                         : "Find files and folders of 1 MB or more that exist more than once\(vm.searchesEntireDisk ? " anywhere on the disk, apart from macOS system folders and app data" : " in the chosen folders"). Contents are compared, not names. The search is read-only.")
                } actions: {
                    Button {
                        vm.findDuplicates()
                    } label: {
                        Label("Find Duplicates", systemImage: "magnifyingglass").padding(.horizontal, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(vm.duplicateRoots.isEmpty)
                }
            }
        }
    }
}

struct DuplicateDetailView: View {
    let dup: DuplicateSet
    @ObservedObject var vm: ScanViewModel
    // @State is a macro unavailable with Command Line Tools; a tiny ObservableObject does the job.
    @StateObject private var picks = DuplicatePicks()

    private var chosen: [String] { dup.paths.filter { picks.trash.contains($0) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: dup.paths[0])).resizable().frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(dup.name).font(.title2).fontWeight(.semibold).lineLimit(2)
                        Text(dup.isFolder ? "Identical folders" : "Identical files").font(.callout).foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 24) {
                    Stat(label: "Copies", value: "\(dup.paths.count)")
                    Stat(label: "Size of each", value: Format.size(dup.bytes))
                    if dup.isFolder { Stat(label: "Files inside", value: dup.fileCount.formatted()) }
                    Stat(label: "Can be freed", value: Format.size(dup.wasted))
                }

                Text(dup.isFolder
                     ? "Every file inside has the same name, place and content in each copy. Copies are listed oldest first; all but the first are ticked."
                     : "Same content byte for byte, whatever the names. Copies are listed oldest first; all but the first are ticked.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 0) {
                    ForEach(dup.paths, id: \.self) { p in
                        HStack(spacing: 8) {
                            Toggle("", isOn: Binding(
                                get: { picks.trash.contains(p) },
                                set: { on in if on { picks.trash.insert(p) } else { picks.trash.remove(p) } }
                            )).labelsHidden().toggleStyle(.checkbox)
                            VStack(alignment: .leading, spacing: 1) {
                                Text((p as NSString).deletingLastPathComponent.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                    .font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                                Text("\((p as NSString).lastPathComponent) · modified \(dup.modified[p].map { Format.date.localizedString(for: $0, relativeTo: .now) } ?? "unknown")")
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            Text(picks.trash.contains(p) ? "Trash" : "Keep").font(.caption.weight(.medium))
                                .foregroundStyle(picks.trash.contains(p) ? .orange : .green)
                            Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)]) } label: {
                                Image(systemName: "magnifyingglass")
                            }.buttonStyle(.borderless).help("Reveal in Finder")
                        }
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .help(p)
                        Divider()
                    }
                }
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))

                if !dup.paths.isEmpty && chosen.count == dup.paths.count {
                    Label("Keep at least one copy.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout)
                }
            }
            .padding(24)
            .frame(maxWidth: 680, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .task(id: dup.id) { picks.trash = Set(dup.paths.dropFirst()) }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ActionBar {
                Spacer()
                Button(role: .destructive) { vm.askToTrashDuplicates(dup, paths: chosen) } label: {
                    Label("Move \(chosen.count == 1 ? "1 copy" : "\(chosen.count) copies"), \(Format.size(dup.bytes * Int64(chosen.count))) to Trash…", systemImage: "trash")
                }
                .disabled(chosen.isEmpty || chosen.count == dup.paths.count)
                .help("Moves the ticked copies to the Trash after confirmation. You can restore them until you empty the Trash.")
            }
        }
    }
}

final class DuplicatePicks: ObservableObject {
    @Published var trash: Set<String> = []
}
