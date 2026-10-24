import Foundation

// MARK: - App Language & Localization Primitives

public enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case zhHans = "zh-Hans"
    case en = "en"

    public var id: String { rawValue }

    public var isEnglish: Bool { self == .en }

    public var speechLocaleIdentifier: String {
        switch self {
        case .zhHans: return "zh-CN"
        case .en: return "en-US"
        }
    }

    public static func detectSystemLanguage(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard let first = preferredLanguages.first?.lowercased() else {
            return .zhHans
        }
        if first.hasPrefix("zh") {
            return .zhHans
        }
        return .en
    }
}

public enum AppLanguagePreference: String, CaseIterable, Identifiable, Codable, Sendable {
    case system = "system"
    case zhHans = "zh-Hans"
    case en = "en"

    public var id: String { rawValue }

    public func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        switch self {
        case .system:
            return AppLanguage.detectSystemLanguage(preferredLanguages: preferredLanguages)
        case .zhHans:
            return .zhHans
        case .en:
            return .en
        }
    }

    public var title: String {
        switch self {
        case .system:
            return L10n.tr("跟随系统", "System Default")
        case .zhHans:
            return "简体中文"
        case .en:
            return "English"
        }
    }

    public var label: String { title }
}

public enum MiCloudRegion: String, CaseIterable, Identifiable, Codable, Sendable {
    case cn = "cn"
    case sg = "sg"
    case de = "de"
    case us = "us"
    case ru = "ru"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cn: return L10n.tr("中国大陆 (cn)", "China Mainland (cn)")
        case .sg: return L10n.tr("新加坡 / 国际 (sg)", "Singapore / Global (sg)")
        case .de: return L10n.tr("欧洲 (de)", "Europe (de)")
        case .us: return L10n.tr("美区 (us)", "United States (us)")
        case .ru: return L10n.tr("俄罗斯 (ru)", "Russia (ru)")
        }
    }

    public var label: String { title }
}

/// Thread-safe, zero-dependency localization helper that builds cleanly on both macOS and Linux.
public enum L10n {
    @TaskLocal public static var overrideLanguage: AppLanguage?

    private final class Storage: @unchecked Sendable {
        private let lock = NSLock()
        private var language: AppLanguage = .zhHans

        func get() -> AppLanguage {
            lock.lock()
            defer { lock.unlock() }
            return language
        }

        func set(_ newValue: AppLanguage) {
            lock.lock()
            defer { lock.unlock() }
            language = newValue
        }
    }

    private static let storage = Storage()

    public static var currentLanguage: AppLanguage {
        get { overrideLanguage ?? storage.get() }
        set { storage.set(newValue) }
    }

    public static var isEnglish: Bool {
        currentLanguage == .en
    }

    @inline(__always)
    public static func tr(_ zh: String, _ en: String) -> String {
        currentLanguage == .en ? en : zh
    }

    /// Displays common room names in English when the UI is in English mode, preserving custom names.
    public static func displayRoomName(_ raw: String) -> String {
        guard currentLanguage == .en else { return raw }
        switch raw {
        case "全部": return "All"
        case "全屋": return "Whole Home"
        case "客厅": return "Living Room"
        case "主卧": return "Master Bedroom"
        case "卧室": return "Bedroom"
        case "次卧", "小卧室": return "Second Bedroom"
        case "书房": return "Study"
        case "厨房": return "Kitchen"
        case "阳台": return "Balcony"
        case "餐厅": return "Dining Room"
        case "卫生间", "浴室": return "Bathroom"
        case "玄关": return "Entryway"
        default: return raw
        }
    }
}
