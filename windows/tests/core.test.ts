import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, it } from "node:test";
import {
  ASSISTANT_PROVIDER_PRESETS,
  DelayPhrase,
  LocalIntentParser,
  ModelIntentResolver,
  UndoPhrase,
} from "../src/core/assistant.js";
import {
  MiAccountLogin,
  MiCloudClient,
  MiotCommandMapper,
  MiotSpecResolver,
  MiotSynthesizer,
  maskedMiUserId,
  parseMiotDeviceSpec,
  parseMiotInstanceIndex,
  type MiotDeviceSpec,
} from "../src/core/miCloudClient.js";
import { MiCloudCrypto, RC4 } from "../src/core/miCloudCrypto.js";
import type { SmartDevice } from "../src/core/models.js";

const Vectors = {
  ssecurity: "AQIDBAUGBwgJCgsMDQ4PEA==",
  nonce: "oLHC0+T1BhcBuoFA",
  signedNonce: "stUjEBQF1H9IaiRGtgWr8jmxbmJs3Xg11OVxJJfJqUI=",
  path: "/home/device_list",
  data: '{"getVirtualModel":true,"getHuamiDevices":1}',
  rc4HashPlain: "+wnR7pbXbANBJTdJEKPTx32/8jc=",
  encData: "zQrgJvr34Xp4b97kO7lmB2GNcU1GhZGWLZUbXNz8fHxrLnNVOUaIiX1/Sl4=",
  encRc4Hash: "nV/pEbnR6lBuW/HKPIJmKEjkG21Mw8aVN5gdFQ==",
  signature: "p4PJO1KloBVLQOZqU31Nl4ZPq4s=",
  respPlain:
    '{"code":0,"message":"ok","result":{"list":[{"did":"123","name":"灯","model":"yeelink.light.ceiling22","isOnline":true}]}}',
  respCipher:
    "zQrkLOrEqjI8Np3lE6VxA2rKaQMWn5+YI9AMTef8cWUgUG0BPEyejn1/IFij2TGz+h6YR3qdIdDNGAZ38HVVeV7I/xFX7t70RZzHM/zsDtMelQgGK0XRgzlsFk4++2JAP/M/aXlqdpyZpKwhzYQ/MJ7bXSF2VIsJkgg=",
};

describe("MiCloudCrypto", () => {
  it("matches classic RC4 vector without drop", () => {
    const rc4 = new RC4(new TextEncoder().encode("Key"), 0);
    const out = rc4.process(new TextEncoder().encode("Plaintext"));
    const hex = Array.from(out)
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");
    assert.equal(hex, "bbf316e8d940af0ad3");
  });

  it("packs 8 random bytes + big-endian minute counter into nonce", () => {
    const nonce = MiCloudCrypto.makeNonce(
      29_000_000 * 60_000,
      [0xa0, 0xb1, 0xc2, 0xd3, 0xe4, 0xf5, 0x06, 0x17]
    );
    assert.equal(nonce, Vectors.nonce);
  });

  it("matches Python reference signed_nonce, rc4_hash__, encrypted fields and signature", () => {
    assert.equal(
      MiCloudCrypto.signedNonce(Vectors.ssecurity, Vectors.nonce),
      Vectors.signedNonce
    );
    assert.equal(
      MiCloudCrypto.sha1Signature(Vectors.path, [["data", Vectors.data]], Vectors.signedNonce),
      Vectors.rc4HashPlain
    );

    const fields = MiCloudCrypto.encryptParams(
      Vectors.path,
      Vectors.data,
      Vectors.ssecurity,
      Vectors.nonce
    );
    assert.deepEqual(
      fields.map(([k]) => k),
      ["data", "rc4_hash__", "signature", "ssecurity", "_nonce"]
    );
    assert.equal(fields[0]?.[1], Vectors.encData);
    assert.equal(fields[1]?.[1], Vectors.encRc4Hash);
    assert.equal(fields[2]?.[1], Vectors.signature);
    assert.equal(fields[3]?.[1], Vectors.ssecurity);
    assert.equal(fields[4]?.[1], Vectors.nonce);
  });

  it("decrypts RC4 response and parses device list", () => {
    const plain = MiCloudCrypto.decryptResponse(Vectors.respCipher, Vectors.signedNonce);
    assert.equal(plain, Vectors.respPlain);

    const result = MiCloudClient.decodeResponse(Vectors.respCipher, 200, Vectors.signedNonce);
    const devices = MiCloudClient.parseDeviceList(result);
    assert.deepEqual(devices, [
      {
        did: "123",
        name: "灯",
        model: "yeelink.light.ceiling22",
        isOnline: true,
        specType: null,
      },
    ]);
  });
});

describe("MiAccountLogin", () => {
  it("parses ticket and completes scan flow with Set-Cookie serviceToken", async () => {
    const body =
      '&&&START&&&{"loginUrl":"https://account.xiaomi.com/longPolling/login?ticket=abc","qr":"https://account.xiaomi.com/longPolling/qr?ticket=abc","lp":"https://lp.example/poll","timeout":"30","code":0}';
    const ticket = MiAccountLogin.parseTicket(body);
    assert.equal(ticket.loginURL, "https://account.xiaomi.com/longPolling/login?ticket=abc");
    assert.equal(ticket.timeout, 30);

    let polls = 0;
    const login = new MiAccountLogin(async (req) => {
      if (req.url.startsWith("https://lp.example")) {
        polls += 1;
        if (polls === 1) throw new Error("Request timed out");
        return {
          status: 200,
          headers: {} as Record<string, string>,
          body: '&&&START&&&{"userId":1234567890,"ssecurity":"c3M=","cUserId":"cu","passToken":"pt","location":"https://sts.example/sts?x=1"}',
        };
      }
      if (req.url.startsWith("https://sts.example")) {
        return {
          status: 200,
          headers: { "Set-Cookie": "serviceToken=tok123; path=/; domain=.example" } as Record<string, string>,
          body: "ok",
        };
      }
      return { status: 404, headers: {} as Record<string, string>, body: "" };
    });

    const session = await login.waitForScan(ticket);
    assert.equal(session.userId, "1234567890");
    assert.equal(maskedMiUserId(session.userId), "12****90");
    assert.equal(session.serviceToken, "tok123");
  });
});

describe("MiotSynthesizer & MiotCommandMapper", () => {
  const lightSpec: MiotDeviceSpec = {
    type: "urn:miot-spec-v2:device:light:0000A001:yeelink-ceiling22:1",
    services: [
      {
        iid: 2,
        type: "urn:miot-spec-v2:service:light:00007802:yeelink-ceiling22:1",
        properties: [
          { iid: 1, type: "urn:miot-spec-v2:property:on:00000006:yeelink-ceiling22:1", format: "bool", access: ["read", "write"] },
          { iid: 2, type: "urn:miot-spec-v2:property:brightness:0000000D:yeelink-ceiling22:1", format: "uint8", access: ["read", "write"], valueRange: [1, 100, 1] },
          {
            iid: 3,
            type: "urn:miot-spec-v2:property:mode:00000008:yeelink-ceiling22:1",
            format: "uint8",
            access: ["read", "write"],
            valueList: [
              { value: 0, description: "Day" },
              { value: 1, description: "Night" },
            ],
          },
        ],
        actions: [],
      },
    ],
  };

  it("synthesizes a light and maps Moonlight effect to MiotPropWrite", () => {
    const home = MiotSynthesizer.synthesize(
      [{ did: "did1", name: "书房吸顶灯", model: "yeelink.light.ceiling22", isOnline: true, specType: null }],
      [{ id: "r1", name: "书房", dids: ["did1"] }],
      { "yeelink.light.ceiling22": lightSpec },
      new Map<string, unknown>([
        ["did1.2.1", true],
        ["did1.2.2", 80],
        ["did1.2.3", 0],
      ])
    );
    assert.equal(home.devices.length, 1);
    const dev = home.devices[0]!;
    assert.equal(dev.kind.kind, "light");
    assert.deepEqual(dev.kind.availableEffects, ["Day", "Night"]);

    const write = MiotCommandMapper.map(
      { kind: "setLightEffect", entityId: "miot:did1:2", effect: "Night" },
      lightSpec
    );
    assert.deepEqual(write, {
      kind: "setProps",
      writes: [
        { did: "did1", siid: 2, piid: 1, value: true },
        { did: "did1", siid: 2, piid: 3, value: 1 },
      ],
    });
  });

  it("resolves Xiaomi devices with null specType via instances index and normalizes kebab-case value-range/value-list", async () => {
    const rawMiotSpecJson = {
      type: "urn:miot-spec-v2:device:air-conditioner:0000A004:xiaomi-mc5:2",
      services: [
        {
          iid: 2,
          type: "urn:miot-spec-v2:service:air-conditioner:0000780F:xiaomi-mc5:1",
          properties: [
            { iid: 1, type: "urn:miot-spec-v2:property:on:00000006:xiaomi-mc5:1", format: "bool", access: ["read", "write"] },
            {
              iid: 2,
              type: "urn:miot-spec-v2:property:mode:00000008:xiaomi-mc5:1",
              format: "uint8",
              access: ["read", "write"],
              "value-list": [
                { value: 2, description: "Cool" },
                { value: 5, description: "Heat" },
              ],
            },
            {
              iid: 4,
              type: "urn:miot-spec-v2:property:target-temperature:00000021:xiaomi-mc5:1",
              format: "float",
              access: ["read", "write"],
              "value-range": [16, 31, 0.5],
            },
          ],
        },
      ],
    };

    const parsedSpec = parseMiotDeviceSpec(rawMiotSpecJson);
    assert.ok(parsedSpec);
    assert.deepEqual(parsedSpec.services[0]?.properties[2]?.valueRange, [16, 31, 0.5]);
    assert.equal(parsedSpec.services[0]?.properties[1]?.valueList?.[0]?.description, "Cool");

    const idx = parseMiotInstanceIndex({
      instances: [
        { model: "xiaomi.aircondition.mc5", version: 1, type: "urn:old" },
        { model: "xiaomi.aircondition.mc5", version: 2, type: rawMiotSpecJson.type },
      ],
    });
    assert.equal(idx["xiaomi.aircondition.mc5"], rawMiotSpecJson.type);

    const resolver = new MiotSpecResolver(async (req) => {
      if (req.url.includes("/instances?status=released")) {
        return {
          status: 200,
          headers: {},
          body: JSON.stringify({
            instances: [{ model: "xiaomi.aircondition.mc5", version: 2, type: rawMiotSpecJson.type }],
          }),
        };
      }
      if (req.url.includes("/instance?type=")) {
        return {
          status: 200,
          headers: {},
          body: JSON.stringify(rawMiotSpecJson),
        };
      }
      return { status: 404, headers: {}, body: "" };
    });

    const rawDevices = [
      { did: "ac1", name: "主卧空调", model: "xiaomi.aircondition.mc5", isOnline: true, specType: null },
      { did: "plug1", name: "书房插座", model: "unknown.brand.socket1", isOnline: true, specType: null },
    ];
    const resolvedSpecs = await resolver.resolveForDevices(rawDevices);
    const home = MiotSynthesizer.synthesize(
      rawDevices,
      [{ id: "r_bed", name: "主卧", dids: ["ac1"] }],
      resolvedSpecs,
      new Map<string, unknown>([
        ["ac1.2.1", true],
        ["ac1.2.2", 2],
        ["ac1.2.4", 24.5],
        ["plug1.2.1", true],
      ])
    );

    assert.equal(home.devices.length, 2);
    assert.equal(home.devices[0]?.kind.kind, "climate");
    assert.equal(home.devices[0]?.kind.targetTemperature, 24.5);
    assert.equal(home.devices[1]?.kind.kind, "plug");
    assert.equal(home.devices[1]?.kind.isOn, true);
  });

  it("matches the cross-platform MIoT golden JSON corpus shared with MijiaCoreTests", () => {
    const raw = readFileSync(resolve(process.cwd(), "../Tests/Fixtures/miot_golden.json"), "utf8");
    const corpus = JSON.parse(raw) as {
      specs: Record<string, unknown>;
      devices: Array<{
        did: string;
        name: string;
        model: string;
        isOnline: boolean;
        splitParentDid?: string | null;
        splitSiid?: number | null;
      }>;
      rooms: Array<{ id: string; name: string; dids: string[] }>;
      values: Array<{ did: string; siid: number; piid: number; value: unknown }>;
      expectedKinds: Record<string, unknown>;
      expectedEnvironmentReadings: Array<unknown>;
      expectedRequiredProps: Record<string, Array<{ did: string; siid: number; piid: number }>>;
      commandCases: Array<{
        model: string;
        command: Parameters<typeof MiotCommandMapper.map>[0];
        expected: ReturnType<typeof MiotCommandMapper.map>;
      }>;
    };

    const parsedSpecs: Record<string, MiotDeviceSpec> = {};
    for (const [model, rawSpec] of Object.entries(corpus.specs)) {
      const parsed = parseMiotDeviceSpec(rawSpec);
      assert.ok(parsed, `Failed to parse MIoT spec for ${model}`);
      parsedSpecs[model] = parsed;
    }

    const records = corpus.devices.map((d) => ({
      ...d,
      specType: null,
    }));
    const values = new Map<string, unknown>();
    for (const v of corpus.values) {
      values.set(`${v.did}.${v.siid}.${v.piid}`, v.value);
    }

    const home = MiotSynthesizer.synthesize(records, corpus.rooms, parsedSpecs, values);
    assert.equal(home.devices.length, Object.keys(corpus.expectedKinds).length);
    for (const [did, expectedKind] of Object.entries(corpus.expectedKinds)) {
      const dev = home.devices.find((d) => d.id === did);
      assert.ok(dev, `Missing synthesized device ${did}`);
      assert.deepEqual(dev.kind, expectedKind, `DeviceKind mismatch on ${did}`);
    }
    assert.deepEqual(home.environmentReadings, corpus.expectedEnvironmentReadings);

    for (const record of records) {
      const spec = parsedSpecs[record.model];
      assert.ok(spec, `Missing spec for ${record.model}`);
      const actualProps = MiotSynthesizer.requiredProps(record, spec);
      assert.deepEqual(actualProps, corpus.expectedRequiredProps[record.did], `requiredProps mismatch on ${record.did}`);
    }

    for (const item of corpus.commandCases) {
      const spec = parsedSpecs[item.model];
      assert.ok(spec, `Missing spec for ${item.model}`);
      const actualWrite = MiotCommandMapper.map(item.command, spec);
      assert.deepEqual(actualWrite, item.expected, `${item.model} ${item.command.kind}`);
    }
    const dev2 = home.devices.find((d) => d.id === "did_panel.s2");
    assert.equal(dev2?.roomName, "客厅");
  });

  it("parses split Mesh switch keys and multi-home rooms with room-less home dids", () => {
    const parsedDevices = MiCloudClient.parseDeviceList({
      list: [
        { did: "1109223163", name: "Mesh双键", model: "lemesh.switch.sw2f12", isOnline: true },
        {
          did: "1109223163.s2",
          name: "筒灯",
          model: "lemesh.switch.sw2f12",
          isOnline: true,
          extra: { split: { parentId: 1109223163, moduleId: 2 } },
        },
      ],
    });
    assert.equal(parsedDevices.length, 2);
    assert.equal(parsedDevices[1]?.splitParentDid, "1109223163");
    assert.equal(parsedDevices[1]?.splitSiid, 2);

    const parsedRooms = MiCloudClient.parseRooms({
      homelist: [
        {
          id: 9001,
          name: "我的家",
          dids: ["unassigned_did"],
          roomlist: [{ id: 101, name: "客厅", dids: ["1109223163"] }],
        },
      ],
    });
    assert.deepEqual(parsedRooms, [
      { id: "101", name: "客厅", dids: ["1109223163"], homeId: "9001", homeName: "我的家" },
      { id: "home_9001", name: "", dids: ["unassigned_did"], homeId: "9001", homeName: "我的家" },
    ]);
  });
});

describe("LocalIntentParser, DelayPhrase, UndoPhrase, and ModelIntentResolver", () => {
  const devices: SmartDevice[] = [
    {
      id: "dev_ceiling",
      name: "书房吸顶灯",
      roomId: "study",
      roomName: "书房",
      model: "yeelink.light.ceiling20",
      isOnline: true,
      kind: {
        kind: "light",
        entityId: "miot:dev_ceiling:2",
        isOn: true,
        brightnessPercent: 80,
        colorTempKelvin: 4000,
        minKelvin: 2700,
        maxKelvin: 6500,
        currentEffect: "Day",
        availableEffects: ["Day", "Night"],
      },
    },
    {
      id: "dev_desk",
      name: "书房台灯",
      roomId: "study",
      roomName: "书房",
      model: "yeelink.light.lamp4",
      isOnline: true,
      kind: {
        kind: "light",
        entityId: "miot:dev_desk:2",
        isOn: true,
        brightnessPercent: 50,
        colorTempKelvin: 4000,
        minKelvin: 2700,
        maxKelvin: 6500,
        currentEffect: null,
        availableEffects: [],
      },
    },
    {
      id: "dev_fan",
      name: "客厅风扇",
      roomId: "living",
      roomName: "客厅",
      model: "dmaker.fan.p5",
      isOnline: true,
      kind: {
        kind: "fan",
        entityId: "miot:dev_fan:2",
        isOn: true,
        percentage: null,
        presetMode: "Level1",
        availablePresetModes: ["Level1", "Level2", "Level3"],
        isOscillating: false,
      },
    },
  ];

  it("parses moonlight effect, multi-light relative dimming, fan speed, delay, and undo", () => {
    const moon = LocalIntentParser.parse("书房灯月光模式", devices, []);
    assert.ok(moon);
    assert.deepEqual(moon.intents, [
      { targetId: "dev_ceiling", operation: { kind: "lightEffect", effect: "Night" } },
    ]);

    const dimmer = LocalIntentParser.parse("再暗一点", devices, []);
    assert.ok(dimmer);
    assert.deepEqual(dimmer.intents, [
      { targetId: "dev_ceiling", operation: { kind: "brightness", percent: 60 } },
      { targetId: "dev_desk", operation: { kind: "brightness", percent: 30 } },
    ]);

    const fanHigh = LocalIntentParser.parse("风扇调到高档", devices, []);
    assert.ok(fanHigh);
    assert.deepEqual(fanHigh.intents, [
      { targetId: "dev_fan", operation: { kind: "fanSpeed", speed: "Level3" } },
    ]);

    const delay = DelayPhrase.extract("10分钟后关闭书房灯");
    assert.deepEqual(delay, { seconds: 600, remainder: "关闭书房灯" });
    assert.equal(DelayPhrase.isCancel("取消定时"), true);
    assert.equal(UndoPhrase.isUndo("刚才那个撤销"), true);
  });

  it("resolves Jev /v1/systemone multi-choice payload", async () => {
    const resolver = new ModelIntentResolver(
      {
        baseURL: "https://openrouter.ai/api/v1",
        model: "typesafe/jev-latest",
        apiKey: "test-key",
      },
      async (req) => {
        assert.equal(req.url, "https://openrouter.ai/api/v1/systemone");
        const body = JSON.parse(req.body ?? "{}") as Record<string, unknown>;
        assert.equal(body["model"], "~typesafe/jev-latest");
        return {
          status: 200,
          headers: {},
          body: JSON.stringify({
            answers: {
              target: { choice: "room_lights:书房", confidence: 0.98 },
              op: { choice: "effect_night", confidence: 0.96 },
              temp: { choice: "none", confidence: 0.99 },
            },
          }),
        };
      }
    );

    const plan = await resolver.resolve("书房来点柔和月光", devices, []);
    assert.equal(plan.source, "model");
    assert.deepEqual(plan.intents, [
      { targetId: "dev_ceiling", operation: { kind: "lightEffect", effect: "Night" } },
    ]);
  });

  it("supports native TypeSafe Jev (/v1/systemone) and DeepSeek (/v1/chat/completions)", async () => {
    assert.deepEqual(
      ASSISTANT_PROVIDER_PRESETS.map((p) => p.id),
      [
        "openrouter_jev",
        "native_jev",
        "deepseek",
        "siliconflow",
        "dashscope",
        "zhipu_glm",
        "moonshot_kimi",
        "openai",
        "gemini",
        "groq",
        "ollama",
        "custom",
      ]
    );
    const nativeJevResolver = new ModelIntentResolver(
      {
        baseURL: "https://api.typesafe.ai",
        model: "~typesafe/jev-latest",
        apiKey: "Bearer ts-native-key",
      },
      async (req) => {
        assert.equal(req.url, "https://api.typesafe.ai/v1/systemone");
        assert.equal(req.headers?.["Authorization"], "Bearer ts-native-key");
        const body = JSON.parse(req.body ?? "{}") as Record<string, unknown>;
        assert.equal(body["model"], "jev-latest");
        return {
          status: 200,
          headers: {},
          body: JSON.stringify({
            answers: {
              target: { choice: "d1", confidence: 0.99 },
              op: { choice: "effect_night", confidence: 0.98 },
              temp: { choice: "none", confidence: 1.0 },
            },
          }),
        };
      }
    );
    const nativePlan = await nativeJevResolver.resolve("柔和一点", devices, []);
    assert.deepEqual(nativePlan.intents, [
      { targetId: "dev_ceiling", operation: { kind: "lightEffect", effect: "Night" } },
    ]);

    const deepSeekResolver = new ModelIntentResolver(
      {
        baseURL: "https://api.deepseek.com",
        model: "deepseek-reasoner",
        apiKey: "sk-deepseek-key",
      },
      async (req) => {
        assert.equal(req.url, "https://api.deepseek.com/v1/chat/completions");
        assert.equal(req.headers?.["Authorization"], "Bearer sk-deepseek-key");
        const body = JSON.parse(req.body ?? "{}") as Record<string, unknown>;
        assert.equal(body["model"], "deepseek-reasoner");
        return {
          status: 200,
          headers: {},
          body: JSON.stringify({
            choices: [
              {
                message: {
                  content:
                    '<think>分析 {d1}</think>{"actions":[{"device":"d1","op":"effect","value":"Night"}],"reply":"已切换月光"}',
                },
              },
            ],
          }),
        };
      }
    );
    const dsPlan = await deepSeekResolver.resolve("书房月光", devices, []);
    assert.deepEqual(dsPlan.intents, [
      { targetId: "dev_ceiling", operation: { kind: "lightEffect", effect: "Night" } },
    ]);
  });

  it("matches the cross-platform golden JSON corpus shared with MijiaCoreTests", () => {
    const raw = readFileSync(resolve(process.cwd(), "../Tests/Fixtures/intent_golden.json"), "utf8");
    const corpus = JSON.parse(raw) as {
      devices: SmartDevice[];
      intentCases: Array<{
        utterance: string;
        expected: Array<{ targetId: string; kind: string; value: boolean | number | string }> | null;
      }>;
      delayCases: Array<{ utterance: string; seconds: number | null; remainder: string | null }>;
      cancelCases: Array<{ utterance: string; isCancel: boolean }>;
      undoCases: Array<{ utterance: string; isUndo: boolean }>;
    };

    const encodeOp = (intent: { targetId: string; operation: Record<string, unknown> }) => {
      const k = String(intent.operation["kind"]);
      const val =
        intent.operation["isOn"] ??
        intent.operation["percent"] ??
        intent.operation["kelvin"] ??
        intent.operation["effect"] ??
        intent.operation["mode"] ??
        intent.operation["celsius"] ??
        intent.operation["speed"] ??
        intent.operation["enabled"] ??
        intent.operation["delta"] ??
        true;
      return { targetId: intent.targetId, kind: k, value: val };
    };

    for (const item of corpus.intentCases) {
      const plan = LocalIntentParser.parse(item.utterance, corpus.devices, []);
      if (item.expected === null) {
        assert.equal(plan, null, item.utterance);
      } else {
        assert.ok(plan, `Expected plan for: ${item.utterance}`);
        assert.deepEqual(plan.intents.map(encodeOp as never), item.expected, item.utterance);
      }
    }

    for (const item of corpus.delayCases) {
      const got = DelayPhrase.extract(item.utterance);
      if (item.seconds === null || item.remainder === null) {
        assert.equal(got, null, item.utterance);
      } else {
        assert.deepEqual(got, { seconds: item.seconds, remainder: item.remainder }, item.utterance);
      }
    }

    for (const item of corpus.cancelCases) {
      assert.equal(DelayPhrase.isCancel(item.utterance), item.isCancel, item.utterance);
    }

    for (const item of corpus.undoCases) {
      assert.equal(UndoPhrase.isUndo(item.utterance), item.isUndo, item.utterance);
    }
  });
});
