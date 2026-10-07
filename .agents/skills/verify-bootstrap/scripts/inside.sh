#!/usr/bin/env bash
# Verification scaffolding: run only in our disposable container.
set -euo pipefail
[[ "${BOOTSTRAP_VERIFY_CONTAINER:-}" == 1 && -f /.dockerenv ]] || exit 2
mode="${1:?}"; shift
mkdir -p "/proof/$mode"
export HOME=/var/tmp/tester USER=tester TERM=dumb LC_ALL=C
cd /src
snapshot() {
    local destination="$1"
    (cd "$HOME"; find . -mindepth 1 -print | LC_ALL=C sort | while IFS= read -r path; do
        if [[ -L "$path" ]]; then printf 'link %s -> %s\n' "$path" "$(readlink "$path")"
        elif [[ -f "$path" ]]; then printf 'file %s %s\n' "$path" "$(cksum <"$path")"
        else printf 'dir %s\n' "$path"; fi
    done) >"$destination.home"
    dpkg-query -W -f='${Package}\t${Version}\n' | LC_ALL=C sort >"$destination.packages"
}
case "$mode" in
    help)
        snapshot /proof/help/before
        ./install.sh --help
        ./install.sh -h
        # Validation must fail before writing anything.
        if ./install.sh --tools verification-does-not-exist; then exit 1; fi
        if ./install.sh --languages verification-does-not-exist; then exit 1; fi
        if ./install.sh --lsp verification-does-not-exist; then exit 1; fi
        snapshot /proof/help/after
        diff -u /proof/help/{before,after}.home
        diff -u /proof/help/{before,after}.packages
        printf 'PASS help aliases and selection validation leave HOME and packages unchanged\n'
        ;;
    offline)
        snapshot /proof/offline/before
        ./install.sh link
        root="$HOME/.local/share/bootstrap"
        cp "$root/state.tsv" /proof/offline/first-state.tsv
        cp "$HOME/.bashrc" /proof/offline/bashrc.txt
        readlink "$HOME/.config/helix" | tee /proof/offline/helix-link.txt
        test "$(readlink "$HOME/.config/helix")" = "$root/repo/config/helix"
        grep -q '# >>> bootstrap env >>>' "$HOME/.bashrc"
        snapshot /proof/offline/linked
        ./install.sh link
        cmp /proof/offline/first-state.tsv "$root/state.tsv"
        snapshot /proof/offline/relinked
        diff -u /proof/offline/{linked,relinked}.home
        diff -u /proof/offline/{before,relinked}.packages
        test -z "$(find "$root/tools" -type f -print)"
        set +e
        ./install.sh doctor > /proof/offline/product-doctor.stdout 2>/proof/offline/product-doctor.stderr
        status=$?
        set -e
        printf '%s\n' "$status" > /proof/offline/product-doctor.exit
        test "$status" = 1
        grep -q '^missing ' /proof/offline/product-doctor.stdout
        # Non-terminal uninstall must refuse without --yes, preserving state.
        if ./install.sh uninstall </dev/null; then exit 1; fi
        cmp /proof/offline/first-state.tsv "$root/state.tsv"
        ./install.sh uninstall --yes
        test ! -e "$root"
        ./install.sh uninstall --yes
        snapshot /proof/offline/after
        diff -u /proof/offline/{before,after}.home
        diff -u /proof/offline/{before,after}.packages
        printf 'PASS offline link, convergence, missing-tool doctor, refusal and uninstall restore HOME/packages\n'
        ;;
    edges)
        bash -x tests/uninstall_edges.sh
        ;;
    roundtrip)
        # Existing user-path harness; xtrace preserves commands and snapshot observations.
        snapshot /proof/roundtrip/before
        bash -x tests/roundtrip.sh /src "$@"
        snapshot /proof/roundtrip/after
        diff -u /proof/roundtrip/{before,after}.home
        diff -u /proof/roundtrip/{before,after}.packages
        ;;
    *) exit 2 ;;
esac
