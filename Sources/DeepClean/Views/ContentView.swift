import SwiftUI

struct ContentView: View {
    @StateObject private var vm = ScanViewModel()

    var body: some View {
        VStack(spacing: 0) {
            splitView
            Divider()
            StatusBar(vm: vm)
        }
    }

    private var splitView: some View {
        NavigationSplitView {
            Sidebar(vm: vm)
                .navigationSplitViewColumnWidth(min: 240, ideal: 290)
        } content: {
            ContentColumn(vm: vm)
                .navigationSplitViewColumnWidth(min: 340, ideal: 400)
        } detail: {
            DetailColumn(vm: vm)
        }
        .navigationSplitViewColumnWidth(min: 380, ideal: 480)
        .onChange(of: vm.filter, initial: true) { _, f in vm.setProcessSampling(active: f == .processes) }
        .task {
            // Debug aid: DEEPCLEAN_DEBUG=procs opens the Processes view and selects the biggest group.
            guard let mode = ProcessInfo.processInfo.environment["DEEPCLEAN_DEBUG"] else { return }
            switch mode {
            case "procs":
                vm.filter = .processes
                try? await Task.sleep(for: .seconds(4))
                vm.selectedProcessGroupID = vm.sortedProcessGroups.first?.id
                try? await Task.sleep(for: .seconds(2))
                if let w = DebugHooks.window, let p = ProcessInfo.processInfo.environment["DEEPCLEAN_SNAPSHOT"] { DebugHooks.snapshot(w, to: p) }
            case "procs-click":
                vm.filter = .processes
                try? await Task.sleep(for: .seconds(4))
                if let w = DebugHooks.window, let cv = w.contentView {
                    let tables = DebugHooks.tableViews(in: cv)
                    FileHandle.standardError.write(Data("debug: \(tables.count) table views, rows: \(tables.map(\.numberOfRows))\n".utf8))
                    if let list = tables.max(by: { $0.numberOfRows < $1.numberOfRows }) { DebugHooks.click(list, row: 2) }
                }
                try? await Task.sleep(for: .seconds(2))
                if let w = DebugHooks.window, let p = ProcessInfo.processInfo.environment["DEEPCLEAN_SNAPSHOT"] { DebugHooks.snapshot(w, to: p) }
            case "procs-noselect":
                vm.filter = .processes
            case "apps":
                vm.filter = .apps
                vm.scanApps()
                try? await Task.sleep(for: .seconds(4))
                vm.selectedAppID = vm.filteredApps.first?.id
            case "demo":
                if ProcessInfo.processInfo.environment["DEEPCLEAN_APPEARANCE"] == "light" { NSApp.appearance = NSAppearance(named: .aqua) }
                vm.fullDiskAccessMissing = false
                vm.items = DemoData.items
                vm.children[DemoData.selectedID] = DemoData.children
                vm.hasScanned = true
                vm.status = "\(vm.items.count) items, \(Format.size(vm.totalBytes)) found"
                try? await Task.sleep(for: .seconds(1))
                if let w = DebugHooks.window {
                    w.setContentSize(NSSize(width: 1540, height: 900)); w.center()
                    NSApp.activate(ignoringOtherApps: true); w.makeKeyAndOrderFront(nil)
                }
                vm.selection = [DemoData.selectedID]
                try? await Task.sleep(for: .seconds(4))
                if let w = DebugHooks.window, let p = ProcessInfo.processInfo.environment["DEEPCLEAN_SNAPSHOT"] { DebugHooks.snapshot(w, to: p) }
            case "menu":
                try? await Task.sleep(for: .seconds(1))
                for item in NSApp.mainMenu?.items.first?.submenu?.items ?? [] { print("menu: \(item.title)") }
                exit(0)
            case "junk":
                vm.scan()
                try? await Task.sleep(for: .seconds(30))
                vm.selection = Set(vm.filtered.prefix(1).map(\.id))
                try? await Task.sleep(for: .seconds(2))
                if let w = DebugHooks.window, let p = ProcessInfo.processInfo.environment["DEEPCLEAN_SNAPSHOT"] { DebugHooks.snapshot(w, to: p) }
            default: break
            }
        }
        .confirmationDialog("Force quit?", isPresented: Binding(get: { vm.pendingForceQuit != nil }, set: { if !$0 { vm.pendingForceQuit = nil } }),
                            presenting: vm.pendingForceQuit) { g in
            Button("Force Quit \(g.name)", role: .destructive) { vm.quit(g, force: true) }
            Button("Cancel", role: .cancel) {}
        } message: { g in
            Text("\(g.rows.count == 1 ? "The process" : "All \(g.rows.count) processes") will be killed immediately. Unsaved work in \(g.name) is lost.")
        }
        .searchable(text: $vm.search, placement: .toolbar, prompt: "Filter by name or path")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Group by", selection: $vm.grouping) {
                    ForEach(Grouping.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(vm.filter == .apps || vm.filter == .processes)
                .help("Group the list by safety tier or by kind (node_modules, target, caches…)")

                Menu {
                    Section("Scanned for build folders") {
                        ForEach(vm.projectRoots, id: \.self) { url in
                            Label(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"), systemImage: "folder")
                        }
                    }
                    Divider()
                    Button("Add project folder…") { vm.chooseProjectRoot() }
                    Menu("Remove folder") {
                        ForEach(vm.projectRoots, id: \.self) { url in
                            Button(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) { vm.removeProjectRoot(url) }
                        }
                    }
                    .disabled(vm.projectRoots.isEmpty)
                } label: {
                    Label("Project folders", systemImage: "folder.badge.gearshape")
                }
                .help("Folders searched for node_modules, build output, virtual environments")

                Button {
                    vm.askToTrash(vm.trashableSelection)
                } label: {
                    Label("Trash selected", systemImage: "trash")
                }
                .disabled(vm.trashableSelection.isEmpty)
                .help("Move the selected items to the Trash after confirmation")

                if vm.isScanning {
                    Button { vm.cancel() } label: { Label("Stop", systemImage: "stop.fill") }
                } else {
                    Button {
                        switch vm.filter {
                        case .apps: vm.scanApps()
                        case .processes: vm.sampleProcessesNow()
                        default: vm.scan()
                        }
                    } label: { Label(vm.filter == .processes ? "Refresh" : "Scan", systemImage: vm.filter == .processes ? "arrow.clockwise" : "magnifyingglass") }
                        .keyboardShortcut("r", modifiers: .command)
                }
            }
        }
        .alert("Could not move to Trash", isPresented: Binding(get: { vm.errorMessage != nil }, set: { if !$0 { vm.errorMessage = nil } })) {
            Button("OK") { vm.errorMessage = nil }
        } message: { Text(vm.errorMessage ?? "") }
        .confirmationDialog(
            "Move to Trash?", isPresented: Binding(get: { vm.pendingTrash != nil }, set: { if !$0 { vm.pendingTrash = nil } }),
            presenting: vm.pendingTrash
        ) { list in
            let total = list.reduce(0) { $0 + $1.bytes }
            Button("Move \(list.count == 1 ? "" : "\(list.count) items, ")\(Format.size(total)) to Trash", role: .destructive) { vm.trash(list) }
            Button("Cancel", role: .cancel) {}
        } message: { list in
            if list.count == 1, let item = list.first {
                Text(item.isAggregate
                     ? "\(item.fileCount) files will be moved to the Trash. You can restore them from the Trash until you empty it."
                     : "\(item.displayPath) will be moved to the Trash. \(item.afterDelete)")
            } else {
                Text("\(list.count) items will be moved to the Trash. You can restore them from the Trash until you empty it.")
            }
        }
    }
}

/// Stable root views for the middle and right columns. Swapping unrelated views directly inside
/// NavigationSplitView's column builders changes the column's identity on every mode change,
/// which on macOS can blank the sidebar and trigger reentrant NSTableView updates.
struct ContentColumn: View {
    @ObservedObject var vm: ScanViewModel

    var body: some View {
        ZStack {
            switch vm.filter {
            case .apps: AppListView(vm: vm)
            case .processes: ProcessListView(vm: vm)
            default: ItemList(vm: vm)
            }
        }
    }
}

struct DetailColumn: View {
    @ObservedObject var vm: ScanViewModel

    var body: some View {
        ZStack {
            switch vm.filter {
            case .processes:
                if let g = vm.selectedProcessGroup {
                    ProcessDetailView(group: g, vm: vm)
                } else {
                    ContentUnavailableView("Select a process", systemImage: "cpu",
                                           description: Text("See every process behind an app, how much memory and CPU each uses, and quit or force quit it."))
                }
            case .apps:
                if let app = vm.selectedApp {
                    AppDetailView(app: app, vm: vm)
                } else {
                    ContentUnavailableView("Select an app", systemImage: "app.badge.checkmark",
                                           description: Text("See its size, where it came from, when it was last used, and the files it left in ~/Library."))
                }
            default:
                let sel = vm.selectedItems
                if sel.count > 1 {
                    MultiDetailView(items: sel, vm: vm)
                } else if let item = sel.first {
                    DetailView(item: item, vm: vm)
                } else {
                    EmptyDetail(vm: vm)
                }
            }
        }
    }
}

struct StatusBar: View {
    @ObservedObject var vm: ScanViewModel

    var body: some View {
        HStack(spacing: 8) {
            if vm.isScanning || vm.isScanningApps { ProgressView().controlSize(.small) }
            Text(vm.filter == .processes ? "\(vm.processCount) processes in \(vm.processGroups.count) groups, refreshing every 3 s"
                 : vm.filter == .apps ? (vm.isScanningApps ? "Listing applications…" : "\(vm.apps.count) applications") : vm.status).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if vm.selection.count > 1 {
                Text("\(vm.selection.count) selected, \(Format.size(vm.selectedItems.reduce(0) { $0 + $1.bytes }))")
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            if vm.hasScanned || vm.isScanning {
                Text("Total \(Format.size(vm.totalBytes))").font(.callout.monospacedDigit()).fontWeight(.medium)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.bar)
    }
}

struct Sidebar: View {
    @ObservedObject var vm: ScanViewModel

    var body: some View {
        List(selection: $vm.filter) {
            StorageCard(storage: vm.storage)
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                .listRowBackground(Color.clear)
                .selectionDisabled()
            SystemCard(s: vm.system)
                .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 8, trailing: 8))
                .listRowBackground(Color.clear)
                .selectionDisabled()
            Section("Junk") {
                Label("Everything", systemImage: "internaldrive").tag(Filter.all)
                    .badge(vm.items.isEmpty ? "" : Format.size(vm.totalBytes))
            }
            Section("By safety") {
                ForEach(Tier.allCases) { tier in
                    Label(tier.title, systemImage: tier.symbol)
                        .tint(tier.color)
                        .badge(vm.items.isEmpty ? "" : Format.size(vm.bytes(for: tier)))
                        .tag(Filter.tier(tier))
                }
            }
            Section("Tools") {
                Label("Applications", systemImage: "app.badge.checkmark")
                    .badge(vm.apps.isEmpty ? "" : Format.size(vm.appsTotalBytes))
                    .tag(Filter.apps)
                Label("Processes", systemImage: "cpu")
                    .badge(vm.processGroups.isEmpty ? "" : "\(vm.processCount)")
                    .tag(Filter.processes)
            }
            if !vm.groups.isEmpty {
                Section("By kind") {
                    ForEach(vm.groups, id: \.self) { g in
                        Text(g).badge(Format.size(vm.bytes(forGroup: g))).tag(Filter.group(g))
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

struct ItemList: View {
    @ObservedObject var vm: ScanViewModel

    var body: some View {
        List(selection: vm.itemSelection) {
            switch (vm.grouping, vm.filter) {
            case (.tier, .tier), (.kind, .group):
                // Filter already equals the grouping key: a flat list.
                ForEach(vm.filtered) { row($0) }
            case (.tier, _):
                ForEach(Tier.allCases) { tier in
                    let rows = vm.filtered.filter { $0.tier == tier }
                    if !rows.isEmpty {
                        Section {
                            ForEach(rows) { row($0) }
                        } header: {
                            SectionHeader(title: tier.title, symbol: tier.symbol, color: tier.color, rows: rows,
                                          selectAll: tier == .personal ? nil : { vm.selectAllVisible(tier: tier) })
                        }
                    }
                }
            case (.kind, _):
                let visibleGroups = vm.groups.filter { g in vm.filtered.contains { $0.group == g } }
                ForEach(visibleGroups, id: \.self) { g in
                    let rows = vm.filtered.filter { $0.group == g }
                    Section {
                        ForEach(rows) { row($0) }
                    } header: {
                        SectionHeader(title: g, symbol: "folder.fill", color: .secondary, rows: rows,
                                      selectAll: rows.allSatisfy { $0.tier == .personal } ? nil : { vm.selectAllVisible(group: g) })
                    }
                }
            }
        }
        .contextMenu(forSelectionType: CleanItem.ID.self) { ids in
            let items = vm.items.filter { ids.contains($0.id) }
            if items.count == 1, let item = items.first {
                Button("Reveal in Finder") { vm.reveal(item) }
            }
            let trashable = items.filter { $0.tier != .personal }
            if !trashable.isEmpty {
                Button("Move \(trashable.count == 1 ? "" : "\(trashable.count) items ")to Trash…", role: .destructive) { vm.askToTrash(trashable) }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if vm.fullDiskAccessMissing {
                FullDiskAccessBanner(vm: vm)
            }
        }
        .overlay {
            if vm.items.isEmpty && !vm.isScanning {
                ContentUnavailableView(
                    vm.hasScanned ? "Nothing found" : "No scan yet",
                    systemImage: vm.hasScanned ? "sparkles" : "magnifyingglass",
                    description: Text(vm.hasScanned ? "No junk in the known locations." : "Press Scan (⌘R) to look for junk. The scan is read-only.")
                )
            }
        }
    }

    private func row(_ item: CleanItem) -> some View {
        ItemRow(item: item).tag(item.id)
    }
}

struct SectionHeader: View {
    let title: String
    let symbol: String
    let color: Color
    let rows: [CleanItem]
    let selectAll: (() -> Void)?

    var body: some View {
        HStack {
            Label(title, systemImage: symbol).foregroundStyle(color)
            Text("\(rows.count)").font(.caption).foregroundStyle(.tertiary)
            Spacer()
            Text(Format.size(rows.reduce(0) { $0 + $1.bytes })).monospacedDigit()
            if let selectAll {
                Button("Select all", action: selectAll).buttonStyle(.link).font(.caption)
            }
        }
    }
}

struct FullDiskAccessBanner: View {
    @ObservedObject var vm: ScanViewModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Some folders need Full Disk Access").font(.callout).fontWeight(.medium)
                Text("Mail, Safari and Messages data is skipped until you allow DeepClean in System Settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings") { vm.openFullDiskAccessSettings() }.controlSize(.small)
            Button { vm.fullDiskAccessMissing = false } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Hide")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.orange.opacity(0.1))
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct ItemRow: View {
    let item: CleanItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.tier.symbol).foregroundStyle(item.tier.color).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).lineLimit(1)
                Text(item.group).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(Format.size(item.bytes)).monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct EmptyDetail: View {
    @ObservedObject var vm: ScanViewModel

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "internaldrive").font(.system(size: 44)).foregroundStyle(.tertiary)
            Text("Select an item to see what it is").font(.title3).foregroundStyle(.secondary)
            Text("⌘-click or shift-click to select several, then use Trash selected.").font(.callout).foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Tier.allCases) { t in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: t.symbol).foregroundStyle(t.color).frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.title).fontWeight(.medium)
                            Text(t.subtitle).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.top, 8)
            .frame(maxWidth: 420, alignment: .leading)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension Tier {
    var color: Color {
        switch self {
        case .safe: return .green
        case .review: return .orange
        case .personal: return .blue
        }
    }
}
