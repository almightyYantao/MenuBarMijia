import Foundation
import Testing
@testable import MijiaCore

struct LocalizationTests {
    @Test("AppLanguage detects Chinese vs English system locales")
    func systemLanguageDetection() {
        #expect(AppLanguage.detectSystemLanguage(preferredLanguages: ["zh-Hans-CN", "en-US"]) == .zhHans)
        #expect(AppLanguage.detectSystemLanguage(preferredLanguages: ["zh-Hant-HK"]) == .zhHans)
        #expect(AppLanguage.detectSystemLanguage(preferredLanguages: ["en-US", "zh-Hans"]) == .en)
        #expect(AppLanguage.detectSystemLanguage(preferredLanguages: ["fr-FR"]) == .en)
        #expect(AppLanguagePreference.system.resolved(preferredLanguages: ["en-GB"]) == .en)
        #expect(AppLanguagePreference.zhHans.resolved(preferredLanguages: ["en-US"]) == .zhHans)
        #expect(AppLanguagePreference.en.resolved(preferredLanguages: ["zh-Hans"]) == .en)
    }

    @Test("L10n translates strings, room names, and device subtitles in English mode")
    func englishFormatting() {
        L10n.$overrideLanguage.withValue(.en) {
            #expect(L10n.tr("书房", "Study") == "Study")
            #expect(L10n.displayRoomName("书房") == "Study")
            #expect(L10n.displayRoomName("客厅") == "Living Room")
            #expect(L10n.displayRoomName("主卧") == "Master Bedroom")
            #expect(L10n.displayRoomName("CustomRoom") == "CustomRoom")

            let light = SmartDevice(
                id: "dev_light",
                name: "Study Ceiling Light",
                roomId: "study",
                roomName: "书房",
                model: "yeelink.light.ceiling20",
                isOnline: true,
                kind: .light(LightSpec(
                    entityId: "light.study",
                    isOn: true,
                    brightnessPercent: 75,
                    colorTempKelvin: 4000,
                    currentEffect: "Night",
                    availableEffects: ["Day", "Night"]
                ))
            )
            #expect(light.statusSubtitle.contains("Moonlight"))
            #expect(light.statusSubtitle.contains("75%"))

            let ac = SmartDevice(
                id: "dev_ac",
                name: "Living Room AC",
                roomId: "living",
                roomName: "客厅",
                model: "xiaomi.aircondition.mt0",
                isOnline: true,
                kind: .climate(ClimateSpec(
                    entityId: "climate.ac",
                    isOn: true,
                    hvacMode: "cool",
                    availableModes: ["off", "cool", "heat"],
                    targetTemperature: 24.0,
                    currentTemperature: 26.0
                ))
            )
            #expect(ac.statusSubtitle.contains("Cool"))
        }
    }

    @Test("LocalIntentParser parses English smart home commands and replies in English")
    func englishLocalIntentParsing() throws {
        try L10n.$overrideLanguage.withValue(.en) {
            let onPlan = try #require(AssistantTests.parse("turn on study light"))
            #expect(onPlan.source == .local)
            #expect(onPlan.intents == [
                DeviceIntent(targetId: "dev_study_ceiling", operation: .power(true)),
                DeviceIntent(targetId: "dev_study_desk", operation: .power(true))
            ])
            #expect(onPlan.reply == "Turned on 书房吸顶灯, 书房台灯")

            let moonPlan = try #require(AssistantTests.parse("study light moonlight mode"))
            #expect(moonPlan.intents == [
                DeviceIntent(targetId: "dev_study_ceiling", operation: .lightEffect("Night"))
            ])
            #expect(moonPlan.reply == "Switched 书房吸顶灯 to Moonlight mode")

            let tempPlan = try #require(AssistantTests.parse("set living room ac to 24 degrees"))
            #expect(tempPlan.intents == [
                DeviceIntent(targetId: "dev_living_ac", operation: .targetTemperature(24))
            ])
            #expect(tempPlan.reply == "Set 客厅空调 to 24°C")

            let coolPlan = try #require(AssistantTests.parse("living room ac cool mode"))
            #expect(coolPlan.intents == [
                DeviceIntent(targetId: "dev_living_ac", operation: .hvacMode("cool"))
            ])
            #expect(coolPlan.reply == "Switched 客厅空调 to Cool")

            let dimPlan = try #require(AssistantTests.parse("dimmer"))
            #expect(dimPlan.intents == [
                DeviceIntent(targetId: "dev_bedside", operation: .brightness(60))
            ])
        }
    }

    @Test("DelayPhrase and UndoPhrase support English spoken timers and undo commands")
    func englishDelayAndUndoPhrases() throws {
        try L10n.$overrideLanguage.withValue(.en) {
            let match = try #require(DelayPhrase.extract("in 10 minutes turn off study light"))
            #expect(match.delay == 600)
            #expect(match.remainder == "turn off study light")
            #expect(DelayPhrase.describe(match.delay) == "In 10m: ")

            let secMatch = try #require(DelayPhrase.extract("after 30 seconds turn on bedside lamp"))
            #expect(secMatch.delay == 30)
            #expect(secMatch.remainder == "turn on bedside lamp")

            #expect(DelayPhrase.isCancel("cancel timer"))
            #expect(DelayPhrase.isCancel("clear all timers"))
            #expect(UndoPhrase.isUndo("undo"))
            #expect(UndoPhrase.isUndo("undo that"))
            #expect(UndoPhrase.isUndo("revert"))
        }
    }

    @Test("HomeStore persists appLanguagePreference and miCloudRegion")
    @MainActor
    func homeStoreLanguageAndRegionPersistence() throws {
        let suiteName = "LocalizationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = HomeStore(provider: MockHomeProvider(), defaultsSuiteName: suiteName)
        #expect(store.appLanguagePreference == .system)
        #expect(store.miCloudRegion == .cn)

        store.appLanguagePreference = .en
        store.miCloudRegion = .sg
        #expect(store.effectiveLanguage == .en)
        #expect(store.homeName == "My Home")
        #expect(defaults.string(forKey: "app_language") == "en")
        #expect(defaults.string(forKey: "mi_cloud_region") == "sg")

        store.appLanguagePreference = .zhHans
        #expect(store.effectiveLanguage == .zhHans)
        #expect(store.homeName == "我的家")
    }
}
