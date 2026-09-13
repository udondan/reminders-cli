import Foundation
@testable import RemindersLibrary
import XCTest

/// Integration-style tests that go through the real argument parsing and command dispatch, but
/// stop short of `CLI.execute()`: the exit status can't be asserted in-process because it would
/// terminate the test runner. `CLIErrorTests` covers the code-to-exit-status mapping instead.
///
/// `EKEventStore.calendars(for:)` returns an empty list when the process has no Reminders
/// access and never prompts, so an unknown list is always "not found" here. A fresh UUID is used
/// as the list name because a developer machine may well have granted the test runner access.
final class CLIRunTests: XCTestCase {
    func testUnknownListIsReportedAsListNotFoundInPlainFormat() throws {
        let list = UUID().uuidString
        let outcome = try CLI.runCommand(["show", list])
        XCTAssertEqual(outcome, .failed(.listNotFound(list), format: .plain))
    }

    func testUnknownListIsReportedAsListNotFoundInJSONFormat() throws {
        let list = UUID().uuidString
        let outcome = try CLI.runCommand(["show", list, "--format", "json"])
        XCTAssertEqual(outcome, .failed(.listNotFound(list), format: .json))
    }

    func testListNotFoundIsReportedBeforeReminderLookup() throws {
        let list = UUID().uuidString
        let outcome = try CLI.runCommand(["complete", list, "some-id", "-f", "json"])
        XCTAssertEqual(outcome, .failed(.listNotFound(list), format: .json))
    }

    func testDeleteAcceptsFormatOption() throws {
        let list = UUID().uuidString
        let outcome = try CLI.runCommand(["delete", list, "some-id", "--format", "json"])
        XCTAssertEqual(outcome, .failed(.listNotFound(list), format: .json))
    }

    func testValidationErrorsAreRethrownUnchanged() {
        XCTAssertThrowsError(try CLI.runCommand(["show"])) { error in
            XCTAssertFalse(error is CLIError, "usage errors stay with ArgumentParser: \(error)")
        }
    }
}
