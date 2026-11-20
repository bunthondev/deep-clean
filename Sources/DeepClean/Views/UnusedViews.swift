import SwiftUI

struct UnusedListView: View {
    @ObservedObject var vm: ScanViewModel

    var body: some View {
        let rows = vm.visibleUnused
        List(selection: vm.unusedSelection) {
            ForEach(UnusedKind.allCases) { kind in
                let kindRows = rows.filter { $0.kind == kind }
                if !kindRows.isEmpty {
                    Section {
                        ForEach(kindRows) { UnusedRow(item: $0).tag($0.id) }
                    } header: {
                        HStack {
                            Label(kind.title, systemImage: kind.symbol)
                            Text("\(kindRows.count)").font(.caption).foregroundStyle(.tertiary)
                            Spacer()
                            Text(Format.size(kindRows.reduce(0) { $0 + $1.bytes })).monospacedDigit()
                        }
                    }
                }
            }
        }
        .contextMenu(forSelectionType: UnusedItem.ID.self) { ids in
            if let item = vm.unusedItems.first(where: { ids.contains($0.id) }) {
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)]) }
                if item.canTrash {
                    Button("Move to Trash…", role: .destructive) { vm.askToTrashUnused(item) }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Unused for at least").font(.callout).foregroundStyle(.secondary)
                Picker("Unused for at least", selection: $vm.unusedDays) {
                    ForEach(ScanViewModel.unusedDayChoices, id: \.days) { Text($0.title).tag($0.days) }
                }
                .pickerStyle(.menu).labelsHidden().fixedSize()
                .help("Show only items not used for at least this long")
                Spacer()
                if !vm.unusedItems.isEmpty {
                    Text("\(rows.count) items, \(Format.size(rows.reduce(0) { $0 + $1.bytes }))")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .padding(8)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
        }
        .overlay {
            if vm.unusedItems.isEmpty && !vm.isScanningUnused {
                ContentUnavailableView {
                    Label(vm.hasScannedUnused ? "Nothing found" : "No search yet", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("List projects, apps, local databases and large files with the date each was last used. The search is read-only.")
                } actions: {
                    Button {
                        vm.scanUnused()
                    } label: {
                        Label("Find Unused", systemImage: "magnifyingglass").padding(.horizontal, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            } else if rows.isEmpty && !vm.isScanningUnused {
                ContentUnavailableView("Everything was used recently", systemImage: "checkmark.circle",
                                       description: Text("Pick a shorter time above to see more."))
            }
        }
    }
}

struct UnusedRow: View {
    let item: UnusedItem

    var body: some View {
        HStack(spacing: 10) {
            if item.kind == .apps || item.kind == .files {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.path)).resizable().frame(width: 24, height: 24)
            } else {
                Image(systemName: item.kind.symbol).foregroundStyle(.secondary).frame(width: 24)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).lineLimit(1).truncationMode(.middle)
                Text(UnusedRow.age(item)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(Format.size(item.bytes)).monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    /// "Last opened 5 months ago", "Last written: unknown".
    static func age(_ item: UnusedItem) -> String {
        guard let d = item.lastUsed else { return "\(item.dateLabel): unknown" }
        return "\(item.dateLabel) \(Format.date.localizedString(for: d, relativeTo: .now))"
    }
}

struct UnusedDetailView: View {
    let item: UnusedItem
    @ObservedObject var vm: ScanViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    if item.kind == .apps || item.kind == .files {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: item.path)).resizable().frame(width: 56, height: 56)
                    } else {
                        Image(systemName: item.kind.symbol).font(.system(size: 40)).foregroundStyle(.secondary).frame(width: 56, height: 56)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name).font(.title2).fontWeight(.semibold).textSelection(.enabled)
                        Text(item.kind.title).foregroundStyle(.secondary)
                    }
                }

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow { label("Size"); Text(Format.size(item.bytes)).monospacedDigit() }
                    GridRow {
                        label(item.dateLabel)
                        if let d = item.lastUsed {
                            Text("\(d.formatted(date: .abbreviated, time: .omitted)) (\(Format.date.localizedString(for: d, relativeTo: .now)))")
                        } else {
                            Text("Unknown")
                        }
                    }
                    GridRow { label("Unused for"); Text(item.daysUnused.map { "\($0) days" } ?? "Unknown") }
                    GridRow { label("Details"); Text(item.detail) }
                    GridRow { label("Location"); Text(item.displayPath).textSelection(.enabled).lineLimit(3) }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("How \"last used\" is measured").font(.headline)
                    Text(item.kind.howMeasured).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }

                if item.kind == .databases {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Removing it").font(.headline)
                        Text("DeepClean never deletes database files: that would break the whole Postgres server. If you no longer need this database, drop it from your database tool:")
                            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Text("DROP DATABASE \"\(item.name)\";")
                            .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    }
                }

                HStack {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
                    } label: { Label("Reveal in Finder", systemImage: "folder") }
                    if item.canTrash {
                        Button(role: .destructive) { vm.askToTrashUnused(item) } label: { Label("Move to Trash…", systemImage: "trash") }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func label(_ s: String) -> some View {
        Text(s).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
    }
}
