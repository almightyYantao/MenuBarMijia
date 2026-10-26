import assert from "node:assert/strict";
import { afterEach, beforeEach, describe, it } from "node:test";
import { setImmediate } from "node:timers/promises";
import { Window } from "happy-dom";

import { installWindow } from "./dom.js";
import { MenuMijiaWindowsApp } from "../src/ui/app.js";
import { cloudFixture } from "./cloudFixture.js";

let dom: Window;

function element(selector: string): HTMLElement {
  const found = document.querySelector<HTMLElement>(selector);
  assert.ok(found, `Missing control ${selector}`);
  return found;
}

async function click(selector: string): Promise<void> {
  element(selector).click();
  await setImmediate();
}

function tile(id: string): string {
  return element(`[data-body-device="${id}"]`).textContent ?? "";
}

function startDemo(): void {
  localStorage.setItem("menumijia.windows.settings.v2", JSON.stringify({
    connectionMode: "demo",
    hasCompletedOnboarding: true,
  }));
  new MenuMijiaWindowsApp(element("#app"));
}

async function setRange(selector: string, value: string): Promise<void> {
  const slider = document.querySelector<HTMLInputElement>(selector);
  assert.ok(slider);
  slider.value = value;
  slider.dispatchEvent(new Event("change", { bubbles: true }));
  await setImmediate();
}

async function command(text: string): Promise<void> {
  const input = document.querySelector<HTMLInputElement>("#command-input");
  assert.ok(input);
  input.value = text;
  await click("#btn-send");
}

beforeEach(() => {
  dom = new Window({ url: "http://localhost/" });
  installWindow(dom);
  document.body.innerHTML = '<div id="app"></div>';
});

afterEach(async () => {
  await dom.happyDOM.abort();
  dom.close();
});

describe("Windows device control and undo", () => {
  it("restores an originally off light without turning it on through brightness", async () => {
    startDemo();
    await click('[data-toggle-device="light.living_ceiling"]');
    assert.match(tile("light.living_ceiling"), /已关闭/);
    await click('[data-toggle-device="light.living_ceiling"]');
    assert.match(tile("light.living_ceiling"), /已开启/);
    await click("#btn-undo");
    assert.match(tile("light.living_ceiling"), /已关闭/);
    assert.match(document.body.textContent ?? "", /已撤销/);
  });

  it("restores the changed light color temperature without changing brightness", async () => {
    startDemo();
    await click('[data-expand-device="light.living_ceiling"]');
    await setRange('[data-colortemp="light.living_ceiling"]', "5500");
    assert.match(tile("light.living_ceiling"), /5500K/);
    await click("#btn-undo");
    assert.match(tile("light.living_ceiling"), /78% · 4100K/);
  });

  it("restores a light effect through the natural command flow", async () => {
    startDemo();
    await command("客厅吸顶灯月光模式");
    assert.match(tile("light.living_ceiling"), /月光/);
    await click("#btn-undo");
    assert.match(tile("light.living_ceiling"), /日光/);
  });

  it("switches moonlight from the light drawer and restores its original mode on undo", async () => {
    startDemo();
    await click('[data-expand-device="light.living_ceiling"]');
    const daylight = '[data-lighteffect="light.living_ceiling"][data-effect="Day"]';
    const moonlight = '[data-lighteffect="light.living_ceiling"][data-effect="Night"]';
    assert.equal(element(daylight).getAttribute("aria-pressed"), "true");
    await click(moonlight);
    assert.match(tile("light.living_ceiling"), /月光/);
    assert.match(tile("light.living_ceiling"), /78%/);
    assert.match(tile("light.living_ceiling"), /4100K/);
    assert.equal(element(moonlight).getAttribute("aria-pressed"), "true");
    await click("#btn-undo");
    assert.match(tile("light.living_ceiling"), /日光/);
    assert.equal(element(daylight).getAttribute("aria-pressed"), "true");
  });

  it("restores a fan preset and its initially off power state", async () => {
    startDemo();
    await click('[data-expand-device="fan.bedroom_standing"]');
    await click('[data-fanpreset="fan.bedroom_standing:Level 4"]');
    assert.match(tile("fan.bedroom_standing"), /Level 4/);
    await click("#btn-undo");
    assert.match(tile("fan.bedroom_standing"), /已关闭/);
    assert.equal(element('[data-fanpreset="fan.bedroom_standing:Level 2"]').classList.contains("is-active"), true);
  });

  it("restores fan oscillation and its initially off power state", async () => {
    startDemo();
    await click('[data-expand-device="fan.bedroom_standing"]');
    await click('[data-fanosc="fan.bedroom_standing"]');
    assert.match(tile("fan.bedroom_standing"), /摇头/);
    await click("#btn-undo");
    assert.match(tile("fan.bedroom_standing"), /已关闭/);
    assert.match(element('[data-fanosc="fan.bedroom_standing"]').textContent ?? "", /摇头 关/);
  });

  it("undoes only acknowledged attributes when another command on the same device fails", async () => {
    const cloud = cloudFixture([
      { targetId: "fixture-light", operation: { kind: "brightness", percent: 80 } },
      { targetId: "fixture-light", operation: { kind: "colorTemperature", kelvin: 5500 } },
    ]);
    new MenuMijiaWindowsApp(element("#app"));
    await setImmediate();
    assert.match(tile("fixture-light"), /50% · 4100K/);
    await command("部分失败");
    assert.match(document.body.textContent ?? "", /1 项失败/);
    assert.match(tile("fixture-light"), /50% · 5500K/);
    cloud.values.set(2, 90);
    await click("#btn-refresh");
    assert.match(tile("fixture-light"), /90% · 5500K/);
    cloud.allowBrightness();
    await click("#btn-undo");
    assert.match(tile("fixture-light"), /90% · 4100K/);
    assert.equal(cloud.values.get(2), 90);
    assert.equal(cloud.values.get(3), 4100);
  });

  it("reverses multiple acknowledged changes to the same attribute in execution order", async () => {
    const cloud = cloudFixture([
      { targetId: "fixture-light", operation: { kind: "brightness", percent: 80 } },
      { targetId: "fixture-light", operation: { kind: "brightness", percent: 60 } },
    ]);
    cloud.allowBrightness();
    new MenuMijiaWindowsApp(element("#app"));
    await setImmediate();
    await command("部分失败");
    assert.match(tile("fixture-light"), /60%/);
    await click("#btn-undo");
    assert.match(tile("fixture-light"), /50%/);
    assert.equal(cloud.values.get(2), 50);
  });

  it("preserves final power correction when a failed undo is retried", async () => {
    const cloud = cloudFixture([]);
    cloud.values.set(1, false);
    new MenuMijiaWindowsApp(element("#app"));
    await setImmediate();
    assert.match(tile("fixture-light"), /已关闭/);
    await click('[data-expand-device="fixture-light"]');
    await setRange('[data-colortemp="fixture-light"]', "5500");
    cloud.reject(3, 4100);
    await click("#btn-undo");
    assert.match(document.body.textContent ?? "", /撤销未完成/);
    assert.match(tile("fixture-light"), /已关闭/);
    cloud.allow(3);
    await click("#btn-undo");
    assert.match(tile("fixture-light"), /已关闭/);
    assert.equal(cloud.values.get(1), false);
    assert.equal(cloud.values.get(3), 4100);
    assert.match(document.body.textContent ?? "", /已撤销/);
  });
});

describe("AI key stays with the server it was saved for (#19)", () => {
  function keyField(): HTMLInputElement {
    return element("#settings-api-key") as HTMLInputElement;
  }

  it("does not carry the saved key to another provider, and restores it when switching back", async () => {
    localStorage.setItem("menumijia.windows.settings.v2", JSON.stringify({
      connectionMode: "demo",
      hasCompletedOnboarding: true,
      assistantBaseURL: "https://openrouter.ai/api/v1",
      openRouterApiKey: "sk-or-saved",
    }));
    new MenuMijiaWindowsApp(element("#app"));
    await click("#btn-settings");
    assert.equal(keyField().value, "sk-or-saved");

    await click('[data-ai-preset="deepseek"]');
    assert.equal(keyField().value, "");

    await click('[data-ai-preset="openrouter_jev"]');
    assert.equal(keyField().value, "sk-or-saved");

    const base = element("#settings-base-url") as HTMLInputElement;
    base.value = "https://openrouter.ai.evil.com/api/v1";
    base.dispatchEvent(new Event("input", { bubbles: true }));
    assert.equal(keyField().value, "");
  });

  it("never sends a key that was saved for a different server", async () => {
    localStorage.setItem("menumijia.windows.settings.v2", JSON.stringify({
      connectionMode: "demo",
      hasCompletedOnboarding: true,
      assistantBaseURL: "https://my-proxy.example.com/v1",
      openRouterApiKey: "sk-saved-for-openrouter",
      assistantKeyEndpoint: "openrouter.ai",
    }));
    new MenuMijiaWindowsApp(element("#app"));
    await command("帮我想想今晚怎么安排灯光氛围");
    assert.match(document.body.textContent ?? "", /未命中本地规则。请在设置中填写 AI 服务的 API Key/);
  });
});

describe("First cloud AI request asks once (#20)", () => {
  function fakeModel(): string[] {
    const urls: string[] = [];
    const content = JSON.stringify({ actions: [], reply: "已经很合适了" });
    const invoke = async (name: string, args: Record<string, unknown> = {}) => {
      if (name !== "native_http") return undefined;
      urls.push(String(args.url));
      return { status: 200, headers: {}, body: JSON.stringify({ choices: [{ message: { content } }] }) };
    };
    Object.defineProperty(window, "__TAURI_INTERNALS__", { value: { invoke }, configurable: true });
    localStorage.setItem("menumijia.windows.settings.v2", JSON.stringify({
      connectionMode: "demo",
      hasCompletedOnboarding: true,
      assistantBaseURL: "https://api.deepseek.com/v1",
      assistantModel: "deepseek-chat",
      openRouterApiKey: "sk-deepseek",
      assistantKeyEndpoint: "api.deepseek.com",
    }));
    return urls;
  }

  it("sends nothing until allowed, then remembers the service", async () => {
    const urls = fakeModel();
    new MenuMijiaWindowsApp(element("#app"));
    await command("帮我想想今晚怎么安排灯光氛围");
    assert.match(document.body.textContent ?? "", /要交给云端 AI（api\.deepseek\.com）处理吗/);
    assert.equal(urls.length, 0);

    await click("#btn-cloud-allow");
    await setImmediate();
    assert.deepEqual(urls, ["https://api.deepseek.com/v1/chat/completions"]);
    const saved = JSON.parse(localStorage.getItem("menumijia.windows.settings.v2") ?? "{}") as { cloudConsentEndpoints?: string[] };
    assert.deepEqual(saved.cloudConsentEndpoints, ["api.deepseek.com"]);

    await command("帮我想想今晚怎么安排灯光氛围");
    assert.equal(urls.length, 2);
    assert.equal(document.querySelector("#btn-cloud-allow"), null);
  });

  it("declining sends nothing", async () => {
    const urls = fakeModel();
    new MenuMijiaWindowsApp(element("#app"));
    await command("帮我想想今晚怎么安排灯光氛围");
    await click("#btn-cloud-decline");
    assert.match(document.body.textContent ?? "", /没有发送/);
    assert.equal(urls.length, 0);
  });
});

describe("AI suggestions wait for a tap (#21)", () => {
  it("shows a chip for an unsure guess and runs it only when tapped", async () => {
    const answers = {
      target: { choice: "d3", confidence: 0.9 },
      op: { choice: "power_off", confidence: 0.55 },
      temp: { choice: "none", confidence: 0.99 },
    };
    const invoke = async (name: string) => {
      if (name !== "native_http") return undefined;
      return { status: 200, headers: {}, body: JSON.stringify({ answers }) };
    };
    Object.defineProperty(window, "__TAURI_INTERNALS__", { value: { invoke }, configurable: true });
    localStorage.setItem("menumijia.windows.settings.v2", JSON.stringify({
      connectionMode: "demo",
      hasCompletedOnboarding: true,
      assistantBaseURL: "https://openrouter.ai/api/v1",
      assistantModel: "~typesafe/jev-latest",
      openRouterApiKey: "sk-or-test",
      assistantKeyEndpoint: "openrouter.ai",
      cloudConsentEndpoints: ["openrouter.ai"],
    }));
    new MenuMijiaWindowsApp(element("#app"));
    const before = tile("light.study_desk");
    await command("帮我想想今晚怎么安排灯光氛围");
    await setImmediate();
    assert.match(document.body.textContent ?? "", /没把握直接执行，点下面的建议再执行/);
    assert.equal(tile("light.study_desk"), before);

    const chip = element("[data-suggestion-id]");
    assert.match(chip.textContent ?? "", /关闭书房台灯 · 55%/);
    chip.click();
    await setImmediate();
    await setImmediate();
    assert.equal(document.querySelector("[data-suggestion-id]"), null);
    assert.match(tile("light.study_desk"), /已关闭/);
  });
});

describe("Timers the PC slept through (#22)", () => {
  it("holds an overdue timer until 立即执行 is tapped", async () => {
    startDemo();
    const before = tile("light.study_desk");
    await command("10分钟后关闭书房台灯");
    assert.match(document.body.textContent ?? "", /已设定 10 分钟后执行「关闭书房台灯」/);
    const realNow = Date.now;
    Date.now = () => realNow() + 3 * 3600 * 1000;
    try {
      await new Promise((resolve) => setTimeout(resolve, 1_200));
      assert.match(document.body.textContent ?? "", /已错过定时：关闭书房台灯/);
      assert.equal(tile("light.study_desk"), before);
      await click("[data-run-missed]");
      await setImmediate();
      assert.match(tile("light.study_desk"), /已关闭/);
      assert.equal(document.querySelector("[data-run-missed]"), null);
    } finally {
      Date.now = realNow;
    }
  });
});

describe("全关 (#23)", () => {
  it("needs a hold in the classic skin and leaves the plug on", async () => {
    startDemo();
    const button = element("#btn-all-off");
    assert.match(button.textContent ?? "", /全关 \(3\)/);
    button.click();
    await setImmediate();
    assert.match(tile("light.living_ceiling"), /已开启/);

    button.dispatchEvent(new Event("pointerdown"));
    await new Promise((resolve) => setTimeout(resolve, 700));
    await setImmediate();
    assert.doesNotMatch(tile("light.living_ceiling"), /已开启/);
    assert.match(tile("plug.entry_socket"), /供电中/);
  });
});
