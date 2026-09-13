# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`reminders-cli` is a macOS command-line tool for interacting with Reminders.app via EventKit, built with Swift Package Manager and Apple's `swift-argument-parser`.

## Commands

- Build (debug): `swift build`
- Build matching CI exactly: `swift build -Xswiftc -warnings-as-errors`
- Run all tests: `swift test` (or `swift test -Xswiftc -warnings-as-errors` to match CI)
- Run a single test: `swift test --filter RemindersTests.NaturalLanguageTests/testTomorrow` (filter format is `<Target>.<TestCase>/<testMethod>`, method optional)
- Release build (universal arm64/x86_64 binary): `make build-release`
- Full release package (tarball + shasums, as used for GitHub releases): `make package`
- Clean build artifacts: `make clean`
- Run locally without installing: `swift run reminders <subcommand> ...`

There is no linter configured (no SwiftLint/SwiftFormat) — code quality is enforced only via `-warnings-as-errors` on both library targets, applied both in `Package.swift` and again explicitly in CI.

## Architecture

Execution flows in one direction through four layers:

1. **`Sources/reminders/main.swift`** — entry point. Requests Reminders access via EventKit (branches on macOS 14+ `requestFullAccessToReminders` vs. the older `requestAccess(to:)`), then hands off to `CLI.main()`.
2. **`Sources/RemindersLibrary/CLI.swift`** — the `CLI: ParsableCommand` root (command name `reminders`) and one private `ParsableCommand` struct per subcommand (`ShowLists`, `ShowAll`, `Show`, `Add`, `Complete`, `Uncomplete`, `Delete`, `Edit`, `NewList`). Each subcommand only declares its `@Argument`/`@Option`/`@Flag` properties and a thin `run()` that delegates to a single shared `Reminders()` instance. Shell-completion for list names is wired up here via `listNameCompletion(_:_:_:)`.
3. **`Sources/RemindersLibrary/Reminders.swift`** — all actual business logic, wrapping `EKEventStore`/`EKReminder`/`EKCalendar`. Every subcommand's real behavior (list/show, add, edit, complete/uncomplete, delete, new list) lives here, along with `OutputFormat`, `DisplayOptions`, and `Priority`. Since EventKit's APIs are callback-based, `DispatchSemaphore` is used to make them synchronous for the CLI.
4. **Supporting extensions**, used by the layers above:
   - `NaturalLanguage.swift` — `DateComponents(argument:)` (`ExpressibleByArgument`), parses natural-language date strings like `"tomorrow 9am"` for `--due-date` options via `NSDataDetector`. Known limitation: `"next weekend"` doesn't parse (Apple Feedback FB8921206), covered by a test expecting `nil`.
   - `Sort.swift` — `Sort`/`CustomSortOrder` enums backing `show --sort`/`--sort-order`.
   - `EKReminder+Encodable.swift` — manual `Encodable` conformance for `EKReminder`, used for `--format json` output.

When adding a new subcommand: add a `ParsableCommand` struct in `CLI.swift`, register it in `CLI`'s `subcommands`, and implement the actual behavior as a method on `Reminders` in `Reminders.swift` — keep `CLI.swift` limited to argument parsing/dispatch.

Reminder items are looked up only by their stable `calendarItemExternalIdentifier` (never by list position) via `Reminders.getReminder(from:withId:)`, exercised directly in `Tests/RemindersTests/IdentifierTests.swift` (via `@testable import RemindersLibrary`) alongside `Tests/RemindersTests/NaturalLanguageTests.swift`'s natural-language date parsing tests.

## Release process

Releases are automated via [release-please](https://github.com/googleapis/release-please): merges to `main` accumulate into a release PR (version bump driven by Conventional Commits, tracked in `version.txt`/`.release-please-manifest.json`/`release-please-config.json`), and merging that PR tags the commit and creates a **draft** GitHub Release. The same `release-please.yml` run then calls `.github/workflows/publish.yml` as a reusable workflow, which checks out the release commit, runs `make package` to build the universal release binary/tarball, attaches `reminders.tar.gz` to the draft, publishes the release, and pushes an updated formula to the `udondan/homebrew-software` tap (`brew install udondan/software/reminders-cli`).

The release must stay a draft until the tarball is attached: this repository has GitHub's immutable releases enabled, so assets cannot be added to a release after it is published, and the tag name of a published release can never be reused. Draft releases do not trigger `release` workflow events, which is why publishing is chained from the release-please workflow instead of listening for a release event. `force-tag-creation` must stay enabled together with `draft`: a draft release has no tag, and without the tag release-please cannot find the release it just created, treats the repository as unreleased, and opens another release PR for the same version on every run. If the publish job fails, leave the draft in place and re-run `publish.yml` via `workflow_dispatch` with the draft's tag and the release commit; re-running release-please does not recreate an existing release.

The CLI's `--version` output is backed by `Sources/RemindersLibrary/Version.swift`, which release-please keeps in sync with `version.txt` via an `extra-files` generic updater — don't hand-edit the version in either file outside of a release-please PR.
