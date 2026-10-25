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
            SmartDevice(
                id: id,
                name: name,
                roomId: roomId,
                roomName: roomName,
                model: model,
                isOnline: isOnline,
                kind: kind.toDeviceKind()
            )
        }
    }

    private enum CorpusKind: Decodable {
        case light(LightPayload)
        case climate(ClimatePayload)
        case fan(FanPayload)

        private enum CodingKeys: String, CodingKey { case kind }

        struct LightPayload: Decodable {
            let entityId: String
            let isOn: Bool
            let brightnessPercent: Int?
            let colorTempKelvin: Int?
            let minKelvin: Int
            let maxKelvin: Int
            let currentEffect: String?
            let availableEffects: [String]
        }

        struct ClimatePayload: Decodable {
            let entityId: String
            let isOn: Bool
            let hvacMode: String
            let availableModes: [String]
            let targetTemperature: Double
            let currentTemperature: Double?
            let minTemp: Double
            let maxTemp: Double
            let step: Double
            let fanMode: String?
            let availableFanModes: [String]
            let swingMode: String?
            let availableSwingModes: [String]
        }

        struct FanPayload: Decodable {
            let entityId: String
            let isOn: Bool
            let percentage: Int?
            let presetMode: String?
            let availablePresetModes: [String]
            let isOscillating: Bool?
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try container.decode(String.self, forKey: .kind)
            switch kind {
            case "light":
                self = .light(try LightPayload(from: decoder))
            case "climate":
                self = .climate(try ClimatePayload(from: decoder))
            case "fan":
                self = .fan(try FanPayload(from: decoder))
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .kind,
                    in: container,
                    debugDescription: "Unknown device kind in golden corpus: \(kind)"
                )
            }
        }

        func toDeviceKind() -> DeviceKind {
            switch self {
            case .light(let p):
                return .light(
                    LightSpec(
                        entityId: p.entityId,
                        isOn: p.isOn,
                        brightnessPercent: p.brightnessPercent,
                        colorTempKelvin: p.colorTempKelvin,
                        minKelvin: p.minKelvin,
                        maxKelvin: p.maxKelvin,
                        currentEffect: p.currentEffect,
                        availableEffects: p.availableEffects
                    )
                )
            case .climate(let p):
                return .climate(
                    ClimateSpec(
                        entityId: p.entityId,
                        isOn: p.isOn,
                        hvacMode: p.hvacMode,
                        availableModes: p.availableModes,
                        targetTemperature: p.targetTemperature,
                        currentTemperature: p.currentTemperature,
                        minTemp: p.minTemp,
                        maxTemp: p.maxTemp,
                        step: p.step,
                        fanMode: p.fanMode,
                        availableFanModes: p.availableFanModes,
                        swingMode: p.swingMode,
                        availableSwingModes: p.availableSwingModes
                    )
                )
            case .fan(let p):
                return .fan(
                    FanSpec(
                        entityId: p.entityId,
                        isOn: p.isOn,
                        percentage: p.percentage,
                        presetMode: p.presetMode,
                        availablePresetModes: p.availablePresetModes,
                        isOscillating: p.isOscillating
                    )
                )
            }
        }
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
        let expected: [ExpectedIntent]?
    }

    private struct DelayCase: Decodable {
        let utterance: String
        let seconds: TimeInterval?
        let remainder: String?
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
            if let expected = item.expected {
                let plan = try #require(LocalIntentParser.parse(item.utterance, devices: devices, scenes: []), "\(item.utterance)")
                let actual = plan.intents.map(Self.encodeIntent)
                #expect(actual == expected, "\(item.utterance)")
            } else {
                #expect(LocalIntentParser.parse(item.utterance, devices: devices, scenes: []) == nil, "\(item.utterance)")
            }
        }

        for item in corpus.delayCases {
            if let seconds = item.seconds, let remainder = item.remainder {
                let got = try #require(DelayPhrase.extract(item.utterance), "\(item.utterance)")
                #expect(got.delay == seconds, "\(item.utterance)")
                #expect(got.remainder == remainder, "\(item.utterance)")
            } else {
                #expect(DelayPhrase.extract(item.utterance) == nil, "\(item.utterance)")
            }
        }

        for item in corpus.cancelCases {
            #expect(DelayPhrase.isCancel(item.utterance) == item.isCancel, "\(item.utterance)")
        }

        for item in corpus.undoCases {
            #expect(UndoPhrase.isUndo(item.utterance) == item.isUndo, "\(item.utterance)")
        }
    }
}
