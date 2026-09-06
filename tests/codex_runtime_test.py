#!/usr/bin/env python3
"""Exercise native Codex discovery in a disposable, unauthenticated home."""

import json
import os
from pathlib import Path
import selectors
import shutil
import signal
import subprocess
import tempfile
import time
from typing import TypeAlias, TypedDict, cast

ROOT = Path(__file__).resolve().parents[1]
CODEX = shutil.which("codex")
assert CODEX, "codex must be installed for the runtime check"


JsonValue: TypeAlias = str | int | float | bool | None | list["JsonValue"] | dict[str, "JsonValue"]
JsonObject: TypeAlias = dict[str, JsonValue]
Skill = TypedDict("Skill", {"name": str, "path": str, "enabled": bool})


def request(process: subprocess.Popen[bytes], selector: selectors.BaseSelector,
            message: JsonObject, pending: bytes) -> tuple[JsonObject, bytes]:
    assert process.stdin is not None
    assert process.stdout is not None
    _ = process.stdin.write(json.dumps(message).encode() + b"\n")
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        while b"\n" in pending:
            line, _, pending = pending.partition(b"\n")
            response = cast(JsonValue, json.loads(line))
            assert isinstance(response, dict), "JSON-RPC response must be an object"
            if response.get("id") == message["id"]:
                assert "error" not in response, response
                result = response["result"]
                assert isinstance(result, dict), "requested method must return an object"
                return result, pending
        ready = selector.select(max(0, deadline - time.monotonic()))
        assert ready, f"Codex timed out handling {message['method']}"
        chunk = os.read(process.stdout.fileno(), 65536)
        assert chunk, f"Codex exited handling {message['method']}"
        pending += chunk
        assert len(pending) <= 2 * 1024 * 1024, "Codex response exceeds test bound"
    raise AssertionError(f"Codex timed out handling {message['method']}")


def skills_from_result(result: JsonObject) -> list[Skill]:
    data = result["data"]
    assert isinstance(data, list)
    assert len(data) == 1
    entry = data[0]
    assert isinstance(entry, dict)
    assert entry["errors"] == []
    rows = entry["skills"]
    assert isinstance(rows, list)
    skills: list[Skill] = []
    for row in rows:
        assert isinstance(row, dict)
        name, path, enabled = row["name"], row["path"], row["enabled"]
        assert isinstance(name, str)
        assert isinstance(path, str)
        assert isinstance(enabled, bool)
        skills.append({"name": name, "path": path, "enabled": enabled})
    return skills


with tempfile.TemporaryDirectory(prefix="codex-port-") as temporary:
    home = Path(temporary)
    cwd = home / "project"
    cwd.mkdir()
    environment = {
        "PATH": os.environ["PATH"],
        "HOME": str(home),
        "CODEX_HOME": str(home / ".codex"),
        "XDG_CONFIG_HOME": str(home / ".config"),
        "XDG_CACHE_HOME": str(home / ".cache"),
        "XDG_DATA_HOME": str(home / ".local/share"),
        "LANG": "C.UTF-8",
        "TERM": "dumb",
        "DOTFILES_SKIP_LOCAL_ENV": "1",
    }
    _ = subprocess.run(["bash", str(ROOT / "install.sh"), "codex-link"],
                   env=environment, check=True, timeout=20)
    expected = (ROOT / "codex/skills.txt").read_text().splitlines()
    _ = shutil.copyfile(ROOT / "codex/config.toml", home / ".codex/config.toml")
    with (home / "server.stderr").open("wb") as errors:
        process = subprocess.Popen([CODEX, "-c", 'model="gpt-5.6-sol"',
                                    "app-server", "--strict-config", "--stdio"], cwd=cwd,
                                   env=environment, stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=errors,
                                   bufsize=0, start_new_session=True)
        try:
            assert process.stdin is not None
            assert process.stdout is not None
            with selectors.DefaultSelector() as selector:
                _ = selector.register(process.stdout, selectors.EVENT_READ)
                _, pending = request(process, selector, {
                    "id": 1, "method": "initialize",
                    "params": {"clientInfo": {"name": "dotfiles_validation", "version": "1"}},
                }, b"")
                _ = process.stdin.write(b'{"method":"initialized"}\n')
                account, pending = request(process, selector, {
                    "id": 2, "method": "account/read", "params": {"refreshToken": False},
                }, pending)
                assert account["account"] is None, "runtime fixture unexpectedly has an authenticated account"
                configuration, pending = request(process, selector, {
                    "id": 5, "method": "config/read", "params": {"includeLayers": False},
                }, pending)
                config = configuration["config"]
                assert isinstance(config, dict)
                agents = config["agents"]
                assert isinstance(agents, dict)
                assert agents["default_subagent_model"] == "gpt-6-astra"
                assert agents["default_subagent_reasoning_effort"] == "low"
                assert config["model"] == "gpt-5.6-sol", "child defaults changed the parent model"
                assert config["model_reasoning_effort"] == "high", "child defaults changed parent effort"
                print("PASS native Codex resolves Astra low child defaults independently of the Sol high parent")
                result, pending = request(process, selector, {
                    "id": 3, "method": "skills/list",
                    "params": {"cwds": [str(cwd)], "forceReload": True},
                }, pending)
                skills = skills_from_result(result)
                for name in expected:
                    matches = [skill for skill in skills if skill["name"] == name]
                    assert len(matches) == 1, (name, matches)
                    assert matches[0]["enabled"], matches[0]
                    assert Path(matches[0]["path"]).resolve() == ROOT / "pi/skills" / name / "SKILL.md"
                print(f"PASS native Codex discovers {len(expected)} exported skills without duplicates or errors")
                custom = home / ".codex/skills/how"
                custom.mkdir(parents=True)
                custom_text = "---\nname: how\ndescription: Custom legacy discovery fixture.\n---\nFixture only.\n"
                _ = (custom / "SKILL.md").write_text(custom_text)
                duplicate, _ = request(process, selector, {
                    "id": 4, "method": "skills/list",
                    "params": {"cwds": [str(cwd)], "forceReload": True},
                }, pending)
                choices = [skill for skill in skills_from_result(duplicate) if skill["name"] == "how"]
                assert len(choices) == 2, "native same-name behavior changed; review conflict policy"
                conflict = subprocess.run(["bash", str(ROOT / "install.sh"), "codex-link"],
                                          env=environment, capture_output=True, text=True, timeout=20)
                assert conflict.returncode != 0
                assert "Ambiguous Codex skill" in conflict.stdout + conflict.stderr
                assert (custom / "SKILL.md").read_text() == custom_text
                assert (home / ".agents/skills/how").resolve() == ROOT / "pi/skills/how"
                shutil.rmtree(custom)
                print("PASS native duplicate definitions cause an explicit linking conflict without replacing either skill")
        finally:
            if process.stdin is not None:
                process.stdin.close()
            try:
                _ = process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    _ = process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    _ = process.wait(timeout=3)
            if process.stdout is not None:
                process.stdout.close()

    rendered = subprocess.run([CODEX, "debug", "prompt-input", "Inspect discovery only."],
                              cwd=cwd, env=environment, capture_output=True,
                              text=True, check=True, timeout=30)
    messages = cast(JsonValue, json.loads(rendered.stdout))
    text = json.dumps(messages, ensure_ascii=False)
    instructions = json.dumps((ROOT / "codex/AGENTS.md").read_text().strip(), ensure_ascii=False)[1:-1]
    assert instructions in text, "Codex global instructions were not fully loaded"
    assert "Then invoke the `pi-subagents` skill" not in text
    assert "feature-shaping" in text, "automatic skills missing from prompt"
    assert "design-control-loop" not in text, "manual-only skill leaked into implicit guidance"
    print("PASS native Codex loads its instructions and excludes the manual-only skill from implicit guidance")
