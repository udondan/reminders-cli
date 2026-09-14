#!/usr/bin/env bash
# Grant Reminders access on a CI runner, where nobody can answer the TCC prompt. It writes an
# "allowed" kTCCServiceReminders row straight into macOS's permission database, which only works
# where SIP is disabled (as on GitHub's hosted macOS runners). Never run this on a personal Mac:
# it disables the permission prompt that protects your data.
#
# macOS attributes the Reminders check to the responsible process, which for a CLI launched from a
# shell is an ancestor rather than the binary itself, so the row is written for the binary and for
# every ancestor process. Refuses to run outside GitHub Actions.
set -euo pipefail

if [ "${GITHUB_ACTIONS:-}" != "true" ]; then
    echo "grant-reminders-access.sh only runs on a GitHub Actions runner. Refusing." >&2
    exit 1
fi

binary=$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")

if [ "$(csrutil status 2>/dev/null)" != "System Integrity Protection status: disabled." ]; then
    echo "SIP is not disabled; cannot write TCC.db. Skipping the grant." >&2
    exit 1
fi

# The binary plus every absolute-path ancestor process.
clients=("$binary")
pid=$$
while [ "$pid" -gt 1 ]; do
    path=$(ps -o comm= -p "$pid" | sed 's/^ *//')
    case "$path" in /*) clients+=("$path") ;; esac
    pid=$(ps -o ppid= -p "$pid" | tr -d ' ')
done

echo "Granting kTCCServiceReminders to:"
printf '  %s\n' "${clients[@]}"

for db in "$HOME/Library/Application Support/com.apple.TCC/TCC.db" \
          "/Library/Application Support/com.apple.TCC/TCC.db"; do
    sudo=""
    case "$db" in /Library/*) sudo="sudo" ;; esac
    for client in "${clients[@]}"; do
        $sudo sqlite3 "$db" "INSERT OR REPLACE INTO access
            (service, client, client_type, auth_value, auth_reason, auth_version, indirect_object_identifier, flags)
            VALUES ('kTCCServiceReminders', '$client', 1, 2, 3, 1, 'UNUSED', 0);"
    done
done

# Make tccd forget anything it cached; launchd restarts it on demand.
sudo killall tccd 2>/dev/null || true
sleep 2

status=$("$binary" doctor --format json | grep -o '"authorization" : "[^"]*"' || true)
echo "After grant: $status"
case "$status" in
    *fullAccess*) ;;
    *) echo "Reminders access was not granted; aborting so the tests fail fast." >&2; exit 1 ;;
esac
