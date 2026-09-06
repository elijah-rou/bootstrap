---
name: omarchy
description: >-
  Customize an installed Omarchy desktop: Hyprland, the shell/bar, terminal appearance, themes, monitors, bindings, idle/lock behavior, reminders, or user-facing Omarchy commands. Use for ~/.config/hypr/, ~/.config/omarchy/, and Linux desktop terminal configuration. Excludes unrelated ~/.config applications, server/system administration unrelated to the desktop, and Omarchy source development.
---

# Omarchy desktop customization

This shared adapter uses the installed Omarchy topic guides without inheriting their general-purpose privilege instructions. It does not modify or copy the system package. Keep `/usr/share/omarchy/` read-only; use user configuration, custom themes, hooks, or cloned plugins for changes.

## Read the matching installed guide

Only load the topic needed for the request, under `/usr/share/omarchy/default/agents/skills/omarchy/`:

- `hyprland.md`: bindings, windows, workspaces, monitors, and display configuration.
- `plugins.md`: shell/bar, widgets, plugins, and idle behavior.
- `theming.md`: themes, backgrounds, and fonts.
- `hooks.md`: event automation.
- `capture.md`: screenshots, recording, and OCR.
- `contributing.md`: reporting a confirmed Omarchy bug.

These are installation-dependent absolute references, not sibling files. Check that the selected guide exists. If absent, use command help and installed source; report missing guidance rather than inventing paths. Do not load the upstream root `SKILL.md`, whose broad activation and privilege rules are replaced here.

## Execute within the requested scope

Read the current configuration and discover commands with `omarchy commands` or the relevant `--help`. Keep changes in the affected user configuration. Back up meaningful customizations before replacement. Confirm destructive resets, reinstalls, shutdowns, and reboots explicitly; a debugging request does not authorize them.

In Pi, use the confirmed `privileged_operation` tool for supported privileged package or service operations. In Codex, this port supplies no privilege bridge: ask the user to execute privileged operations directly unless a separately approved interactive integration is available. Do not invoke `sudo` or `pkexec` through shell tools, including through an Omarchy command that wraps them. Inspect wrappers before running privileged paths. Ask the user to execute unsupported privileged or AUR operations explicitly; headless children report the required operation to the parent.

Use `omarchy debug --no-sudo --print` for bounded diagnostics. Do not include sensitive logs or private configuration in reports.

For desktop reminders, use `omarchy reminder <minutes> [message]`; convert the requested duration to minutes and title-case short labels when appropriate. Use `omarchy reminder show` to inspect reminders and `omarchy reminder clear` only when clearing was requested. Do not replace a desktop reminder with a new scheduled agent workflow.

For terminal configuration, use `omarchy restart terminal` to apply changes; Foot picks them up in new windows. Shell JSON, user plugins, and menu configuration hot-reload on save.

After editing, exercise the affected consumer: for Hyprland use `hyprctl reload` and inspect `hyprctl configerrors`; for shell or terminal changes inspect the relevant reload and visible result. Do not reset unrelated configuration to make a check pass.
