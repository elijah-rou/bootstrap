import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const projectValidate = await readFile(new URL("../extensions/project-validate.ts", import.meta.url), "utf8");
const lspDiagnostics = await readFile(new URL("../extensions/lsp-diagnostics.ts", import.meta.url), "utf8");
const validate = await readFile(new URL("../../scripts/validate", import.meta.url), "utf8");

test("project validation is repository bounded with exhaustive outcomes", () => {
  assert.match(projectValidate, /git[\s\S]*rev-parse[\s\S]*--show-toplevel/);
  for (const outcome of ["passed", "failed", "timed_out", "cancelled", "execution_error", "unsupported"]) {
    assert.match(projectValidate, new RegExp(`"${outcome}"`));
  }
  assert.match(projectValidate, /terminationCause/);
  assert.match(projectValidate, /processSignal/);
});

test("LSP clean excludes skipped, unsupported, and failed work", () => {
  for (const outcome of ["clean", "diagnostics", "not_applicable", "unsupported", "failed", "timed_out", "cancelled"]) {
    assert.match(lspDiagnostics, new RegExp(`"${outcome}"`));
  }
  assert.match(lspDiagnostics, /serverFailures/);
  assert.match(lspDiagnostics, /grouped\.unsupported\.length > 0 \|\| grouped\.omitted\.length > 0 \? "unsupported"/);
  assert.match(lspDiagnostics, /grouped\.skipped\.length > 0 \? "not_applicable" : "clean"/);
});

test("repository validation discovers every Pi test", () => {
  assert.match(validate, /find pi\/tests -maxdepth 1 -type f -name '\*\.test\.mjs'/);
  assert.match(validate, /node --test "\$\{pi_tests\[@\]\}"/);
});
