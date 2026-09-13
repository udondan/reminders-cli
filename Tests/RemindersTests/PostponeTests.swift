import Foundation
@testable import RemindersLibrary
import XCTest

final class PostponeTests: XCTestCase {
    // 2024-01-03 was a Wednesday, so this whole week is fixed and deterministic
    // regardless of when these tests actually run.
    private func anchor(day: Int, hour: Int? = 9, minute: Int = 0) -> DateComponents {
        var components = DateComponents(
            year: 2024, month: 1, day: day, hour: hour, minute: hour != nil ? minute : nil)
        // `.date` (used both here and inside `nextWeekday`) resolves to nil unless the
        // components carry their own calendar -- mirrors how NaturalLanguage.swift's
        // `allComponents` always includes `.calendar` on real due-date components.
        components.calendar = Calendar.current
        return components
    }

    private func weekday(of components: DateComponents) throws -> Int {
        let date = try XCTUnwrap(components.date)
        return Calendar.current.component(.weekday, from: date)
    }

    func testMidweekAdvancesByOneDay() throws {
        // Wednesday (2024-01-03) -> Thursday, not a no-op.
        let result = try XCTUnwrap(nextWeekday(after: anchor(day: 3)))
        XCTAssertEqual(try weekday(of: result), 5) // Thursday
    }

    func testFridayLandsOnMonday() throws {
        let result = try XCTUnwrap(nextWeekday(after: anchor(day: 5)))
        XCTAssertEqual(try weekday(of: result), 2) // Monday
    }

    func testSaturdayLandsOnMonday() throws {
        let result = try XCTUnwrap(nextWeekday(after: anchor(day: 6)))
        XCTAssertEqual(try weekday(of: result), 2) // Monday
    }

    func testSundayLandsOnMonday() throws {
        let result = try XCTUnwrap(nextWeekday(after: anchor(day: 7)))
        XCTAssertEqual(try weekday(of: result), 2) // Monday
    }

    func testPreservesTimeOfDay() throws {
        let result = try XCTUnwrap(nextWeekday(after: anchor(day: 3, hour: 14, minute: 30)))
        XCTAssertEqual(result.hour, 14)
        XCTAssertEqual(result.minute, 30)
    }

    func testPreservesDateOnlyReminders() throws {
        let result = try XCTUnwrap(nextWeekday(after: anchor(day: 3, hour: nil)))
        XCTAssertNil(result.hour)
    }

    func testReturnsNilWithoutResolvableAnchor() {
        XCTAssertNil(nextWeekday(after: DateComponents()))
    }
}
