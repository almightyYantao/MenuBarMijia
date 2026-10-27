import AppKit
import Observation

/// Opens the ⌘, Settings scene from code paths that cannot read SwiftUI's environment (the local key
/// monitor in `HotkeyAndNotificationManager`).
///
/// `ControlCenterPanel` registers the real `openSettings` action when it appears; the AppKit selector
/// is only a fallback for the window-closed case.
@Observable
@MainActor
final class SettingsWindowOpener {
    static let shared = SettingsWindowOpener()

    @ObservationIgnored var open: (() -> Void)?

    private init() {}

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let open {
            open()
        } else {
            _ = NSApp.sendAction(NSSelectorFromString("showSettingsWindow:"), to: nil, from: nil)
        }
    }
}
