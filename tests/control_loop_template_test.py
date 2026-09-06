#!/usr/bin/env python3
"""Exercise the workflow template's real capture step in disposable repositories."""

import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = ROOT / "pi/skills/design-control-loop/references/workflow-template.yml"


def capture_script() -> str:
    text = TEMPLATE.read_text()
    step = text.split("      - name: Capture review artifact\n", 1)[1].split("\n      - name:", 1)[0]
    block = step.split("        run: |\n", 1)[1]
    return "\n".join(line[10:] if line.startswith("          ") else line for line in block.splitlines())


def exercise(selection: str | None, agent: str | None, expected: str,
             *, changed: bool = False, controller: str = "success",
             actuator: str = "success", validation: str = "success") -> None:
    with tempfile.TemporaryDirectory(prefix="control-loop-") as temporary:
        directory = Path(temporary)
        repo = directory / "repo"
        repo.mkdir()
        output = directory / "output"
        output.mkdir()
        env = {"PATH": os.environ["PATH"], "HOME": temporary,
               "GIT_CONFIG_NOSYSTEM": "1", "CONTROLLER_OUTCOME": controller,
               "ACTUATOR_OUTCOME": actuator, "VALIDATION_OUTCOME": validation}
        for arguments in (["init", "--quiet"], ["-c", "user.name=Fixture", "-c",
                          "user.email=fixture@example.invalid", "commit", "--quiet",
                          "--allow-empty", "-m", "Fixture"]):
            subprocess.run(["git", *arguments], cwd=repo, env=env, check=True,
                           capture_output=True, timeout=10)
        if selection is not None:
            (output / "controller-status.txt").write_text(selection + "\n")
        (output / "controller-output.md").write_text("Measured selection evidence.\n")
        if agent is not None:
            (output / "agent-status.txt").write_text(agent + "\n")
            (output / "agent-report.md").write_text("Actuator evidence.\n")
        if changed:
            (repo / "change.txt").write_text("Reviewable change.\n")
        script = capture_script().replace("/tmp/", str(output) + "/")
        result = subprocess.run(["bash", "-c", script], cwd=repo, env=env,
                                capture_output=True, text=True, timeout=10)
        assert (result.returncode == 0) == (expected in {"changed", "no-change"}), result.stdout + result.stderr
        assert (output / "loop-status.txt").read_text().strip() == expected
        assert (output / "agent-report.md").read_text().strip()
        assert bool((output / "agent.patch").stat().st_size) == changed
        assert re.fullmatch(r"[0-9a-f]{40,64}", (output / "base-sha.txt").read_text().strip())
        staged = subprocess.run(["git", "diff", "--cached", "--quiet"], cwd=repo,
                                env=env, timeout=10)
        assert staged.returncode == 0

def test_converged_selection_is_successful_without_actuator() -> None:
    exercise("no-change", None, "no-change", actuator="skipped", validation="skipped")

def test_validated_change_is_publishable() -> None:
    exercise("selected", "changed", "changed", changed=True)

def test_validated_actuator_no_change_is_successful() -> None:
    exercise("selected", "no-change", "no-change")

def test_blocked_selection_retains_evidence() -> None:
    exercise("blocked", None, "blocked", actuator="skipped", validation="skipped")

def test_blocked_actuator_retains_partial_patch() -> None:
    exercise("selected", "blocked", "blocked", changed=True, validation="skipped")

def test_execution_and_validation_failures_cannot_publish() -> None:
    for overrides in ({"controller": "failure"}, {"actuator": "failure"},
                      {"validation": "failure"}, {"actuator": "cancelled"}):
        exercise("selected", "changed", "failed", changed=True, **overrides)

def test_inconsistent_or_missing_outcomes_fail() -> None:
    for selection, agent, changed in [(None, None, False),
                                       ("", None, False),
                                       ("unknown", None, False),
                                       ("no-change\nselected", None, False),
                                       ("selected", None, False),
                                       ("selected", "", False),
                                       ("selected", "unknown", False),
                                       ("selected", "changed", False),
                                       ("selected", "no-change", True),
                                       ("no-change", None, True)]:
        exercise(selection, agent, "failed", changed=changed)

def test_evidence_upload_runs_after_failure() -> None:
    step = TEMPLATE.read_text().split("      - name: Upload patch and evidence\n", 1)[1]
    assert re.search(r"(?m)^        if:.*always\(\)", step)
    assert "/tmp/loop-status.txt" in step


if __name__ == "__main__":
    for case in (test_converged_selection_is_successful_without_actuator,
                 test_validated_change_is_publishable,
                 test_validated_actuator_no_change_is_successful,
                 test_blocked_selection_retains_evidence,
                 test_blocked_actuator_retains_partial_patch,
                 test_execution_and_validation_failures_cannot_publish,
                 test_inconsistent_or_missing_outcomes_fail,
                 test_evidence_upload_runs_after_failure):
        case()
        print(f"PASS {case.__name__}")
