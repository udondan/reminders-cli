@testable import RemindersLibrary
import XCTest

/// The option combinations `show` and `show-all` reject. Only parsed, never run, so nothing reads
/// the machine's real reminders; `show`'s list argument is a random name for the same reason.
final class ListingValidationTests: XCTestCase {
    private var listings: [[String]] {
        [["show", UUID().uuidString], ["show-all"]]
    }

    func testOnlyCompletedConflictsWithIncludeCompleted() {
        for command in listings {
            assertParseError(
                command + ["--only-completed", "--include-completed"],
                contains: "Cannot specify both --include-completed and --only-completed")
        }
    }

    func testNoDueDateConflictsWithEveryDueDateFilter() {
        let conflicting: [[String]] = [
            ["--due-date", "2026-09-10"],
            ["--due-before", "2026-09-10"],
            ["--due-after", "2026-09-10"],
            ["--overdue"],
            ["--include-overdue"],
        ]
        for command in listings {
            for options in conflicting {
                assertParseError(
                    command + ["--no-due-date"] + options,
                    contains: "Cannot combine --no-due-date with --due-date")
            }
        }
    }

    func testCompletedSinceRequiresACompletedFlag() {
        for command in listings {
            assertParseError(
                command + ["--completed-since", "2026-09-01"],
                contains: "--completed-since requires --only-completed or --include-completed")
            XCTAssertNoThrow(
                try CLI.parseAsRoot(command + ["--completed-since", "2026-09-01", "--only-completed"]))
            XCTAssertNoThrow(
                try CLI.parseAsRoot(command + ["--completed-since", "2026-09-01", "--include-completed"]))
        }
    }

    func testNoDueDateAloneIsAccepted() {
        for command in listings {
            XCTAssertNoThrow(try CLI.parseAsRoot(command + ["--no-due-date"]))
        }
    }
}
