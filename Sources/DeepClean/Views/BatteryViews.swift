import SwiftUI
import Charts

struct EnergyListView: View {
    @ObservedObject var vm: ScanViewModel

    var body: some View {
        List(selection: vm.energySelection) {
            HStack(spacing: 10) {
                Image(systemName: "chart.xyaxis.line").foregroundStyle(.green).frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Battery history")
                    Text(vm.system.hasBattery ? "Charge over the last days, \(vm.system.batteryPercent)% now" : "No battery in this Mac")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 1)
            .tag(EnergyGroup.historyID)

            Section("Energy impact by app") {
                ForEach(vm.sortedEnergyGroups) { g in
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
                            Text(g.rows.isEmpty ? "not running" : g.rows.count == 1 ? "1 process" : "\(g.rows.count) processes")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(String(format: "%.1f", g.power)).font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary).frame(width: 56, alignment: .trailing)
                        let avg = vm.averageEnergy(of: g.id)
                        Text(String(format: "%.1f", avg)).font(.callout.monospacedDigit())
                            .foregroundStyle(avg > 20 ? .orange : .primary).frame(width: 64, alignment: .trailing)
                    }
                    .padding(.vertical, 1)
                    .tag(g.id)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text(vm.energySamples == 0 ? "Measuring…" : "Average of \(vm.energySamples) sample\(vm.energySamples == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("Now").font(.caption).foregroundStyle(.secondary).frame(width: 56, alignment: .trailing)
                Text("Average").font(.caption).foregroundStyle(.secondary).frame(width: 64, alignment: .trailing)
            }
            .padding(8)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
        }
    }
}

struct BatteryHistoryView: View {
    @ObservedObject var vm: ScanViewModel

    var body: some View {
        // Inside a ScrollView like the other detail panes (see ProcessDetailView).
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Battery").font(.title2).fontWeight(.semibold)

                let s = vm.system
                if s.hasBattery {
                    HStack(spacing: 24) {
                        Stat(label: "Charge", value: "\(s.batteryPercent)%")
                        Stat(label: "Source", value: s.charging ? "Charging" : s.onAC ? "Power adapter" : "Battery")
                        if let m = s.minutesRemaining {
                            Stat(label: s.charging ? "Time to full" : "Time left", value: String(format: "%d:%02d", m / 60, m % 60))
                        }
                        if let h = s.healthPercent { Stat(label: "Health", value: "\(h)%") }
                        if let c = s.cycleCount { Stat(label: "Cycles", value: "\(c)") }
                    }
                }

                // The log only has past events; end the latest stretch at the live reading.
                let readings = vm.batteryReadings.isEmpty || !s.hasBattery ? vm.batteryReadings
                    : vm.batteryReadings + [BatteryReading(date: Date(), percent: s.batteryPercent, onAC: s.onAC)]
                if vm.isLoadingBatteryHistory && readings.isEmpty {
                    ProgressView("Reading the power log…").frame(maxWidth: .infinity, minHeight: 200)
                } else if readings.isEmpty {
                    Text("macOS has no battery readings in its power log on this Mac.")
                        .foregroundStyle(.secondary)
                } else {
                    let sessions = BatteryHistory.sessions(readings)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Charge level").font(.headline)
                        chart(readings, sessions: sessions)
                        HStack(spacing: 14) {
                            HStack(spacing: 4) { Rectangle().fill(.blue).frame(width: 14, height: 2); Text("Charge %") }
                            HStack(spacing: 4) { Rectangle().fill(.green.opacity(0.18)).frame(width: 14, height: 10); Text("On power adapter") }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("On battery and on power").font(.headline)
                        sessionTable(sessions)
                    }
                    // verbatim: a literal "%" inside Text("…") is parsed as a format specifier.
                    Text(verbatim: "From the macOS power log, which keeps about a week of readings taken at sleep, wake and other power events. Drain is percentage points lost per hour on battery, including time asleep.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: 680, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func chart(_ readings: [BatteryReading], sessions: [BatterySession]) -> some View {
        Chart {
            ForEach(sessions.filter(\.onAC)) { s in
                RectangleMark(xStart: .value("Start", s.start), xEnd: .value("End", s.end), yStart: .value("Low", 0), yEnd: .value("High", 100))
                    .foregroundStyle(.green.opacity(0.18))
            }
            ForEach(readings, id: \.self) { r in
                LineMark(x: .value("Time", r.date), y: .value("Charge", r.percent))
                    .foregroundStyle(.blue)
                    .interpolationMethod(.linear)
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 25, 50, 75, 100]) { v in
                AxisGridLine()
                AxisValueLabel { Text("\(v.as(Int.self) ?? 0)%") }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.weekday(.abbreviated).day())
            }
        }
        .frame(height: 200)
    }

    private func sessionTable(_ sessions: [BatterySession]) -> some View {
        VStack(spacing: 0) {
            SessionLine(when: "When", source: "Source", charge: "Charge", duration: "Duration", drain: "Drain", header: true)
            Divider()
            // Source switches seconds apart (plugging in and out) are noise in a table.
            ForEach(sessions.filter { $0.hours >= 1.0 / 60 }.prefix(30)) { s in
                SessionLine(when: Self.when(s), source: s.onAC ? "Power" : "Battery",
                            charge: "\(s.fromPercent)% → \(s.toPercent)%",
                            duration: Self.duration(s.hours),
                            drain: s.drainPerHour.map { String(format: "%.1f%%/h", $0) } ?? "–", header: false)
                Divider()
            }
        }
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
    }

    private static func when(_ s: BatterySession) -> String {
        let day = Calendar.current.isDateInToday(s.start) ? "Today" : Calendar.current.isDateInYesterday(s.start) ? "Yesterday"
            : s.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        return "\(day) \(s.start.formatted(date: .omitted, time: .shortened))"
    }

    private static func duration(_ hours: Double) -> String {
        let m = Int((hours * 60).rounded())
        return m < 60 ? "\(m) min" : String(format: "%d h %02d min", m / 60, m % 60)
    }
}

private struct SessionLine: View {
    let when: String, source: String, charge: String, duration: String, drain: String, header: Bool
    var body: some View {
        HStack(spacing: 8) {
            Text(when).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
            Text(source).frame(width: 60, alignment: .leading)
            Text(charge).frame(width: 96, alignment: .trailing)
            Text(duration).frame(width: 90, alignment: .trailing)
            Text(drain).frame(width: 70, alignment: .trailing)
        }
        .font(header ? .caption.weight(.medium) : .callout.monospacedDigit())
        .foregroundStyle(header ? .secondary : .primary)
        .padding(.horizontal, 8).padding(.vertical, 4)
    }
}

struct EnergyDetailView: View {
    let group: EnergyGroup
    @ObservedObject var vm: ScanViewModel

    var body: some View {
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
                    Stat(label: "Energy impact now", value: String(format: "%.1f", group.power))
                    Stat(label: "Average", value: String(format: "%.1f", vm.averageEnergy(of: group.id)))
                    Stat(label: "Processes", value: "\(group.rows.count)")
                }

                Text("Energy impact is the figure Activity Monitor shows in its Energy tab: CPU, GPU, wakeups and other work, weighted by what they cost in power. Average covers the time since you opened this view; apps that quit stay in the list.")
                    .font(.caption).foregroundStyle(.secondary)

                if !group.rows.isEmpty {
                    VStack(spacing: 0) {
                        EnergyRowLine(pid: "PID", name: "Process", power: "Energy impact", header: true)
                        Divider()
                        ForEach(group.rows) { r in
                            EnergyRowLine(pid: String(r.pid), name: r.name, power: String(format: "%.1f", r.power), header: false)
                                .help(r.path)
                            Divider()
                        }
                    }
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(24)
            .frame(maxWidth: 680, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct EnergyRowLine: View {
    let pid: String, name: String, power: String, header: Bool
    var body: some View {
        HStack(spacing: 8) {
            Text(pid).frame(width: 56, alignment: .trailing)
            Text(name).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
            Text(power).frame(width: 96, alignment: .trailing)
        }
        .font(header ? .caption.weight(.medium) : .callout.monospacedDigit())
        .foregroundStyle(header ? .secondary : .primary)
        .padding(.horizontal, 8).padding(.vertical, 4)
    }
}
