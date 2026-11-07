#!/usr/bin/env bash
# Completes a list name in bash, zsh and fish through the completion scripts the binary
# generates, and checks that each shell offers the name unchanged and runs nothing in it.
# Called by live-test.sh with a throwaway list whose name contains the characters to check.
#
# Usage: check-completion.sh <binary> <list name> <unique prefix of the name>
set -euo pipefail

binary="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
name="$2"
prefix="$3"
here="$(cd "$(dirname "$0")" && pwd)"
brew_bin="$(brew --prefix)/bin"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/fpath"
# The completion scripts call `reminders` from PATH. A wrapper, not a symlink, so the process
# keeps the binary's own path, which the Reminders access was granted to.
printf '#!/bin/sh\nexec "%s" "$@"\n' "$binary" >"$work/bin/reminders"
chmod +x "$work/bin/reminders"
export PATH="$work/bin:$PATH"
cd "$work"

"$binary" --generate-completion-script bash >reminders.bash
"$binary" --generate-completion-script zsh >fpath/_reminders
"$binary" --generate-completion-script fish >reminders.fish

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# check <shell> <completed name>
check() {
    [ "$2" = "$name" ] || fail "$1 list name completion: expected [$name], got [$2]"
    [ ! -e zz-marker ] || fail "$1 list name completion ran a command from the list name"
    echo "$1: ok"
}

check bash "$("$brew_bin/bash" "$here/complete-bash.sh" "$prefix")"
check zsh "$(zsh -f "$here/complete-zsh.zsh" "$prefix")"
check fish "$("$brew_bin/fish" --no-config -c \
    "source reminders.fish; complete -C 'reminders show $prefix'")"
