import ArgumentParser
import EventKit
@testable import RemindersLibrary
import XCTest

final class PrettyOutputTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    private let plain = PrettyStyle(enabled: false)

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func jan(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        date(2024, 1, day, hour, minute)
    }

    /// 2024-01-04 09:00 UTC, a Thursday.
    private var now: Date { jan(4, 9) }

    private func row(
        _ title: String = "Task", id: String = "44C111DE", due: Date? = nil, dateOnly: Bool = false,
        completed: Date?? = nil, priority: Priority? = nil,
        recurrence: (EKRecurrenceFrequency, Int)? = nil, flagged: Bool = false, notes: String? = nil
    ) -> PrettyRow {
        PrettyRow(
            title: title, idPrefix: id, isCompleted: completed != nil, completionDate: completed ?? nil,
            dueDate: due, dueIsDateOnly: dateOnly, priority: priority,
            recurrence: recurrence.map { (frequency: $0.0, interval: $0.1) }, isFlagged: flagged,
            notes: notes)
    }

    private func due(_ row: PrettyRow, now: Date? = nil) -> String? {
        prettyDueText(for: row, now: now ?? self.now, calendar: calendar)?.text
    }

    private func render(_ groups: [PrettyGroup], verbose: Bool = false, style: PrettyStyle? = nil) -> [String] {
        formatPretty(groups, now: now, calendar: calendar, style: style ?? plain, verbose: verbose)
    }

    private func render(_ rows: [PrettyRow], verbose: Bool = false) -> [String] {
        render([PrettyGroup(title: "Soon", rows: rows)], verbose: verbose)
    }

    // MARK: Due column

    func testOverdueByDays() {
        let text = prettyDueText(for: row(due: jan(2, 10)), now: now, calendar: calendar)
        XCTAssertEqual(text?.text, "2d overdue")
        XCTAssertEqual(text?.attribute, .red)
    }

    func testOverdueEarlierToday() {
        let text = prettyDueText(for: row(due: jan(4, 6)), now: now, calendar: calendar)
        XCTAssertEqual(text?.text, "3h overdue")
        XCTAssertEqual(text?.attribute, .red)
        XCTAssertEqual(due(row(due: jan(4, 8, 35))), "25m overdue")
    }

    func testDueLaterToday() {
        let text = prettyDueText(for: row(due: jan(4, 12)), now: now, calendar: calendar)
        XCTAssertEqual(text?.text, "in 3h")
        XCTAssertEqual(text?.attribute, .yellow)
        XCTAssertEqual(due(row(due: jan(4, 9, 25))), "in 25m")
        XCTAssertEqual(due(row(due: jan(4, 9, 0))), "in 1m")
    }

    /// A date-only due date is midnight, so by `isOverdue` it has passed once the day has started.
    func testDateOnlyDueToday() {
        let text = prettyDueText(for: row(due: jan(4), dateOnly: true), now: now, calendar: calendar)
        XCTAssertEqual(text?.text, "today")
        XCTAssertEqual(text?.attribute, .red)
    }

    func testFutureDueDates() {
        XCTAssertEqual(due(row(due: jan(5, 8))), "tomorrow")
        XCTAssertEqual(due(row(due: jan(7, 8))), "in 3d")
        XCTAssertEqual(due(row(due: jan(11, 23))), "in 7d")
        XCTAssertEqual(due(row(due: jan(12, 8))), "Jan 12")
        XCTAssertEqual(due(row(due: date(2025, 1, 5))), "Jan 5 2025")
        XCTAssertEqual(prettyDueText(for: row(due: jan(7, 8)), now: now, calendar: calendar)?.attribute, .dim)
    }

    func testNoDueDate() {
        XCTAssertNil(prettyDueText(for: row(), now: now, calendar: calendar))
    }

    func testCompleted() {
        XCTAssertEqual(due(row(due: jan(2, 10), completed: jan(4, 8))), "done today")
        XCTAssertEqual(due(row(completed: jan(1, 10))), "done Mon")
        XCTAssertEqual(due(row(completed: date(2023, 12, 20))), "done Dec 20 2023")
        XCTAssertEqual(due(row(completed: date(2024, 2, 1)), now: date(2024, 3, 1)), "done Feb 1")
        XCTAssertEqual(due(row(completed: .some(nil))), "done")
        XCTAssertEqual(prettyDueText(for: row(completed: jan(1, 10)), now: now, calendar: calendar)?.attribute, .dim)
    }

    func testRecurrenceText() {
        XCTAssertEqual(prettyRecurrenceText(frequency: .daily, interval: 1), "daily")
        XCTAssertEqual(prettyRecurrenceText(frequency: .weekly, interval: 1), "weekly")
        XCTAssertEqual(prettyRecurrenceText(frequency: .weekly, interval: 2), "every 2 weeks")
        XCTAssertEqual(prettyRecurrenceText(frequency: .yearly, interval: 3), "every 3 years")
    }

    // MARK: Layout

    func testIssueExample() {
        let lines = render([
            row("Ship reminders-cli", id: "44C111DE", due: jan(2, 10), priority: .high,
                recurrence: (.weekly, 1), notes: "Remember the changelog"),
            row("Contribute to open source", id: "B3D8E2A1", due: jan(4, 12)),
            row("Read a book", id: "F7B2C6E5"),
            row("Write README", id: "2A29C8B1", completed: jan(1, 10)),
        ])
        XCTAssertEqual(lines, [
            "Soon (3 open, 1 overdue, 1 completed)",
            "─────────────────────────────────────",
            " ○ Ship reminders-cli         2d overdue  !!!  ↻ weekly  📝  44C111DE",
            " ○ Contribute to open source  in 3h                          B3D8E2A1",
            " ○ Read a book                                               F7B2C6E5",
            " ✓ Write README               done Mon                       2A29C8B1",
        ])
    }

    func testEmptyColumnsAreOmitted() {
        XCTAssertEqual(render([row("Read a book", id: "F7B2C6E5")]), [
            "Soon (1 open)",
            "─────────────",
            " ○ Read a book  F7B2C6E5",
        ])
    }

    func testPriorities() {
        XCTAssertEqual(render([
            row("a", id: "1", priority: .low), row("b", id: "2", priority: .medium),
            row("c", id: "3", priority: .high),
        ]).dropFirst(2), [
            " ○ a  !    1",
            " ○ b  !!   2",
            " ○ c  !!!  3",
        ])
    }

    func testRecurringAndFlagged() {
        XCTAssertEqual(render([
            row("a", id: "1", recurrence: (.monthly, 2), flagged: true), row("b", id: "2"),
        ]).dropFirst(2), [
            " ○ a  ↻ every 2 months  ⚑  1",
            " ○ b                       2",
        ])
    }

    func testLongTitleIsTruncated() {
        let title = String(repeating: "x", count: 50)
        XCTAssertEqual(render([row(title, id: "1")]).last,
                       " ○ " + String(repeating: "x", count: 39) + "…  1")
    }

    func testWideCharactersAlign() {
        XCTAssertEqual(render([row("日本", id: "1"), row("abcd", id: "2")]).dropFirst(2), [
            " ○ 日本  1",
            " ○ abcd  2",
        ])
    }

    func testVerboseShowsNotesExcerptUnderTitle() {
        let lines = render([
            row("a", id: "1", notes: "Line one\n  line two"),
            row("b", id: "2", notes: String(repeating: "n", count: 80)),
            row("c", id: "3"),
        ], verbose: true)
        XCTAssertEqual(lines.dropFirst(2), [
            " ○ a  1",
            "   Line one line two",
            " ○ b  2",
            "   " + String(repeating: "n", count: 60) + "…",
            " ○ c  3",
        ])
    }

    func testWithoutVerboseNotesAreAMarker() {
        XCTAssertEqual(render([row("a", id: "1", notes: "Some notes")]).last, " ○ a  📝  1")
    }

    func testGroupsShareColumnWidths() {
        let lines = render([
            PrettyGroup(title: "Home", rows: [row("Short", id: "1", due: jan(7, 8))]),
            PrettyGroup(title: "Work", rows: [row("A much longer title", id: "2")]),
        ])
        XCTAssertEqual(lines, [
            "Home (1 open)",
            "─────────────",
            " ○ Short                in 3d  1",
            "",
            "Work (1 open)",
            "─────────────",
            " ○ A much longer title         2",
        ])
    }

    func testEmptyOutput() {
        XCTAssertEqual(render([] as [PrettyGroup]), ["No reminders"])
        XCTAssertEqual(render([PrettyGroup(title: "Work", rows: [])]), [
            "Work (0 open)",
            "─────────────",
            " No reminders",
        ])
    }

    func testColours() {
        let style = PrettyStyle(enabled: true)
        let lines = render(
            [PrettyGroup(title: "Soon", rows: [
                row("a", id: "1", due: jan(2, 10)), row("b", id: "2", completed: jan(4, 8)),
            ])],
            style: style)
        XCTAssertEqual(lines, [
            "\u{1B}[1mSoon (1 open, 1 overdue, 1 completed)\u{1B}[0m",
            "─────────────────────────────────────",
            " ○ a  \u{1B}[31m2d overdue\u{1B}[0m  \u{1B}[2m1\u{1B}[0m",
            " \u{1B}[32m✓\u{1B}[0m \u{1B}[2mb\u{1B}[0m  \u{1B}[2mdone today\u{1B}[0m  \u{1B}[2m2\u{1B}[0m",
        ])
    }

    func testColorEnabled() {
        XCTAssertTrue(PrettyStyle.colorEnabled(isTTY: true, environment: [:]))
        XCTAssertTrue(PrettyStyle.colorEnabled(isTTY: true, environment: ["NO_COLOR": ""]))
        XCTAssertFalse(PrettyStyle.colorEnabled(isTTY: false, environment: [:]))
        XCTAssertFalse(PrettyStyle.colorEnabled(isTTY: true, environment: ["NO_COLOR": "1"]))
        XCTAssertFalse(PrettyStyle.colorEnabled(isTTY: true, environment: ["TERM": "dumb"]))
    }

    func testDisplayWidth() {
        XCTAssertEqual(displayWidth("abc"), 3)
        XCTAssertEqual(displayWidth("📝"), 2)
        XCTAssertEqual(displayWidth("日本"), 4)
        XCTAssertEqual(displayWidth("↻ ⚑"), 3)
    }

    // MARK: Plain output

    /// `pretty` must not change the plain format scripts parse.
    func testPlainOutputIsUnchanged() {
        let store = EKEventStore()
        let reminder = EKReminder(eventStore: store)
        reminder.title = "Ship reminders-cli"
        reminder.notes = "Remember the changelog"
        reminder.priority = Int(EKReminderPriority.high.rawValue)
        reminder.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .weekly, interval: 2, end: nil))
        let id = "44C111DE-0B69-4E96-8C93-6A5D0A6C2A17"
        XCTAssertEqual(
            format(reminder, id: id),
            "44C111DE-0B69-4E96-8C93-6A5D0A6C2A17: Ship reminders-cli (Remember the changelog) (priority: high) (repeats: weekly, interval: 2)")
        XCTAssertEqual(
            format(reminder, id: id, listName: "Soon"),
            "Soon: 44C111DE-0B69-4E96-8C93-6A5D0A6C2A17: Ship reminders-cli (Remember the changelog) (priority: high) (repeats: weekly, interval: 2)")
    }

    private func plainReminder(_ title: String) -> EKReminder {
        let reminder = EKReminder(eventStore: EKEventStore())
        reminder.title = title
        return reminder
    }

    func testPlainOutputOfWeeklyDaysAndEndDate() throws {
        let reminder = plainReminder("Standup")
        // The end date is printed as a local day, so it's built in the local calendar.
        let until = try XCTUnwrap(
            recurrenceEndDate(from: DateComponents(calendar: .current, year: 2026, month: 12, day: 31)))
        reminder.addRecurrenceRule(
            Recurrence.weekly.recurrenceRule(
                interval: 1, end: EKRecurrenceEnd(end: until), days: try RepeatDays(parsing: "wed,mon")))
        XCTAssertEqual(format(reminder, id: "1"), "1: Standup (repeats: weekly on Mon, Wed, until: 2026-12-31)")
    }

    func testPlainOutputOfOccurrenceCount() {
        let reminder = plainReminder("Medicine")
        reminder.addRecurrenceRule(
            Recurrence.daily.recurrenceRule(interval: 3, end: EKRecurrenceEnd(occurrenceCount: 10)))
        XCTAssertEqual(format(reminder, id: "1"), "1: Medicine (repeats: daily, interval: 3, count: 10)")
    }

    func testPlainOutputOmitsEmptyNotes() {
        let reminder = plainReminder("Read a book")
        reminder.notes = ""
        XCTAssertEqual(format(reminder, id: "1"), "1: Read a book")
    }
}

final class ListingFormatTests: XCTestCase {
    func testDefaultIsPlain() throws {
        XCTAssertEqual(try ListingFormat.resolve(explicit: nil, environment: [:]), .plain)
        XCTAssertEqual(try ListingFormat.resolve(explicit: nil, environment: ["REMINDERS_FORMAT": ""]), .plain)
    }

    func testEnvironmentSetsDefault() throws {
        XCTAssertEqual(try ListingFormat.resolve(explicit: nil, environment: ["REMINDERS_FORMAT": "pretty"]), .pretty)
        XCTAssertEqual(try ListingFormat.resolve(explicit: nil, environment: ["REMINDERS_FORMAT": "json"]), .json)
    }

    func testExplicitFormatWins() throws {
        XCTAssertEqual(try ListingFormat.resolve(explicit: .json, environment: ["REMINDERS_FORMAT": "pretty"]), .json)
        XCTAssertEqual(try ListingFormat.resolve(explicit: .plain, environment: ["REMINDERS_FORMAT": "bogus"]), .plain)
    }

    func testInvalidEnvironmentValueIsRejected() {
        XCTAssertThrowsError(try ListingFormat.resolve(explicit: nil, environment: ["REMINDERS_FORMAT": "yaml"])) {
            XCTAssertEqual(
                ($0 as? ValidationError)?.message,
                "REMINDERS_FORMAT must be one of 'plain', 'json' or 'pretty', got 'yaml'")
        }
    }

    func testErrorsRenderAsPlainForPretty() {
        XCTAssertEqual(ListingFormat.pretty.errorFormat, .plain)
        XCTAssertEqual(ListingFormat.plain.errorFormat, .plain)
        XCTAssertEqual(ListingFormat.json.errorFormat, .json)
    }

    // Only parsed, never run, so nothing reads the machine's real reminders.

    func testVerboseRequiresPretty() {
        let list = UUID().uuidString
        assertParseError(["show", list, "--verbose"], contains: "--verbose requires --format pretty")
        assertParseError(["show-all", "--format", "json", "-v"], contains: "--verbose requires --format pretty")
        XCTAssertNoThrow(try CLI.parseAsRoot(["show", list, "--format", "pretty", "--verbose"]))
        XCTAssertNoThrow(try CLI.parseAsRoot(["today", "-f", "pretty", "-v"]))
    }

    func testPrettyIsOnlyAcceptedByListings() {
        for command in [["show", "x"], ["show-all"], ["today"], ["overdue"], ["upcoming"]] {
            XCTAssertNoThrow(try CLI.parseAsRoot(command + ["--format", "pretty"]), "\(command)")
        }
        assertParseError(["add", "x", "y", "--format", "pretty"], contains: "The value 'pretty' is invalid for '--format <format>'")
        assertParseError(["show-lists", "--format", "pretty"], contains: "The value 'pretty' is invalid for '--format <format>'")
    }

    func testListingCommandsReportErrorsInResolvedFormat() throws {
        let list = UUID().uuidString
        guard case .failed(let error, let format) = try CLI.runCommand(["show", list, "--format", "pretty"]) else {
            return XCTFail("expected a failure")
        }
        XCTAssertEqual(error.code, .listNotFound)
        XCTAssertEqual(format, .plain)
    }
}

/// The mapping from an `EKReminder` to the row `pretty` output renders.
final class PrettyRowTests: InMemoryReminderTestCase {
    func testMapsTheReminder() throws {
        let reminder = makeReminder()
        reminder.notes = "Balcony too"
        reminder.priority = Int(EKReminderPriority.high.rawValue)
        reminder.dueDateComponents = due(2026, 9, 20, hour: 8)
        reminder.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .weekly, interval: 2, end: nil))

        let row = PrettyRow(reminder)

        XCTAssertEqual(row.title, "Water plants")
        let id = reminder.calendarItemExternalIdentifier ?? "<unknown-id>"
        XCTAssertEqual(row.idPrefix, String(id.prefix(PrettyRow.idPrefixLength)))
        XCTAssertEqual(row.idPrefix.count, PrettyRow.idPrefixLength)
        XCTAssertFalse(row.isCompleted)
        XCTAssertNil(row.completionDate)
        XCTAssertEqual(row.dueDate, date(2026, 9, 20, 8))
        XCTAssertFalse(row.dueIsDateOnly)
        XCTAssertEqual(row.priority, .high)
        XCTAssertEqual(row.recurrence?.frequency, .weekly)
        XCTAssertEqual(row.recurrence?.interval, 2)
        XCTAssertFalse(row.isFlagged)
        XCTAssertEqual(row.notes, "Balcony too")
    }

    func testDateOnlyDueDateAndCompletion() throws {
        let reminder = makeReminder()
        reminder.dueDateComponents = due(2026, 9, 20)
        reminder.completionDate = date(2026, 9, 19, 17)

        let row = PrettyRow(reminder)

        XCTAssertEqual(row.dueDate, date(2026, 9, 20))
        XCTAssertTrue(row.dueIsDateOnly)
        XCTAssertTrue(row.isCompleted)
        XCTAssertEqual(row.completionDate, date(2026, 9, 19, 17))
    }

    func testAbsentFieldsAreNil() throws {
        let reminder = makeReminder()
        reminder.notes = ""

        let row = PrettyRow(reminder)

        XCTAssertNil(row.dueDate)
        XCTAssertFalse(row.dueIsDateOnly)
        XCTAssertNil(row.priority)
        XCTAssertNil(row.recurrence)
        XCTAssertNil(row.notes)
    }
}
