#!/usr/bin/env bash
# Shared Bash/Zsh desktop opener.

# macOS provides open; use the desktop default application elsewhere.
if [[ "$OSTYPE" != "darwin"* ]]; then
    unalias open 2>/dev/null
    function open {
        if command -v gio &>/dev/null; then
            local DISPLAY="${DISPLAY:-}"
            local WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}"
            local XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-}"
            local XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-}"
            local HYPRLAND_INSTANCE_SIGNATURE="${HYPRLAND_INSTANCE_SIGNATURE:-}"
            local manager_environment manager_name manager_value

            # Detached shells may need the graphical environment held by systemd.
            if [[ -z "$DISPLAY$WAYLAND_DISPLAY" ]] && command -v systemctl &>/dev/null; then
                manager_environment=$(systemctl --user show-environment 2>/dev/null) ||
                    manager_environment=""
                while IFS='=' read -r manager_name manager_value; do
                    case "$manager_name" in
                        DISPLAY) DISPLAY="$manager_value" ;;
                        WAYLAND_DISPLAY) WAYLAND_DISPLAY="$manager_value" ;;
                        XDG_CURRENT_DESKTOP) XDG_CURRENT_DESKTOP="$manager_value" ;;
                        XDG_SESSION_TYPE) XDG_SESSION_TYPE="$manager_value" ;;
                        HYPRLAND_INSTANCE_SIGNATURE) HYPRLAND_INSTANCE_SIGNATURE="$manager_value" ;;
                        *) ;;
                    esac
                done <<< "$manager_environment"
            fi

            export DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE
            export HYPRLAND_INSTANCE_SIGNATURE
            command gio open "$@"
            return $?
        fi

        if command -v xdg-open &>/dev/null; then
            command xdg-open "$@"
            return $?
        fi

        printf 'open: no desktop opener found\n' >&2
        return 127
    }
fi
