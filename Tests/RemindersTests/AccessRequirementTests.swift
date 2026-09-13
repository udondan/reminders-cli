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

    func testActualSubcommandsRequireAccess() {
        XCTAssertTrue(AccessRequirement.requiresReminderAccess(arguments: ["show-lists"]))
        XCTAssertTrue(
            AccessRequirement.requiresReminderAccess(arguments: ["add", "List", "Task"]))
    }
}
