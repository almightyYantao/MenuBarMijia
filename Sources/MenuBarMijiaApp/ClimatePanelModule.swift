import SwiftUI
import MijiaCore

/// Full-width air-conditioner panel: power, target temperature stepper with a range gauge, and
/// mode chips on one card, so the common controls need no drawer.
struct ClimatePanelModule: View {
    @Environment(\.appSkin) private var skin
    @Environment(\.skinPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var modeNamespace

    let device: SmartDevice
    let spec: ClimateSpec
    let store: HomeStore
    let showRoomBadge: Bool
    var forceExpanded = false

    private var isRunning: Bool { device.isOnline && spec.isOn && spec.hvacMode != "off" }

    private var accent: Color {
        skin.isClassic ? DevicePalette.accentColor(for: device) : palette.accent
    }

    private var modeColor: Color {
        spec.hvacMode == "heat" ? Color(red: 0.95, green: 0.42, blue: 0.18) : Color(red: 0.12, green: 0.58, blue: 0.96)
    }

    private var fg: Color { skin.isClassic ? .primary : (isRunning ? palette.activeText : palette.fg) }
    private var muted: Color { skin.isClassic ? .secondary : palette.muted }

    private var isExpanded: Bool { forceExpanded || store.expandedDeviceId == device.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            strip
            gauge
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if !modes.isEmpty { modeChips }
                    if !spec.availableFanModes.isEmpty {
                        optionRow(icon: "fan.fill", options: spec.availableFanModes, current: spec.fanMode) {
                            store.setClimateFanMode(device.id, fanMode: $0)
                        }
                    }
                    if !spec.availableSwingModes.isEmpty {
                        optionRow(icon: "arrow.up.and.down", options: spec.availableSwingModes, current: spec.swingMode) {
                            store.setClimateSwingMode(device.id, swingMode: $0)
                        }
                    }
                }
                .transition(AppleMotion.drawerTransition)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .glassTile(isActive: isRunning, accent: accent, cornerRadius: 16)
        .opacity(device.isOnline ? 1 : 0.58)
        .disabled(!device.isOnline)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: isRunning)
    }

    // MARK: Strip: power badge · name (tap to expand) · − temp +

    private var strip: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(AppleMotion.snappySpring) { store.togglePrimary(device) }
                if device.isOnline { SoundFeedback.playSuccess() }
            } label: {
                ZStack {
                    Circle()
                        .fill(isRunning ? (skin.isClassic ? AnyShapeStyle(modeColor) : AnyShapeStyle(palette.accentGradient)) : AnyShapeStyle(skin.isClassic ? Color.primary.opacity(0.08) : palette.chip))
                        .frame(width: 32, height: 32)
                        .shadowIf(isRunning, color: accent.opacity(0.4), radius: 6)
                    Image(systemName: spec.hvacMode == "heat" ? "flame.fill" : "snowflake")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isRunning ? (skin.isClassic ? Color.white : palette.onAccent) : muted)
                        .rotationEffect(.degrees(isRunning && !reduceMotion && spec.hvacMode != "heat" ? 180 : 0))
                        .animation(.spring(response: 0.8, dampingFraction: 0.6), value: isRunning)
                }
            }
            .buttonStyle(PressableCardButtonStyle(scaleAmount: 0.88))
            .accessibilityLabel(Text(isRunning
                ? L10n.tr("关闭 \(device.name)", "Turn off \(device.name)")
                : L10n.tr("打开 \(device.name)", "Turn on \(device.name)")))
            .skinHelp(isRunning ? L10n.tr("关闭空调", "Turn off") : L10n.tr("打开空调", "Turn on"))

            Button {
                withAnimation(AppleMotion.snappySpring) { store.toggleExpanded(device.id) }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(fg)
                        .lineLimit(1)
                    HStack(spacing: 3) {
                        Text(showRoomBadge ? "\(L10n.displayRoomName(device.roomName)) · \(statusLine)" : statusLine)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .skinHelp(L10n.tr("展开模式与风速", "Show modes and fan speed"))

            stepButton(symbol: "minus", delta: -spec.step)

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(formatted(spec.targetTemperature))
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: spec.targetTemperature))
                Text("°")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(muted)
            }
            .foregroundStyle(fg)
            .frame(minWidth: 44)

            stepButton(symbol: "plus", delta: spec.step)
        }
    }

    private var statusLine: String {
        guard isRunning else { return L10n.tr("已关闭", "Off") }
        var parts = [SmartDevice.localizeHVACMode(spec.hvacMode)]
        if let cur = spec.currentTemperature { parts.append(String(format: L10n.tr("室温 %.1f°", "Room %.1f°"), cur)) }
        return parts.joined(separator: " · ")
    }

    private var gauge: some View {
        let span = max(spec.maxTemp - spec.minTemp, 1)
        let progress = min(max((spec.targetTemperature - spec.minTemp) / span, 0), 1)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                Capsule(style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(red: 0.30, green: 0.66, blue: 1.0), Color(red: 1.0, green: 0.56, blue: 0.24)],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .opacity(isRunning ? 1 : 0.35)
                    .frame(width: max(6, geo.size.width * progress))
            }
        }
        .frame(height: 4)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: spec.targetTemperature)
    }

    private func stepButton(symbol: String, delta: Double) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                store.stepClimateTemperature(device.id, delta: delta)
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(fg)
                .frame(width: 28, height: 28)
                .adaptiveGlass(in: Circle(), interactive: true)
        }
        .buttonStyle(PressableCardButtonStyle(scaleAmount: 0.86))
        .accessibilityLabel(Text(delta > 0
            ? L10n.tr("升高目标温度", "Raise target temperature")
            : L10n.tr("降低目标温度", "Lower target temperature")))
    }

    // MARK: Modes

    private var modes: [String] { spec.availableModes.filter { $0 != "off" } }

    private var modeChips: some View {
        HStack(spacing: 4) {
            ForEach(modes, id: \.self) { mode in
                let selected = isRunning && spec.hvacMode == mode
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        store.setClimateMode(device.id, mode: mode)
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: symbol(for: mode)).font(.system(size: 9.5, weight: .semibold))
                        Text(SmartDevice.localizeHVACMode(mode)).font(.system(size: 11, weight: selected ? .semibold : .medium))
                    }
                    .foregroundStyle(selected ? (skin.isClassic ? Color.white : palette.onAccent) : muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background {
                        if selected {
                            Capsule(style: .continuous)
                                .fill(skin.isClassic ? AnyShapeStyle(modeColor) : AnyShapeStyle(palette.accentGradient))
                                .matchedGeometryEffect(id: "mode", in: modeNamespace)
                        }
                    }
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(PressableCardButtonStyle(scaleAmount: 0.94))
            }
        }
        .padding(3)
        .adaptiveGlass(in: Capsule(style: .continuous))
    }

    /// Fan speed / swing: a compact labelled row of chips, scrolling when the device lists many levels.
    private func optionRow(icon: String, options: [String], current: String?, onSelect: @escaping (String) -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(muted)
                .frame(width: 14)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(options, id: \.self) { option in
                        Button(Self.localizeOption(option)) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { onSelect(option) }
                        }
                        .buttonStyle(PillActionButtonStyle(isSelected: option == current, tintColor: skin.isClassic ? modeColor : .accentColor))
                    }
                }
                .padding(6)
            }
            .padding(-6)
        }
    }

    static func localizeOption(_ raw: String) -> String {
        switch raw.lowercased() {
        case "auto": return L10n.tr("自动", "Auto")
        case "low", "silent", "quiet": return L10n.tr("低", "Low")
        case "medium", "middle": return L10n.tr("中", "Medium")
        case "high": return L10n.tr("高", "High")
        case "on": return L10n.tr("开", "On")
        case "off": return L10n.tr("关", "Off")
        default:
            if raw.lowercased().hasPrefix("level"), let n = Int(raw.dropFirst(5)) { return L10n.tr("\(n) 档", "Lv \(n)") }
            return raw
        }
    }

    private func symbol(for mode: String) -> String {
        switch mode {
        case "cool": return "snowflake"
        case "heat": return "flame.fill"
        case "dry": return "drop.fill"
        case "fan_only": return "wind"
        case "auto": return "a.circle.fill"
        default: return "circle"
        }
    }

    private func formatted(_ t: Double) -> String {
        t.rounded() == t ? String(format: "%.0f", t) : String(format: "%.1f", t)
    }
}
