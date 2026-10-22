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

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.isAggregate ? "Paths (\(item.paths.count))" : "Path").font(.subheadline).fontWeight(.medium)
                    ForEach(item.paths.prefix(12), id: \.self) { p in
                        Text(p.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .font(.callout.monospaced()).textSelection(.enabled).foregroundStyle(.secondary)
                    }
                    if item.paths.count > 12 {
                        Text("… and \(item.paths.count - 12) more").font(.callout).foregroundStyle(.tertiary)
                    }
                }

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
        .task(id: item.id) { vm.loadChildren(for: item) }
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
