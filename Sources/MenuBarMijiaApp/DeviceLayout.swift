import SwiftUI
import AppKit
import MijiaCore

/// Per-device card size picked from the card's context menu.
public enum TileSize: String, CaseIterable, Identifiable, Sendable {
    case auto, half, full, panel

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto: return L10n.tr("自动", "Auto")
        case .half: return L10n.tr("半行", "Half Row")
        case .full: return L10n.tr("整行", "Full Row")
        case .panel: return L10n.tr("展开面板", "Open Panel")
        }
    }

    public var symbol: String {
        switch self {
        case .auto: return "wand.and.stars"
        case .half: return "rectangle.split.2x1"
        case .full: return "rectangle"
        case .panel: return "rectangle.expand.vertical"
        }
    }
}

/// Stores `[deviceId: TileSize]` as JSON under one defaults key so views can observe it with `@AppStorage`.
public enum DeviceLayoutPrefs {
    public static let storageKey = "device_tile_sizes"

    public static func decode(_ raw: String) -> [String: TileSize] {
        guard let data = raw.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return dict.compactMapValues(TileSize.init(rawValue:))
    }

    public static func encode(_ sizes: [String: TileSize]) -> String {
        let dict = sizes.filter { $0.value != .auto }.mapValues(\.rawValue)
        guard let data = try? JSONEncoder().encode(dict) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Memoised decode: cards read their size on every render, the JSON only changes on edits.
    @MainActor private static var cache: (raw: String, sizes: [String: TileSize]) = ("", [:])

    @MainActor
    public static func cachedSize(raw: String, id: String) -> TileSize {
        if cache.raw != raw { cache = (raw, decode(raw)) }
        return cache.sizes[id] ?? .auto
    }

    /// Resolves `.auto` into a concrete size for the current grid mode and climate setting.
    public static func resolved(_ size: TileSize, device: SmartDevice, compactGrid: Bool, climatePanel: Bool) -> TileSize {
        guard size == .auto else { return size }
        if case .climate = device.kind, climatePanel { return .full }
        return compactGrid ? .half : .full
    }
}

// MARK: - Custom Order

extension DeviceLayoutPrefs {
    public static let orderKey = "device_custom_order"

    public static func decodeOrder(_ raw: String) -> [String] {
        guard let data = raw.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return ids
    }

    public static func encodeOrder(_ ids: [String]) -> String {
        guard let data = try? JSONEncoder().encode(ids) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    /// Sorts by the saved order; devices not in it keep their incoming order after the known ones.
    public static func apply(order: [String], to devices: [SmartDevice]) -> [SmartDevice] {
        guard !order.isEmpty else { return devices }
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return devices.enumerated().sorted { a, b in
            let ra = rank[a.element.id] ?? (order.count + a.offset)
            let rb = rank[b.element.id] ?? (order.count + b.offset)
            return ra < rb
        }.map(\.element)
    }
}

// MARK: - Edit Mode (long-press → jiggle, drag to reorder, tap badge to resize)

private struct LayoutEditingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    public var isEditingLayout: Bool {
        get { self[LayoutEditingKey.self] }
        set { self[LayoutEditingKey.self] = newValue }
    }
}

/// Wraps one device card. Long-press then keep dragging picks the card up straight away (no
/// second click); while editing a plain drag moves any card. The card follows the pointer via
/// `dragOffset`, jiggles, and shows a size badge that cycles half → full → panel.
struct LayoutEditable: ViewModifier {
    @Environment(\.isEditingLayout) private var editing
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appSkin) private var skin

    let deviceId: String
    let size: TileSize
    let isDragging: Bool
    let dragOffset: CGSize
    let onCycleSize: () -> Void

    // Per-card phase so neighbouring cards do not swing in sync.
    private var phase: Double { Double(abs(deviceId.hashValue % 97)) / 97 * .pi * 2 }

    func body(content: Content) -> some View {
        jiggling(content.allowsHitTesting(!editing))
            .scaleEffect(isDragging ? 1.05 : 1)
            .shadowIf(isDragging, color: .black.opacity(0.3), radius: 12, y: 6)
            .offset(dragOffset)
            .zIndex(isDragging ? 10 : 0)
            .overlay(alignment: .topTrailing) {
                if editing && !isDragging {
                    Button(action: onCycleSize) {
                        Image(systemName: size.symbol)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(skin.isClassic ? Color.white : skin.palette.onAccent)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(skin.isClassic ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(skin.palette.accentGradient)))
                            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    }
                    .buttonStyle(PressableCardButtonStyle(scaleAmount: 0.85))
                    .help(L10n.tr("切换卡片大小：\(size.title)", "Card size: \(size.title)"))
                    .offset(x: 5, y: -5)
                    .transition(.scale.combined(with: .opacity))
                }
            }
    }

    /// Angle is computed from the clock each frame, so a card rebuilt mid-edit keeps jiggling
    /// instead of freezing at the last animated angle.
    @ViewBuilder
    private func jiggling<V: View>(_ view: V) -> some View {
        if editing && !reduceMotion && !isDragging {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                view.rotationEffect(.degrees(sin(t * 2 * .pi * 3.6 + phase) * 1.1))
            }
        } else {
            view
        }
    }
}

enum TileSpace {
    static let name = "device_tiles"
}

/// Card frames in the tile coordinate space, used to find which card the pointer is over.
struct TileFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - Flow Layout

struct TileSpanKey: LayoutValueKey {
    static let defaultValue = 6
}

/// Packs children left to right into rows of 6 columns using each child's `TileSpanKey`.
/// Cards in a row share the tallest card's height.
struct TileFlowLayout: Layout {
    var spacing: CGFloat = 7

    private struct Row {
        var indices: [Int] = []
        var height: CGFloat = 0
    }

    private func width(for span: Int, total: CGFloat) -> CGFloat {
        let unit = (total - spacing * 5) / 6
        return unit * CGFloat(span) + spacing * CGFloat(span - 1)
    }

    private func rows(_ subviews: Subviews, total: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        var used = 0
        for (i, sub) in subviews.enumerated() {
            let span = min(max(sub[TileSpanKey.self], 1), 6)
            if used + span > 6, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
                used = 0
            }
            let h = sub.sizeThatFits(ProposedViewSize(width: width(for: span, total: total), height: nil)).height
            current.indices.append(i)
            current.height = max(current.height, h)
            used += span
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? 330
        let rs = rows(subviews, total: total)
        let height = rs.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rs.count - 1, 0))
        return CGSize(width: total, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, total: bounds.width) {
            var x = bounds.minX
            for i in row.indices {
                let span = min(max(subviews[i][TileSpanKey.self], 1), 6)
                let w = width(for: span, total: bounds.width)
                subviews[i].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: w, height: row.height))
                x += w + spacing
            }
            y += row.height + spacing
        }
    }
}
