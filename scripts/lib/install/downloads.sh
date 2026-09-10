#!/usr/bin/env bash
# Bounded HTTPS downloads activated only after SHA-256 verification.

download_verified() {
    local url="$1"
    local expected_sha256="$2"
    local destination="$3"
    local partial_path="${destination}.part.$$"
    local actual_sha256

    [[ "$url" == https://* ]] || {
        warn "Refusing non-HTTPS download: $url"
        return 1
    }
    [[ "$expected_sha256" =~ ^[0-9a-f]{64}$ ]] || {
        warn "Invalid SHA-256 for $url"
        return 1
    }
    rm -f "$partial_path"
    if ! curl --fail --location --show-error --silent --proto '=https' --proto-redir '=https' --retry 3 \
        --connect-timeout 15 --max-time 300 --output "$partial_path" "$url"; then
        rm -f "$partial_path"
        return 1
    fi
    if command -v sha256sum &>/dev/null; then
        actual_sha256="$(sha256sum "$partial_path" | awk '{ print $1 }')"
    elif command -v shasum &>/dev/null; then
        actual_sha256="$(shasum -a 256 "$partial_path" | awk '{ print $1 }')"
    else
        rm -f "$partial_path"
        warn "No SHA-256 tool available"
        return 1
    fi
    if [[ "$actual_sha256" != "$expected_sha256" ]]; then
        rm -f "$partial_path"
        warn "Checksum mismatch for $url"
        return 1
    fi
    mv "$partial_path" "$destination"
}
