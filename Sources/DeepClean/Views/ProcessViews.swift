import SwiftUI

struct ProcessListView: View {
    @ObservedObject var vm: ScanViewModel

    var body: some View {
        List(vm.sortedProcessGroups, selection: vm.processSelection) { g in
            HStack(spacing: 10) {
                Group {
                    if let b = g.bundlePath {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: b)).resizable()
                    } else {
                        Image(systemName: "terminal").foregroundStyle(.secondary)
                    }
                }
                .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(g.name).lineLimit(1)
                    Text(g.rows.count == 1 ? "1 process" : "\(g.rows.count) processes").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(String(format: "%.1f%%", g.cpuPercent)).font(.callout.monospacedDigit())
                    .foregroundStyle(g.cpuPercent > 50 ? .orange : .secondary).frame(width: 56, alignment: .trailing)
                Text(Format.size(g.memory)).font(.callout.monospacedDigit()).frame(width: 76, alignment: .trailing)
            }
            .padding(.vertical, 1)
            .tag(g.id)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Picker("Sort", selection: $vm.processSort) {
                    Text("Memory").tag(ProcessSort.memory)
                    Text("CPU").tag(ProcessSort.cpu)
                }
                .pickerStyle(.segmented).frame(width: 150)
                TextField("Filter", text: $vm.processSearch).textFieldStyle(.roundedBorder)
                Spacer()
                Text("CPU").font(.caption).foregroundStyle(.secondary).frame(width: 56, alignment: .trailing)
                Text("Memory").font(.caption).foregroundStyle(.secondary).frame(width: 76, alignment: .trailing)
            }
            .padding(8)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
        }
        .overlay {
            if vm.processGroups.isEmpty {
                ProgressView("Sampling processes…")
            }
        }
    }
}

private struct ProcessRowLine: View {
    let pid: String, name: String, user: String, cpu: String, mem: String, header: Bool
    var body: some View {
        HStack(spacing: 8) {
            Text(pid).frame(width: 56, alignment: .trailing)
            Text(name).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
            Text(user).frame(width: 70, alignment: .leading).lineLimit(1)
            Text(cpu).frame(width: 56, alignment: .trailing)
            Text(mem).frame(width: 76, alignment: .trailing)
        }
        .font(header ? .caption.weight(.medium) : .callout.monospacedDigit())
        .foregroundStyle(header ? .secondary : .primary)
        .padding(.horizontal, 8).padding(.vertical, 4)
    }
}

struct ProcessDetailView: View {
    let group: ProcessGroup
    @ObservedObject var vm: ScanViewModel
    var body: some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) { bar }
    }

    private var bar: some View {
        ActionBar {
            if let b = group.bundlePath {
                Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: b)]) } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
            }
            Spacer()
            Button { vm.quit(group, force: false) } label: { Label("Quit", systemImage: "xmark.circle") }
                .disabled(!group.rows.contains { $0.isOwn })
                .help("Asks the app to quit normally, like ⌘Q. Unsaved work can be saved.")
            Button(role: .destructive) { vm.pendingForceQuit = group } label: { Label("Force Quit", systemImage: "bolt.fill") }
                .disabled(!group.rows.contains { $0.isOwn })
                .help("Kills the processes immediately. Unsaved work is lost.")
        }
    }

    // Inside a ScrollView like the other detail panes. A wrapping Text placed directly in the
    // split view's detail column (no ScrollView) sends SwiftUI into a layout loop that blanks the sidebar.
    private var content: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                if let b = group.bundlePath {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: b)).resizable().frame(width: 48, height: 48)
                } else {
                    Image(systemName: "terminal").font(.system(size: 36)).foregroundStyle(.secondary).frame(width: 48, height: 48)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name).font(.title2).fontWeight(.semibold)
                    Text(group.bundlePath ?? group.rows.first?.path ?? "").font(.callout.monospaced()).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                }
            }

            HStack(spacing: 24) {
                Stat(label: "Memory", value: Format.size(group.memory))
                Stat(label: "CPU", value: String(format: "%.1f%%", group.cpuPercent))
                Stat(label: "Processes", value: "\(group.rows.count)")
                if let share = vm.memoryShare(of: group) {
                    Stat(label: "Of used memory", value: String(format: "%.0f%%", share * 100))
                }
            }

            // verbatim: a literal "%" inside Text("…") is parsed as a format specifier and corrupts the window layout.
            Text(verbatim: "CPU is per core: 100% means one core fully busy. Memory is the physical footprint, the same figure Activity Monitor shows.")
                .font(.caption).foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ProcessRowLine(pid: "PID", name: "Process", user: "User", cpu: "CPU", mem: "Memory", header: true)
                Divider()
                VStack(spacing: 0) {
                    ForEach(group.rows) { r in
                        ProcessRowLine(pid: String(r.pid), name: r.name, user: r.user,
                                       cpu: String(format: "%.1f%%", r.cpuPercent), mem: Format.size(r.memory), header: false)
                            .help(r.path)
                        Divider()
                    }
                }
            }
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(24)
        .frame(maxWidth: 680, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
