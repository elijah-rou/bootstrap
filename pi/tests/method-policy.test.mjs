import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const agents = await readFile(new URL("../AGENTS.md", import.meta.url), "utf8");
const research = await readFile(new URL("../skills/source-grounded-research/SKILL.md", import.meta.url), "utf8");
const verification = await readFile(new URL("../skills/verification/SKILL.md", import.meta.url), "utf8");

test("research stops on supported facts or explicit gaps", () => {
  assert.match(research, /one bounded question[^\n]*evidence requirement/i);
  assert.match(research, /prefer[^\n]*specifications[^\n]*official documentation/i);
  assert.match(research, /exact passage/i);
  assert.match(research, /conflicting sources/i);
  assert.match(research, /Stop when every required fact has primary support or an explicit unresolved gap/i);
});

test("verification keeps parent authority and problem-first ordering", () => {
  assert.match(verification, /root parent independently runs and inspects/i);
  assert.match(verification, /checked child evidence[^\n]*not runtime proof/i);
  assert.match(verification, /inventory existing coverage before production edits/i);
  assert.match(verification, /observe RED[^\n]*GREEN/i);
  assert.match(verification, /Implementation-first work is a regression check/i);
  assert.match(verification, /no check or journey reproduces[^\n]*without speculative production changes/i);
});

test("deterministic boundary policy explicitly covers undefined", () => {
  for (const boundary of ["limits", "one step outside", "absent input", "explicit `undefined`", "`null`", "non-finite", "fractional", "wrong primitive types"]) assert.match(verification, new RegExp(boundary.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "i"));
  assert.match(agents, /Every retained row requires executable evidence/i);
  assert.match(agents, /reviewer prose cannot discharge it/i);
  assert.match(agents, /Adequately covered behavior-preserving refactors add no tests/i);
  assert.match(agents, /changed expectation requires an independently established contract change/i);
});
