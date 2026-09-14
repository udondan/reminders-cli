---
name: reminders-cli
description: Read, add, edit, complete and delete macOS Reminders from the command line. Use when the user asks about their reminders, to-dos, or tasks on a Mac.
allowed-tools: Bash(reminders:*)
---

# reminders-cli

`reminders` is a macOS command-line tool that talks to Reminders.app through EventKit.

## Invocation

- The binary is `reminders` and must be on `PATH`. Install with `brew install udondan/software/reminders-cli`.
- The terminal application running the command needs Reminders access (System Settings > Privacy & Security > Reminders). Without it every command fails with exit status 11.
- Output goes to stdout. Errors go to stderr only, with a stable code and exit status (see Errors).

## Rules for agents

1. **Always pass `--format json`.** Every subcommand supports it. Parse the output instead of the plain-text format.
2. **Always act on reminders by ID.** Every reminder has a stable `externalId`. Look it up with `show` or `show-all`, then pass it to `edit`, `complete`, `uncomplete`, `postpone` and `delete`. Never match reminders by title.
3. Wherever a `<list>` argument is accepted, either the list name or its `calendarIdentifier` (from `show-lists --format json`) works. Prefer the ID when the name is ambiguous or contains shell-unfriendly characters.
4. `show`, `show-all`, `today`, `overdue`, `upcoming` and `show-lists` print a JSON array. `add`, `edit`, `complete`, `uncomplete`, `postpone` and `delete` print the affected reminder as a single JSON object (for `delete`, the reminder as it was before removal). `new-list` prints the created list. Keys are sorted alphabetically.
5. Reminder text and notes are passed as trailing positional arguments and may contain spaces; quote them.
6. `delete` finds a reminder by ID regardless of completion state, so completed reminders need no special handling.

## Commands

| Command | Arguments and options |
| --- | --- |
| `reminders show-lists` | Lists with their open and overdue reminder counts. `--default-only`/`-d` (only the list Reminders.app adds to by default), `--include-completed` (also count completed reminders, slower), `--sort`/`-s <none\|name\|open\|overdue>` |
| `reminders show <list>` | Reminders on one list. Filters: `--only-completed`, `--include-completed`, `--include-overdue` (with `--due-date`, also include items due before that date), `--due-date`/`-d <date>`, `--overdue`, `--due-before <date>`, `--due-after <date>`, `--no-due-date`, `--priority <none\|low\|medium\|high>` (repeatable), `--search <text>` (case-insensitive, matches title or notes), `--flagged`, `--completed-since <date>`. Sorting: `--sort`/`-s <none\|creation-date\|due-date\|priority>`, `--sort-order`/`-o <ascending\|descending>` |
| `reminders show-all` | Reminders across all lists. Same filters and sorting as `show`, plus `--list <list>` (repeatable) to restrict to some lists |
| `reminders today` | Incomplete reminders due today plus overdue ones, across all lists. `--no-overdue` (only due today), `--list <list>` (repeatable), `--sort`/`--sort-order` (default due date ascending) |
| `reminders overdue` | Incomplete reminders whose due date has passed. `--list <list>` (repeatable), `--sort`/`--sort-order` (default due date ascending) |
| `reminders upcoming` | Incomplete reminders due from now through the end of the day N days ahead. `--days <n>` (default 7), `--include-overdue` (also past-due ones), `--list <list>` (repeatable), `--sort`/`--sort-order` (default due date ascending) |
| `reminders add <list> <text...>` | `--due-date`/`-d <date>`, `--priority`/`-p <none\|low\|medium\|high>`, `--notes`/`-n <text>`, `--repeat <daily\|weekly\|monthly\|yearly>`, `--repeat-interval <n>`, `--repeat-until <date>` |
| `reminders edit <list> <id> [new text...]` | `--due-date`/`-d <date>`, `--clear-due-date`, `--priority`/`-p <value>`, `--clear-priority`, `--notes`/`-n <text>` (overwrites), `--clear-notes`, `--list <list>` (move to another list), `--repeat <frequency>`, `--repeat-interval <n>`, `--repeat-until <date>`, `--clear-repeat-end` (repeat forever), `--clear-repeat` |
| `reminders complete <list> <id>` | Mark done |
| `reminders uncomplete <list> <id>` | Mark not done |
| `reminders postpone <list> <id> [date]` | Move the due date without touching the repeat rule. Pass either a `date` or `--next-weekday` (next Mon-Fri, keeps the time of day, requires an existing due date) |
| `reminders delete <list> <id>` | Delete the reminder |
| `reminders new-list <name>` | `--source`/`-s <name>` (account to create the list in, e.g. iCloud; required only when several accounts hold lists) |

All commands also accept `--format`/`-f <plain|json>`.

Constraints enforced by the CLI (violations are usage errors, exit status 64):

- `show`/`show-all`: `--only-completed` and `--include-completed` are exclusive. `--no-due-date` cannot be combined with `--due-date`, `--due-before`, `--due-after`, `--overdue` or `--include-overdue`. `--completed-since` requires `--only-completed` or `--include-completed`. `--list` exists only on `show-all`. `--flagged` combines with every other filter.
- Flagged state is read-only. `add` and `edit` have no flag options, so tell the user to flag or unflag in Reminders.app.
- `add`: `--repeat` requires `--due-date`. `--repeat-interval` and `--repeat-until` require `--repeat`. `--repeat-interval` must be at least 1. `--repeat-until` must not be earlier than `--due-date`. `hourly` is rejected because EventKit reminders have no hourly frequency.
- `edit`: at least one change is required. `--due-date`/`--clear-due-date`, `--priority`/`--clear-priority` and `--notes`/`--clear-notes` are pairwise exclusive. `--clear-repeat` cannot be combined with other repeat options. Changing only the interval or end keeps the existing frequency. Changing the frequency resets the interval to 1 unless `--repeat-interval` is given.
- `postpone`: exactly one of `date` or `--next-weekday`.
- `upcoming`: `--days` must be at least 1.
- `--sort priority` orders high, medium, low, then none, with due date ascending as the tiebreaker. `--sort due-date` always puts reminders without a due date last.
- `show-lists --sort name` is ascending and case-insensitive; `--sort open` and `--sort overdue` are descending (busiest list first) with the name as the tiebreaker. `show-lists` has no `--sort-order`.

## JSON fields of a reminder

All dates are ISO 8601 strings in UTC (for example `2026-09-14T07:00:00Z`). Fields marked optional are omitted from the object when they do not apply.

<!-- json-fields:start -->
| Field | Type | Present | Meaning |
| --- | --- | --- | --- |
| `externalId` | string | always | Stable identifier. Use it for `edit`, `complete`, `uncomplete`, `postpone` and `delete`. |
| `lastModified` | string | optional | Last modification time. |
| `creationDate` | string | optional | Creation time. |
| `title` | string | always | Reminder text. |
| `notes` | string | optional | Notes. Omitted when empty. |
| `url` | string | never | Reserved. EventKit never returns a URL for reminders, so the key is absent in practice. |
| `location` | string | optional | `"latitude, longitude"` of a location-based alarm. |
| `locationTitle` | string | optional | Title of a location-based alarm. |
| `completionDate` | string or null | always | Completion time, `null` while incomplete. |
| `isCompleted` | boolean | always | Whether the reminder is done. |
| `priority` | integer | always | EventKit priority: `0` none, `1` high, `5` medium, `9` low. |
| `startDate` | string | optional | Start date, if set. |
| `dueDate` | string | optional | Due date. For repeating reminders this is the date last set, not the next occurrence (see below). |
| `list` | string | always | Name of the list containing the reminder. |
| `listId` | string | always | `calendarIdentifier` of that list. |
| `recurrence` | string | optional | `daily`, `weekly`, `monthly` or `yearly`. Only present when `hasRecurrence` is true. |
| `recurrenceInterval` | integer | optional | Repeat every N units of `recurrence`. Only present when `hasRecurrence` is true. |
| `recurrenceEnd` | string | optional | Date the repeat rule ends. Only for date-ended rules. |
| `recurrenceCount` | integer | optional | Number of occurrences. Only for count-ended rules (created by Reminders.app, not by this CLI). |
| `hasRecurrence` | boolean | always | Whether a repeat rule is set. |
| `isFlagged` | boolean | always | Whether the reminder is flagged. Read-only: no command can set or clear it. Reads `false` on macOS versions that don't expose the flag. |
| `nextDueDate` | string | optional | Next actionable occurrence of a repeating reminder, computed by the CLI. Only present when `hasRecurrence` is true, `isCompleted` is false and the rule is a plain daily/weekly/monthly/yearly (+ interval) rule. |
<!-- json-fields:end -->

`show-lists --format json` returns list objects with `title`, `calendarIdentifier`, `openCount` (reminders that are not completed) and `overdueCount` (of those, the ones whose due date has passed — the same definition as `show --overdue`). `completedCount` is present only with `--include-completed`. `new-list --format json` returns a list object with `title` and `calendarIdentifier` only.

## Errors

Errors never appear on stdout. With `--format json` an error is one JSON object on stderr, `{"error":{"code":"...","message":"...","suggestion":"..."}}` (`suggestion` omitted when there is none). The `code` and the exit status are a stable contract; `message` and `suggestion` may change.

| Exit | Code | Meaning |
| --- | --- | --- |
| 2 | `list_not_found` | No list matches the name or ID, or no default list exists |
| 4 | `reminder_not_found` | No reminder with that ID on that list |
| 6 | `no_due_date` | `postpone --next-weekday` on a reminder without a due date |
| 7 | `no_sources` | `new-list` found no account that can hold lists |
| 8 | `source_not_found` | `new-list --source` named an account without reminder lists |
| 9 | `source_ambiguous` | `new-list` without `--source` while several accounts hold lists |
| 10 | `save_failed` | EventKit refused to save or delete |
| 11 | `access_denied` | Reminders access not granted to the terminal |
| 12 | `invalid_argument` | Arguments invalid for this reminder, e.g. a repeat ending before the due date |
| 64 | (usage) | Argument-parser error: missing arguments, unknown flags, unparseable dates. Reported in ArgumentParser's own text format |
| 1 | (unexpected) | Anything else |

Exit statuses 3 (`list_ambiguous`) and 5 (`reminder_ambiguous`) are reserved and not produced yet.

## Repeating reminders

EventKit does not advance a repeating reminder's due date as occurrences pass. `dueDate` stays at whatever it was last set to and can be arbitrarily far in the past. When you need the next occurrence, read `nextDueDate`. It is absent for rules with EventKit-native selectors such as "the last Friday of every month", which this CLI cannot create; in that case fall back to `dueDate` and say so.

To move a repeating reminder forward without changing its rule, use `postpone`.

## Dates

`--due-date`, `--due-before`, `--due-after`, `--completed-since`, `--repeat-until` and the `postpone` date accept natural language, parsed by Apple's data detector. Known to work:

- `today`, `tomorrow`, `yesterday`, `tonight`
- `12:00`, `tomorrow 9pm`, `on monday at 9pm`
- `in 2 days`, `in 7 days`
- `next monday`, `next saturday`
- ISO dates such as `2026-09-01`

Known limitation: `next weekend` does not parse (Apple Feedback FB8921206). Use a concrete weekday instead.

A date without a time covers the whole local day for `--due-before` and `--repeat-until`. `--due-after` uses the parsed date's start as an inclusive lower bound. An unparseable date is a usage error (exit status 64). Prefer ISO dates when you already know the exact day.
