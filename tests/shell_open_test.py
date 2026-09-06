#!/usr/bin/env python3
"""Exercise the installed opener through both shell startup files."""
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run_case(shell, mode):
    with tempfile.TemporaryDirectory(prefix="dotfiles-open-") as temporary:
        root = Path(temporary)
        home, binaries = root / "home with spaces", root / "bin"
        home.mkdir()
        binaries.mkdir()
        for command in ("readlink", "dirname"):
            executable = shutil.which(command)
            assert executable, f"{command} is required"
            (binaries / command).symlink_to(executable)
        if mode != "missing":
            opener = binaries / ("xdg-open" if mode == "xdg" else "gio")
            opener.write_text("#!/bin/sh\nprintf 'ARG=%s\\n' \"$@\"\nprintf 'DISPLAY=%s WAYLAND=%s EXTRA=%s\\n' \"$DISPLAY\" \"$WAYLAND_DISPLAY\" \"$EXTRA\"\nexit 7\n")
            opener.chmod(0o755)
        manager = binaries / "systemctl"
        manager.write_text("#!/bin/sh\nprintf '%s\\n' 'DISPLAY=:9' 'WAYLAND_DISPLAY=wayland-9' 'EXTRA=must-not-export'\n")
        manager.chmod(0o755)
        env = {"HOME": str(home), "PATH": str(binaries), "TERM": "xterm"}
        if mode == "existing":
            env.update(DISPLAY=":2", WAYLAND_DISPLAY="wayland-2")
        rc = "bashrc" if Path(shell).name == "bash" else "zshrc"
        source = home / f".{rc}"
        source.symlink_to(ROOT / rc)
        script = '''
OSTYPE="$1"
open() { printf 'native\\n'; }
source "$2" >/dev/null
# Host Homebrew startup can prepend its tools; exercise only fixture openers.
PATH="$3"
open 'file with spaces' 'https://example.invalid/a?b=c'
result=$?
printf 'STATUS=%s AFTER=%s/%s\\n' "$result" "$DISPLAY" "$WAYLAND_DISPLAY"
'''
        result = subprocess.run([shell, "-c", script, "_", "darwin24" if mode == "macos" else "linux-gnu", str(source), str(binaries)],
                                env=env, text=True, capture_output=True, timeout=15)
        assert result.returncode == 0, result.stderr
        output = result.stdout
        context = f"{Path(shell).name}/{mode}: {output} STDERR={result.stderr}"
        if mode == "macos":
            assert output == "native\nSTATUS=0 AFTER=/\n", context
        elif mode == "missing":
            assert output == "STATUS=127 AFTER=/\n", context
            assert "no desktop opener found" in result.stderr
        else:
            assert "ARG=file with spaces\nARG=https://example.invalid/a?b=c\n" in output, context
            assert "STATUS=7" in output and "EXTRA=\n" in output, context
            if mode == "existing":
                assert "DISPLAY=:2 WAYLAND=wayland-2" in output and "AFTER=:2/wayland-2" in output, context
            elif mode == "detached":
                assert "DISPLAY=:9 WAYLAND=wayland-9" in output and "AFTER=/" in output, context
            else:
                assert "ARG=open" not in output and "DISPLAY= WAYLAND=" in output, context


for name in ("bash", "zsh"):
    shell = shutil.which(name)
    assert shell, f"{name} is required"
    for mode in ("existing", "detached", "xdg", "missing", "macos"):
        run_case(shell, mode)
print("PASS Bash/Zsh opener forwarding, fallback, environment isolation, and macOS preservation")
