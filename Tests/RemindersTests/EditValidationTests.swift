@testable import RemindersLibrary
import XCTest

final class EditValidationTests: XCTestCase {
    private let base = ["edit", "Soon", "2A29C8B1-3D0F-4A9E-9C8D-5B6E7F8A9B0C"]

    func testClearNotesAloneIsAValidEdit() throws {
        XCTAssertNoThrow(try CLI.parseAsRoot(base + ["--clear-notes"]))
    }

    func testClearNotesConflictsWithNotes() throws {
        assertParseError(
            base + ["--notes", "x", "--clear-notes"], contains: "Cannot specify both --notes and --clear-notes")
    }

    func testEmptyNotesAsSeparateArgumentParses() throws {
        XCTAssertNoThrow(try CLI.parseAsRoot(base + ["--notes", ""]))
    }

    func testEditWithoutAnyChangeIsRejected() throws {
        assertParseError(base, contains: "Must specify new reminder content, a notes change")
    }

    func testBatchEditOfOtherFieldsParses() throws {
        XCTAssertNoThrow(try CLI.parseAsRoot(["edit", "Soon", "855B,91F4", "--priority", "high"]))
        XCTAssertNoThrow(try CLI.parseAsRoot(["edit", "Soon", "-", "--clear-due-date"]))
    }

    func testNewTextOnSeveralRemindersIsRejected() throws {
        let message = "New reminder text can only be set on one reminder at a time"
        assertParseError(["edit", "Soon", "855B,91F4", "New", "title"], contains: message)
        assertParseError(["edit", "Soon", "-", "New title"], contains: message)
    }

    func testDueDateConflictsWithClearDueDate() throws {
        assertParseError(
            base + ["--due-date", "2026-09-10", "--clear-due-date"],
            contains: "Cannot specify both --due-date and --clear-due-date")
    }

    func testPriorityConflictsWithClearPriority() throws {
        assertParseError(
            base + ["--priority", "high", "--clear-priority"],
            contains: "Cannot specify both --priority and --clear-priority")
    }

    func testEachSingleChangeIsAValidEdit() throws {
        let changes: [[String]] = [
            ["New", "title"],
            ["--notes", "x"],
            ["--notes", "- [ ] x"],
            ["--due-date", "2026-09-10"],
            ["--clear-due-date"],
            ["--priority", "low"],
            ["--clear-priority"],
            ["--list", "Other"],
            ["--repeat", "daily"],
            ["--repeat-interval", "2"],
            ["--repeat-until", "2026-12-31"],
            ["--clear-repeat-end"],
            ["--repeat-on", "mon"],
            ["--clear-repeat-on"],
            ["--clear-repeat"],
        ]
        for change in changes {
            XCTAssertNoThrow(try CLI.parseAsRoot(base + change), "\(change)")
        }
    }
}

/// The `postpone` rule that exactly one of a new date or `--next-weekday` is given.
final class PostponeValidationTests: XCTestCase {
    private let base = ["postpone", "Soon", "2A29C8B1-3D0F-4A9E-9C8D-5B6E7F8A9B0C"]

    func testDateAndNextWeekdayConflict() throws {
        assertParseError(
            base + ["2026-09-10", "--next-weekday"],
            contains: "Cannot specify both a new due date and --next-weekday")
    }

    func testDateOrNextWeekdayIsRequired() throws {
        assertParseError(base, contains: "Must specify either a new due date or --next-weekday")
    }

    func testEitherAloneIsAccepted() throws {
        XCTAssertNoThrow(try CLI.parseAsRoot(base + ["2026-09-10"]))
        XCTAssertNoThrow(try CLI.parseAsRoot(base + ["--next-weekday"]))
    }
}
