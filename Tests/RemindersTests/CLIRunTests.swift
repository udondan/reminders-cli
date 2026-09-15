import Foundation
@testable import RemindersLibrary
import XCTest

/// Integration-style tests that go through the real argument parsing and command dispatch, but
/// stop short of `CLI.execute()`: the exit status can't be asserted in-process because it would
/// terminate the test runner. `CLIErrorTests` covers the code-to-exit-status mapping instead.
///
/// `EKEventStore.calendars(for:)` returns an empty list when the process has no Reminders
/// access and never prompts, so an unknown list is always "not found" here. A fresh UUID is used
/// as the list name because a developer machine may well have granted the test runner access;
/// in that case the error's suggestion names the machine's real lists, so only the code and the
/// message are asserted, not the whole error.
final class CLIRunTests: XCTestCase {
    private func assertListNotFound(
        _ outcome: CLIRunOutcome, list: String, format: OutputFormat,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        guard case .failed(let error, let actualFormat) = outcome else {
            XCTFail("expected a failure, got \(outcome)", file: file, line: line)
            return
        }
        XCTAssertEqual(error.code, .listNotFound, file: file, line: line)
        XCTAssertEqual(error.message, CLIError.listNotFound(list).message, file: file, line: line)
        XCTAssertEqual(actualFormat, format, file: file, line: line)
    }

    /// Usage errors stay with ArgumentParser (help text, exit status 64) instead of becoming a
    /// `CLIError`; the message makes sure the arguments fail for the reason the test is named after.
    private func assertUsageError(
        _ arguments: [String], contains message: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertThrowsError(try CLI.runCommand(arguments), file: file, line: line) { error in
            XCTAssertFalse(error is CLIError, "usage errors stay with ArgumentParser: \(error)", file: file, line: line)
            let rendered = CLI.message(for: error)
            XCTAssertTrue(
                rendered.contains(message), "expected '\(message)' in '\(rendered)'", file: file, line: line)
        }
    }

    func testUnknownListIsReportedAsListNotFoundInPlainFormat() throws {
        let list = UUID().uuidString
        let outcome = try CLI.runCommand(["show", list])
        assertListNotFound(outcome, list: list, format: .plain)
    }

    func testUnknownListIsReportedAsListNotFoundInJSONFormat() throws {
        let list = UUID().uuidString
        let outcome = try CLI.runCommand(["show", list, "--format", "json"])
        assertListNotFound(outcome, list: list, format: .json)
    }

    func testListNotFoundIsReportedBeforeReminderLookup() throws {
        let list = UUID().uuidString
        let outcome = try CLI.runCommand(["complete", list, "some-id", "-f", "json"])
        assertListNotFound(outcome, list: list, format: .json)
    }

    func testDeleteAcceptsFormatOption() throws {
        let list = UUID().uuidString
        let outcome = try CLI.runCommand(["delete", list, "some-id", "--format", "json"])
        assertListNotFound(outcome, list: list, format: .json)
    }

    func testMutatingCommandsAcceptSeveralIds() throws {
        let arguments: [[String]] = [
            ["complete", "some-id", "other-id"],
            ["uncomplete", "some-id,other-id"],
            ["delete", "some-id", "other-id,third-id"],
            ["postpone", "some-id,other-id", "tomorrow"],
            ["edit", "some-id,other-id", "--priority", "high"],
        ]
        for command in arguments {
            let list = UUID().uuidString
            let outcome = try CLI.runCommand(
                [command[0], list] + command.dropFirst() + ["--format", "json"])
            assertListNotFound(outcome, list: list, format: .json)
        }
    }

    func testCompleteRequiresAnId() {
        assertUsageError(["complete", UUID().uuidString], contains: "Missing expected argument '<ids> ...'")
    }

    /// `delete-list` resolves the list before anything else, so an unknown list fails even with
    /// `--confirm` and nothing on a real machine can be touched.
    func testDeleteListReportsUnknownListInRequestedFormat() throws {
        let list = UUID().uuidString
        let outcome = try CLI.runCommand(["delete-list", list, "--confirm", "--format", "json"])
        guard case .failed(let error, let format) = outcome else {
            return XCTFail("expected a failure, got \(outcome)")
        }
        XCTAssertEqual(error.code, .listNotFound)
        XCTAssertEqual(format, .json)
    }

    func testDeleteListRequiresListArgument() {
        assertUsageError(["delete-list", "--confirm"], contains: "Missing expected argument '<list-name-or-id>'")
    }

    func testValidationErrorsAreRethrownUnchanged() {
        assertUsageError(["show"], contains: "Missing expected argument '<list-name-or-id>'")
    }

    /// Only the parse failure is exercised: a valid `show-lists` would print the machine's real
    /// lists on a developer machine that has granted the test runner access.
    func testShowListsRejectsUnknownSort() {
        assertUsageError(
            ["show-lists", "--sort", "bogus"], contains: "The value 'bogus' is invalid for '--sort <sort>'")
    }

    /// The convenience commands run `show-all`'s query, so an unknown `--list` fails the same way
    /// and in the requested format.
    func testConvenienceCommandsReportUnknownList() throws {
        for command in ["today", "overdue", "upcoming"] {
            let list = UUID().uuidString
            let outcome = try CLI.runCommand([command, "--list", list, "--format", "json"])
            assertListNotFound(outcome, list: list, format: .json)
        }
    }

    func testUpcomingRejectsDaysBelowOne() {
        assertUsageError(["upcoming", "--days", "0"], contains: "--days must be at least 1")
    }
}
