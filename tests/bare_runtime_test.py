#!/usr/bin/env python3
"""Opt-in smoke test: dev-shell python3 tests/bare_runtime_test.py c rust python typescript bash.

Uses temporary source files, local compilers and LSP initialization. No provider
requests, authentication inspection, package installation or service startup.
"""

import argparse
import json
import os
from pathlib import Path
import select
import shutil
import signal
import subprocess
import tempfile
import time


def run(arguments, directory):
    result = subprocess.run(arguments, cwd=directory, capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, (arguments, result.stdout, result.stderr)
    return result.stdout.strip()


def initialize_server(arguments):
    request = json.dumps({
        "jsonrpc": "2.0", "id": 1, "method": "initialize",
        "params": {"processId": None, "rootUri": None, "capabilities": {}},
    }).encode()
    process = subprocess.Popen(arguments, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, start_new_session=True)
    try:
        assert process.stdin is not None and process.stdout is not None
        process.stdin.write(f"Content-Length: {len(request)}\r\n\r\n".encode() + request)
        process.stdin.flush()
        pending = b""
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            readable, _, _ = select.select([process.stdout], [], [], max(0, deadline - time.monotonic()))
            assert readable, (arguments, "initialize timed out")
            chunk = os.read(process.stdout.fileno(), 65536)
            assert chunk, (arguments, "server closed before initialize response")
            pending += chunk
            assert len(pending) < 1_000_000, (arguments, "unexpected LSP output size")
            while b"\r\n\r\n" in pending:
                header, body = pending.split(b"\r\n\r\n", 1)
                lengths = [int(line.split(b":", 1)[1]) for line in header.split(b"\r\n") if line.lower().startswith(b"content-length:")]
                assert len(lengths) == 1, header
                length = lengths[0]
                assert 0 < length < 1_000_000, length
                if len(body) < length:
                    break
                message = json.loads(body[:length])
                pending = body[length:]
                if message.get("id") == 1:
                    assert "capabilities" in message.get("result", {}), message
                    return
        raise AssertionError((arguments, "initialize timed out"))
    finally:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=5)
        if process.stdin is not None:
            process.stdin.close()
        if process.stdout is not None:
            process.stdout.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('languages', nargs='*', choices=['c', 'rust', 'python', 'typescript', 'bash'])
    parser.add_argument('--codex', action='store_true', help='also check the optional Codex CLI')
    args = parser.parse_args()
    bare_root = Path(os.environ.get("DOTFILES_BARE_ROOT", str(Path.home() / ".local/share/dotfiles/bare")))
    assert Path(os.environ.get("CONDA_PREFIX", "/missing")).resolve() == (bare_root / "env").resolve(), "Run this test through dev-shell"
    servers = {
        "python": ["basedpyright-langserver", "--stdio"],
        "typescript": ["typescript-language-server", "--stdio"],
        "rust": ["rustup", "run", "stable", "rust-analyzer"],
        "bash": ["bash-language-server", "start"],
    }
    with tempfile.TemporaryDirectory(prefix="bare-dev-smoke-") as temporary:
        directory = Path(temporary)
        for language in dict.fromkeys(args.languages):
            match language:
                case "c":
                    (directory / "sample.c").write_text('int main(void) { return 0; }\n')
                    compiler = os.environ.get("CC", "cc")
                    executable = shutil.which(compiler)
                    assert executable and executable.startswith(os.environ["CONDA_PREFIX"] + "/bin/"), executable
                    run([compiler, "sample.c", "-o", "sample-c"], directory)
                    run([str(directory / "sample-c")], directory)
                case "rust":
                    (directory / "sample.rs").write_text('fn main() { println!("rust-ok"); }\n')
                    run(["rustc", "sample.rs", "-o", "sample-rust"], directory)
                    assert run([str(directory / "sample-rust")], directory) == "rust-ok"
                case "typescript":
                    (directory / "sample.ts").write_text('const value: number = 42;\n')
                    run(["tsc", "--noEmit", "sample.ts"], directory)
                case "python":
                    run(["python3", "-c", "import sys; assert sys.version_info[:2] == (3, 13)"], directory)
                case "bash":
                    (directory / "sample.sh").write_text('#!/bin/sh\nprintf "%s\\n" shell-ok\n')
                    run(["shellcheck", "sample.sh"], directory)
                case _:
                    raise AssertionError(f"Unhandled language: {language}")
            print("PASS language check:", language)
            if language in servers:
                initialize_server(servers[language])
                print("PASS LSP initialize:", language)
        commands = [["pi", "--version"], ["herdr", "--version"]]
        if args.codex:
            commands.append(["codex", "--version"])
        for command in commands:
            print(run(command, directory))
    print("PASS selected language checks and agent CLI startup")


if __name__ == "__main__":
    main()
