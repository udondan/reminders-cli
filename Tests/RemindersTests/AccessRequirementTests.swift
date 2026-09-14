@testable import RemindersLibrary
import XCTest

final class AccessRequirementTests: XCTestCase {
    func testNoArgumentsDoesNotRequireAccess() {
        XCTAssertFalse(AccessRequirement.requiresReminderAccess(arguments: []))
    }

    func testGenerateCompletionScriptDoesNotRequireAccess() {
        XCTAssertFalse(
            AccessRequirement.requiresReminderAccess(
                arguments: ["--generate-completion-script", "zsh"]))
    }

    func testVersionDoesNotRequireAccess() {
        XCTAssertFalse(AccessRequirement.requiresReminderAccess(arguments: ["--version"]))
    }

    func testHelpDoesNotRequireAccess() {
        XCTAssertFalse(AccessRequirement.requiresReminderAccess(arguments: ["--help"]))
        XCTAssertFalse(AccessRequirement.requiresReminderAccess(arguments: ["-h"]))
        XCTAssertFalse(AccessRequirement.requiresReminderAccess(arguments: ["show", "--help"]))
    }

    /// ArgumentParser's built-in `help` subcommand only prints usage, like `--help`.
    func testHelpSubcommandDoesNotRequireAccess() {
        XCTAssertFalse(AccessRequirement.requiresReminderAccess(arguments: ["help"]))
        XCTAssertFalse(AccessRequirement.requiresReminderAccess(arguments: ["help", "show"]))
    }

    func testHelpAsAnArgumentStillRequiresAccess() {
        XCTAssertTrue(AccessRequirement.requiresReminderAccess(arguments: ["add", "List", "help"]))
    }

    /// `doctor` reports the authorization state, so it must never trigger the access prompt.
    func testDoctorDoesNotRequireAccess() {
        XCTAssertFalse(AccessRequirement.requiresReminderAccess(arguments: ["doctor"]))
        XCTAssertFalse(
            AccessRequirement.requiresReminderAccess(arguments: ["doctor", "--format", "json"]))
    }

    func testDoctorAsAnArgumentStillRequiresAccess() {
        XCTAssertTrue(AccessRequirement.requiresReminderAccess(arguments: ["show", "doctor"]))
        XCTAssertTrue(
            AccessRequirement.requiresReminderAccess(arguments: ["add", "List", "doctor"]))
    }

    func testActualSubcommandsRequireAccess() {
        XCTAssertTrue(AccessRequirement.requiresReminderAccess(arguments: ["show-lists"]))
        XCTAssertTrue(
            AccessRequirement.requiresReminderAccess(arguments: ["add", "List", "Task"]))
    }
}
