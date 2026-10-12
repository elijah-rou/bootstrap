#!/usr/bin/env bash
# Verification scaffolding: run only in our disposable container. One mode per feature in ../features;
# verify.sh drives them. Every mode restores HOME and packages, so modes may run in any order.
set -euo pipefail
[[ "${BOOTSTRAP_VERIFY_CONTAINER:-}" == 1 && -f /.dockerenv ]] || exit 2
mode="${1:?}"; shift
proof="/proof/$mode"
mkdir "$proof"   # a rerun would overwrite this mode's evidence; launch a new run instead
export HOME=/var/tmp/tester USER=tester TERM=dumb LC_ALL=C
cd /src
root="$HOME/.local/share/bootstrap"
snapshot() {
    local destination="$1"
    (cd "$HOME"; find . -mindepth 1 -print | LC_ALL=C sort | while IFS= read -r path; do
        if [[ -L "$path" ]]; then printf 'link %s -> %s\n' "$path" "$(readlink "$path")"
        elif [[ -f "$path" ]]; then printf 'file %s %s\n' "$path" "$(cksum <"$path")"
        else printf 'dir %s\n' "$path"; fi
    done) >"$destination.home"
    dpkg-query -W -f='${Package}\t${Version}\n' | LC_ALL=C sort >"$destination.packages"
}
unchanged() {
    snapshot "$proof/after"
    diff -u "$proof"/{before,after}.home
    diff -u "$proof"/{before,after}.packages
}
case "$mode" in
    help)
        snapshot "$proof/before"
        ./install.sh --help
        ./install.sh -h
        # Validation must fail before writing anything.
        if ./install.sh --tools verification-does-not-exist; then exit 1; fi
        if ./install.sh --languages verification-does-not-exist; then exit 1; fi
        if ./install.sh --lsp verification-does-not-exist; then exit 1; fi
        unchanged
        printf 'PASS help: aliases and selection validation leave HOME and packages unchanged\n'
        ;;
    link)
        snapshot "$proof/before"
        ./install.sh link
        cp "$root/state.tsv" "$proof/first-state.tsv"
        cp "$HOME/.bashrc" "$proof/bashrc.txt"
        readlink "$HOME/.config/helix" | tee "$proof/helix-link.txt"
        test "$(readlink "$HOME/.config/helix")" = "$root/repo/config/helix"
        grep -q '# >>> bootstrap env >>>' "$HOME/.bashrc"
        snapshot "$proof/linked"
        ./install.sh link
        cmp "$proof/first-state.tsv" "$root/state.tsv"
        snapshot "$proof/relinked"
        diff -u "$proof"/{linked,relinked}.home
        diff -u "$proof"/{before,relinked}.packages
        test -z "$(find "$root/tools" -type f -print)"
        ./install.sh uninstall --yes
        unchanged
        # User replacement files, existing skills, unsafe roots, and malformed blocks.
        bash -x tests/uninstall_edges.sh
        printf 'PASS link: clean link, convergent relink, and edge cases leave HOME and packages unchanged\n'
        ;;
    doctor)
        snapshot "$proof/before"
        ./install.sh link
        set +e
        ./install.sh doctor >"$proof/product-doctor.stdout" 2>"$proof/product-doctor.stderr"
        status=$?
        set -e
        printf '%s\n' "$status" >"$proof/product-doctor.exit"
        cat "$proof/product-doctor.stdout"
        test "$status" = 1
        grep -q '^missing ' "$proof/product-doctor.stdout"
        ./install.sh uninstall --yes
        unchanged
        printf 'PASS doctor: missing tools reported after offline link; HOME and packages unchanged\n'
        ;;
    uninstall)
        snapshot "$proof/before"
        ./install.sh link
        cp "$root/state.tsv" "$proof/first-state.tsv"
        # Non-terminal uninstall must refuse without --yes, preserving state.
        if ./install.sh uninstall </dev/null; then exit 1; fi
        cmp "$proof/first-state.tsv" "$root/state.tsv"
        ./install.sh uninstall --yes
        test ! -e "$root"
        ./install.sh uninstall --yes
        unchanged
        # Failed-uninstall recovery and preservation of user content.
        bash -x tests/uninstall_edges.sh
        printf 'PASS uninstall: refusal, confirmed and repeated uninstall, and recovery leave HOME and packages unchanged\n'
        ;;
    install)
        # Existing user-path harness with the caller's selection; xtrace preserves its commands.
        snapshot "$proof/before"
        bash -x tests/roundtrip.sh /src "$@" | tee "$proof/roundtrip.stdout"
        test "$(grep -c 'installed; start a new shell to use it' "$proof/roundtrip.stdout")" = 2
        grep -qx 'PASS: install, rerun, doctor, and uninstall left HOME and packages unchanged' "$proof/roundtrip.stdout"
        unchanged
        printf 'PASS install: install, rerun, relink, doctor, shell use, and uninstall left HOME and packages unchanged\n'
        ;;
    *) exit 2 ;;
esac
