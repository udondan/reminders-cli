@testable import RemindersLibrary
import XCTest

/// Values that start with `-`, such as Markdown checklists in notes (issue #86). The commands are
/// private, so where a value must have been captured this is shown through a validation error that
/// only fires when it was.
final class DashPrefixedValueTests: XCTestCase {
    private let editBase = ["edit", "Soon", "2A29C8B1-3D0F-4A9E-9C8D-5B6E7F8A9B0C"]

    func testAddAcceptsNotesStartingWithDash() throws {
        XCTAssertNoThrow(try CLI.parseAsRoot(["add", "Soon", "Migrate", "--notes", "- [ ] repo-a\n- [ ] repo-b"]))
        XCTAssertNoThrow(try CLI.parseAsRoot(["add", "Soon", "Migrate", "-n", "-x"]))
    }

    func testOptionAfterDashPrefixedNotesIsStillAnOption() throws {
        assertParseError(
            ["add", "Soon", "Medicine", "--notes", "- [ ] a", "--repeat", "daily"],
            contains: "--repeat requires --due-date")
    }

    func testEditAcceptsNotesStartingWithDash() throws {
        XCTAssertNoThrow(try CLI.parseAsRoot(editBase + ["--notes", "- [ ] via edit"]))
        assertParseError(
            editBase + ["-n", "- [ ] a", "--clear-notes"], contains: "Cannot specify both --notes and --clear-notes")
    }

    func testTitleStartingWithDashIsAcceptedAfterTerminator() throws {
        XCTAssertNoThrow(try CLI.parseAsRoot(["add", "Soon", "--", "- [ ] title"]))
        XCTAssertNoThrow(try CLI.parseAsRoot(["add", "Soon", "--notes", "- n", "--", "- [ ] title"]))
        XCTAssertNoThrow(try CLI.parseAsRoot(editBase + ["--", "- [ ] title"]))
        assertParseError(
            ["edit", "Soon", "855B,91F4", "--", "- [ ] title"],
            contains: "New reminder text can only be set on one reminder at a time")
    }

    func testSearchAcceptsTextStartingWithDash() throws {
        XCTAssertNoThrow(try CLI.parseAsRoot(["show", "Soon", "--search", "- [ ]"]))
        XCTAssertNoThrow(try CLI.parseAsRoot(["show-all", "--search", "- [ ]"]))
    }
}
