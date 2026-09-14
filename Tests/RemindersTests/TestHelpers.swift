import ArgumentParser
@testable import RemindersLibrary
import XCTest

/// Asserts that parsing `arguments` fails with an error message containing `message`. A bare
/// `XCTAssertThrowsError(try CLI.parseAsRoot(...))` also passes when the arguments fail for another
/// reason, such as a misspelled option, so the test would no longer check the rule it's named after.
/// Only parses, so nothing reads or changes reminders.
func assertParseError(
    _ arguments: [String], contains message: String,
    file: StaticString = #filePath, line: UInt = #line
) {
    XCTAssertThrowsError(try CLI.parseAsRoot(arguments), file: file, line: line) { error in
        let rendered = CLI.message(for: error)
        XCTAssertTrue(
            rendered.contains(message), "expected '\(message)' in '\(rendered)'", file: file, line: line)
    }
}
