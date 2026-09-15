#!/usr/bin/env bash
# End-to-end smoke test of the built binary against a real EventKit store. It creates its own
# throwaway list and only ever touches reminders it created there, addressed by the IDs the create
# commands return, and it deletes the list on the way out. It refuses to run outside GitHub Actions
# so it can never touch a personal Mac's Reminders.
#
# Exit codes:
#   0  every command behaved as expected
#   20 no source can hold a new list (a runner without any reminder account)
#   1  any command misbehaved
set -euo pipefail

if [ "${GITHUB_ACTIONS:-}" != "true" ]; then
    echo "live-test.sh only runs on a GitHub Actions runner. Refusing." >&2
    exit 1
fi

binary="$1"

# Kill any command that hangs, e.g. on an access prompt nobody can answer.
run() {
    perl -e 'alarm shift; exec @ARGV' 60 "$binary" "$@"
}

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# assert_eq <what> <expected> <actual>
assert_eq() {
    [ "$2" = "$3" ] || fail "$1: expected [$2], got [$3]"
}

list_id=""
cleanup() {
    if [ -n "$list_id" ]; then
        echo "--- cleanup: delete-list $list_id"
        run delete-list "$list_id" --confirm --format json || true
    fi
}
trap cleanup EXIT

jqr() { jq -r "$1"; }

# --- new-list ---------------------------------------------------------------
name="zz-cli-ci-$(uuidgen)"
echo "--- new-list $name"
if ! created=$(run new-list "$name" --format json 2>new-list.err); then
    cat new-list.err >&2
    grep -q '"no_sources"' new-list.err && exit 20
    fail "new-list"
fi
echo "$created"
list_id=$(jqr .calendarIdentifier <<<"$created")
if [ -z "$list_id" ] || [ "$list_id" = null ]; then
    fail "new-list returned no calendarIdentifier"
fi

# --- add: due date, notes, priority, weekly repeat --------------------------
echo "--- add"
added=$(run add --due-date "2026-09-20 09:00" --notes "buy soil" --priority high \
    --repeat weekly --repeat-on "mon,thu" --format json "$list_id" "Water plants")
echo "$added"
id=$(jqr .externalId <<<"$added")
assert_eq "add list"       "$list_id"       "$(jqr .listId <<<"$added")"
assert_eq "add title"      "Water plants"   "$(jqr .title <<<"$added")"
assert_eq "add notes"      "buy soil"       "$(jqr .notes <<<"$added")"
assert_eq "add priority"   "1"              "$(jqr .priority <<<"$added")"
assert_eq "add recurrence" "weekly"         "$(jqr .recurrence <<<"$added")"
assert_eq "add repeat-on"  "mon,thu"        "$(jqr '.recurrenceDays | join(",")' <<<"$added")"

# A second, plain reminder to test batches and filters against.
second=$(run add --due-date "2026-09-21 10:00" --format json "$list_id" "Take out bins")
id2=$(jqr .externalId <<<"$second")

# --- show: json is an array, plain and pretty render --------------------------
echo "--- show json/plain/pretty"
shown=$(run show "$list_id" --format json)
assert_eq "show count" "2" "$(jq length <<<"$shown")"
run show "$list_id" --format plain  | grep -q "Water plants" || fail "plain show missing reminder"
run show "$list_id" --format pretty | grep -q "Water plants" || fail "pretty show missing reminder"

# A single-ID json show is the object, not an array.
one=$(run show "$list_id" --format json | jq --arg id "$id" '[.[] | select(.externalId == $id)][0]')
assert_eq "single object title" "Water plants" "$(jqr .title <<<"$one")"

# --- edit: text, notes, priority, clear priority ----------------------------
echo "--- edit"
edited=$(run edit --priority low --notes "buy compost" --format json "$list_id" "$id" "Water the plants")
assert_eq "edit title"    "Water the plants" "$(jqr .title <<<"$edited")"
assert_eq "edit notes"    "buy compost"      "$(jqr .notes <<<"$edited")"
assert_eq "edit priority" "9"                "$(jqr .priority <<<"$edited")"

cleared=$(run edit --clear-priority --format json "$list_id" "$id")
assert_eq "clear priority" "0" "$(jqr .priority <<<"$cleared")"

# --- postpone: explicit date, then next weekday -----------------------------
echo "--- postpone"
postponed=$(run postpone --format json "$list_id" "$id2" "2026-09-25 10:00")
assert_eq "postpone due" "2026-09-25T10:00:00Z" "$(jqr .dueDate <<<"$postponed")"
# 2026-09-25 is a Friday; --next-weekday must land on Monday the 28th, same time.
nextwd=$(run postpone --next-weekday --format json "$list_id" "$id2")
assert_eq "next weekday" "2026-09-28T10:00:00Z" "$(jqr .dueDate <<<"$nextwd")"

# postpone --next-weekday on a reminder with no due date is no_due_date (exit 6).
nodue=$(run add --format json "$list_id" "No due date")
nodue_id=$(jqr .externalId <<<"$nodue")
set +e
run postpone --next-weekday --format json "$list_id" "$nodue_id" 2>nodue.err
code=$?
set -e
assert_eq "next-weekday without due exit code" "6" "$code"
grep -q '"no_due_date"' nodue.err || fail "expected no_due_date error"

# --- complete / uncomplete --------------------------------------------------
# Uses the non-recurring reminders so the counts don't depend on how EventKit treats
# completing a repeating reminder. Three reminders are open here: id, id2, nodue_id.
echo "--- complete/uncomplete"
run complete "$list_id" "$id2" --format json >/dev/null
assert_eq "completed hidden" "2" "$(run show "$list_id" --format json | jq length)"
assert_eq "completed shown"  "3" "$(run show "$list_id" --include-completed --format json | jq length)"
run uncomplete "$list_id" "$id2" --format json >/dev/null
assert_eq "uncompleted back" "3" "$(run show "$list_id" --format json | jq length)"

# --- batch: comma-separated, and stdin '-' ----------------------------------
echo "--- batch complete"
batch=$(run complete "$list_id" "$id2,$nodue_id" --format json)
assert_eq "comma batch is array" "2" "$(jq length <<<"$batch")"
run uncomplete "$list_id" "$id2,$nodue_id" --format json >/dev/null

echo "--- batch via stdin"
stdin_batch=$(printf '%s\n%s\n' "$id2" "$nodue_id" | run complete "$list_id" - --format json)
assert_eq "stdin batch is array" "2" "$(jq length <<<"$stdin_batch")"
run uncomplete "$list_id" "$id2,$nodue_id" --format json >/dev/null

# --- show-all, today, show-lists all see the test list ----------------------
echo "--- show-all / today / show-lists"
run show-all --list "$list_id" --format json  | jq -e 'length >= 1' >/dev/null || fail "show-all"
run show-all --list "$list_id" --format pretty | grep -q "Water the plants" || fail "show-all pretty"
run show-lists --format json | jq -e --arg id "$list_id" 'any(.[]; .calendarIdentifier == $id)' \
    >/dev/null || fail "show-lists missing test list"

# --- delete: single, then batch ---------------------------------------------
echo "--- delete"
run delete "$list_id" "$nodue_id" --format json >/dev/null
assert_eq "after single delete" "2" "$(run show "$list_id" --include-completed --format json | jq length)"
run delete "$list_id" "$id,$id2" --format json >/dev/null
assert_eq "after batch delete" "0" "$(run show "$list_id" --include-completed --format json | jq length)"

# --- delete-list: refuse without --confirm, then delete ---------------------
echo "--- delete-list refusal"
set +e
run delete-list "$list_id" --format json 2>refuse.err
code=$?
set -e
assert_eq "delete-list without confirm exit code" "13" "$code"
grep -q '"confirmation_required"' refuse.err || fail "expected confirmation_required"

echo "--- delete-list --confirm"
run delete-list "$list_id" --confirm --format json
if run show-lists --format json | jq -e --arg id "$list_id" 'any(.[]; .calendarIdentifier == $id)' >/dev/null; then
    fail "list still exists after delete-list --confirm"
fi
list_id=""

echo "PASS"
