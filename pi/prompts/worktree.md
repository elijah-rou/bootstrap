---
description: Require worktree-based changes in current repo or a specified repo
argument-hint: "[repo]"
---
Use a git worktree for all subsequent file-changing work.

Target repo:
- If `$1` is provided, use repo/path `$1`.
- Otherwise use the git repo for the current working directory.

Rules:
1. Resolve the target repo root with `git -C <repo> rev-parse --show-toplevel`. If that fails, stop and report it.
2. Do not edit the primary checkout. Create or reuse a dedicated worktree for the task, then run all reads, writes, tests, and commits there.
3. If the primary checkout is dirty or worktree creation would be unsafe, stop and ask how to proceed.
4. Tell me the chosen repo root and worktree path before making changes.
5. Keep the task worktree until the branch/commit is merged into the upstream default branch (`origin/main` or `origin/master`) or otherwise confirmed present upstream. After that, remove it only after verifying it is clean and fully merged/reachable.
6. Only skip the worktree if I explicitly tell you to work in-place.

Treat this as a standing instruction for the rest of the session.
