import { mkdtempSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { pathToFileURL } from "node:url";
import { join } from "node:path";
import { after } from "node:test";

export async function loadExtension(name) {
  const root = mkdtempSync(join(tmpdir(), "pi-extension-test-"));
  after(() => rmSync(root, { recursive: true, force: true }));
  const bashRuntime = name === "project-validate"
    ? process.env.PI_BASH_OPERATIONS_TEST_RUNTIME_PATH
      ? pathToFileURL(process.env.PI_BASH_OPERATIONS_TEST_RUNTIME_PATH).href
      : import.meta.resolve("@earendil-works/pi-coding-agent")
    : undefined;
  const source = readFileSync(new URL(`../extensions/${name}.ts`, import.meta.url), "utf8")
    .replace('from "@earendil-works/pi-coding-agent"', `from ${JSON.stringify(bashRuntime)}`)
    .replace(/import \{ Type \} from "(?:@mariozechner\/pi-ai|typebox)";/, "const Type = { Object: () => ({}), Optional: x => x, Array: () => ({}), String: () => ({}), Number: () => ({}), Integer: () => ({}), Union: () => ({}), Literal: () => ({}), Boolean: () => ({}) };");
  writeFileSync(join(root, `${name}.ts`), source);
  writeFileSync(join(root, "verification-receipt.ts"), readFileSync(new URL("../extensions/verification-receipt.ts", import.meta.url)));
  const { default: register } = await import(join(root, `${name}.ts`));
  return function createTools(api = {}) {
    const tools = new Map();
    register({ on() {}, ...api, registerTool(tool) { tools.set(tool.name, tool); } });
    return tools;
  };
}
