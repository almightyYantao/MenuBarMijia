import SwiftUI
import MijiaCore

/// Temperature / humidity sensor card: large temperature, humidity ring, comfort hint, battery.
/// Compact (half row) stacks temperature over a humidity bar; full row lays them out side by side.
struct SensorCardView: View {
    @Environment(\.appSkin) private var skin
    @Environment(\.skinPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    /// Observed so a temperature-unit change in Settings re-renders open cards (#52).
    @AppStorage(TemperatureUnitPreference.storageKey) private var temperatureUnitRaw = TemperatureUnitPreference.system.rawValue

    let device: SmartDevice
    let spec: SensorSpec
    let isCompact: Bool
    let showRoomBadge: Bool

    private var fg: Color { skin.isClassic ? .primary : palette.fg }
    private var muted: Color { skin.isClassic ? .secondary : palette.muted }
    private var track: Color { skin.isClassic ? Color.primary.opacity(0.08) : palette.chip }

    var body: some View {
        Group {
            if isCompact { compact } else { wide }
        }
        .frame(minHeight: isCompact ? (skin.isClassic ? 50 : 60) : nil, maxHeight: .infinity)
        .glassTile(isActive: false, accent: .teal, cornerRadius: 14)
        .opacity(device.isOnline ? 1 : 0.58)
        // Display-only card: VoiceOver reads one sentence instead of five loose labels (#41).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilitySummary))
    }

    private var accessibilitySummary: String {
        guard device.isOnline else {
            return L10n.tr("\(device.name)，离线", "\(device.name), offline")
        }
        var parts: [String] = [device.name]
        if let t = spec.temperature {
            parts.append(L10n.format("温度 %@", "temperature %@", L10n.temperature(t, fractionDigits: 1)))
        }
        if let h = spec.humidity {
            parts.append(String(format: L10n.tr("湿度 %.0f%%", "humidity %.0f%%"), h))
        }
        if let b = spec.battery {
            parts.append(L10n.tr("电量 \(b)%", "battery \(b)%"))
        }
        return parts.joined(separator: "，")
    }

    // MARK: Layouts

    private var compact: some View {
        VStack(alignment: .leading, spacing: skin.isClassic ? 2.5 : 3.5) {
            HStack(spacing: 4) {
                Image(systemName: "thermometer.medium")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(tempColor)
                Text(displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(muted)
                    .lineLimit(1)
                Spacer(minLength: 2)
                comfortChip
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                temperatureText(size: skin.isClassic ? 16.5 : 19)
                if let h = spec.humidity {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 8.5, weight: .semibold))
                        Text(String(format: "%.0f%%", h))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    .foregroundStyle(humidityColor)
                }
            }
            humidityBar
        }
        .padding(.horizontal, !skin.isClassic && palette.capsuleTiles ? 15 : (skin.isClassic ? 9 : 11))
        .padding(.vertical, skin.isClassic ? 6 : 7.5)
    }

    private var wide: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(fg)
                        .lineLimit(1)
                    if showRoomBadge {
                        Text(L10n.displayRoomName(device.roomName))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(muted)
                    }
                }
                temperatureText(size: 34)
                HStack(spacing: 6) {
                    comfortChip
                    if let b = spec.battery {
                        Label("\(b)%", systemImage: batterySymbol(b))
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(b <= 20 ? Color.red : muted)
                    }
                }
            }
            Spacer(minLength: 0)
            if let h = spec.humidity { humidityRing(h) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: Pieces

    private func temperatureText(size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(spec.temperature.map { L10n.temperatureValue($0, fractionDigits: 1) } ?? "--")
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: spec.temperature ?? 0))
                .foregroundStyle(fg)
            Text(L10n.temperatureSymbol)
                .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                .foregroundStyle(muted)
        }
    }

    private var humidityBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous).fill(track)
                Capsule(style: .continuous)
                    .fill(LinearGradient(colors: [humidityColor.opacity(0.6), humidityColor], startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * CGFloat(min(max((spec.humidity ?? 0) / 100, 0), 1)))
            }
        }
        .frame(height: isCompact ? 3 : 4)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: spec.humidity)
    }

    private func humidityRing(_ h: Double) -> some View {
        ZStack {
            Circle().stroke(track, lineWidth: 6)
            // Comfortable band 40–60% drawn faintly behind the value arc.
            Circle()
                .trim(from: 0.4, to: 0.6)
                .stroke(Color.green.opacity(0.25), style: StrokeStyle(lineWidth: 6, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            Circle()
                .trim(from: 0, to: CGFloat(min(max(h / 100, 0), 1)))
                .stroke(
                    AngularGradient(colors: [humidityColor.opacity(0.55), humidityColor], center: .center),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(humidityColor)
                Text(String(format: "%.0f%%", h))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(fg)
            }
        }
        .frame(width: 62, height: 62)
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: h)
    }

    private var comfortChip: some View {
        let c = comfort
        return Text(c.label)
            .font(.system(size: isCompact ? 10 : 10.5, weight: .semibold))
            .foregroundStyle(c.color)
            .padding(.horizontal, isCompact ? 5.5 : 6)
            .padding(.vertical, isCompact ? 1.5 : 2)
            .background(Capsule(style: .continuous).fill(c.color.opacity(0.14)))
    }

    // MARK: Semantics

    private var displayName: String {
        let n = device.name.replacingOccurrences(of: "米家智能温湿度计", with: "温湿度计")
        return n.isEmpty ? device.name : n
    }

    private var comfort: (label: String, color: Color) {
        let t = spec.temperature ?? 24, h = spec.humidity ?? 50
        if t >= 28 { return (L10n.tr("偏热", "Warm"), .orange) }
        if t <= 16 { return (L10n.tr("偏冷", "Cool"), .blue) }
        if h < 35 { return (L10n.tr("偏干", "Dry"), Color(red: 0.85, green: 0.55, blue: 0.1)) }
        if h > 70 { return (L10n.tr("偏湿", "Humid"), .teal) }
        return (L10n.tr("舒适", "Comfy"), Color(red: 0.2, green: 0.68, blue: 0.4))
    }

    private var tempColor: Color {
        guard let t = spec.temperature else { return muted }
        if t >= 28 { return .orange }
        if t <= 16 { return .blue }
        return Color(red: 0.2, green: 0.68, blue: 0.4)
    }

    private var humidityColor: Color { Color(red: 0.25, green: 0.62, blue: 0.98) }

    private func batterySymbol(_ b: Int) -> String {
        switch b {
        case ..<15: return "battery.0percent"
        case ..<40: return "battery.25percent"
        case ..<65: return "battery.50percent"
        case ..<90: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}
