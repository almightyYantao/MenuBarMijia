import SwiftUI
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

    /// Resolves `.auto` into a concrete size for the current grid mode and climate setting.
    public static func resolved(_ size: TileSize, device: SmartDevice, compactGrid: Bool, climatePanel: Bool) -> TileSize {
        guard size == .auto else { return size }
        if case .climate = device.kind, climatePanel { return .full }
        return compactGrid ? .half : .full
    }
}
