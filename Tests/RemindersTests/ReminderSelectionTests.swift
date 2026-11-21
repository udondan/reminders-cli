@testable import RemindersLibrary
import XCTest

final class ReminderSelectionTests: XCTestCase {
    private func selection(_ arguments: [String], stdin: String = "") throws -> ReminderSelection {
        try ReminderSelection(arguments: arguments, readStandardInput: { stdin })
    }

    private func assertInvalidArgument(
        _ arguments: [String], stdin: String = "", file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertThrowsError(try selection(arguments, stdin: stdin), file: file, line: line) { error in
            XCTAssertEqual((error as? CLIError)?.code, .invalidArgument, file: file, line: line)
        }
    }

    func testSingleIdIsNotABatch() throws {
        let result = try selection(["855B"])
        XCTAssertEqual(result.ids, ["855B"])
        XCTAssertFalse(result.isBatch)
    }

    func testSeveralArgumentsAreABatch() throws {
        let result = try selection(["855B", "91F4", "600B"])
        XCTAssertEqual(result.ids, ["855B", "91F4", "600B"])
        XCTAssertTrue(result.isBatch)
    }

    func testCommaSeparatedIdsAreABatch() throws {
        let result = try selection(["855B, 91F4,600B"])
        XCTAssertEqual(result.ids, ["855B", "91F4", "600B"])
        XCTAssertTrue(result.isBatch)
    }

    /// Even a single ID on stdin prints a JSON array, so a pipeline always gets the same shape.
    func testStandardInputIsABatchEvenWithOneId() throws {
        let result = try selection(["-"], stdin: "855B\n")
        XCTAssertEqual(result.ids, ["855B"])
        XCTAssertTrue(result.isBatch)
    }

    func testStandardInputSkipsBlankLinesAndWhitespace() throws {
        let result = try selection(["-"], stdin: "  855B\r\n\n91F4\t\n\n")
        XCTAssertEqual(result.ids, ["855B", "91F4"])
    }

    func testStandardInputIsExpandedInPlace() throws {
        let result = try selection(["AAAA", "-", "DDDD"], stdin: "BBBB\nCCCC")
        XCTAssertEqual(result.ids, ["AAAA", "BBBB", "CCCC", "DDDD"])
    }

    func testStandardInputIsNotReadWithoutDash() throws {
        _ = try ReminderSelection(arguments: ["855B"], readStandardInput: {
            XCTFail("stdin must only be read for '-'")
            return ""
        })
    }

    func testDashTwiceIsRejected() {
        assertInvalidArgument(["-", "-"], stdin: "855B")
    }

    func testEmptyStandardInputIsRejected() {
        assertInvalidArgument(["-"], stdin: "\n \n")
    }

    func testOnlySeparatorsAreRejected() {
        assertInvalidArgument([","])
        assertInvalidArgument([""])
    }

    func testIsBatchFromArgumentsAlone() {
        XCTAssertFalse(ReminderSelection.isBatch(arguments: ["855B"]))
        XCTAssertTrue(ReminderSelection.isBatch(arguments: ["855B,91F4"]))
        XCTAssertTrue(ReminderSelection.isBatch(arguments: ["-"]))
        XCTAssertTrue(ReminderSelection.isBatch(arguments: ["855B", "91F4"]))
    }
}
