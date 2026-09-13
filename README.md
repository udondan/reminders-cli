# reminders-cli

A simple CLI for interacting with OS X reminders.

## Usage:

#### Show all lists

```
$ reminders show-lists
Soon
Eventually
```

#### Show reminders on a specific list

```
$ reminders show Soon
0 Write README
1 Ship reminders-cli
```

#### Complete an item on a list

```
$ reminders complete Soon 0
Completed 'Write README'
$ reminders show Soon
0 Ship reminders-cli
```

#### Undo a completed item

```
$ reminders show Soon --only-completed
0 Write README
$ reminders uncomplete Soon 0
Uncompleted 'Write README'
$ reminders show Soon
0 Write README
```

#### Edit an item on a list

```
$ reminders edit Soon 0 Some edited text
Updated reminder 'Some edited text'
$ reminders edit Soon 0 --due-date "tomorrow 9am"
Updated reminder 'Some edited text'
$ reminders edit Soon 0 --clear-due-date
Updated reminder 'Some edited text'
$ reminders show Soon
0 Ship reminders-cli
1 Some edited text
```

Set or clear a reminder's priority:

```
$ reminders edit Soon 0 --priority high
Updated reminder 'Some edited text'
$ reminders edit Soon 0 --clear-priority
Updated reminder 'Some edited text'
```

Move a reminder to a different list:

```
$ reminders edit Soon 0 --list "Some Other List"
Updated reminder 'Some edited text'
$ reminders show "Some Other List"
0 Some edited text
```

#### Delete an item on a list

```
$ reminders delete Soon 0
Completed 'Write README'
$ reminders show Soon
0 Ship reminders-cli
```

#### Add a reminder to a list

```
$ reminders add Soon Contribute to open source
$ reminders add Soon Go to the grocery store --due-date "tomorrow 9am"
$ reminders add Soon Something really important --priority high
$ reminders show Soon
0: Ship reminders-cli
1: Contribute to open source
2: Go to the grocery store (in 10 hours)
3: Something really important (priority: high)
```

#### Add a repeating reminder

```
$ reminders add Soon Weekly review --due-date "monday 9am" --repeat weekly
$ reminders add Soon Pay rent --due-date "2026-09-01" --repeat monthly --repeat-until "2027-09-01"
$ reminders add Soon Water the plants --due-date "tomorrow" --repeat daily --repeat-interval 3
```

`--repeat` accepts `daily`, `weekly`, `monthly`, or `yearly` (EventKit reminders have no hourly
recurrence frequency, so `--repeat hourly` is rejected with an explanation rather than silently
degrading to daily). `--repeat-interval` repeats every N units instead of every 1 (e.g.
`--repeat-interval 2 --repeat weekly` for every other week) and defaults to 1. Use
`--repeat-until` to stop after a date; omitting it repeats forever, matching the Reminders.app
default. A date without a time includes the whole local day. On `add`, recurrence options require
`--repeat` to also be set, and a repeating reminder requires `--due-date`.

To change or remove a repeat rule on an existing reminder, use `edit`:

```
$ reminders edit Soon 0 --repeat monthly
$ reminders edit Soon 0 --repeat-until "2027-09-01"
$ reminders edit Soon 0 --clear-repeat-end
$ reminders edit Soon 0 --clear-repeat
```

Changing only the interval or end condition preserves the existing frequency and any complex
selectors, such as "the last Friday of every month". Changing the frequency preserves the existing
end condition but resets its interval to 1 unless `--repeat-interval` is supplied. An end-only edit
copies the complete EventKit rule so provider-specific calendar metadata is preserved as well.
JSON output includes `recurrence`, `recurrenceInterval`, and either `recurrenceEnd` or
`recurrenceCount` (when an existing rule is count-based) for repeating reminders, plus a `hasRecurrence`
boolean on every reminder (so scripts can check it without testing for a missing or `null` field) and,
where computable, a `nextDueDate`.

Known behavior: EventKit does not advance a repeating reminder's due date as occurrences pass — once
the due date is in the past, `dueDate`/`dueDateComponents` stay at whatever they were last set to
(observed directly against Reminders.app; this isn't otherwise documented by Apple), and the
reminder can end up showing arbitrarily overdue instead of jumping to the next occurrence. Use the
`nextDueDate` JSON field if you need the next actionable occurrence instead: it's computed by this
CLI by stepping the rule's frequency/interval forward from its due date, respecting `--repeat-until`/
occurrence-count ends. It's only populated for the plain daily/weekly/monthly/yearly (+ interval)
rules this CLI itself creates and edits; a rule with EventKit-native selectors such as "the last
Friday of every month" (only reachable by editing a rule this CLI didn't create) omits the field
rather than guess.

#### Show reminders due on or by a date

```
$ reminders show-all --due-date today
1: Contribute to open source (in 3 hours)
$ reminders show-all --due-date today --include-overdue
0: Ship reminders-cli (2 days ago)
1: Contribute to open source (in 3 hours)
$ reminders show-all --due-date 2025-02-16
1: Contribute to open source (in 3 hours)
$ reminders show Soon --due-date today --include-overdue
0: Ship reminders-cli (2 days ago)
1: Contribute to open source (in 3 hours)
```

#### See help for more examples

```
$ reminders --help
$ reminders show -h
```

## Installation:

#### With [Homebrew](http://brew.sh/)

```
$ brew install keith/formulae/reminders-cli
```

#### From GitHub releases

Download the latest release from
[here](https://github.com/keith/reminders-cli/releases)

```
$ tar -zxvf reminders.tar.gz
$ mv reminders /usr/local/bin
$ rm reminders.tar.gz
```

#### Building manually

This requires a recent Xcode installation.

```
$ cd reminders-cli
$ make build-release
$ cp .build/apple/Products/Release/reminders /usr/local/bin/reminders
```
