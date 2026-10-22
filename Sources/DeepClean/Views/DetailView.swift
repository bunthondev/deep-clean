import SwiftUI

struct DetailView: View {
    let item: CleanItem
    @ObservedObject var vm: ScanViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.name).font(.title2).fontWeight(.semibold)
                    Text(item.group).foregroundStyle(.secondary)
                }

                HStack(spacing: 24) {
                    Stat(label: "Size", value: Format.size(item.bytes))
                    Stat(label: "Files", value: item.fileCount.formatted())
                    if let m = item.modified {
                        Stat(label: "Last changed", value: Format.date.localizedString(for: m, relativeTo: .now))
                    }
                }

                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.tier.title).fontWeight(.medium)
                        Text(item.tier.subtitle).font(.callout).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: item.tier.symbol).foregroundStyle(item.tier.color)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(item.tier.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

                Field(title: "What it is", body: item.what)
                Field(title: "If you delete it", body: item.afterDelete)

                PathsSection(item: item, vm: vm)

                if !item.isAggregate {
                    ChildrenSection(item: item, vm: vm)
                }

            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ActionBar {
                Button { vm.reveal(item) } label: { Label("Reveal in Finder", systemImage: "folder") }
                Spacer()
                Button(role: .destructive) { vm.askToTrash([item]) } label: {
                    Label("Move to Trash…", systemImage: "trash")
                }
                .disabled(item.tier == .personal)
                .help(item.tier == .personal ? "Personal data is only reported, delete it yourself in Finder." : "Moves to Trash after confirmation")
            }
        }
        .task(id: item.id) { vm.pathSelection = []; vm.expandedFolders = []; vm.loadChildren(for: item) }
    }
}

/// Every path behind an item, as a folder tree. For aggregates: a checkbox per row (a folder's
/// checkbox covers everything inside), size, how long untouched, and "Trash selected". Rows are
/// flattened from the expanded folders into a LazyVStack, so thousands of files stay cheap.
private struct PathsSection: View {
    let item: CleanItem
    @ObservedObject var vm: ScanViewModel

    private var canTrash: Bool { item.isAggregate && item.tier != .personal }
    private var selected: [String] { item.paths.filter { vm.pathSelection.contains($0) } }
    private var selectedBytes: Int64 { selected.reduce(0) { $0 + (item.pathInfo[$1]?.bytes ?? 0) } }
    private var root: String { PathNode.commonRoot(of: item.paths) }

    private var visibleRows: [PathNode] {
        guard item.isAggregate else {
            return item.paths.map { PathNode(path: $0, name: $0, depth: 0, isDirectory: false, leaves: [$0]) }
        }
        var out: [PathNode] = []
        func walk(_ nodes: [PathNode]) {
            for n in nodes {
                out.append(n)
                if n.isDirectory, vm.expandedFolders.contains(n.path) { walk(n.children) }
            }
        }
        walk(PathNode.tree(of: item.paths, info: item.pathInfo))
        return out
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
            Section {
                ForEach(visibleRows) { row($0) }
            } header: {
                header.background(.background)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if canTrash { checkbox(for: item.paths) }
                Text(item.isAggregate ? "Files (\(item.paths.count))" : "Path").font(.subheadline).fontWeight(.medium)
                if item.isAggregate {
                    Text("in " + root.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.callout).foregroundStyle(.tertiary)
                }
                Spacer()
                if canTrash {
                    Button(role: .destructive) {
                        vm.askToTrash(selected.map(single))
                    } label: {
                        Label(selected.isEmpty ? "Trash selected" : "Trash \(selected.count) (\(Format.size(selectedBytes)))", systemImage: "trash")
                    }
                    .controlSize(.small).disabled(selected.isEmpty)
                }
            }
            if item.isAggregate {
                HStack(spacing: 0) {
                    Text("Name").frame(maxWidth: .infinity, alignment: .leading).padding(.leading, canTrash ? 28 : 0)
                    Text("Size").frame(width: 72, alignment: .trailing)
                    Text("Inactive").frame(width: 84, alignment: .trailing)
                    Color.clear.frame(width: 28)
                }
                .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.bottom, 4)
    }

    /// Tri-state checkbox over a set of file paths: all, some, or none selected.
    private func checkbox(for leaves: [String]) -> some View {
        let picked = leaves.filter { vm.pathSelection.contains($0) }.count
        let symbol = picked == 0 ? "square" : picked == leaves.count ? "checkmark.square.fill" : "minus.square.fill"
        return Button {
            if picked == leaves.count { vm.pathSelection.subtract(leaves) } else { vm.pathSelection.formUnion(leaves) }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(picked == 0 ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.accentColor))
        }
        .buttonStyle(.plain)
        .frame(width: 20, alignment: .leading)
        .help(picked == leaves.count ? "Deselect" : "Select")
    }

    private func row(_ n: PathNode) -> some View {
        let picked = n.leaves.filter { vm.pathSelection.contains($0) }.count
        let open = vm.expandedFolders.contains(n.path)
        return HStack(spacing: 0) {
            if canTrash { checkbox(for: n.leaves).padding(.trailing, 8) }
            Color.clear.frame(width: CGFloat(n.depth) * 18)
            if item.isAggregate {
                if n.isDirectory {
                    Button {
                        if open { vm.expandedFolders.remove(n.path) } else { vm.expandedFolders.insert(n.path) }
                    } label: {
                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
                            .rotationEffect(.degrees(open ? 90 : 0))
                    }
                    .buttonStyle(.plain).frame(width: 14)
                } else {
                    Color.clear.frame(width: 14)
                }
                Image(systemName: n.isDirectory ? "folder.fill" : "doc").font(.callout)
                    .foregroundStyle(n.isDirectory ? AnyShapeStyle(Color.accentColor.opacity(0.85)) : AnyShapeStyle(.secondary))
                    .frame(width: 22)
            }
            Text(item.isAggregate ? n.name : n.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                .font(item.isAggregate ? .callout : .callout.monospaced()).textSelection(.enabled)
                .foregroundStyle(n.isDirectory ? .primary : .secondary)
                .lineLimit(1).truncationMode(.middle).help(n.path)
            if n.isDirectory {
                Text("\(n.leaves.count)").font(.caption).foregroundStyle(.tertiary).padding(.leading, 6)
            }
            Spacer(minLength: 8)
            if item.isAggregate {
                Text(n.isDirectory || item.pathInfo[n.path] != nil ? Format.size(n.bytes) : "–").monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .trailing)
                Text(n.daysInactive.map { "\($0) d" } ?? "–").monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: 84, alignment: .trailing)
            }
            Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: n.path)]) } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless).help("Reveal in Finder").frame(width: 28, alignment: .trailing)
        }
        .font(.callout)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { if n.isDirectory { if open { vm.expandedFolders.remove(n.path) } else { vm.expandedFolders.insert(n.path) } } }
        .background(picked > 0 && picked == n.leaves.count ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 4))
    }

    private func single(_ path: String) -> CleanItem {
        CleanItem(id: "child:" + path, name: (path as NSString).lastPathComponent, paths: [path], tier: item.tier, group: item.group,
                  what: "Part of \(item.name). \(item.what)", afterDelete: item.afterDelete,
                  bytes: item.pathInfo[path]?.bytes ?? 0, fileCount: 1, modified: item.pathInfo[path]?.modified)
    }
}

/// "Largest contents": the biggest immediate children, each with reveal and (when allowed) trash.
private struct ChildrenSection: View {
    let item: CleanItem
    @ObservedObject var vm: ScanViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Largest contents").font(.subheadline).fontWeight(.medium)
                if vm.children[item.id] == nil { ProgressView().controlSize(.mini) }
            }
            if let kids = vm.children[item.id] {
                if kids.isEmpty {
                    Text("Single file, nothing inside.").font(.callout).foregroundStyle(.tertiary)
                }
                ForEach(kids) { kid in
                    HStack(spacing: 8) {
                        Image(systemName: kid.isDirectory ? "folder" : "doc").foregroundStyle(.secondary).frame(width: 16)
                        Text(kid.name).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(Format.size(kid.bytes)).monospacedDigit().foregroundStyle(.secondary)
                        Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: kid.path)]) } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .buttonStyle(.borderless).help("Reveal in Finder")
                        if item.tier != .personal {
                            Button(role: .destructive) { vm.askToTrash([child(kid)]) } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless).help("Move just this to Trash")
                        }
                    }
                    .font(.callout)
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func child(_ kid: ChildStat) -> CleanItem {
        CleanItem(id: "child:" + kid.path, name: kid.name, paths: [kid.path], tier: item.tier, group: item.group,
                  what: "Part of \(item.name). \(item.what)", afterDelete: item.afterDelete,
                  bytes: kid.bytes, fileCount: 0, modified: nil)
    }
}

/// Fixed bar at the bottom of a detail pane. Buttons never scroll away or truncate.
struct ActionBar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 12) { content }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 24).padding(.vertical, 12)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
    }
}

private struct Field: View {
    let title: String
    let body_: String
    init(title: String, body: String) { self.title = title; self.body_ = body }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).fontWeight(.medium)
            Text(body_).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
