import ArgumentParser
import Foundation
@testable import RemindersLibrary
import XCTest

/// The small helpers the store-touching methods are built from, tested without a store.
final class StoreHelperTests: InMemoryReminderTestCase {
    private struct StoreError: LocalizedError {
        var errorDescription: String? { "the store is read-only" }
    }

    func testReportingSaveFailureWrapsTheErrorAsSaveFailed() {
        assertCLIError(
            try reportingSaveFailure(action: "create list 'Groceries'") { throw StoreError() },
            code: .saveFailed,
            message: "Failed to create list 'Groceries': the store is read-only")
    }

    func testReportingSaveFailureRunsTheWrite() throws {
        var wrote = false
        try reportingSaveFailure(action: "save reminder") { wrote = true }
        XCTAssertTrue(wrote)
    }

    func testOrThrowReturnsTheValue() throws {
        XCTAssertEqual(try Optional(3).orThrow(CLIError.noDefaultList()), 3)
    }

    func testOrThrowThrowsForNil() {
        assertCLIError(
            try (nil as Int?).orThrow(CLIError.noDefaultList()),
            code: .listNotFound,
            message: "No default reminders list is configured")
    }

    func testFetchingNoListsReturnsNothing() {
        // EventKit would read an empty list of calendars as every list.
        XCTAssertEqual(Reminders().fetchReminders(on: [], displayOptions: .all), [])
    }

    func testChosenSourceIndex() throws {
        XCTAssertEqual(try ListSourceSelection.chosen(2).chosenIndex(), 2)
    }

    func testNoSourcesIsAnError() {
        assertCLIError(
            try ListSourceSelection.noSources.chosenIndex(),
            code: .noSources, message: "No existing list sources were found")
    }

    func testUnknownSourceIsAnError() {
        assertCLIError(
            try ListSourceSelection.notFound("Work").chosenIndex(),
            code: .sourceNotFound, message: "No source named 'Work' holds reminder lists")
    }

    func testAmbiguousSourceIsAnError() {
        assertCLIError(
            try ListSourceSelection.ambiguous(["iCloud", "Exchange"]).chosenIndex(),
            code: .sourceAmbiguous, message: "Multiple sources hold reminder lists: iCloud, Exchange")
    }

    func testPostponeTargetFromArguments() throws {
        let date = due(2026, 9, 16)
        XCTAssertEqual(try PostponeTarget(date: date, nextWeekday: false), .date(date))
        XCTAssertEqual(try PostponeTarget(date: nil, nextWeekday: true), .nextWeekday)
    }

    func testPostponeTargetNeedsExactlyOneArgument() {
        XCTAssertThrowsError(try PostponeTarget(date: due(2026, 9, 16), nextWeekday: true)) {
            XCTAssertEqual(
                ($0 as? ValidationError)?.message, "Cannot specify both a new due date and --next-weekday")
        }
        XCTAssertThrowsError(try PostponeTarget(date: nil, nextWeekday: false)) {
            XCTAssertEqual(
                ($0 as? ValidationError)?.message, "Must specify either a new due date or --next-weekday")
        }
    }
}
