# agent-kit pin

Moves bootstrap's agent-kit pin to a commit on agent-kit's main and opens the pull request, or reports that the pin is current. `scripts/pin-agent-kit` does every step; this file says when to run it and what it leaves to others. It never merges.

## Trigger

An agent-kit landing run (the `ship` or `autopilot-full` mode in agent-kit), after each pull request it merges, with that merge's commit. By hand, from a clone of this repository:

```sh
scripts/pin-agent-kit --dry-run          # preview against agent-kit's current main
scripts/pin-agent-kit                    # pin agent-kit's current main
scripts/pin-agent-kit <40-hex commit>    # pin a given commit on agent-kit's main
```

## Gates (the script checks these and changes nothing)

- The commit is not a full 40-character hex commit reachable from agent-kit's main: exit 2.
- `origin/main` already pins it: it prints that the pin is current and exits 0.
- An open pull request uses `agent/pin-agent-kit-<12-char sha>`: it prints that pull request's URL and exits 0.
- A pushed branch of that name without an open pull request is reused only when it pins the commit; anything else stops the run for a person to inspect it.

## What the script changes

- `catalog.tsv`, through `scripts/pin agent-kit <commit>`.
- `pi/agents/autopilot-owner.md`: the body becomes agent-kit's `claude/agents/autopilot-owner.md` at that commit, with "escalate anything outside the brief in your report." replaced by the Pi wording "through the supervisor". If agent-kit drops that sentence, the run stops and names the substitution to update. The Pi frontmatter stays bootstrap's.

Nothing else a pin may need is detected: an agent-kit change to a path `install.sh` links, or a new role or extension that needs bootstrap wiring, needs a bootstrap change of its own. The pull request lists the agent-kit commits since the old pin for that review.

## Boundaries

- `scripts/validate` must pass in the pin worktree before anything is committed or pushed. The install round trip is left to CI and the verifier.
- This run never records a verdict. Landing needs one from a fresh verifier, a separate session, that drives the install at the pull request's head; whoever lands follows the verdict gate in the installed `babysit-and-ship` skill.
- One commit per run. Never merge, deploy, or release.

## Report

The script's last line: the pull request URL, the "pin is current" line, or the error and its exit status.
