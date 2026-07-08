import SwiftUI

// Compact, live system-status widget: three animated ring gauges for CPU, RAM
// and temperature. Tap to open the full System screen.
struct SystemWidget: View {
    let system: SystemStats?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                HStack {
                    Label(system?.chip ?? "Mac", systemImage: "cpu.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
                HStack(spacing: 14) {
                    RingGauge(fraction: cpuFraction, display: cpuText, label: "CPU", color: color(cpu, warm: 70, hot: 90))
                    RingGauge(fraction: ramFraction, display: ramText, label: "RAM", color: color(ram, warm: 80, hot: 92))
                    RingGauge(fraction: tempFraction, display: tempText, label: "TEMP", color: color(temp, warm: 60, hot: 80))
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Theme.accentSoft)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.accent.opacity(0.18), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    // Values (0 when unknown).
    private var cpu: Double { system?.cpuPercent ?? 0 }
    private var ram: Double { system?.memPercent ?? 0 }
    private var temp: Double { system?.tempCpu ?? 0 }

    private var cpuFraction: Double { min(cpu / 100, 1) }
    private var ramFraction: Double { min(ram / 100, 1) }
    private var tempFraction: Double { temp > 0 ? min(temp / 100, 1) : 0 }

    private var cpuText: String { system?.cpuPercent != nil ? "\(Int(cpu))%" : "—" }
    private var ramText: String { system?.memPercent != nil ? "\(Int(ram))%" : "—" }
    private var tempText: String { (system?.tempCpu).map { "\(Int($0))°" } ?? "—" }

    private func color(_ v: Double, warm: Double, hot: Double) -> Color {
        if v <= 0 { return .secondary }
        if v >= hot { return .red }
        if v >= warm { return .orange }
        return Theme.accent
    }
}

struct RingGauge: View {
    let fraction: Double
    let display: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle().stroke(color.opacity(0.16), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: max(0.001, fraction))
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.6), value: fraction)
                Text(display)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
            }
            .frame(width: 54, height: 54)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
