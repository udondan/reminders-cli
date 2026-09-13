@testable import RemindersLibrary
import XCTest

final class EditValidationTests: XCTestCase {
    private let base = ["edit", "Soon", "2A29C8B1-3D0F-4A9E-9C8D-5B6E7F8A9B0C"]

    func testClearNotesAloneIsAValidEdit() throws {
        XCTAssertNoThrow(try CLI.parseAsRoot(base + ["--clear-notes"]))
    }

    func testClearNotesConflictsWithNotes() throws {
        XCTAssertThrowsError(try CLI.parseAsRoot(base + ["--notes", "x", "--clear-notes"]))
    }

    func testEmptyNotesAsSeparateArgumentParses() throws {
        XCTAssertNoThrow(try CLI.parseAsRoot(base + ["--notes", ""]))
    }

    func testEditWithoutAnyChangeIsRejected() throws {
        XCTAssertThrowsError(try CLI.parseAsRoot(base))
    }
}
