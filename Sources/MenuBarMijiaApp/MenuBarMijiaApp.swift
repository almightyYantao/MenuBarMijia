import SwiftUI
import AppKit
import MijiaCore

@main
@MainActor
struct MenuBarMijiaApp: App {
    @State private var store = HomeStore.shared
    @State private var speech = SpeechInputController.shared

    init() {
        let sharedStore = HomeStore.shared
        HotkeyAndNotificationManager.shared.start(with: sharedStore)
        SystemActivityMonitor.shared.start(with: sharedStore)
    }

    var body: some Scene {
        let _ = store.effectiveLanguage
        MenuBarExtra {
            ControlCenterPanel(store: store)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: speech.isListening ? "waveform" : store.menuBarSymbolName)
                if speech.isListening {
                    Text(menuBarSpeechText)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                } else if let text = store.menuBarText {
                    Text(text)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .monospacedDigit()
                }
            }
            .help(MenuBarStatusSummary.text(for: store))
            .accessibilityLabel(Text(MenuBarStatusSummary.text(for: store)))
        }
        .menuBarExtraStyle(.window)

        // ⌘, standard Settings window (#42). Living in its own scene means switching to the browser
        // to copy a token no longer tears the form down with the popover.
        Settings {
            SettingsWindowView(store: store)
        }
    }

    private var menuBarSpeechText: String {
        let trimmed = speech.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return L10n.tr("聆听中…", "Listening…") }
        if trimmed.count > 10 {
            return String(trimmed.suffix(10))
        }
        return trimmed
    }
}

// MARK: - Menu Bar Tooltip (#54)

/// One-line status shown when hovering the menu-bar icon: "MenuBarMijia · 3 on · Study 26.5° ·
/// Xiaomi Cloud connected". Disconnected shows the reason instead of the backend name.
@MainActor
enum MenuBarStatusSummary {
    static func text(for store: HomeStore) -> String {
        let _ = store.effectiveLanguage
        var parts: [String] = ["MenuBarMijia"]
        parts.append(L10n.tr("\(store.activeDeviceCount) 台开启", "\(store.activeDeviceCount) on"))

        if let reading = store.environmentReadings.first(where: { $0.temperature != nil }),
           let temperature = reading.temperature {
            parts.append("\(L10n.displayRoomName(reading.label)) \(String(format: "%.1f°", temperature))")
        }

        switch store.connectionStatus {
        case .connected:
            switch store.homeBackend {
            case .xiaomiCloud:
                parts.append(L10n.tr("已连接米家云", "Xiaomi Cloud connected"))
            case .homeAssistant:
                parts.append(L10n.tr("已连接 Home Assistant", "Home Assistant connected"))
            case .demo:
                parts.append(L10n.tr("演示模式", "Demo mode"))
            }
        case .connecting:
            parts.append(L10n.tr("正在连接…", "Connecting…"))
        case .disconnected(let reason):
            parts.append(L10n.tr("未连接：\(reason)", "Disconnected: \(reason)"))
        }

        return parts.joined(separator: " · ")
    }
}
