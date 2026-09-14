# reminders-cli

A simple CLI for interacting with OS X reminders.

## Usage

### Show all lists

```console
$ reminders show-lists
Soon        (2A29C8B1-3D0F-4A9E-9C8D-5B6E7F8A9B0C)   12 open, 3 overdue
Eventually  (7E1F2A3B-4C5D-6E7F-8A9B-0C1D2E3F4A5B)    4 open
Someday     (9F0A1B2C-3D4E-5F60-7182-93A4B5C6D7E8)    0 open
```

"Open" counts the reminders that are not completed; "overdue" counts those among them whose due date
has passed, the same definition `show --overdue` uses, and it is only shown when it is not zero.

Completed reminders are not counted by default, because fetching them is noticeably slower on a
store that has been in use for a while. Ask for them explicitly:

```console
$ reminders show-lists --include-completed
Soon        (2A29C8B1-3D0F-4A9E-9C8D-5B6E7F8A9B0C)   12 open, 3 overdue, 214 completed
Eventually  (7E1F2A3B-4C5D-6E7F-8A9B-0C1D2E3F4A5B)    4 open, 8 completed
Someday     (9F0A1B2C-3D4E-5F60-7182-93A4B5C6D7E8)    0 open, 0 completed
```

Lists are printed in the order Reminders.app keeps them. `--sort`/`-s` reorders them by `name`
(case-insensitive), `open` or `overdue`. The two count orders put the busiest list first and break
ties by name:

```console
$ reminders show-lists --sort name
Eventually  (7E1F2A3B-4C5D-6E7F-8A9B-0C1D2E3F4A5B)    4 open
Someday     (9F0A1B2C-3D4E-5F60-7182-93A4B5C6D7E8)    0 open
Soon        (2A29C8B1-3D0F-4A9E-9C8D-5B6E7F8A9B0C)   12 open, 3 overdue
```

With `--format json` the counts are `openCount`, `overdueCount` and, with `--include-completed`,
`completedCount`:

```console
$ reminders show-lists --format json
[
  {
    "calendarIdentifier" : "2A29C8B1-3D0F-4A9E-9C8D-5B6E7F8A9B0C",
    "openCount" : 12,
    "overdueCount" : 3,
    "title" : "Soon"
  }
]
```

Show only the default list (the one Reminders.app adds new reminders to):

```console
$ reminders show-lists --default-only
Soon  (2A29C8B1-3D0F-4A9E-9C8D-5B6E7F8A9B0C)   12 open, 3 overdue
```

Every list also has a stable identifier, shown above in parentheses (and available as
`calendarIdentifier` with `--format json`). Anywhere a list name is accepted — `show`, `show-all`,
`add`, `complete`, `uncomplete`, `edit`, `postpone`, `delete` — a list ID works too, which is useful
for scripting against a list whose name might change or contains characters that are awkward on the
command line.

For interactive use, the list argument doesn't have to be the exact name either. It's resolved by
trying, in order: an exact ID, an exact name, a case-insensitive name, and finally a case-insensitive
substring of a name. So `reminders show soon` and `reminders show even` both work with the lists
above. Exact matches always win, so scripts that pass full names or IDs are unaffected. A fragment
that matches several lists is an error, never a guess:

```console
$ reminders show-lists
Work                  (2A29C8B1-3D0F-4A9E-9C8D-5B6E7F8A9B0C)   12 open, 3 overdue
Work – Side projects  (7E1F2A3B-4C5D-6E7F-8A9B-0C1D2E3F4A5B)    4 open
$ reminders show wor
Error: Multiple reminders lists match 'wor': Work, Work – Side projects
Suggestion: Be more specific, or pass the list's ID from 'reminders show-lists'
```

(`reminders show work` does resolve to `Work`, because the whole-name match is tried before the
substring match.) `new-list` always creates exactly the name you give it; no fuzzy matching applies
there.

### Show reminders on a specific list

```console
$ reminders show Soon
2A29C8B1-3D0F-4A9E-9C8D-5B6E7F8A9B0C: Write README
44C111DE-0B69-4E96-8C93-6A5D0A6C2A17: Ship reminders-cli
```

Each reminder's own stable identifier is shown as the leading prefix — the same kind of ID as the
list identifiers above. This is what you pass to `complete`, `uncomplete`, `edit`, `postpone`, and
`delete` to act on a specific reminder; unlike a list position, it keeps pointing at the same
reminder even if the list changes in between.

You don't have to type the whole ID: a case-insensitive prefix of at least 4 characters is enough as
long as it identifies exactly one reminder on the list, so `reminders complete Soon 44c1` completes
"Ship reminders-cli" above. A prefix that matches several reminders is reported as
`reminder_ambiguous` together with the matching IDs and titles, and a prefix shorter than 4
characters never matches anything (an exact full ID always does).

### Complete an item on a list

```console
$ reminders complete Soon 2A29C8B1-3D0F-4A9E-9C8D-5B6E7F8A9B0C
Completed 'Write README'

$ reminders show Soon
44C111DE-0B69-4E96-8C93-6A5D0A6C2A17: Ship reminders-cli
```

`complete`, `uncomplete`, `edit`, `postpone`, and `delete` also accept `--format json` to print the
affected reminder as JSON instead of the plain-text confirmation shown above, and `new-list
--format json` prints the created list. Errors are never printed to stdout; see [Errors](#errors).

### Undo a completed item

```console
$ reminders show Soon --only-completed
2A29C8B1-3D0F-4A9E-9C8D-5B6E7F8A9B0C: Write README

$ reminders uncomplete Soon 2A29C8B1-3D0F-4A9E-9C8D-5B6E7F8A9B0C
Uncompleted 'Write README'

$ reminders show Soon
2A29C8B1-3D0F-4A9E-9C8D-5B6E7F8A9B0C: Write README
```

### Edit an item on a list

```console
$ reminders edit Soon 2A29C8B1-3D0F-4A9E-9C8D-5B6E7F8A9B0C Some edited text
Updated reminder 'Some edited text'

$ reminders edit Soon 2A29C8B1-3D0F-4A9E-9C8D-5B6E7F8A9B0C --due-date "tomorrow 9am"
Updated reminder 'Some edited text'

$ reminders edit Soon 2A29C8B1-3D0F-4A9E-9C8D-5B6E7F8A9B0C --clear-due-date
Updated reminder 'Some edited text'

$ reminders show Soon
44C111DE-0B69-4E96-8C93-6A5D0A6C2A17: Ship reminders-cli
2A29C8B1-3D0F-4A9E-9C8D-5B6E7F8A9B0C: Some edited text
```

Set or clear a reminder's notes:

```console
$ reminders edit Soon 2A29C8B1-3D0F-4A9E-9C8D-5B6E7F8A9B0C --notes "Bring the charger"
Updated reminder 'Some edited text'

$ reminders edit Soon 2A29C8B1-3D0F-4A9E-9C8D-5B6E7F8A9B0C --clear-notes
Updated reminder 'Some edited text'
```

`--notes ""` (with the empty string as a separate argument) also clears the notes, but the
`--notes=""` spelling is rejected by the argument parser as a missing value, so prefer
`--clear-notes` in scripts.

Set or clear a reminder's priority:

```console
$ reminders edit Soon 2A29C8B1-3D0F-4A9E-9C8D-5B6E7F8A9B0C --priority high
Updated reminder 'Some edited text'

$ reminders edit Soon 2A29C8B1-3D0F-4A9E-9C8D-5B6E7F8A9B0C --clear-priority
Updated reminder 'Some edited text'
```

Move a reminder to a different list:

```console
$ reminders edit Soon 2A29C8B1-3D0F-4A9E-9C8D-5B6E7F8A9B0C --list "Some Other List"
Updated reminder 'Some edited text'

$ reminders show "Some Other List"
2A29C8B1-3D0F-4A9E-9C8D-5B6E7F8A9B0C: Some edited text
```

### Postpone a reminder

Set a specific new due date; any existing repeat rule is left completely unchanged:

```console
$ reminders postpone Soon B9D4E8A7-6FAC-4D3B-EA87-1C2E5F607182 "next monday 9am"
Postponed reminder 'Water the plants'
```

Or shift it to the next weekday, preserving its time of day:

```console
$ reminders postpone Soon B9D4E8A7-6FAC-4D3B-EA87-1C2E5F607182 --next-weekday
Postponed reminder 'Water the plants'
```

`--next-weekday` always moves the due date forward by at least one day, based on the reminder's
_current_ due date (not today), skipping Saturday and Sunday — so a reminder due Wednesday moves to
Thursday, and one due Friday moves to the following Monday. It requires the reminder to already
have a due date.

### Delete an item on a list

```console
$ reminders delete Soon 2A29C8B1-3D0F-4A9E-9C8D-5B6E7F8A9B0C
Deleted 'Write README'

$ reminders show Soon
44C111DE-0B69-4E96-8C93-6A5D0A6C2A17: Ship reminders-cli
```

`delete` looks a reminder up by ID regardless of its completion state, so a reminder that's already
been completed can be deleted the same way, without any special-casing.

With `--format json` the deleted reminder is printed as JSON, so a script can keep a record of
what it removed:

```console
$ reminders delete Soon 2A29C8B1-3D0F-4A9E-9C8D-5B6E7F8A9B0C --format json
{
  "externalId" : "2A29C8B1-3D0F-4A9E-9C8D-5B6E7F8A9B0C",
  "isCompleted" : false,
  "list" : "Soon",
  "listId" : "9E1F1D3B-9C63-4B2E-A7F2-5C1B7E1E8A44",
  "priority" : 0,
  "title" : "Write README"
}
```

### Add a reminder to a list

```console
$ reminders add Soon Contribute to open source

$ reminders add Soon Go to the grocery store --due-date "tomorrow 9am"

$ reminders add Soon Something really important --priority high

$ reminders show Soon
44C111DE-0B69-4E96-8C93-6A5D0A6C2A17: Ship reminders-cli
B3D8E2A1-9F4C-4D7B-8A21-5C6E9F0A1B2C: Contribute to open source
C4E9F3B2-1A5D-4E8C-9B32-6D7F0A1B2C3D: Go to the grocery store (in 10 hours)
D5F0A4C3-2B6E-4F9D-AC43-7E8A1B2C3D4E: Something really important (priority: high)
```

### Add a repeating reminder

```console
reminders add Soon Weekly review --due-date "monday 9am" --repeat weekly
reminders add Soon Pay rent --due-date "2026-09-01" --repeat monthly --repeat-until "2027-09-01"
reminders add Soon Water the plants --due-date "tomorrow" --repeat daily --repeat-interval 3
reminders add Soon Gym --due-date "monday 7am" --repeat-on mon,wed,fri
reminders add Soon Stand-up --due-date "monday 9am" --repeat weekly --repeat-on weekdays
reminders add Soon Swim --due-date "tuesday 6pm" --repeat-on tue,thu --repeat-interval 2
```

- `--repeat` accepts `daily`, `weekly`, `monthly`, or `yearly`. EventKit reminders have no hourly
  recurrence frequency, so `--repeat hourly` is rejected with an explanation rather than silently
  degrading to daily.
- `--repeat-interval` repeats every N units instead of every 1 (e.g. `--repeat-interval 2
--repeat weekly` for every other week) and defaults to 1.
- `--repeat-until` stops the recurrence after a date; omitting it repeats forever, matching the
  Reminders.app default. A date without a time includes the whole local day.
- `--repeat-on` picks the days a weekly repeat fires on: a comma-separated list of day names,
  full (`monday`) or three-letter (`mon`), case-insensitive, or the aliases `weekdays` (Monday to
  Friday) and `weekends` (Saturday and Sunday). Duplicates are ignored and unknown names are
  rejected with the accepted spellings. It only applies to weekly repeats: on `add` it implies
  `--repeat weekly` and is rejected together with `daily`, `monthly`, or `yearly`.
- On `add`, `--repeat-interval` and `--repeat-until` require `--repeat` or `--repeat-on`, and a
  repeating reminder requires `--due-date`.

To change or remove a repeat rule on an existing reminder, use `edit`:

```console
reminders edit Soon 44C111DE-0B69-4E96-8C93-6A5D0A6C2A17 --repeat monthly
reminders edit Soon 44C111DE-0B69-4E96-8C93-6A5D0A6C2A17 --repeat-until "2027-09-01"
reminders edit Soon 44C111DE-0B69-4E96-8C93-6A5D0A6C2A17 --clear-repeat-end
reminders edit Soon 44C111DE-0B69-4E96-8C93-6A5D0A6C2A17 --repeat-on weekdays
reminders edit Soon 44C111DE-0B69-4E96-8C93-6A5D0A6C2A17 --clear-repeat-on
reminders edit Soon 44C111DE-0B69-4E96-8C93-6A5D0A6C2A17 --clear-repeat
```

- Changing only the interval or end condition preserves the existing frequency and any complex
  selectors, such as "the last Friday of every month".
- `--repeat-on` replaces only the days of an existing weekly repeat and keeps its interval and end
  condition; `--clear-repeat-on` removes the days and keeps everything else. Both fail on a
  reminder whose repeat isn't weekly, unless combined with `--repeat weekly`.
- Changing the frequency preserves the existing end condition but resets its interval to 1 unless
  `--repeat-interval` is supplied.
- An end-only edit copies the complete EventKit rule so provider-specific calendar metadata is
  preserved as well.
- Plain output shows the days as `(repeats: weekly on Mon, Wed, Fri)`.
- JSON output includes `recurrence`, `recurrenceInterval`, `recurrenceDays` (lowercase
  three-letter names in Sunday-first order, e.g. `["mon","wed","fri"]`, omitted when the rule has
  no days), and either `recurrenceEnd` or
  `recurrenceCount` (when an existing rule is count-based) for repeating reminders, plus a
  `hasRecurrence` boolean on every reminder (so scripts can check it without testing for a
  missing or `null` field) and, where computable, a `nextDueDate`.

**Known behavior:** EventKit does not advance a repeating reminder's due date as occurrences pass.

- Once the due date is in the past, `dueDate`/`dueDateComponents` stay at whatever they were last
  set to (observed directly against Reminders.app; this isn't otherwise documented by Apple), and
  the reminder can end up showing arbitrarily overdue instead of jumping to the next occurrence.
- Use the `nextDueDate` JSON field if you need the next actionable occurrence instead: it's
  computed by this CLI by stepping the rule's frequency/interval forward from its due date,
  respecting `--repeat-until`/occurrence-count ends.
- Completing a repeating reminder moves it to its next occurrence and leaves a completed copy
  without a repeat rule. A completed reminder that still has a rule has run out of occurrences,
  so it has no `nextDueDate`.
- It's only populated for the rules this CLI itself creates and edits: plain
  daily/weekly/monthly/yearly (+ interval) rules and weekly rules on days (`--repeat-on`), where
  the interval counts weeks from the due date's week. A rule with other EventKit-native selectors
  such as "the last Friday of every month" (only reachable by editing a rule this CLI didn't
  create) omits the field rather than guess.

### Show reminders due on or by a date

```console
$ reminders show-all --due-date today
B3D8E2A1-9F4C-4D7B-8A21-5C6E9F0A1B2C: Contribute to open source (in 3 hours)

$ reminders show-all --due-date today --include-overdue
44C111DE-0B69-4E96-8C93-6A5D0A6C2A17: Ship reminders-cli (2 days ago)
B3D8E2A1-9F4C-4D7B-8A21-5C6E9F0A1B2C: Contribute to open source (in 3 hours)

$ reminders show-all --due-date 2025-02-16
B3D8E2A1-9F4C-4D7B-8A21-5C6E9F0A1B2C: Contribute to open source (in 3 hours)

$ reminders show Soon --due-date today --include-overdue
44C111DE-0B69-4E96-8C93-6A5D0A6C2A17: Ship reminders-cli (2 days ago)
B3D8E2A1-9F4C-4D7B-8A21-5C6E9F0A1B2C: Contribute to open source (in 3 hours)
```

The three most common views have shortcuts across all lists, sorted by due date with the earliest
first:

```console
$ reminders today
Soon: 44C111DE-0B69-4E96-8C93-6A5D0A6C2A17: Ship reminders-cli (2 days ago)
Soon: B3D8E2A1-9F4C-4D7B-8A21-5C6E9F0A1B2C: Contribute to open source (in 3 hours)

$ reminders overdue
Soon: 44C111DE-0B69-4E96-8C93-6A5D0A6C2A17: Ship reminders-cli (2 days ago)

$ reminders upcoming --days 14
Soon: B3D8E2A1-9F4C-4D7B-8A21-5C6E9F0A1B2C: Contribute to open source (in 3 hours)
Work: E6A1B5D4-3C7F-4A0E-BD54-8F9B2C3D4E5F: Renew passport (in 2 weeks)
```

| Command | Same as |
| --- | --- |
| `today` | `show-all --due-date today --include-overdue --sort due-date` |
| `today --no-overdue` | `show-all --due-date today --sort due-date` |
| `overdue` | `show-all --overdue --sort due-date` |
| `upcoming` | `show-all --due-after <current time> --due-before "in 7 days" --sort due-date` |
| `upcoming --include-overdue` | `show-all --due-before "in 7 days" --sort due-date` |

- `upcoming --days <n>` sets how many days ahead to look (default 7, at least 1), including the
  whole last day.
- All three accept `--list` (repeatable), `--format`, and `--sort`/`--sort-order` to override the
  due-date order, with the same meaning as on `show-all`. Their plain and JSON output is the same
  as `show-all`'s.

### Filter reminders

`show` and `show-all` support additional, freely combinable filters (all ANDed together, and
applied identically to `--format plain` and `--format json`):

```console
$ reminders show-all --overdue
44C111DE-0B69-4E96-8C93-6A5D0A6C2A17: Ship reminders-cli (2 days ago)

$ reminders show-all --due-before "in 7 days"
B3D8E2A1-9F4C-4D7B-8A21-5C6E9F0A1B2C: Contribute to open source (in 3 hours)

$ reminders show-all --due-after "in 7 days"
E6A1B5D4-3C7F-4A0E-BD54-8F9B2C3D4E5F: Renew passport (in 2 weeks)

$ reminders show-all --no-due-date
F7B2C6E5-4D8A-4B1F-CE65-9A0C3D4E5F60: Read a book

$ reminders show-all --priority high --priority medium
44C111DE-0B69-4E96-8C93-6A5D0A6C2A17: Ship reminders-cli (2 days ago)

$ reminders show-all --search groceries
A8C3D7F6-5E9B-4C2A-DF76-0B1D4E5F6071: Buy groceries

$ reminders show-all --flagged
44C111DE-0B69-4E96-8C93-6A5D0A6C2A17: Ship reminders-cli (2 days ago) (flagged)

$ reminders show-all --list Soon --list Work
44C111DE-0B69-4E96-8C93-6A5D0A6C2A17: Ship reminders-cli (2 days ago)
B3D8E2A1-9F4C-4D7B-8A21-5C6E9F0A1B2C: Contribute to open source (in 3 hours)

$ reminders show-all --include-completed --completed-since monday
2A29C8B1-3D0F-4A9E-9C8D-5B6E7F8A9B0C: Write README
```

- `--priority` and `--list` may be repeated to match any of several values. `--list` restricts
  which lists are searched and is only available on `show-all` (`show <list>` already targets a
  single list).
- `--due-before`/`--due-after` accept the same natural-language dates as `--due-date`. A date
  without a time includes the whole local day for `--due-before` (matching the `--repeat-until`
  behavior above), while `--due-after` uses the parsed date's own start as an inclusive lower
  bound.
- `--overdue` is independent of, and combinable with, `--due-date`/`--include-overdue`.
- `--no-due-date` cannot be combined with `--due-date`, `--due-before`, `--due-after`,
  `--overdue`, or `--include-overdue`, since those all require a due date to compare against.
- `--completed-since` accepts the same natural-language dates as `--due-date`/`--due-after`, uses
  an inclusive lower bound against each reminder's completion time, and requires
  `--only-completed` or `--include-completed`, since there's nothing to filter otherwise.
- `--flagged` shows only reminders flagged in Reminders.app. Plain output marks them with a
  `(flagged)` suffix, and JSON output has an `isFlagged` boolean on every reminder.
  - The flagged state is **read-only**: the CLI can't set or clear it yet
    ([#63](https://github.com/udondan/reminders-cli/issues/63)).
  - EventKit has no public flag property, so the CLI reads it through undocumented EventKit
    internals ([#51](https://github.com/udondan/reminders-cli/issues/51)). If a macOS version
    doesn't expose them, every reminder reads as not flagged instead of failing.

### Sort reminders

`show` and `show-all` support `--sort`, one of `none` (default), `creation-date`, `due-date`, or
`priority`, and `--sort-order`, one of `ascending` (default) or `descending`. Each reminder's ID is
always shown as the leading prefix, regardless of `--sort`, since it identifies the reminder rather
than its position in the list:

```console
$ reminders show-all --sort due-date
Soon: B3D8E2A1-9F4C-4D7B-8A21-5C6E9F0A1B2C: Contribute to open source (in 3 hours)
Work: E6A1B5D4-3C7F-4A0E-BD54-8F9B2C3D4E5F: Renew passport (in 2 weeks)
Eventually: F7B2C6E5-4D8A-4B1F-CE65-9A0C3D4E5F60: Read a book

$ reminders show-all --sort priority
Soon: 44C111DE-0B69-4E96-8C93-6A5D0A6C2A17: Ship reminders-cli (priority: high)
Work: CAE5F9B8-70BD-4E4C-FB98-2D3F60718293: Prepare slides (priority: medium)
Eventually: F7B2C6E5-4D8A-4B1F-CE65-9A0C3D4E5F60: Read a book (priority: low)
Soon: B3D8E2A1-9F4C-4D7B-8A21-5C6E9F0A1B2C: Contribute to open source (in 3 hours)

$ reminders show-all --sort priority --sort-order descending
Soon: B3D8E2A1-9F4C-4D7B-8A21-5C6E9F0A1B2C: Contribute to open source (in 3 hours)
Eventually: F7B2C6E5-4D8A-4B1F-CE65-9A0C3D4E5F60: Read a book (priority: low)
Work: CAE5F9B8-70BD-4E4C-FB98-2D3F60718293: Prepare slides (priority: medium)
Soon: 44C111DE-0B69-4E96-8C93-6A5D0A6C2A17: Ship reminders-cli (priority: high)
```

- `--sort priority` orders high before medium before low before no-priority reminders in
  ascending order (reversed for `descending`); reminders tied on priority are always broken by
  due date ascending, regardless of `--sort-order`.
- `--sort due-date` always sorts reminders with no due date to the end, in both ascending and
  descending order.

### See help for more examples

```console
reminders --help

reminders show -h
```

## Errors

Errors are always written to **stderr**, never to stdout, so `reminders ... --format json | jq`
only ever sees JSON on stdout. Every error carries a stable, machine-readable code and its own
exit status, so scripts can branch on `$?` or on the code without parsing English text.

Without `--format json`, an error is one or two human-readable lines:

```console
$ reminders show Grocery
Error: No reminders list matching 'Grocery'
Suggestion: Run 'reminders show-lists' to see available lists and their IDs
$ echo $?
2
```

With `--format json`, the same error is a single JSON object on stderr. The `suggestion` key is
omitted when there is nothing to suggest:

```console
$ reminders show Grocery --format json
{"error":{"code":"list_not_found","message":"No reminders list matching 'Grocery'","suggestion":"Run 'reminders show-lists' to see available lists and their IDs"}}
```

The codes and exit statuses are a stable contract; the `message` and `suggestion` text may change
between releases.

| Exit status | Code                 | Meaning                                                              |
| ----------- | -------------------- | -------------------------------------------------------------------- |
| `2`         | `list_not_found`     | No list matches the name, fragment, or ID, or there is no default list |
| `3`         | `list_ambiguous`     | A list name fragment is a substring of several list names            |
| `4`         | `reminder_not_found` | No reminder with the given ID or ID prefix on the given list         |
| `5`         | `reminder_ambiguous` | A reminder ID prefix matches several reminders on the list           |
| `6`         | `no_due_date`        | `postpone --next-weekday` on a reminder without a due date           |
| `7`         | `no_sources`         | `new-list` found no account that can hold reminder lists             |
| `8`         | `source_not_found`   | `new-list --source` named an account that has no reminder lists      |
| `9`         | `source_ambiguous`   | `new-list` without `--source` when several accounts hold lists       |
| `10`        | `save_failed`        | EventKit refused to save or delete                                   |
| `11`        | `access_denied`      | Reminders access was not granted to the terminal                     |
| `12`        | `invalid_argument`   | Arguments are invalid for this reminder, e.g. a repeat ending early  |

Exit status `1` is reserved for unexpected errors that don't fit any code. Usage errors (missing
arguments, unknown flags, values that can't be parsed) are reported by the argument parser in its
own format and exit with `64`.

## Installation

### With [Homebrew](http://brew.sh/)

```console
brew install udondan/software/reminders-cli
```

### From GitHub releases

Download the latest release from
[here](https://github.com/udondan/reminders-cli/releases)

```console
tar -zxvf reminders.tar.gz
mv reminders /usr/local/bin
rm reminders.tar.gz
```

### Building manually

This requires a recent Xcode installation.

```console
cd reminders-cli
make build-release
cp .build/apple/Products/Release/reminders /usr/local/bin/reminders
```

## Using with AI agents

Install the Claude Code plugin with `claude plugin marketplace add udondan/skills` followed by
`claude plugin install reminders-cli@udondan`. Other agent frameworks can load the skill file
directly from [skills/reminders-cli/SKILL.md](skills/reminders-cli/SKILL.md). Agents should always
pass `--format json` and act on reminders by their stable ID, never by title.
