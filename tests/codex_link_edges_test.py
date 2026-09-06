#!/usr/bin/env python3
"""Regression checks for installer isolation, profiles, and ownership."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def checkout_fixture(directory: Path) -> Path:
    directory.mkdir()
    _ = shutil.copyfile(ROOT / "install.sh", directory / "install.sh")
    tracked = subprocess.check_output(["git", "-C", str(ROOT), "ls-files", "-z"]).decode().split("\0")
    names = {Path(path).parts[0] for path in tracked if path}
    assert "local" not in names, "machine-local configuration must not be tracked"
    for name in names - {"install.sh"}:
        (directory / name).symlink_to(ROOT / name, target_is_directory=(ROOT / name).is_dir())
    (directory / "local").mkdir()
    return directory


def environment(home: Path) -> dict[str, str]:
    home.mkdir()
    return {
        "PATH": os.environ["PATH"],
        "HOME": str(home),
        "CODEX_HOME": str(home / "profile"),
        "XDG_CONFIG_HOME": str(home / ".config"),
        "XDG_DATA_HOME": str(home / ".local/share"),
        "XDG_STATE_HOME": str(home / ".local/state"),
        "DOTFILES_SKIP_LOCAL_ENV": "1",
    }


def run(checkout: Path, env: dict[str, str], *arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["bash", str(checkout / "install.sh"), *arguments],
                          cwd=checkout, env=env, capture_output=True, text=True, timeout=30)


def duplicate_custom_skills(root: Path) -> None:
    checkout = checkout_fixture(root / "checkout")
    for custom_root in ("legacy", "shared"):
        env = environment(root / custom_root)
        result = run(checkout, env, "codex-link")
        assert result.returncode == 0, result.stderr
        shared = Path(env["HOME"]) / ".agents/skills/how"
        legacy = Path(env["CODEX_HOME"]) / "skills/how"
        if custom_root == "legacy":
            custom, managed = legacy, shared
        else:
            shared.unlink()
            custom, managed = shared, legacy
            legacy.parent.mkdir(parents=True, exist_ok=True)
            legacy.symlink_to(checkout / "pi/skills/how", target_is_directory=True)
        custom.mkdir(parents=True)
        _ = (custom / "SKILL.md").write_text("custom skill\n")
        target = managed.readlink()
        result = run(checkout, env, "codex-link")
        assert result.returncode != 0, f"ambiguous {custom_root} custom skill reported success"
        assert "Ambiguous Codex skill" in result.stdout + result.stderr
        assert (custom / "SKILL.md").read_text() == "custom skill\n"
        assert managed.readlink() == target, "a shared/profile-owned counterpart was silently removed"
    return None


def partial_failure_retry(root: Path) -> None:
    checkout = checkout_fixture(root / "checkout")
    env = environment(root / "home")
    env["DOTFILES_SOURCE_ONLY"] = "1"
    script = '''set -e
source "$1"
ln() {
    local target
    for target; do :; done
    [[ "$target" != "$CODEX_HOME/native-tools.md" ]] || return 91
    command ln "$@"
}
if link_codex_assets; then exit 92; fi
[[ -L "$CODEX_HOME/AGENTS.md" ]]
[[ ! -e "$CODEX_HOME/native-tools.md" ]]
unset -f ln
link_codex_assets
[[ -L "$CODEX_HOME/native-tools.md" ]]
[[ -L "$HOME/.agents/skills/how" ]]
'''
    result = subprocess.run(["bash", "-c", script, "_", str(checkout / "install.sh")],
                            cwd=checkout, env=env, capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, result.stdout + result.stderr
    return None


failures = 0
for case in (duplicate_custom_skills, partial_failure_retry):
    with tempfile.TemporaryDirectory(prefix="codex-link-edge-") as temporary:
        try:
            case(Path(temporary))
            print(f"PASS {case.__name__}")
        except AssertionError as error:
            failures += 1
            print(f"FAIL {case.__name__}: {error}")
raise SystemExit(1 if failures else 0)
