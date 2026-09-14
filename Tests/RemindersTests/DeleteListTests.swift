import EventKit
@testable import RemindersLibrary
import XCTest

final class DeleteListTests: XCTestCase {
    private let store = EKEventStore()

    private func makeCalendar(title: String) -> EKCalendar {
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = title
        return calendar
    }

    private func check(
        isDefault: Bool = false, allowsModifications: Bool = true,
        reminderCount: Int = 14, completedCount: Int = 3, confirm: Bool
    ) throws {
        try checkListDeletion(
            title: "Groceries", isDefault: isDefault, allowsModifications: allowsModifications,
            reminderCount: reminderCount, completedCount: completedCount, confirm: confirm)
    }

    // MARK: - Deletion rules

    func testConfirmedDeletionOfNormalListPasses() {
        XCTAssertNoThrow(try check(confirm: true))
    }

    func testMissingConfirmRequiresConfirmation() {
        XCTAssertThrowsError(try check(confirm: false)) { error in
            XCTAssertEqual(
                error as? CLIError,
                .confirmationRequired(title: "Groceries", reminderCount: 14, completedCount: 3))
        }
    }

    func testDefaultListIsRefusedEvenWithConfirm() {
        for confirm in [true, false] {
            XCTAssertThrowsError(try check(isDefault: true, confirm: confirm)) { error in
                XCTAssertEqual((error as? CLIError)?.code, .invalidArgument, "confirm: \(confirm)")
            }
        }
    }

    func testReadOnlyListIsRefusedEvenWithConfirm() {
        for confirm in [true, false] {
            XCTAssertThrowsError(try check(allowsModifications: false, confirm: confirm)) { error in
                XCTAssertEqual((error as? CLIError)?.code, .invalidArgument, "confirm: \(confirm)")
            }
        }
    }

    // MARK: - Confirmation message

    func testConfirmationMessageCountsReminders() {
        let error = CLIError.confirmationRequired(title: "Groceries", reminderCount: 14, completedCount: 3)
        XCTAssertEqual(error.code, .confirmationRequired)
        XCTAssertEqual(
            error.message,
            "'Groceries' contains 14 reminders (3 completed). Deleting the list deletes all of them.")
        XCTAssertEqual(error.suggestion, "Re-run with --confirm to delete.")
        XCTAssertEqual(error.exitCode.rawValue, 13)
    }

    func testConfirmationMessageForSingleReminder() {
        let error = CLIError.confirmationRequired(title: "Groceries", reminderCount: 1, completedCount: 0)
        XCTAssertEqual(
            error.message, "'Groceries' contains 1 reminder (0 completed). Deleting the list deletes it too.")
    }

    func testConfirmationMessageForEmptyList() {
        let error = CLIError.confirmationRequired(title: "Groceries", reminderCount: 0, completedCount: 0)
        XCTAssertEqual(error.message, "'Groceries' contains no reminders.")
    }

    // MARK: - JSON output

    func testDeletedListEncoding() throws {
        let data = try JSONEncoder().encode(
            DeletedList(title: "Groceries", calendarIdentifier: "ABC", reminderCount: 14))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["deleted"] as? Bool, true)
        XCTAssertEqual(json["title"] as? String, "Groceries")
        XCTAssertEqual(json["calendarIdentifier"] as? String, "ABC")
        XCTAssertEqual(json["reminderCount"] as? Int, 14)
        XCTAssertEqual(json.count, 4)
    }

    // MARK: - Exact list resolution

    func testResolvesById() throws {
        let a = makeCalendar(title: "A")
        let b = makeCalendar(title: "B")
        let resolved = try resolveCalendarExactly([a, b], nameOrId: b.calendarIdentifier)
        XCTAssertEqual(resolved.calendarIdentifier, b.calendarIdentifier)
    }

    func testResolvesByExactTitle() throws {
        let lower = makeCalendar(title: "work")
        let upper = makeCalendar(title: "Work")
        let resolved = try resolveCalendarExactly([lower, upper], nameOrId: "Work")
        XCTAssertEqual(resolved.calendarIdentifier, upper.calendarIdentifier)
    }

    func testResolvesByCaseInsensitiveTitle() throws {
        let groceries = makeCalendar(title: "Groceries")
        let resolved = try resolveCalendarExactly([groceries], nameOrId: "groceries")
        XCTAssertEqual(resolved.calendarIdentifier, groceries.calendarIdentifier)
    }

    func testPartialNameIsNotFoundAndNamesTheMatch() {
        let groceries = makeCalendar(title: "Groceries")
        let work = makeCalendar(title: "Work")
        XCTAssertThrowsError(try resolveCalendarExactly([groceries, work], nameOrId: "gro")) { error in
            XCTAssertEqual(error as? CLIError, .listNotFoundExactly("gro", partialMatches: ["Groceries"]))
            XCTAssertEqual((error as? CLIError)?.code, .listNotFound)
        }
    }

    func testUnknownNameIsNotFound() {
        let groceries = makeCalendar(title: "Groceries")
        XCTAssertThrowsError(try resolveCalendarExactly([groceries], nameOrId: "Nope")) { error in
            XCTAssertEqual(error as? CLIError, .listNotFoundExactly("Nope", partialMatches: []))
        }
    }

    func testEmptyNameDoesNotListEveryListAsPartialMatch() {
        let groceries = makeCalendar(title: "Groceries")
        XCTAssertThrowsError(try resolveCalendarExactly([groceries], nameOrId: " ")) { error in
            XCTAssertEqual(error as? CLIError, .listNotFoundExactly(" ", partialMatches: []))
        }
    }

    func testDuplicateExactTitlesAreAmbiguous() {
        let first = makeCalendar(title: "Groceries")
        let second = makeCalendar(title: "Groceries")
        XCTAssertThrowsError(try resolveCalendarExactly([first, second], nameOrId: "Groceries")) { error in
            XCTAssertEqual(
                error as? CLIError, .listAmbiguous("Groceries", matches: ["Groceries", "Groceries"]))
        }
    }

    func testDuplicateCaseInsensitiveTitlesAreAmbiguous() {
        let lower = makeCalendar(title: "work")
        let upper = makeCalendar(title: "Work")
        XCTAssertThrowsError(try resolveCalendarExactly([lower, upper], nameOrId: "WORK")) { error in
            XCTAssertEqual((error as? CLIError)?.code, .listAmbiguous)
        }
    }
}
