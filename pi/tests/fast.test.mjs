import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { stripTypeScriptTypes } from "node:module";
import { resolve } from "node:path";
import test from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";
import { zstdDecompressSync } from "node:zlib";

const source = stripTypeScriptTypes(readFileSync(new URL("../extensions/fast.ts", import.meta.url), "utf8"));
const { default: register } = await import(`data:text/javascript;base64,${Buffer.from(source).toString("base64")}`);

function model(provider = "openai-codex", id = "gpt-6-astra", api = "openai-codex-responses", baseUrl = "https://chatgpt.com/backend-api") {
  return { provider, id, api, baseUrl };
}

function fixture(selected = model()) {
  const handlers = new Map();
  const commands = new Map();
  const notices = [];
  const statuses = new Map();
  const ctx = {
    model: selected,
    hasUI: true,
    isIdle: () => true,
    ui: {
      notify: (text, level) => notices.push({ text, level }),
      setStatus: (key, value) => statuses.set(key, value),
    },
  };
  register({
    on: (name, handler) => handlers.set(name, handler),
    registerCommand: (name, command) => commands.set(name, command),
  });
  const emit = (name, event = {}) => handlers.get(name)?.(event, ctx);
  return {
    ctx, notices, statuses, emit,
    command: (args = "") => commands.get("fast").handler(args, ctx),
    complete: (prefix) => commands.get("fast").getArgumentCompletions(prefix),
    request: (payload = { model: ctx.model?.id, input: [], stream: true }) => emit("before_provider_request", { payload }),
    headers: (headers = {}) => { emit("before_provider_headers", { headers }); return headers; },
    select: (next) => { const previousModel = ctx.model; ctx.model = next; emit("model_select", { model: next, previousModel }); },
  };
}

const openaiModels = [
  "gpt-6-astra", "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5",
  "gpt-5.4", "gpt-5.4-mini", "gpt-5.3-codex", "gpt-5.2", "gpt-5.1", "gpt-5", "gpt-5-mini",
  "gpt-4.1", "gpt-4.1-mini", "gpt-4.1-nano", "gpt-4o", "gpt-4o-2024-05-13", "gpt-4o-mini", "o3", "o4-mini",
];

test("supported OpenAI API models use priority on Responses and Chat Completions", async () => {
  for (const api of ["openai-responses", "openai-completions"]) {
    for (const id of openaiModels) {
      const f = fixture(model("openai", id, api, "https://api.openai.com/v1"));
      await f.command("on");
      assert.equal(f.request().service_tier, "priority", `${api}/${id}`);
      assert.deepEqual(f.headers({ "x-existing": "keep" }), { "x-existing": "keep" });
    }
  }
});

test("current Codex fast models are supported without changing model or reasoning", async () => {
  for (const id of ["gpt-6-astra", "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5"]) {
    const selected = model("openai-codex", id);
    const f = fixture(selected);
    const payload = Object.freeze({ model: id, input: [], reasoning: { effort: "high" }, stream: true, type: "response.create" });
    assert.equal(f.request(payload), undefined);
    await f.command();
    assert.deepEqual(f.request(payload), { ...payload, service_tier: "priority" });
    assert.equal(f.ctx.model, selected);
    assert.match(f.statuses.get("fast"), /requested/);
    assert.match(f.notices.at(-1).text, /cost|quota|credit/i);
    await f.command();
    assert.deepEqual(f.request(payload), { ...payload, service_tier: "default" });
  }
});

test("Anthropic fast models are refused without replacing native beta headers", async () => {
  for (const id of ["claude-opus-5", "claude-opus-4-8"]) {
    const f = fixture(model("anthropic", id, "anthropic-messages", "https://api.anthropic.com"));
    await f.command("on");
    assert.equal(f.request({ model: id, messages: [], max_tokens: 64 }), undefined);
    assert.match(f.notices.at(-1).text, /header hook/i);
    const headers = { "anthropic-beta": "oauth-2025-04-20,interleaved-thinking-2025-05-14" };
    assert.deepEqual(f.headers({ ...headers }), headers);
  }
});

test("unknown models, third-party providers, wrong APIs, and Astra EU are rejected", async () => {
  const unsupported = [
    undefined,
    model("openai", "gpt-future", "openai-responses"),
    model("openai", "gpt-5.5-pro", "openai-responses"),
    model("openai", "gpt-5-nano", "openai-responses"),
    model("openai", "ft:gpt-4o:custom", "openai-responses"),
    model("openai", "gpt-6-astra", "openai-responses", "https://eu.api.openai.com/v1"),
    model("openai", "gpt-6-astra", "anthropic-messages"),
    model("openai-codex", "gpt-5.3-codex-spark"),
    model("openai-codex", "gpt-5.4"),
    model("openai-codex", "gpt-6-astra", "openai-responses"),
    model("openrouter", "gpt-6-astra", "openai-completions"),
    model("azure-openai-responses", "gpt-6-astra", "azure-openai-responses"),
    model("anthropic", "claude-opus-4-6", "anthropic-messages"),
    model("anthropic", "claude-opus-4-7", "anthropic-messages"),
    model("anthropic", "claude-sonnet-4-6", "anthropic-messages"),
    model("amazon-bedrock", "claude-opus-5", "bedrock-converse-stream"),
    model("google-vertex-anthropic", "claude-opus-5", "anthropic-messages"),
  ];
  for (const selected of unsupported) {
    const f = fixture();
    f.ctx.model = selected;
    await f.command("on");
    assert.equal(f.request(), undefined, JSON.stringify(selected));
    assert.equal(f.notices.at(-1).level, "warning");
    assert.match(f.notices.at(-1).text, /unsupported|not supported|no model/i);
    assert.deepEqual(f.headers(), {});
  }
});

test("status is read-only; on/off are idempotent; arguments and completions are bounded", async () => {
  const f = fixture();
  await f.command("status");
  assert.equal(f.request(), undefined);
  assert.match(f.notices.at(-1).text, /off.*defaults/i);
  for (const arg of ["on", "on", "  ON  "]) {
    await f.command(arg);
    assert.equal(f.request().service_tier, "priority");
  }
  await f.command("status");
  assert.equal(f.request().service_tier, "priority");
  for (const arg of ["true", "on extra", "toggle", "1", "x".repeat(1000)]) {
    await f.command(arg);
    assert.match(f.notices.at(-1).text, /usage/i);
    assert.equal(f.request().service_tier, "priority");
  }
  for (const arg of ["off", "off"]) {
    await f.command(arg);
    assert.equal(f.request({ model: "gpt-6-astra", service_tier: "fast" }).service_tier, "default");
  }
  assert.deepEqual(f.complete("o").map((item) => item.value), ["on", "off"]);
  assert.equal(f.complete("nope"), null);
});

test("model changes and session lifecycle reset opt-in without affecting other threads", async () => {
  const f = fixture();
  const other = fixture();
  await f.command("on");
  assert.equal(other.request(), undefined);
  f.select(model("openai-codex", "gpt-5.6-sol"));
  assert.equal(f.request(), undefined);
  assert.equal(f.statuses.get("fast"), undefined);
  assert.match(f.notices.at(-1).text, /reset/i);
  f.select(model());
  assert.equal(f.request(), undefined);
  for (const reason of ["startup", "reload", "new", "resume", "fork"]) {
    await f.command("on");
    f.emit("session_start", { reason });
    assert.equal(f.request(), undefined);
    assert.equal(f.statuses.get("fast"), undefined);
  }
  await f.command("on");
  f.emit("session_shutdown", { reason: "quit" });
  assert.equal(f.request(), undefined);
});

test("busy changes are refused without changing in-flight requests", async () => {
  const f = fixture();
  await f.command("on");
  f.ctx.isIdle = () => false;
  await f.command("off");
  assert.equal(f.request().service_tier, "priority");
  assert.match(f.notices.at(-1).text, /idle|finish/i);
  await f.command("status");
  assert.match(f.notices.at(-1).text, /requested/i);
});

test("only the opted-in model and endpoint are changed, including without model_select", async () => {
  const f = fixture();
  await f.command("on");
  assert.equal(f.request({ model: "gpt-5.6-sol", input: [] }), undefined);
  for (const change of [{ id: "gpt-5.6-sol" }, { provider: "openai" }, { api: "openai-responses" }, { baseUrl: "https://other.example" }]) {
    f.ctx.model = { ...model(), ...change };
    assert.equal(f.request(), undefined);
    assert.deepEqual(f.headers(), {});
  }
});

test("invalid payload boundaries are asserted; absent or mismatched model fields are untouched", async () => {
  const f = fixture();
  await f.command("on");
  for (const payload of [undefined, null, [], "text", true, 1, 1.5, NaN, Infinity]) {
    assert.throws(() => f.emit("before_provider_request", { payload }), /payload/i);
  }
  for (const payload of [{}, { model: undefined }, { model: null }, { model: 42 }]) {
    assert.equal(f.request(payload), undefined);
  }
});

test("headless command calls do not opt into paid mode or require UI", async () => {
  const f = fixture();
  f.ctx.hasUI = false;
  f.ctx.ui = undefined;
  await f.command("on");
  f.emit("session_start", { reason: "startup" });
  assert.equal(f.request(), undefined);
});

const runtimeSource = process.env.PI_FAST_RUNTIME_SOURCE;
test("installed Pi loads /fast and native providers serialize its tier without network access", { skip: !runtimeSource, timeout: 30000 }, async () => {
  const { loadExtensions } = await import(pathToFileURL(resolve(runtimeSource, "dist/core/extensions/loader.js")));
  const extensionPath = fileURLToPath(new URL("../extensions/fast.ts", import.meta.url));
  const loaded = await loadExtensions([extensionPath], process.cwd());
  assert.deepEqual(loaded.errors, []);
  assert.equal(loaded.extensions.length, 1);
  assert.ok(loaded.extensions[0].commands.has("fast"));

  for (const [provider, api] of [["openai", "openai-responses"], ["openai", "openai-completions"], ["openai-codex", "openai-codex-responses"]]) {
    const { stream } = await import(pathToFileURL(resolve(runtimeSource, `../pi-ai/dist/api/${api}.js`)));
    const selected = {
      ...model(provider, "gpt-6-astra", api, "https://example.invalid/v1"),
      name: "Test model", reasoning: true, input: ["text"],
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 200000, maxTokens: 4096,
    };
    const f = fixture(selected);
    const requests = [];
    const jwtPayload = Buffer.from(JSON.stringify({ "https://api.openai.com/auth": { chatgpt_account_id: "test-account" } })).toString("base64url");
    for (const action of ["status", "on", "off"]) {
      await f.command(action);
      const result = await stream(selected, { messages: [{ role: "user", content: "test", timestamp: 0 }] }, {
        apiKey: provider === "openai-codex" ? ["test", jwtPayload, "test"].join(".") : "test-key",
        maxRetries: 0, transport: "sse", timeoutMs: 1000,
        onPayload: (payload) => f.request(payload),
        fetch: async (_url, init) => {
          const headers = new Headers(init.headers);
          const body = headers.get("content-encoding") === "zstd" ? zstdDecompressSync(init.body).toString("utf8") : init.body;
          requests.push({ body: JSON.parse(body), headers });
          return new Response(JSON.stringify({ error: { type: "invalid_request_error", message: "mock endpoint" } }), {
            status: 400, headers: { "content-type": "application/json" },
          });
        },
      }).result();
      assert.equal(result.stopReason, "error", "mock deliberately stops after capturing the request");
      assert.equal(requests.length, ["status", "on", "off"].indexOf(action) + 1, result.errorMessage);
    }
    assert.equal(requests.length, 3, api);
    const [baseline, fast, standard] = requests;
    assert.equal(baseline.body.service_tier, undefined);
    assert.deepEqual(fast.body, { ...baseline.body, service_tier: "priority" }, api);
    assert.deepEqual(standard.body, { ...baseline.body, service_tier: "default" }, api);
    assert.equal(fast.headers.get("authorization"), baseline.headers.get("authorization"));
  }
});
