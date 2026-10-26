import SwiftUI
import AppKit
import MijiaCore

// MARK: - Skin Catalog

/// Panel skins. `classic` keeps the original Liquid Glass look; the others paint opaque surfaces
/// from their own palette and turn on the richer motion set (sliding room pill, staggered tiles,
/// drag-to-dim, hold-to-confirm all-off).
public enum AppSkin: String, CaseIterable, Identifiable, Sendable {
    case classic, frost, night, glass, soft, bento, neon, capsule, dawn

    public static let storageKey = "app_skin"
    public static let climatePanelKey = "climate_panel_module"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .classic: return L10n.tr("经典", "Classic")
        case .frost: return L10n.tr("霜白", "Frost")
        case .night: return L10n.tr("夜航", "Night Flight")
        case .glass: return L10n.tr("液态玻璃", "Liquid Glass")
        case .soft: return L10n.tr("柔雾", "Soft Mist")
        case .bento: return L10n.tr("便当格", "Bento")
        case .neon: return L10n.tr("霓虹夜", "Neon")
        case .capsule: return L10n.tr("胶囊", "Capsule")
        case .dawn: return L10n.tr("晨光", "Dawn")
        }
    }

    public var isClassic: Bool { self == .classic }

    public var palette: SkinPalette {
        switch self {
        case .classic: return .classic
        case .frost: return .frost
        case .night: return .night
        case .glass: return .glass
        case .soft: return .soft
        case .bento: return .bento
        case .neon: return .neon
        case .capsule: return .capsule
        case .dawn: return .dawn
        }
    }
}

// MARK: - Panel Height

/// User-chosen panel height; `.max` fills the screen below the menu bar.
public enum PanelHeight: String, CaseIterable, Identifiable, Sendable {
    case compact, standard, tall, max

    public static let storageKey = "panel_height"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .compact: return L10n.tr("紧凑", "Compact")
        case .standard: return L10n.tr("标准", "Standard")
        case .tall: return L10n.tr("加高", "Tall")
        case .max: return L10n.tr("最大", "Max")
        }
    }

    @MainActor
    public var points: CGFloat {
        let screen = (NSScreen.main?.visibleFrame.height ?? 900) - 40
        switch self {
        case .compact: return 460
        case .standard: return Swift.min(560, screen)
        case .tall: return Swift.min(680, screen)
        case .max: return Swift.max(460, screen)
        }
    }
}

// MARK: - Palette

public struct SkinPalette: Sendable {
    public var background: [Color]
    public var fg: Color
    public var muted: Color
    public var line: Color
    public var chip: Color
    public var tile: Color
    public var accent: Color
    public var accentEnd: Color
    public var onAccent: Color
    public var activeTile: Color
    public var activeLine: Color
    public var activeText: Color
    public var fill: Color
    public var ok: Color
    public var scheme: ColorScheme?
    public var tileRadius: CGFloat = 14
    public var capsuleTiles = false
    public var neumorphic = false
    public var glow = false
    public var dashedIdle = false
    public var translucent = false
    public var fontDesign: Font.Design = .default

    static func hex(_ v: UInt32, _ a: Double = 1) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255, opacity: a)
    }

    static let classic = SkinPalette(
        background: [], fg: .primary, muted: .secondary, line: .clear, chip: .clear, tile: .clear,
        accent: .accentColor, accentEnd: .accentColor, onAccent: .white, activeTile: .clear, activeLine: .clear,
        activeText: .primary, fill: .clear, ok: .green, scheme: nil
    )

    static let frost = SkinPalette(
        background: [hex(0xF7F8FA)], fg: hex(0x1C1F24), muted: hex(0x7A818C), line: hex(0xE4E7EC),
        chip: .white, tile: .white, accent: hex(0xEF7D32), accentEnd: hex(0xEF7D32), onAccent: .white,
        activeTile: hex(0xFFF6EF), activeLine: hex(0xF6C9A6), activeText: hex(0xB4561A), fill: hex(0xFFE7D4),
        ok: hex(0x33B36B), scheme: .light
    )

    static let night = SkinPalette(
        background: [hex(0x131518)], fg: hex(0xECEAE4), muted: hex(0x969AA1), line: hex(0x3A3E46),
        chip: hex(0x2A2E34), tile: hex(0x22252B), accent: hex(0xF2B84B), accentEnd: hex(0xF2B84B), onAccent: hex(0x1A1406),
        activeTile: hex(0x2A2416), activeLine: hex(0x5A4A22), activeText: hex(0xF2B84B), fill: hex(0x3A3018),
        ok: hex(0x6FD08C), scheme: .dark, tileRadius: 12, glow: true
    )

    static let glass = SkinPalette(
        background: [hex(0xF6A96B), hex(0x6C6F9A), hex(0x2B3A52)], fg: .white, muted: .white.opacity(0.72),
        line: .white.opacity(0.38), chip: .white.opacity(0.18), tile: .white.opacity(0.14),
        accent: .white, accentEnd: .white, onAccent: hex(0xE4762E),
        activeTile: .white.opacity(0.85), activeLine: .white.opacity(0.9), activeText: hex(0x24324A), fill: .white.opacity(0.45),
        ok: hex(0x7CF0A6), scheme: .dark, tileRadius: 18, translucent: true
    )

    static let soft = SkinPalette(
        background: [hex(0xE7EAF0)], fg: hex(0x3A4252), muted: hex(0x8890A0), line: .clear,
        chip: hex(0xE7EAF0), tile: hex(0xE7EAF0), accent: hex(0x5B7CFA), accentEnd: hex(0x5B7CFA), onAccent: .white,
        activeTile: hex(0xE7EAF0), activeLine: .clear, activeText: hex(0x4563D8), fill: hex(0x5B7CFA, 0.12),
        ok: hex(0x4CC38A), scheme: .light, tileRadius: 20, neumorphic: true
    )

    static let bento = SkinPalette(
        background: [hex(0xFBFAF8)], fg: hex(0x17181B), muted: hex(0x8B8D93), line: hex(0xECEBE7),
        chip: hex(0xF1F0EC), tile: hex(0xF1F0EC), accent: hex(0xFFB020), accentEnd: hex(0xFFB020), onAccent: hex(0x1B1404),
        activeTile: hex(0xFFF3D6), activeLine: hex(0xFFD98A), activeText: hex(0x8A5A00), fill: hex(0xFFE39E),
        ok: hex(0x22A861), scheme: .light, tileRadius: 18, fontDesign: .rounded
    )

    static let neon = SkinPalette(
        background: [hex(0x0B0914)], fg: hex(0xEFEAFF), muted: hex(0x9A92B8), line: hex(0x3A3158),
        chip: hex(0x221C38), tile: hex(0x18142A), accent: hex(0xFF3D9A), accentEnd: hex(0x7A5CFF), onAccent: .white,
        activeTile: hex(0x1D0F22), activeLine: hex(0xFF3D9A), activeText: hex(0xFF7DBE), fill: hex(0xFF3D9A, 0.16),
        ok: hex(0x33F0C8), scheme: .dark, tileRadius: 12, glow: true
    )

    static let capsule = SkinPalette(
        background: [hex(0x161618)], fg: hex(0xF5F5F7), muted: hex(0x98989F), line: hex(0x3A3A3D),
        chip: hex(0x48484B), tile: hex(0x2C2C2F), accent: hex(0x30D158), accentEnd: hex(0x30D158), onAccent: hex(0x06210F),
        activeTile: hex(0xF5F5F7), activeLine: .clear, activeText: hex(0x1C1C1E), fill: hex(0xFFD60A, 0.55),
        ok: hex(0x30D158), scheme: .dark, tileRadius: 22, capsuleTiles: true, fontDesign: .rounded
    )

    static let dawn = SkinPalette(
        background: [hex(0xFFF8F1)], fg: hex(0x3B2A22), muted: hex(0x9B8579), line: hex(0xF1DFD1),
        chip: .white, tile: .white, accent: hex(0xE85D3F), accentEnd: hex(0xE85D3F), onAccent: .white,
        activeTile: hex(0xFFE9DC), activeLine: hex(0xF5B49E), activeText: hex(0xB5432A), fill: hex(0xFFD9C6),
        ok: hex(0x6AA84F), scheme: .light, tileRadius: 16, dashedIdle: true, fontDesign: .rounded
    )

    public var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accentEnd], startPoint: .leading, endPoint: .trailing)
    }

    public var backgroundStyle: AnyShapeStyle {
        if background.count > 1 {
            return AnyShapeStyle(LinearGradient(colors: background, startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        return AnyShapeStyle(background.first ?? .clear)
    }
}

// MARK: - Environment

private struct AppSkinKey: EnvironmentKey {
    static let defaultValue: AppSkin = .classic
}

extension EnvironmentValues {
    public var appSkin: AppSkin {
        get { self[AppSkinKey.self] }
        set { self[AppSkinKey.self] = newValue }
    }
}

/// Applied once at the panel root: stores the skin in the environment, forces its color scheme
/// and font design, and paints the panel background.
public struct SkinRoot: ViewModifier {
    public let skin: AppSkin

    public func body(content: Content) -> some View {
        let p = skin.palette
        if skin.isClassic {
            content
                .environment(\.appSkin, skin)
                .background(.ultraThinMaterial)
        } else {
            content
                .environment(\.appSkin, skin)
                .environment(\.colorScheme, p.scheme ?? .light)
                .fontDesign(p.fontDesign)
                .foregroundStyle(p.fg)
                .tint(p.accent)
                .background {
                    ZStack {
                        Rectangle().fill(p.backgroundStyle)
                        if p.translucent {
                            Rectangle().fill(.ultraThinMaterial).opacity(0.55)
                        }
                    }
                }
        }
    }
}

// MARK: - Skinned Surfaces

/// Replacement for the glass fill on chips, capsules and small buttons when a skin is active.
struct SkinChipSurface<S: Shape>: ViewModifier {
    @Environment(\.appSkin) private var skin
    let shape: S
    let tint: Color?
    let interactive: Bool
    let clear: Bool

    func body(content: Content) -> some View {
        if skin.isClassic || skin == .glass {
            content.modifier(ClassicGlass(shape: shape, tint: tint, interactive: interactive, clear: clear, translucentOnly: skin == .glass))
        } else {
            let p = skin.palette
            content
                .background {
                    shape.fill(p.chip)
                    if let tint { shape.fill(tint) }
                }
                .overlay { shape.stroke(p.line, lineWidth: 0.8) }
                .shadow(color: p.neumorphic ? Color(red: 0.78, green: 0.80, blue: 0.85) : .clear, radius: 4, x: 3, y: 3)
                .shadow(color: p.neumorphic ? .white : .clear, radius: 4, x: -3, y: -3)
        }
    }
}

/// The original adaptive glass behaviour, kept verbatim for the classic skin.
struct ClassicGlass<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool
    let clear: Bool
    var translucentOnly = false

    func body(content: Content) -> some View {
        if translucentOnly {
            content
                .background { shape.fill(.white.opacity(0.14)); if let tint { shape.fill(tint) } }
                .overlay { shape.stroke(.white.opacity(0.28), lineWidth: 0.8) }
        } else if #available(macOS 26.0, *) {
            if clear {
                content.glassEffect(interactive ? .clear.interactive() : .clear, in: shape)
            } else if let tint {
                content.glassEffect(interactive ? .regular.tint(tint).interactive() : .regular.tint(tint), in: shape)
            } else {
                content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
            }
        } else {
            content.background {
                if clear {
                    shape.fill(.thinMaterial)
                } else if let tint {
                    shape.fill(.ultraThinMaterial).overlay(shape.fill(tint))
                } else {
                    shape.fill(.ultraThinMaterial)
                }
            }
        }
    }
}

/// Device tile surface for non-classic skins.
struct SkinTileSurface: ViewModifier {
    @Environment(\.appSkin) private var skin
    let isActive: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let p = skin.palette
        let radius = p.capsuleTiles ? 999 : p.tileRadius
        let shape = RoundedRectangle(cornerRadius: min(radius, 40), style: .continuous)
        content
            .background {
                shape.fill(isActive ? p.activeTile : p.tile)
                    .shadow(color: p.neumorphic && !isActive ? Color(red: 0.78, green: 0.80, blue: 0.85) : .clear, radius: 6, x: 5, y: 5)
                    .shadow(color: p.neumorphic && !isActive ? .white : .clear, radius: 6, x: -5, y: -5)
                if p.neumorphic && isActive {
                    shape.stroke(Color(red: 0.78, green: 0.80, blue: 0.85), lineWidth: 4).blur(radius: 4).offset(x: 2, y: 2).mask(shape)
                    shape.stroke(.white, lineWidth: 4).blur(radius: 4).offset(x: -2, y: -2).mask(shape)
                }
            }
            .overlay {
                if p.dashedIdle && !isActive {
                    shape.stroke(p.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                } else {
                    shape.strokeBorder(isActive ? p.activeLine : p.line, lineWidth: isActive && p.glow ? 2 : 1)
                }
            }
            .clipShape(shape)
            .shadow(color: isActive && p.glow ? p.accent.opacity(0.5) : .clear, radius: 9)
            .animation(.easeOut(duration: 0.25), value: isActive)
    }
}

// MARK: - Motion Helpers

/// Fades and lifts a tile in with a per-index delay; re-runs whenever `trigger` changes identity upstream.
struct StaggerIn: ViewModifier {
    @Environment(\.appSkin) private var skin
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        if skin.isClassic || reduceMotion {
            content
        } else {
            content
                .opacity(shown ? 1 : 0)
                .offset(y: shown ? 0 : 10)
                .scaleEffect(shown ? 1 : 0.96)
                .onAppear {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.72).delay(Double(min(index, 12)) * 0.045)) {
                        shown = true
                    }
                }
        }
    }
}

/// A soft expanding ring from the icon whenever the device turns on.
struct ToggleRipple: ViewModifier {
    @Environment(\.appSkin) private var skin
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isOn: Bool
    let color: Color
    @State private var pulse = false

    func body(content: Content) -> some View {
        content
            .background {
                if !skin.isClassic && !reduceMotion {
                    Circle()
                        .fill(color.opacity(pulse ? 0 : 0.35))
                        .scaleEffect(pulse ? 3.2 : 0.6)
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: isOn) { _, on in
                guard on, !skin.isClassic, !reduceMotion else { return }
                pulse = false
                withAnimation(.easeOut(duration: 0.6)) { pulse = true }
            }
    }
}

/// Repeating halo used for the microphone while listening.
struct ListeningPulse: ViewModifier {
    let active: Bool
    let color: Color
    @State private var phase = false

    func body(content: Content) -> some View {
        content
            .background {
                if active {
                    Capsule(style: .continuous)
                        .stroke(color.opacity(phase ? 0 : 0.7), lineWidth: 2)
                        .scaleEffect(phase ? 1.6 : 1)
                        .onAppear {
                            phase = false
                            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) { phase = true }
                        }
                }
            }
    }
}

/// Status dot that breathes slowly while connected.
struct BreathingDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let color: Color
    let animate: Bool
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .opacity(dim ? 0.35 : 1)
            .onAppear {
                guard animate, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { dim = true }
            }
    }
}

extension View {
    func staggerIn(_ index: Int) -> some View { modifier(StaggerIn(index: index)) }
    func toggleRipple(isOn: Bool, color: Color) -> some View { modifier(ToggleRipple(isOn: isOn, color: color)) }
    func listeningPulse(_ active: Bool, color: Color) -> some View { modifier(ListeningPulse(active: active, color: color)) }
    public func skinRoot(_ skin: AppSkin) -> some View { modifier(SkinRoot(skin: skin)) }
}

// MARK: - Hold-to-Confirm All Off

/// Skinned "All Off" control: press and hold 0.6s to fire, with a filling progress sweep.
struct HoldToConfirmButton: View {
    @Environment(\.appSkin) private var skin
    let title: String
    let count: Int
    let onConfirm: () -> Void
    let onTap: () -> Void

    @State private var holding = false

    var body: some View {
        let p = skin.palette
        HStack(spacing: 4) {
            Image(systemName: "power").font(.system(size: 10.5, weight: .bold))
            Text(title).font(.system(size: 11.5, weight: .semibold))
            Text("(\(count))")
                .font(.system(size: 11.5, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(count)))
        }
        .foregroundStyle(skin == .capsule ? Color.white : p.onAccent)
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background {
            ZStack(alignment: .leading) {
                Capsule(style: .continuous).fill(skin == .capsule ? AnyShapeStyle(Color(red: 1, green: 0.27, blue: 0.23)) : AnyShapeStyle(p.accentGradient))
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.black.opacity(0.2))
                        .frame(width: holding ? geo.size.width : 0)
                }
                .clipShape(Capsule(style: .continuous))
            }
        }
        .shadow(color: p.glow ? p.accent.opacity(0.6) : .clear, radius: 8)
        .scaleEffect(holding ? 0.95 : 1)
        .contentShape(Capsule(style: .continuous))
        .onTapGesture(perform: onTap)
        .onLongPressGesture(minimumDuration: 0.6, maximumDistance: 20) {
            holding = false
            onConfirm()
        } onPressingChanged: { pressing in
            withAnimation(pressing ? .linear(duration: 0.6) : .easeOut(duration: 0.2)) { holding = pressing }
        }
        .help(L10n.tr("按住 0.6 秒全部关闭", "Hold 0.6s to turn everything off"))
    }
}

// MARK: - Skin Picker (Settings)

struct SkinPickerGrid: View {
    @Binding var selection: AppSkin

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(AppSkin.allCases) { skin in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selection = skin }
                } label: {
                    SkinSwatch(skin: skin, isSelected: selection == skin)
                }
                .buttonStyle(PressableCardButtonStyle(scaleAmount: 0.95))
            }
        }
    }
}

private struct SkinSwatch: View {
    let skin: AppSkin
    let isSelected: Bool

    var body: some View {
        let p = skin.palette
        VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(skin.isClassic ? AnyShapeStyle(.ultraThinMaterial) : p.backgroundStyle)
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: p.capsuleTiles ? 6 : 4, style: .continuous)
                        .fill(skin.isClassic ? Color.orange.opacity(0.25) : p.activeTile)
                        .overlay {
                            Circle().fill(skin.isClassic ? Color.orange : p.accent).frame(width: 7, height: 7)
                        }
                    RoundedRectangle(cornerRadius: p.capsuleTiles ? 6 : 4, style: .continuous)
                        .fill(skin.isClassic ? Color.primary.opacity(0.08) : p.tile)
                        .overlay {
                            RoundedRectangle(cornerRadius: p.capsuleTiles ? 6 : 4, style: .continuous)
                                .stroke(skin.isClassic ? Color.clear : p.line, lineWidth: 0.6)
                        }
                }
                .frame(height: 14)
                .padding(.horizontal, 8)
            }
            .frame(height: 38)
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isSelected ? 2 : 0.7)
            }

            Text(skin.title)
                .font(.system(size: 10.5, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        }
        .contentShape(Rectangle())
    }
}
