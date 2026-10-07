# Catalog bumps

An outer loop on the Benny pattern (design slice 11): find a pinned download with a newer upstream release, move the pin, prove the install in a container, and open a pull request, or report why not. One name per run. It never merges.

## Trigger

A scheduled run on the always-on box, once the box exists (design O3), or by hand:

```sh
pi -p "Run the catalog-bumps automation in .agents/automations/catalog-bumps/AUTOMATION.md"
```

## Gates (stop and report, changing nothing)

- `gh auth status` fails, `docker info` fails, or the checkout is not a clean clone of this repository.
- `scripts/outdated` lists nothing: report "catalog current".
- For each candidate in its order, skip it if branch `agent/bump-<name>-<version>` already exists on the remote or an open pull request uses it (`gh pr list --head agent/bump-<name>-<version>`). Someone already owns that bump. If every candidate is owned, report that.

## Run

1. Take the first unowned candidate `NAME PINNED LATEST`.
2. Make a worktree from `origin/main` on branch `agent/bump-NAME-LATEST`. Work only there.
3. Run `scripts/pin NAME LATEST`. A failure (no digest for an asset, a renamed artifact) ends the run with a report; do not edit the catalog by hand.
4. Prove the install, keeping every output in a run directory under `local/`:
   - `bash -n install.sh` and `scripts/validate`;
   - `tests/container.sh debian:13 user <selection>`, where the selection installs NAME: nothing for a `core` row (core installs on every run), `--tools NAME` for a tools row, or the group flag for a language or LSP row, for example `--languages python` for uv. The row's groups column says which.
   - When the repository carries `.agents/skills/verify-bootstrap`, also run its download round trip with the same selection.
5. If every check passes, commit with the subject `Pin NAME LATEST` and a body naming the upstream release and the checks that passed. Push `agent/bump-NAME-LATEST` and open a pull request whose body has these sections: Why (the release), What changed (the catalog rows), Verification (each command and its result), Revert (revert the commit). Allowed from autonomy A2.
6. If any check fails, open no pull request. Report the failing command, its last lines of output, and the run directory; leave the branch local.

## Boundaries

- One name per run. Never merge, deploy, or release; landing follows the repository's autonomy level.
- Subagents may run checks, but they hold no publish credentials and never push, comment, or open pull requests. The policy gate enforces this.
- Fail closed: if a gate or check cannot be evaluated, stop and report.
- Do not post anywhere but the pull request. Messages to people go through the user.

## Report

Lead with what needs the user (a pull request to review, or a failure to look at), then the candidate list from `scripts/outdated`, the chosen name, each check with its result, and the pull request link or run directory.
