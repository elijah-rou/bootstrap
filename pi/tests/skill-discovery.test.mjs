import assert from "node:assert/strict";
import { chmodSync, cpSync, existsSync, mkdirSync, mkdtempSync, readdirSync, rmSync, symlinkSync, unlinkSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
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

test("Pi and Codex configuration repair snapshot collisions through the Pi consumer", { skip: !runtime || !existsSync(runtime) }, async () => {
  const { loadSkills } = await import(pathToFileURL(runtime).href);
  const repository = fileURLToPath(new URL("../../", import.meta.url));
  for (const command of ["pi", "codex"]) {
    const home = mkdtempSync(join(tmpdir(), "skill-upgrade-"));
    try {
      const cache = join(home, ".local/share/bootstrap");
      const snapshot = join(cache, "snapshots", "a".repeat(40));
      cpSync(join(repository, "pi/skills"), join(snapshot, "pi/skills"), { recursive: true });
      writeFileSync(join(snapshot, "install.sh"), "#!/bin/sh\n");
      chmodSync(join(snapshot, "install.sh"), 0o755);
      writeFileSync(join(snapshot, ".bootstrap-archive-sha256"), "b".repeat(64) + "\n");
      const paths = [join(home, ".pi/agent/skills"), join(home, ".agents/skills")];
      for (const path of paths) mkdirSync(path, { recursive: true });
      const name = "blast-radius";
      for (const path of paths) symlinkSync(join(repository, "pi/skills", name), join(path, name), "dir");
      const staleAlias = join(paths[command === "pi" ? 1 : 0], name);
      unlinkSync(staleAlias);
      symlinkSync(join(snapshot, "pi/skills", name), staleAlias, "dir");
      const options = { cwd: home, agentDir: join(home, ".pi/agent"), includeDefaults: false, skillPaths: paths };
      assert.ok(loadSkills(options).diagnostics.some(diagnostic => diagnostic.type === "collision"));
      for (let attempt = 0; attempt < 2; attempt++) {
        const result = spawnSync("bash", [join(repository, "configure.sh"), command], {
          env: { ...process.env, HOME: home, CODEX_HOME: join(home, ".codex"),
            XDG_CONFIG_HOME: join(home, ".config"), XDG_STATE_HOME: join(home, ".local/state"),
            DOTFILES_BOOTSTRAP_ROOT: cache },
          encoding: "utf8", timeout: 30_000, maxBuffer: 1024 * 1024,
        });
        assert.equal(result.status, 0, `${result.error ?? ""}\n${result.stdout}\n${result.stderr}`);
        const { skills, diagnostics } = loadSkills(options);
        assert.deepEqual(diagnostics, []);
        assert.equal(skills.filter(skill => skill.name === name).length, 1);
      }
    } finally {
      rmSync(home, { recursive: true, force: true });
    }
  }
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
