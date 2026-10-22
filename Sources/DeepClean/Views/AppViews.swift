import SwiftUI

/// Used / purgeable / free bar for the boot volume, shown at the top of the sidebar.
struct StorageCard: View {
    let storage: StorageInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Macintosh HD", systemImage: "internaldrive.fill").font(.subheadline).fontWeight(.medium)
                Spacer()
                Text(Format.size(storage.total)).font(.caption).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                let w = geo.size.width
                let total = max(1, Double(storage.total))
                HStack(spacing: 1) {
                    Rectangle().fill(.blue).frame(width: w * Double(storage.used) / total)
                    Rectangle().fill(.orange.opacity(0.7)).frame(width: w * Double(storage.purgeable) / total)
                    Rectangle().fill(.quaternary)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 10)
            HStack(spacing: 12) {
                Legend(color: .blue, label: "Used", value: storage.used)
                Legend(color: .orange.opacity(0.7), label: "Purgeable", value: storage.purgeable)
                Legend(color: .secondary.opacity(0.3), label: "Free", value: storage.available)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        .help("Purgeable space is held by macOS (local snapshots, caches) and released automatically when needed.")
    }

    private struct Legend: View {
        let color: Color
        let label: String
        let value: Int64
        var body: some View {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 0) {
                    Text(label).font(.caption2).foregroundStyle(.secondary)
                    Text(Format.size(value)).font(.caption.monospacedDigit())
                }
            }
        }
    }
}

struct AppListView: View {
    @ObservedObject var vm: ScanViewModel

    var body: some View {
        List(vm.filteredApps, selection: vm.appSelection) { app in
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                    .resizable().frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(app.name).lineLimit(1)
                        if app.isRunning {
                            Text("running").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                                .background(.green.opacity(0.15), in: Capsule()).foregroundStyle(.green)
                        }
                    }
                    Text(subtitle(app)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(Format.size(app.bytes)).monospacedDigit().foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            .tag(app.id)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                TextField("Filter apps", text: $vm.appSearch).textFieldStyle(.roundedBorder)
                Text("\(vm.apps.count) apps, \(Format.size(vm.appsTotalBytes))").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .padding(8)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
        }
        .overlay {
            if vm.apps.isEmpty && !vm.isScanningApps {
                ContentUnavailableView("No apps listed yet", systemImage: "app.dashed",
                                       description: Text("Press Scan to list the apps in /Applications with their size and leftovers."))
            }
        }
    }

    private func subtitle(_ app: InstalledApp) -> String {
        var parts = [app.source.rawValue]
        if let v = app.version { parts.append("v\(v)") }
        if let d = app.lastUsed { parts.append("used " + Format.date.localizedString(for: d, relativeTo: .now)) }
        else { parts.append("never opened") }
        return parts.joined(separator: " · ")
    }
}

struct AppDetailView: View {
    let app: InstalledApp
    @ObservedObject var vm: ScanViewModel
    // @State is a macro unavailable with Command Line Tools; a tiny ObservableObject does the job.
    @StateObject private var picks = LeftoverPicks()
    private var excluded: Set<String> { picks.excluded }

    private var found: [Leftover]? { vm.leftovers[app.id] }
    private var chosen: [Leftover] { (found ?? []).filter { !excluded.contains($0.path) } }
    private var leftoverBytes: Int64 { chosen.reduce(0) { $0 + $1.bytes } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.name).font(.title2).fontWeight(.semibold)
                        Text([app.version.map { "Version \($0)" }, app.bundleID].compactMap { $0 }.joined(separator: " · "))
                            .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }

                HStack(spacing: 24) {
                    Stat(label: "App size", value: Format.size(app.bytes))
                    Stat(label: "Leftovers", value: found == nil ? "…" : Format.size((found ?? []).reduce(0) { $0 + $1.bytes }))
                    Stat(label: "Source", value: app.source.rawValue)
                    Stat(label: "Last used", value: app.lastUsed.map { Format.date.localizedString(for: $0, relativeTo: .now) } ?? "never")
                }

                if app.isRunning {
                    Label("\(app.name) is running. Quit it before uninstalling.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.callout)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Leftover files in ~/Library").font(.subheadline).fontWeight(.medium)
                        if found == nil { ProgressView().controlSize(.mini) }
                    }
                    Text("Matched by bundle identifier and exact app name. Uncheck anything you want to keep, for example settings you may reuse after reinstalling.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let found {
                        if found.isEmpty {
                            Text("No leftovers found.").font(.callout).foregroundStyle(.tertiary)
                        }
                        ForEach(found) { l in
                            HStack(spacing: 8) {
                                Toggle("", isOn: Binding(
                                    get: { !picks.excluded.contains(l.path) },
                                    set: { on in if on { picks.excluded.remove(l.path) } else { picks.excluded.insert(l.path) } }
                                )).labelsHidden().toggleStyle(.checkbox)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(l.kind).font(.callout)
                                    Text(l.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                        .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                }
                                Spacer()
                                Text(Format.size(l.bytes)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                                Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: l.path)]) } label: {
                                    Image(systemName: "magnifyingglass")
                                }.buttonStyle(.borderless).help("Reveal in Finder")
                            }
                        }
                    }
                }

                Text(app.path).font(.callout.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            }
            .padding(24)
            .frame(maxWidth: 680, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .task(id: app.id) { picks.excluded = []; vm.loadLeftovers(for: app) }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ActionBar {
                Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)]) } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                Spacer()
                Button { vm.askToUninstall(app, leftovers: chosen, includeApp: false) } label: {
                    Label("Remove leftovers only", systemImage: "broom")
                }
                .disabled(chosen.isEmpty)
                Button(role: .destructive) { vm.askToUninstall(app, leftovers: chosen, includeApp: true) } label: {
                    Label("Uninstall \(Format.size(app.bytes + leftoverBytes))…", systemImage: "trash")
                }
                .disabled(app.isRunning)
                .help(app.isRunning ? "Quit the app first" : "Moves the app and checked leftovers to the Trash after confirmation. Root-owned apps go through Finder, which asks for your password.")
            }
        }
    }
}

final class LeftoverPicks: ObservableObject {
    @Published var excluded: Set<String> = []
}

struct Stat: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.monospacedDigit()).fontWeight(.medium).lineLimit(1)
        }
    }
}
