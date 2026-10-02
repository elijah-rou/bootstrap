import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, rmSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import test from "node:test";

const runtime = process.env.PI_SKILLS_TEST_RUNTIME_PATH;

test("repository skills parse and load through the installed Pi consumer", { skip: !runtime || !existsSync(runtime) }, async () => {
  const { loadSkillsFromDir } = await import(pathToFileURL(runtime).href);
  const dir = fileURLToPath(new URL("../skills", import.meta.url));
  const { skills, diagnostics } = loadSkillsFromDir({ dir, source: "test" });
  assert.deepEqual(diagnostics, []);
  const expected = readdirSync(dir).filter(name => existsSync(join(dir, name, "SKILL.md"))).sort();
  assert.deepEqual(skills.map(skill => skill.name).sort(), expected);
  assert.match(skills.find(skill => skill.name === "omarchy").description, /Excludes unrelated/);
});

test("Pi deduplicates the shared Codex skill links and retains manual invocation", { skip: !runtime || !existsSync(runtime) }, async () => {
  const { loadSkills } = await import(pathToFileURL(runtime).href);
  const root = mkdtempSync(join(tmpdir(), "shared-skills-"));
  try {
    const source = fileURLToPath(new URL("../skills", import.meta.url));
    const paths = [join(root, ".pi/agent/skills"), join(root, ".agents/skills")];
    const names = readdirSync(source).filter(name => existsSync(join(source, name, "SKILL.md"))).sort();
    for (const path of paths) {
      mkdirSync(path, { recursive: true });
      for (const name of names) symlinkSync(join(source, name), join(path, name), "dir");
    }
    const { skills, diagnostics } = loadSkills({ cwd: root, agentDir: join(root, ".pi/agent"), includeDefaults: false, skillPaths: paths });
    assert.deepEqual(diagnostics, []);
    assert.deepEqual(skills.map(skill => skill.name).sort(), names);
    assert.equal(skills.find(skill => skill.name === "design-control-loop").disableModelInvocation, true);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
