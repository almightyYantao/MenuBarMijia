import Foundation
import Security

public enum MenuBarDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case primaryTemp = "primaryTemp"
    case balconyTemp = "balconyTemp"
    case activeCount = "activeCount"
    case iconOnly = "iconOnly"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .primaryTemp: return L10n.tr("主卧温度 (如 26.6°)", "Bedroom Temp (e.g. 26.6°)")
        case .balconyTemp: return L10n.tr("阳台温度 (如 28.1°)", "Balcony Temp (e.g. 28.1°)")
        case .activeCount: return L10n.tr("开启设备数", "Active Devices")
        case .iconOnly: return L10n.tr("仅显示图标", "Icon Only")
        }
    }
}

public enum KeychainHelper {
    static let service = "com.jryang1997.MenuBarMijia"
    private static let account = "ha_access_token"

    public static let defaultHomeName = "我的家"
    public static var localizedDefaultHomeName: String {
        L10n.tr("我的家", "My Home")
    }
    public static let defaultNASURL = "http://homeassistant.local:8123"
    public static let defaultSeededToken = ""

    public static func loadToken() -> String {
        if let envToken = ProcessInfo.processInfo.environment["HA_ACCESS_TOKEN"],
           !envToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return envToken.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let ud = UserDefaults.standard.string(forKey: "ha_fallback_token"),
           !ud.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ud.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess,
           let data = item as? Data,
           let str = String(data: data, encoding: .utf8),
           !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return str.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return defaultSeededToken
    }

    public static func saveToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmed, forKey: "ha_fallback_token")
        guard let data = trimmed.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }
}
