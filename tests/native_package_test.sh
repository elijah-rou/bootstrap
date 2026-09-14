#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; fixture="$(mktemp -d)"; trap 'rm -rf "$fixture"' EXIT
export HOME="$fixture/home"; mkdir -p "$HOME"; source "$ROOT/install.sh"
BOOTSTRAP_PACKAGE_BACKEND=apt; [[ "$(native_backend)" == apt ]]
[[ "$(catalog_query package gh pacman)" == $'gh\tgithub-cli' ]]
[[ "$(catalog_query package fd apt)" == $'fd\tfd-find' ]]
commands="$fixture/commands"; package_db="$fixture/installed"
printf 'fixture-package\n' >"$package_db"
native_privileged() { "$@"; }
dpkg-query() { while read -r name; do printf '%s\tinstall ok installed\n' "$name"; done <"$package_db"; }
apt-get() {
    printf 'apt-get %s\n' "$*" >>"$commands"
    case "$*" in '--simulate remove fixture-package') printf 'Remv fixture-package [1]\n';; *) return 99;; esac
}
dpkg() { [[ "$*" == '--remove -- fixture-package' ]] || return 99; printf 'dpkg %s\n' "$*" >>"$commands"; : >"$package_db"; }
native_remove_names apt fixture-package
grep -q '^apt-get --simulate remove fixture-package$' "$commands"
grep -q '^dpkg --remove -- fixture-package$' "$commands"
! grep -q autoremove "$commands"
printf 'fixture-package\n' >"$package_db"
apt-get() { if [[ "$*" == --simulate* ]]; then printf 'Remv fixture-package [1]\nRemv unrelated-dependent [2]\n'; else return 99; fi; }
if native_remove_names apt fixture-package; then exit 1; fi
apt-get() { return 0; }; dpkg() { return 0; }
if native_remove_names apt fixture-package; then echo 'accepted unchanged package'; exit 1; fi
dpkg() { [[ "$*" == '--remove -- fixture-package' ]] || return 99; return 1; }
if native_remove_names apt fixture-package; then echo 'accepted concurrent dependent'; exit 1; fi
dpkg() { printf 'config-files\n' >"$package_db"; }
dpkg-query() { if [[ "$(cat "$package_db")" == config-files ]]; then printf 'fixture-package\tdeinstall ok config-files\n'; else printf 'fixture-package\tinstall ok installed\n'; fi; }
native_remove_names apt fixture-package 2>"$fixture/conffiles"
grep -q 'Native conffiles remain' "$fixture/conffiles"
printf "fixture-package\n" >"$package_db"

apt-get() { return 12; }
if native_preview_remove apt fixture-package; then exit 1; fi
dpkg-query() { return 2; }
if native_preview_remove apt fixture-package; then echo 'query error treated as absence'; exit 1; fi

# Every backend uses its production inventory predicate, including query errors.
for backend in apt dnf pacman brew; do
    dpkg-query() { [[ "$query" != error ]] || return 2; [[ "$query" != present ]] || printf 'fixture-package\tinstall ok installed\n'; return 0; }
    rpm() { [[ "$query" != error ]] || return 2; [[ "$query" != present ]] || printf 'fixture-package\n'; return 0; }
    pacman() { [[ "$query" != error ]] || return 2; [[ "$query" != present ]] || printf 'fixture-package\n'; return 0; }
    brew() { [[ "$query" != error ]] || return 2; [[ "$query" != present ]] || printf 'fixture-package\n'; return 0; }
    query=present; native_package_present "$backend" fixture-package
    query=absent; status=0; native_package_present "$backend" fixture-package || status=$?; [[ "$status" == 1 ]]
    query=error; status=0; native_package_present "$backend" fixture-package || status=$?; [[ "$status" == 2 ]]
    if native_remove_names "$backend" fixture-package; then exit 1; fi
done
query=present
brew() { case "$1" in list) printf 'fixture-package\n';; uses) return 13;; *) return 99;; esac; }
if native_preview_remove brew fixture-package; then exit 1; fi
brew() { case "$1" in list) printf 'fixture-package\n';; uses) printf 'unrelated\n';; *) return 99;; esac; }
if native_preview_remove brew fixture-package; then exit 1; fi
pacman() { case "$1" in -Qq) printf 'fixture-package\n';; -R) printf 'fixture-package\nunrelated\n';; *) return 99;; esac; }
if native_preview_remove pacman fixture-package; then exit 1; fi
rpm() {
    case "$*" in
        '-qa --qf %{NAME}\n') printf 'fixture-package\n' ;;
        '-q --qf '*) printf 'P\tfixture-package\tfixture-capability\nF\tfixture-package\t/usr/bin/fixture\n' ;;
        '-qa --qf '*) printf '%b' "$requirements" ;;
        *) return 99 ;;
    esac
}
dnf() { echo 'preview must not invoke DNF' >&2; return 99; }
requirements='R\tfixture-package\tlibc\n'; native_preview_remove dnf fixture-package
for requirement in fixture-capability /usr/bin/fixture '(fixture-capability if alternative)' '(alternative or fixture-capability)' '(fixture-capability and alternative'; do
    requirements="R\tunrelated\t$requirement\n"
    if native_preview_remove dnf fixture-package; then exit 1; fi
done
requirements='malformed\n'; if native_preview_remove dnf fixture-package; then exit 1; fi
rpm() { return 2; }; if native_preview_remove dnf fixture-package; then exit 1; fi
# A concurrent new dependent is rejected by RPM itself, never cascaded by DNF.
rpm() {
    case "$*" in
        '-qa --qf %{NAME}\n') printf 'fixture-package\n' ;;
        '-q --qf '*) printf 'P\tfixture-package\tfixture-capability\n' ;;
        '-qa --qf '*) return 0 ;;
        '-e -- fixture-package') printf 'concurrent dependency blocks erase\n' >>"$commands"; return 1 ;;
        *) return 99 ;;
    esac
}
if native_remove_names dnf fixture-package; then exit 1; fi
grep -q 'concurrent dependency blocks erase' "$commands"
echo 'PASS real native predicates, read-only capability previews, query errors, and non-cascading removal'
