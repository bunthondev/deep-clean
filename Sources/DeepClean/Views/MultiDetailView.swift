import SwiftUI

/// Shown when several items are selected: a summary plus one Trash action for all of them.
struct MultiDetailView: View {
    let items: [CleanItem]
    @ObservedObject var vm: ScanViewModel

    private var trashable: [CleanItem] { items.filter { $0.tier != .personal } }
    private var skipped: Int { items.count - trashable.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(items.count) items selected").font(.title2).fontWeight(.semibold)
                Text(Format.size(items.reduce(0) { $0 + $1.bytes }) + " in total").foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                ForEach(Tier.allCases) { tier in
                    let n = items.filter { $0.tier == tier }.count
                    if n > 0 {
                        Label("\(n) \(tier.title.lowercased())", systemImage: tier.symbol)
                            .foregroundStyle(tier.color).font(.callout)
                    }
                }
            }

            List(items) { item in
                HStack(spacing: 10) {
                    ItemRow(item: item)
                    Button { vm.reveal(item) } label: { Image(systemName: "magnifyingglass") }
                        .buttonStyle(.borderless).help("Reveal in Finder")
                    Button { vm.selection.remove(item.id) } label: { Image(systemName: "xmark.circle") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary).help("Remove from selection")
                }
                .contextMenu {
                    Button("Reveal in Finder") { vm.reveal(item) }
                    Button("Remove from selection") { vm.selection.remove(item.id) }
                }
            }
            .listStyle(.inset)
            .frame(minHeight: 160)

            if skipped > 0 {
                Label("\(skipped) personal item\(skipped == 1 ? "" : "s") will be skipped. Personal data is report-only.", systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }

        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ActionBar {
                Button("Clear selection") { vm.selection = [] }
                Spacer()
                Button(role: .destructive) { vm.askToTrash(trashable) } label: {
                    Label("Move \(trashable.count) items to Trash…", systemImage: "trash")
                }
                .disabled(trashable.isEmpty)
            }
        }
    }
}
