@testable import RemindersLibrary
import XCTest

final class OutputFormatDetectionTests: XCTestCase {
    func testLongOptionWithSeparateValue() {
        XCTAssertEqual(OutputFormat.detect(in: ["show", "Groceries", "--format", "json"]), .json)
    }

    func testLongOptionWithEqualsValue() {
        XCTAssertEqual(OutputFormat.detect(in: ["show", "--format=json", "Groceries"]), .json)
    }

    func testShortOption() {
        XCTAssertEqual(OutputFormat.detect(in: ["show", "-f", "json", "Groceries"]), .json)
    }

    func testExplicitPlain() {
        XCTAssertEqual(OutputFormat.detect(in: ["show", "--format", "plain"]), .plain)
    }

    func testNoOptionMeansPlain() {
        XCTAssertEqual(OutputFormat.detect(in: ["show", "Groceries"]), .plain)
        XCTAssertEqual(OutputFormat.detect(in: []), .plain)
    }

    func testDanglingOptionMeansPlain() {
        XCTAssertEqual(OutputFormat.detect(in: ["show", "--format"]), .plain)
        XCTAssertEqual(OutputFormat.detect(in: ["show", "--format="]), .plain)
    }

    func testUnknownValueMeansPlain() {
        XCTAssertEqual(OutputFormat.detect(in: ["show", "--format", "yaml"]), .plain)
    }

    func testValueAfterTerminatorIsIgnored() {
        XCTAssertEqual(OutputFormat.detect(in: ["add", "Groceries", "--", "--format", "json"]), .plain)
    }

    func testFirstOccurrenceWins() {
        XCTAssertEqual(OutputFormat.detect(in: ["--format", "json", "--format", "plain"]), .json)
    }
}
