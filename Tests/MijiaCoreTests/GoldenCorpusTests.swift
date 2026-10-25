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
        case plug(PlugPayload)
        case vacuum(VacuumPayload)
        case sensor(SensorPayload)

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
            let availableSwingModes: [String]?
        }

        struct FanPayload: Decodable {
            let entityId: String
            let isOn: Bool
            let percentage: Int?
            let presetMode: String?
            let availablePresetModes: [String]
            let isOscillating: Bool?
        }

        struct PlugPayload: Decodable {
            let switchEntityId: String
            let isOn: Bool
            let powerWatts: Double?
            let childLockEntityId: String?
            let isChildLocked: Bool
        }

        struct VacuumPayload: Decodable {
            let entityId: String
            let status: String
            let battery: Int?
            let modeEntityId: String?
            let currentMode: String?
            let availableModes: [String]
        }

        struct SensorPayload: Decodable {
            let temperature: Double?
            let humidity: Double?
            let battery: Int?
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
            case "plug":
                self = .plug(try PlugPayload(from: decoder))
            case "vacuum":
                self = .vacuum(try VacuumPayload(from: decoder))
            case "sensor":
                self = .sensor(try SensorPayload(from: decoder))
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
                        availableSwingModes: p.availableSwingModes ?? []
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
            case .plug(let p):
                return .plug(
                    PlugSpec(
                        switchEntityId: p.switchEntityId,
                        isOn: p.isOn,
                        powerWatts: p.powerWatts,
                        energyKwh: nil,
                        childLockEntityId: p.childLockEntityId,
                        isChildLocked: p.isChildLocked
                    )
                )
            case .vacuum(let p):
                return .vacuum(
                    VacuumSpec(
                        entityId: p.entityId,
                        status: p.status,
                        battery: p.battery,
                        modeEntityId: p.modeEntityId,
                        currentMode: p.currentMode,
                        availableModes: p.availableModes
                    )
                )
            case .sensor(let p):
                return .sensor(
                    SensorSpec(
                        temperature: p.temperature,
                        humidity: p.humidity,
                        battery: p.battery
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

    private struct MiotCorpus: Decodable {
        let specs: [String: MiotDeviceSpec]
        let devices: [MiotDeviceEntry]
        let rooms: [MiotRoomEntry]
        let values: [MiotValueEntry]
        let expectedKinds: [String: CorpusKind]
        let expectedEnvironmentReadings: [MiotReadingEntry]
        let expectedRequiredProps: [String: [MiotKeyEntry]]
        let commandCases: [MiotCommandCase]
    }

    private struct MiotReadingEntry: Decodable {
        let id: String
        let label: String
        let roomName: String
        let temperature: Double?
        let humidity: Double?
        let battery: Int?

        func toEnvironmentReading() -> EnvironmentReading {
            EnvironmentReading(
                id: id,
                label: label,
                roomName: roomName,
                temperature: temperature,
                humidity: humidity,
                battery: battery
            )
        }
    }

    private struct MiotDeviceEntry: Decodable {
        let did: String
        let name: String
        let model: String
        let isOnline: Bool
    }

    private struct MiotRoomEntry: Decodable {
        let id: String
        let name: String
        let dids: [String]
    }

    private struct MiotValueEntry: Decodable {
        let did: String
        let siid: Int
        let piid: Int
        let value: JSONValue
    }

    private struct MiotKeyEntry: Decodable, Equatable {
        let did: String
        let siid: Int
        let piid: Int
    }

    private struct MiotCommandPayload: Decodable {
        let kind: String
        let entityId: String
        let isOn: Bool?
        let percent: Int?
        let kelvin: Int?
        let effect: String?
        let hvacMode: String?
        let temperature: Double?
        let fanMode: String?
        let presetMode: String?
        let oscillating: Bool?
        let action: String?

        func toDeviceCommand() throws -> DeviceCommand {
            switch kind {
            case "setLightPower":
                return .setLightPower(entityId: entityId, isOn: isOn ?? false)
            case "setLightBrightness":
                return .setLightBrightness(entityId: entityId, percent: percent ?? 0)
            case "setLightColorTemp":
                return .setLightColorTemp(entityId: entityId, kelvin: kelvin ?? 4000)
            case "setLightEffect":
                return .setLightEffect(entityId: entityId, effect: effect ?? "")
            case "setClimateMode":
                return .setClimateMode(entityId: entityId, hvacMode: hvacMode ?? "off")
            case "setClimateTemperature":
                return .setClimateTemperature(entityId: entityId, temperature: temperature ?? 26)
            case "setClimateFanMode":
                return .setClimateFanMode(entityId: entityId, fanMode: fanMode ?? "")
            case "setFanPresetMode":
                return .setFanPresetMode(entityId: entityId, presetMode: presetMode ?? "")
            case "setFanOscillating":
                return .setFanOscillating(entityId: entityId, oscillating: oscillating ?? false)
            case "setSwitch":
                return .setSwitch(entityId: entityId, isOn: isOn ?? false)
            case "vacuumAction":
                let vAction: VacuumAction = switch action {
                case "start": .start
                case "pause": .pause
                default: .returnToBase
                }
                return .vacuumAction(entityId: entityId, action: vAction)
            default:
                throw CocoaError(.coderInvalidValue)
            }
        }
    }

    private struct MiotExpectedWrite: Decodable {
        let kind: String
        let writes: [MiotValueEntry]?
        let call: MiotExpectedAction?

        func toMiotWrite() -> MiotWrite {
            if kind == "action", let c = call {
                return .action(MiotActionCall(did: c.did, siid: c.siid, aiid: c.aiid, inputs: c.inputs))
            }
            let props = (writes ?? []).map {
                MiotPropWrite(did: $0.did, siid: $0.siid, piid: $0.piid, value: $0.value)
            }
            return .setProps(props)
        }
    }

    private struct MiotExpectedAction: Decodable {
        let did: String
        let siid: Int
        let aiid: Int
        let inputs: [JSONValue]
    }

    private struct MiotCommandCase: Decodable {
        let model: String
        let command: MiotCommandPayload
        let expected: MiotExpectedWrite
    }

    private static func locateGoldenFixture(_ relativePath: String = "Tests/Fixtures/intent_golden.json") throws -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = dir.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            dir.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }

    @Test("Cross-platform golden JSON corpus matches MijiaCore LocalIntentParser, DelayPhrase, and UndoPhrase")
    func goldenCorpusParity() throws {
        let fixtureURL = try Self.locateGoldenFixture("Tests/Fixtures/intent_golden.json")
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

    @Test("Cross-platform MIoT golden JSON corpus matches MijiaCore MiotSynthesizer and MiotCommandMapper")
    func miotGoldenCorpusParity() throws {
        let fixtureURL = try Self.locateGoldenFixture("Tests/Fixtures/miot_golden.json")
        let data = try Data(contentsOf: fixtureURL)
        let corpus = try JSONDecoder().decode(MiotCorpus.self, from: data)

        let records = corpus.devices.map {
            MiDeviceRecord(did: $0.did, name: $0.name, model: $0.model, isOnline: $0.isOnline)
        }
        let rooms = corpus.rooms.map {
            MiRoom(id: $0.id, name: $0.name, dids: $0.dids)
        }
        var values: [MiotPropKey: JSONValue] = [:]
        for v in corpus.values {
            values[MiotPropKey(did: v.did, siid: v.siid, piid: v.piid)] = v.value
        }

        let home = MiotSynthesizer.synthesize(
            devices: records,
            rooms: rooms,
            specs: corpus.specs,
            values: values
        )

        #expect(home.devices.count == corpus.expectedKinds.count)
        for (did, expectedKind) in corpus.expectedKinds {
            let dev = try #require(home.devices.first(where: { $0.id == did }), "Missing device \(did)")
            #expect(dev.kind == expectedKind.toDeviceKind(), "Mismatch on \(did)")
        }
        #expect(home.environmentReadings == corpus.expectedEnvironmentReadings.map { $0.toEnvironmentReading() })

        for record in records {
            let spec = try #require(corpus.specs[record.model])
            let expectedProps = try #require(corpus.expectedRequiredProps[record.did]).map {
                MiotPropKey(did: $0.did, siid: $0.siid, piid: $0.piid)
            }
            let actualProps = MiotSynthesizer.requiredProps(for: record, spec: spec)
            #expect(actualProps == expectedProps, "requiredProps mismatch on \(record.did)")
        }

        for item in corpus.commandCases {
            let spec = try #require(corpus.specs[item.model], "Missing spec \(item.model)")
            let cmd = try item.command.toDeviceCommand()
            let actualWrite = try MiotCommandMapper.map(cmd, spec: spec)
            #expect(actualWrite == item.expected.toMiotWrite(), "\(item.model) \(item.command.kind)")
        }
    }
}
