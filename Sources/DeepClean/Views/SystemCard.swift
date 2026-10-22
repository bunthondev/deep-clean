import SwiftUI

/// Live CPU / memory / battery readout for the sidebar.
struct SystemCard: View {
    let s: SystemSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Meter(title: "CPU", value: s.cpuPercent / 100,
                  trailing: "\(Int(s.cpuPercent.rounded()))%",
                  detail: s.cpuName.isEmpty ? "\(s.cores) cores" : "\(s.cpuName) · \(s.cores) cores",
                  color: s.cpuPercent > 85 ? .red : .blue)

            Meter(title: "Memory", value: s.memoryTotal > 0 ? Double(s.memoryUsed) / Double(s.memoryTotal) : 0,
                  trailing: "\(Format.size(s.memoryUsed)) / \(Format.size(s.memoryTotal))",
                  detail: "Pressure \(s.memoryPressure)",
                  color: s.memoryPressure == "critical" ? .red : s.memoryPressure == "warning" ? .orange : .green)

            if s.hasBattery {
                Meter(title: "Battery", value: Double(s.batteryPercent) / 100,
                      trailing: "\(s.batteryPercent)%" + (s.charging ? " ⚡︎" : s.onAC ? " 🔌" : ""),
                      detail: batteryDetail,
                      color: s.batteryPercent <= 20 && !s.onAC ? .red : .green)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private var batteryDetail: String {
        var parts: [String] = []
        if s.charging { parts.append("charging") }
        else if s.onAC { parts.append("on power") }
        if let m = s.minutesRemaining { parts.append(String(format: "%d:%02d %@", m / 60, m % 60, s.charging ? "to full" : "left")) }
        if let h = s.healthPercent { parts.append("health \(h)%") }
        if let c = s.cycleCount { parts.append("\(c) cycles") }
        if let t = s.batteryTemperatureC { parts.append(String(format: "%.0f°C", t)) }
        return parts.joined(separator: " · ")
    }

    private struct Meter: View {
        let title: String
        let value: Double
        let trailing: String
        let detail: String
        let color: Color

        var body: some View {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title).font(.subheadline).fontWeight(.medium)
                    Spacer()
                    Text(trailing).font(.caption.monospacedDigit())
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(.quaternary)
                        Rectangle().fill(color).frame(width: geo.size.width * min(1, max(0, value)))
                            .animation(.easeOut(duration: 0.4), value: value)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .frame(height: 6)
                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
        }
    }
}
