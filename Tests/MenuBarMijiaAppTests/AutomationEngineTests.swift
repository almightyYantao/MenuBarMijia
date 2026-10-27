import Foundation
import Testing
import MijiaCore
@testable import MenuBarMijiaApp

/// #59: the engine maps an observed Mac-state trigger to the stored rule, runs it through
/// `HomeStore`, and never performs network work itself.
@MainActor
struct AutomationEngineTests {
    static let studyLight = SmartDevice(
        id: "light_study",
        name: "书房台灯",
        roomId: "study",
        roomName: "书房",
        model: "yeelink.light.lamp4",
        isOnline: true,
        kind: .light(LightSpec(entityId: "light.study", isOn: true))
    )
    static let scenes = [
        HomeScene(id: "scene_home", name: "回家模式", entityId: "scene.home"),
        HomeScene(id: "scene_work", name: "办公模式", entityId: "scene.work")
    ]

    private func makeStore() async throws -> (HomeStore, MockHomeProvider) {
        let mock = MockHomeProvider(snapshot: SynthesizedHome(
            devices: [Self.studyLight],
            scenes: Self.scenes
        ))
        let store = HomeStore(provider: mock, defaultsSuiteName: "test.automation.engine.\(UUID().uuidString)")
        for _ in 0..<50 where store.devices.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        return (store, mock)
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suite = "test.automation.engine.defaults.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (defaults, suite)
    }

    @Test("Away rule turns the light off once per minute and leaves an undo banner")
    func awayRuleExecutesAndDedupes() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        AutomationRuleStore(defaults: defaults).save([
            AutomationRule(
                trigger: .away,
                action: .devices(ids: [Self.studyLight.id], isOn: false)
            )
        ])

        let (store, mock) = try await makeStore()
        let engine = AutomationEngine(defaults: defaults)
        engine.attach(store: store)

        let start = Date()
        await engine.handle(trigger: .away, at: start)

        #expect(store.devices.first(where: { $0.id == Self.studyLight.id })?.isActiveOn == false)
        #expect(store.undoBanner != nil)
        #expect(store.userHabitMemory.entries.isEmpty)
        let firstCommands = await mock.executedCommands
        #expect(firstCommands == [.setLightPower(entityId: "light.study", isOn: false)])

        // A second lock/wake flap within the cooldown must not dispatch again.
        await engine.handle(trigger: .away, at: start.addingTimeInterval(30))
        let afterSecond = await mock.executedCommands
        #expect(afterSecond.count == firstCommands.count)
    }

    @Test("Rules added while the cooldown clock is idle still fire immediately")
    func emptyRuleListDoesNotBurnCooldown() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let (store, mock) = try await makeStore()
        let engine = AutomationEngine(defaults: defaults)
        engine.attach(store: store)
        let start = Date()

        await engine.handle(trigger: .away, at: start)
        #expect(await mock.executedCommands.isEmpty)

        AutomationRuleStore(defaults: defaults).save([
            AutomationRule(
                trigger: .away,
                action: .devices(ids: [Self.studyLight.id], isOn: false)
            )
        ])
        await engine.handle(trigger: .away, at: start.addingTimeInterval(5))
        #expect(store.devices.first(where: { $0.id == Self.studyLight.id })?.isActiveOn == false)
    }

    @Test("Disabled rules and non-matching triggers do nothing")
    func disabledRuleIgnored() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        AutomationRuleStore(defaults: defaults).save([
            AutomationRule(
                trigger: .back,
                action: .devices(ids: [Self.studyLight.id], isOn: false),
                isEnabled: false
            )
        ])

        let (store, mock) = try await makeStore()
        let engine = AutomationEngine(defaults: defaults)
        engine.attach(store: store)

        await engine.handle(trigger: .back, at: Date())
        await engine.handle(trigger: .away, at: Date())
        #expect(await mock.executedCommands.isEmpty)
        #expect(store.devices.first(where: { $0.id == Self.studyLight.id })?.isActiveOn == true)
    }

    @Test("Connecting an external display can run the configured scene")
    func displayConnectRunsScene() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        AutomationRuleStore(defaults: defaults).save([
            AutomationRule(
                trigger: .externalDisplayConnected,
                action: .scene(sceneId: "scene_work")
            )
        ])

        let (store, mock) = try await makeStore()
        let engine = AutomationEngine(defaults: defaults)
        engine.attach(store: store)

        await engine.handle(trigger: .externalDisplayConnected, at: Date())
        let commands = await mock.executedCommands
        #expect(commands == [.activateScene(entityId: "scene.work")])
        #expect(store.userHabitMemory.entries.isEmpty)
    }

    @Test("A quick-action rule uses the built-in action path and leaves an undo banner")
    func quickActionRule() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        AutomationRuleStore(defaults: defaults).save([
            AutomationRule(trigger: .away, action: .quickAction(.lightsOff))
        ])

        let (store, _) = try await makeStore()
        let engine = AutomationEngine(defaults: defaults)
        engine.attach(store: store)

        await engine.handle(trigger: .away, at: Date())
        #expect(store.devices.first(where: { $0.id == Self.studyLight.id })?.isActiveOn == false)
        #expect(store.undoBanner != nil)
        #expect(store.userHabitMemory.entries.isEmpty)
    }
}
