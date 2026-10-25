import Foundation
import Testing
@testable import MijiaCore

struct GoldenCorpusTests {
    private struct Corpus: Decodable {
        let devices: [CorpusDevice]
        let intentCases: [IntentCase]
        let delayCases: [DelayCase]
        let cancelCases: [CancelCase]
        let undoCases: [UndoCase]
    }

    private struct CorpusDevice: Decodable {
        let id: String
        let name: String
        let roomId: String
        let roomName: String
        let model: String
        let isOnline: Bool
        let kind: CorpusKind

        func toSmartDevice() -> SmartDevice {
            let deviceKind: DeviceKind
            switch kind.kind {
            case "light":
                deviceKind = .light(
                    LightSpec(
                        entityId: kind.entityId ?? "",
                        isOn: kind.isOn ?? false,
                        brightnessPercent: kind.brightnessPercent,
                        colorTempKelvin: kind.colorTempKelvin,
                        minKelvin: kind.minKelvin ?? 2700,
                        maxKelvin: kind.maxKelvin ?? 6500,
                        currentEffect: kind.currentEffect,
                        availableEffects: kind.availableEffects ?? []
                    )
                )
            case "climate":
                deviceKind = .climate(
                    ClimateSpec(
                        entityId: kind.entityId ?? "",
                        isOn: kind.isOn ?? false,
                        hvacMode: kind.hvacMode ?? "off",
                        availableModes: kind.availableModes ?? [],
                        targetTemperature: kind.targetTemperature ?? 26,
                        currentTemperature: kind.currentTemperature,
                        minTemp: kind.minTemp ?? 16,
                        maxTemp: kind.maxTemp ?? 31,
                        step: kind.step ?? 0.5,
                        fanMode: kind.fanMode,
                        availableFanModes: kind.availableFanModes ?? [],
                        swingMode: kind.swingMode,
                        availableSwingModes: kind.availableSwingModes ?? []
                    )
                )
            default:
                deviceKind = .fan(
                    FanSpec(
                        entityId: kind.entityId ?? "",
                        isOn: kind.isOn ?? false,
                        percentage: kind.percentage,
                        presetMode: kind.presetMode,
                        availablePresetModes: kind.availablePresetModes ?? [],
                        isOscillating: kind.isOscillating
                    )
                )
            }
            return SmartDevice(
                id: id,
                name: name,
                roomId: roomId,
                roomName: roomName,
                model: model,
                isOnline: isOnline,
                kind: deviceKind
            )
        }
    }

    private struct CorpusKind: Decodable {
        let kind: String
        let entityId: String?
        let isOn: Bool?
        let brightnessPercent: Int?
        let colorTempKelvin: Int?
        let minKelvin: Int?
        let maxKelvin: Int?
        let currentEffect: String?
        let availableEffects: [String]?
        let hvacMode: String?
        let availableModes: [String]?
        let targetTemperature: Double?
        let currentTemperature: Double?
        let minTemp: Double?
        let maxTemp: Double?
        let step: Double?
        let fanMode: String?
        let availableFanModes: [String]?
        let swingMode: String?
        let availableSwingModes: [String]?
        let percentage: Int?
        let presetMode: String?
        let availablePresetModes: [String]?
        let isOscillating: Bool?
    }

    private enum ExpectedValue: Decodable, Equatable {
        case bool(Bool)
        case number(Double)
        case string(String)

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let b = try? c.decode(Bool.self) {
                self = .bool(b)
            } else if let n = try? c.decode(Double.self) {
                self = .number(n)
            } else {
                self = .string(try c.decode(String.self))
            }
        }
    }

    private struct ExpectedIntent: Decodable, Equatable {
        let targetId: String
        let kind: String
        let value: ExpectedValue
    }

    private struct IntentCase: Decodable {
        let utterance: String
        let expected: [ExpectedIntent]
    }

    private struct DelayCase: Decodable {
        let utterance: String
        let seconds: TimeInterval
        let remainder: String
    }

    private struct CancelCase: Decodable {
        let utterance: String
        let isCancel: Bool
    }

    private struct UndoCase: Decodable {
        let utterance: String
        let isUndo: Bool
    }

    private static func encodeIntent(_ intent: DeviceIntent) -> ExpectedIntent {
        switch intent.operation {
        case .power(let on):
            return ExpectedIntent(targetId: intent.targetId, kind: "power", value: .bool(on))
        case .brightness(let pct):
            return ExpectedIntent(targetId: intent.targetId, kind: "brightness", value: .number(Double(pct)))
        case .colorTemperature(let k):
            return ExpectedIntent(targetId: intent.targetId, kind: "colorTemperature", value: .number(Double(k)))
        case .lightEffect(let eff):
            return ExpectedIntent(targetId: intent.targetId, kind: "lightEffect", value: .string(eff))
        case .hvacMode(let mode):
            return ExpectedIntent(targetId: intent.targetId, kind: "hvacMode", value: .string(mode))
        case .targetTemperature(let t):
            return ExpectedIntent(targetId: intent.targetId, kind: "targetTemperature", value: .number(t))
        case .fanSpeed(let s):
            return ExpectedIntent(targetId: intent.targetId, kind: "fanSpeed", value: .string(s))
        case .oscillation(let on):
            return ExpectedIntent(targetId: intent.targetId, kind: "oscillation", value: .bool(on))
        case .activateScene:
            return ExpectedIntent(targetId: intent.targetId, kind: "activateScene", value: .bool(true))
        case .brightnessStep(let d):
            return ExpectedIntent(targetId: intent.targetId, kind: "brightnessStep", value: .number(Double(d)))
        case .temperatureStep(let d):
            return ExpectedIntent(targetId: intent.targetId, kind: "temperatureStep", value: .number(d))
        }
    }

    @Test("Cross-platform golden JSON corpus matches MijiaCore LocalIntentParser, DelayPhrase, and UndoPhrase")
    func goldenCorpusParity() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixtureURL = repoRoot.appendingPathComponent("Tests/Fixtures/intent_golden.json")
        let data = try Data(contentsOf: fixtureURL)
        let corpus = try JSONDecoder().decode(Corpus.self, from: data)
        let devices = corpus.devices.map { $0.toSmartDevice() }

        for item in corpus.intentCases {
            let plan = try #require(LocalIntentParser.parse(item.utterance, devices: devices, scenes: []), "\(item.utterance)")
            let actual = plan.intents.map(Self.encodeIntent)
            #expect(actual == item.expected, "\(item.utterance)")
        }

        for item in corpus.delayCases {
            let got = try #require(DelayPhrase.extract(item.utterance), "\(item.utterance)")
            #expect(got.delay == item.seconds, "\(item.utterance)")
            #expect(got.remainder == item.remainder, "\(item.utterance)")
        }

        for item in corpus.cancelCases {
            #expect(DelayPhrase.isCancel(item.utterance) == item.isCancel, "\(item.utterance)")
        }

        for item in corpus.undoCases {
            #expect(UndoPhrase.isUndo(item.utterance) == item.isUndo, "\(item.utterance)")
        }
    }
}
