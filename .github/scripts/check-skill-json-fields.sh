#!/usr/bin/env bash
# Fails when the JSON field table in the agent skill drifts from the
# EncodingKeys enum that produces `--format json` output for reminders.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

swift_file="Sources/RemindersLibrary/EKReminder+Encodable.swift"
skill_file="skills/reminders-cli/SKILL.md"

expected=$(sed -n '/enum EncodingKeys/,/^    }/p' "$swift_file" \
  | sed -n 's/^ *case \([A-Za-z0-9_]*\).*/\1/p')

# The backticks are literal table markup, not command substitution.
# shellcheck disable=SC2016
actual=$(sed -n '/<!-- json-fields:start -->/,/<!-- json-fields:end -->/p' "$skill_file" \
  | sed -n 's/^| `\([A-Za-z0-9_]*\)`.*/\1/p')

if [ -z "$expected" ]; then
  echo "No EncodingKeys cases found in $swift_file" >&2
  exit 1
fi

if [ -z "$actual" ]; then
  echo "No JSON field table found between the json-fields markers in $skill_file" >&2
  exit 1
fi

if ! diff <(echo "$expected") <(echo "$actual") >/dev/null; then
  echo "The JSON field table in $skill_file does not match EncodingKeys in $swift_file." >&2
  echo "Rows must list every key, in enum order. Diff (< enum, > SKILL.md):" >&2
  diff <(echo "$expected") <(echo "$actual") >&2 || true
  exit 1
fi

echo "SKILL.md JSON field table matches EncodingKeys ($(echo "$expected" | wc -l | tr -d ' ') keys)."
