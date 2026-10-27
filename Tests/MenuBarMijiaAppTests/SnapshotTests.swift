import Testing
import Foundation
import SwiftUI
import AppKit
import SnapshotTesting
import MijiaCore
@testable import MenuBarMijiaApp

/// UI snapshots for the menu-bar panel and the five device-card families (#46).
///
/// Two-phase baseline: CI first runs `SNAPSHOT_RECORD=1 swift test --filter SnapshotTests`, which
/// writes PNGs into `Tests/MenuBarMijiaAppTests/__Snapshots__/SnapshotTests/`; those files are then
/// committed. SnapshotTesting also reports "Record mode is on" as a failure for that run, so the
/// record job is expected to exit non-zero while still producing every baseline. Later runs compare
/// against them; on a mismatch the new bitmap is written under `$SNAPSHOT_ARTIFACTS`/SnapshotTests
/// (or `$TMPDIR/SnapshotTests`) and the diff command is printed in the failure message.
///
/// The renderer is fed fixed demo data and the accessibility "reduce motion" / "reduce transparency"
/// switches, so animations and materials cannot make two runs differ. The suite is serialized
/// because it changes `UserDefaults.standard` (the panel reads skin/appearance through
/// `@AppStorage`) and `L10n.currentLanguage`.
@MainActor
@Suite(.serialized)
struct SnapshotTests {
    private var recordMode: SnapshotTestingConfiguration.Record {
        ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1" ? .all : .missing
    }

    // MARK: - Panel: one snapshot per skin (Chinese, light, single column)

    @Test("Panel renders in all nine skins")
    func panelSnapshotsAcrossSkins() async throws {
        let fixture = try await SnapshotFixture()
        defer { fixture.restore() }

        for skin in AppSkin.allCases {
            UserDefaults.standard.set(skin.rawValue, forKey: AppSkin.storageKey)
            UserDefaults.standard.set(AppAppearance.system.rawValue, forKey: AppAppearance.storageKey)

            let view = snapshotReady(ControlCenterPanel(store: fixture.store))
            assertRendered(
                view,
                size: CGSize(width: 376, height: 560),
                named: "panel-\(skin.rawValue)-zh-light"
            )
        }
    }

    // MARK: - Device cards: light / climate / plug / sensor / TV (classic skin)

    @Test("Five device card families render in the classic skin")
    func deviceCardSnapshots() async throws {
        let fixture = try await SnapshotFixture()
        defer { fixture.restore() }
        UserDefaults.standard.set(AppSkin.classic.rawValue, forKey: AppSkin.storageKey)

        let light = try #require(fixture.store.devices.first { device in
            if case .light = device.kind { return true } else { return false }
        })
        let climate = try #require(fixture.store.devices.first { device in
            if case .climate = device.kind { return true } else { return false }
        })
        let plug = try #require(fixture.store.devices.first { device in
            if case .plug = device.kind { return true } else { return false }
        })
        let sensor = try #require(fixture.store.devices.first { device in
            if case .sensor = device.kind { return true } else { return false }
        })
        let tv = try #require(fixture.store.devices.first { device in
            if case .tv = device.kind { return true } else { return false }
        })

        let cards: [(String, SmartDevice)] = [
            ("light", light),
            ("climate", climate),
            ("plug", plug),
            ("sensor", sensor),
            ("tv", tv)
        ]

        for (name, device) in cards {
            let view = snapshotReady(
                DeviceCardView(device: device, store: fixture.store, showRoomBadge: true)
                    .padding(8)
                    .frame(width: 360)
                    .environment(\.skinPalette, AppSkin.classic.palette)
            )
            assertRendered(
                view,
                size: CGSize(width: 376, height: 140),
                named: "card-\(name)-classic-zh-light"
            )
        }
    }

    // MARK: - Non-visual guards for the appearance work (#51) and tooltip (#54)

    @Test("Light and dark skins pair with the opposite scheme")
    func skinsPairWithTheOppositeScheme() {
        #expect(AppSkin.frost.palette(for: .light).scheme == .light)
        #expect(AppSkin.frost.palette(for: .dark).scheme == .dark)
        #expect(AppSkin.night.palette(for: .light).scheme == .light)
        #expect(AppSkin.night.palette(for: .dark).scheme == .dark)
        #expect(AppSkin.dawn.palette(for: .dark).scheme == .dark)
        #expect(AppSkin.neon.palette(for: .light).scheme == .light)
        #expect(AppSkin.soft.palette(for: .dark).scheme == .dark)
        #expect(AppSkin.capsule.palette(for: .light).scheme == .light)
        #expect(AppSkin.bento.palette(for: .dark).scheme == .dark)
        #expect(AppSkin.glass.palette(for: .light).scheme == .light)
        // Classic follows the system, so it never declares a fixed scheme.
        #expect(AppSkin.classic.palette(for: .light).scheme == nil)
        #expect(AppSkin.classic.palette(for: .dark).scheme == nil)
    }

    @Test("Menu-bar tooltip summarises devices, temperature and backend")
    func menuBarSummaryDescribesCurrentState() async throws {
        let fixture = try await SnapshotFixture()
        defer { fixture.restore() }

        let text = MenuBarStatusSummary.text(for: fixture.store)
        #expect(text.hasPrefix("MenuBarMijia · "))
        #expect(text.contains("台开启"))
        #expect(text.contains("已连接 Home Assistant"))
    }

    // MARK: - Rendering switches

    private func snapshotReady<V: View>(_ view: V) -> some View {
        view
            .environment(\.colorScheme, .light)
            .environment(\.reduceMotionOverride, true)
            .environment(\.reduceTransparencyOverride, true)
            .transaction { transaction in
                transaction.disablesAnimations = true
            }
    }

    /// SnapshotTesting only ships the SwiftUI `.image(layout:)` strategy for iOS/tvOS, so macOS
    /// renders through an `NSHostingView` inside a borderless window and snapshots the NSView.
    private func assertRendered<V: View>(
        _ view: V,
        size: CGSize,
        named name: String,
        file: StaticString = #filePath,
        testName: String = #function
    ) {
        // `swift test` does not launch an app; AppKit still needs its shared application object
        // before offscreen windows and hosting views can be created.
        _ = NSApplication.shared

        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        window.displayIfNeeded()

        let snapshotView: NSView = hosting
        assertSnapshot(
            of: snapshotView,
            as: .image(size: size),
            named: name,
            record: recordMode,
            file: file,
            testName: testName
        )

        window.contentView = nil
        window.orderOut(nil)
    }
}

/// A loaded store over the built-in virtual home, with a fixed language and the standard-defaults
/// keys the panel reads through `@AppStorage`.
@MainActor
private struct SnapshotFixture {
    struct MissingDefaults: Error {}

    let store: HomeStore
    private let previousSkin: String?
    private let previousAppearance: String?
    private let previousLanguage: AppLanguage

    init() async throws {
        previousLanguage = L10n.currentLanguage
        L10n.currentLanguage = .zhHans
        previousSkin = UserDefaults.standard.string(forKey: AppSkin.storageKey)
        previousAppearance = UserDefaults.standard.string(forKey: AppAppearance.storageKey)
        UserDefaults.standard.set(AppSkin.classic.rawValue, forKey: AppSkin.storageKey)
        UserDefaults.standard.set(AppAppearance.system.rawValue, forKey: AppAppearance.storageKey)

        let suiteName = "MenuBarMijiaSnapshotTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw MissingDefaults()
        }
        defaults.set(true, forKey: "has_completed_onboarding")
        defaults.set(AppLanguagePreference.zhHans.rawValue, forKey: "app_language")
        defaults.set(false, forKey: "show_quick_actions_bar")
        // The panel's `.task` checks for updates; keep the snapshot offline and deterministic.
        defaults.set(false, forKey: "automatically_checks_for_updates")

        store = HomeStore(
            provider: MockHomeProvider(snapshot: DemoHomeProvider.defaultHome()),
            defaultsSuiteName: suiteName
        )

        var attempts = 0
        while store.devices.isEmpty && attempts < 200 {
            try await Task.sleep(for: .milliseconds(20))
            attempts += 1
        }
        #expect(!store.devices.isEmpty, "MockHomeProvider should deliver a snapshot right away")
    }

    func restore() {
        if let previousSkin {
            UserDefaults.standard.set(previousSkin, forKey: AppSkin.storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: AppSkin.storageKey)
        }
        if let previousAppearance {
            UserDefaults.standard.set(previousAppearance, forKey: AppAppearance.storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: AppAppearance.storageKey)
        }
        L10n.currentLanguage = previousLanguage
    }
}
