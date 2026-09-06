import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { stripTypeScriptTypes } from "node:module";
import vm from "node:vm";
import test from "node:test";
import { execFile as execFileReal } from "node:child_process";

const source = stripTypeScriptTypes(readFileSync(new URL("../extensions/notify.ts", import.meta.url), "utf8"))
  .replace("export default function", "function register");
const context = { mode: "tui", hasUI: true, cwd: "/repo/project", sessionManager: { getSessionFile: () => undefined }, ui: { notify() {} } };

function fixture(env = {}, platform = "linux") {
  const handlers = new Map();
  const calls = [];
  const register = vm.runInNewContext(`${source}\nregister;`, {
    require: () => ({ execFile: (file, args, options, callback) => {
      const call = { file, args, options, callback, killed: [] };
      calls.push(call);
      return { stdin: { end() { call.stdinClosed = true; } }, kill: signal => { call.killed.push(signal); return true; } };
    } }),
    Buffer,
    process: { platform, env, stdout: { write: text => calls.push({ file: "stdout", args: [text] }) } },
  });
  register({ on: (name, handler) => handlers.set(name, handler) });
  const emit = (name, event = {}, ctx = context) => handlers.get(name)?.(event, ctx);
  return { calls, emit, complete(text, ctx = context) {
    emit("agent_end", { messages: [{ role: "assistant", content: text }] }, ctx);
    return emit("agent_settled", {}, ctx);
  } };
}

test("completion summarizes the turn without awaiting inference or notifying before settlement", () => {
  const f = fixture();
  const text = "Investigation details. ".repeat(30) + "Blocked: missing credentials.";
  assert.equal(f.emit("agent_end", { messages: [{ role: "assistant", content: text }] }), undefined);
  assert.equal(f.calls.length, 0);
  assert.equal(f.emit("agent_settled"), undefined);
  assert.equal(f.calls[0].file, "pi");
  assert.match(f.calls[0].args.at(-1), /Blocked: missing credentials/);
  for (const flag of ["--no-tools", "--no-extensions", "--no-context-files", "--no-session"]) assert.ok(f.calls[0].args.includes(flag));
  assert.equal(f.calls[0].options.timeout, 10000);
  assert.equal(f.calls[0].stdinClosed, true);
  f.calls[0].callback(null, "**Blocked:** missing credentials.", "");
  assert.equal(f.calls[1].file, "notify-send");
  assert.deepEqual(Array.from(f.calls[1].args), ["Pi: project", "Blocked: missing credentials."]);
});

test("RPC, print, JSON and child sessions never spawn inference or notifications", () => {
  for (const [env, mode] of [[{}, "rpc"], [{}, "print"], [{}, "json"], [{ PI_SUBAGENT_CHILD: "1" }, "tui"]]) {
    const f = fixture(env);
    f.complete("Done", { ...context, mode, hasUI: mode === "rpc" || mode === "tui" });
    assert.equal(f.calls.length, 0);
  }
});

test("summary failures and empty output fall back to final text", () => {
  for (const error of [null, new Error("timeout")]) {
    const f = fixture();
    f.complete("**Fixed** the parser.");
    assert.equal(f.calls[0].file, "pi");
    f.calls[0].callback(error, "", "");
    assert.equal(f.calls[1].args[1], "Fixed the parser.");
  }
  const f = fixture();
  f.emit("agent_end", { messages: [] }); f.emit("agent_settled");
  assert.equal(f.calls[0].file, "notify-send");
  assert.equal(f.calls[0].args[1], "Ready for input");
});

test("one summary runs at a time and only the latest queued turn is retained", () => {
  const f = fixture();
  f.complete("first"); f.complete("second"); f.complete("third");
  f.emit("agent_settled");
  assert.equal(f.calls.length, 1);
  f.calls[0].callback(null, "stale first", "");
  assert.equal(f.calls.length, 2);
  assert.equal(f.calls[1].file, "pi");
  assert.match(f.calls[1].args.at(-1), /third/);
  assert.doesNotMatch(f.calls[1].args.at(-1), /second/);
  f.calls[1].callback(null, "latest third", "");
  assert.equal(f.calls[2].args[1], "latest third");
});

test("a new agent run suppresses stale summaries and shutdown cancels pending work", () => {
  const f = fixture();
  f.complete("old"); f.emit("agent_start");
  f.calls[0].callback(null, "stale", "");
  assert.equal(f.calls.length, 1);
  f.complete("new"); f.complete("queued");
  f.emit("session_shutdown"); f.emit("session_shutdown");
  assert.deepEqual(f.calls[1].killed, ["SIGKILL"]);
  f.calls[1].callback(new Error("killed"), "", "");
  assert.equal(f.calls.length, 2);
});

test("Windows notification data is encoded outside PowerShell syntax", () => {
  for (const body of ["It's done", "It’s done", "x’)); Start-Process calc; Write-Output ((‘x", "Unicode 😀"]) {
    const f = fixture({ WT_SESSION: "test" }, "win32");
    f.complete("done");
    f.calls[0].callback(null, body, "");
    assert.equal(f.calls[1].file, "powershell.exe");
    const script = f.calls[1].args.at(-1);
    const values = [...script.matchAll(/FromBase64String\('([A-Za-z0-9+/=]*)'\)/g)].map(match => Buffer.from(match[1], "base64").toString("utf8"));
    assert.deepEqual(values, ["Pi: project", body]);
    assert.doesNotMatch(script, /Start-Process|[‘’]/);
  }
});

test("late desktop failures cannot write terminal output after shutdown or a new turn", () => {
  for (const event of ["session_shutdown", "agent_start"]) {
    const f = fixture();
    f.complete("Done");
    f.calls[0].callback(null, "Summary", "");
    f.emit(event);
    f.calls[1].callback(new Error("notification failed"), "", "");
    assert.equal(f.calls.length, 2);
  }
});

test("summary subprocess receives EOF and completes instead of waiting for timeout", async () => {
  const handlers = new Map();
  const delivered = new Promise(resolve => {
    const register = vm.runInNewContext(`${source}\nregister;`, {
      Buffer,
      require: () => ({ execFile(file, args, options, callback) {
        if (file === "pi") return execFileReal(process.execPath, ["-e", 'process.stdin.resume(); process.stdin.on("end", () => process.stdout.write("Summary after EOF"));'], { ...options, timeout: 1000 }, callback);
        resolve(args[1]);
        return { kill() { return true; } };
      } }),
      process: { platform: "linux", env: {}, stdout: { write() {} } },
    });
    register({ on(name, handler) { handlers.set(name, handler); } });
    handlers.get("agent_end")({ messages: [{ role: "assistant", content: "fallback" }] }, context);
    handlers.get("agent_settled")({}, context);
  });
  assert.equal(await delivered, "Summary after EOF");
});

test("summary input is bounded and only recent conversation is included", () => {
  const f = fixture();
  f.emit("agent_end", { messages: [
    { role: "user", content: "old excluded context" },
    ...Array.from({ length: 8 }, () => ({ role: "assistant", content: "x".repeat(100000) })),
  ] });
  f.emit("agent_settled");
  assert.equal(f.calls[0].file, "pi");
  assert.ok(f.calls[0].args.at(-1).length < 17000);
  assert.doesNotMatch(f.calls[0].args.at(-1), /old excluded context/);
});
