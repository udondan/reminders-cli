import Foundation
@testable import RemindersLibrary
import XCTest

final class PostponeTests: XCTestCase {
    /// A fixed Gregorian calendar with a Saturday/Sunday weekend, so neither the machine's time
    /// zone nor its locale's weekend definition changes the results.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    // 2024-01-03 was a Wednesday, so this whole week is fixed and deterministic
    // regardless of when these tests actually run.
    private func anchor(day: Int, hour: Int? = 9, minute: Int = 0) -> DateComponents {
        var components = DateComponents(
            year: 2024, month: 1, day: day, hour: hour, minute: hour != nil ? minute : nil)
        // `.date` (used both here and inside `nextWeekday`) resolves to nil unless the
        // components carry their own calendar -- mirrors how NaturalLanguage.swift's
        // `allComponents` always includes `.calendar` on real due-date components.
        components.calendar = calendar
        return components
    }

    private func assertNextWeekday(
        afterDay day: Int, is expected: (month: Int, day: Int),
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let result = try XCTUnwrap(nextWeekday(after: anchor(day: day), calendar: calendar), file: file, line: line)
        XCTAssertEqual(result.year, 2024, file: file, line: line)
        XCTAssertEqual(result.month, expected.month, file: file, line: line)
        XCTAssertEqual(result.day, expected.day, file: file, line: line)
    }

    func testMidweekAdvancesByOneDay() throws {
        // Wednesday (2024-01-03) -> Thursday, not a no-op.
        try assertNextWeekday(afterDay: 3, is: (1, 4))
    }

    func testThursdayLandsOnFriday() throws {
        try assertNextWeekday(afterDay: 4, is: (1, 5))
    }

    func testFridayLandsOnMonday() throws {
        try assertNextWeekday(afterDay: 5, is: (1, 8))
    }

    func testSaturdayLandsOnMonday() throws {
        try assertNextWeekday(afterDay: 6, is: (1, 8))
    }

    func testSundayLandsOnMonday() throws {
        try assertNextWeekday(afterDay: 7, is: (1, 8))
    }

    func testCrossesMonthBoundary() throws {
        // Wednesday 2024-01-31 -> Thursday 2024-02-01.
        try assertNextWeekday(afterDay: 31, is: (2, 1))
    }

    func testPreservesTimeOfDay() throws {
        let result = try XCTUnwrap(nextWeekday(after: anchor(day: 3, hour: 14, minute: 30), calendar: calendar))
        XCTAssertEqual(result.day, 4)
        XCTAssertEqual(result.hour, 14)
        XCTAssertEqual(result.minute, 30)
    }

    func testPreservesDateOnlyReminders() throws {
        let result = try XCTUnwrap(nextWeekday(after: anchor(day: 3, hour: nil), calendar: calendar))
        XCTAssertEqual(result.day, 4)
        XCTAssertNil(result.hour)
        XCTAssertNil(result.minute)
    }

    func testReturnsNilWithoutResolvableAnchor() {
        XCTAssertNil(nextWeekday(after: DateComponents(), calendar: calendar))
    }
}
