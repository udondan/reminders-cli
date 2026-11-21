import Foundation
@testable import RemindersLibrary
import XCTest

final class DueDateFormattingTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    private var formatter: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }

    // 2024-01-04 was a Thursday.
    private func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        return calendar.date(from: DateComponents(year: 2024, month: 1, day: day, hour: hour, minute: minute))!
    }

    private func format(_ due: Date, now: Date) -> String {
        return relativeDueDate(for: due, relativeTo: now, calendar: calendar, formatter: formatter)
    }

    func testDayAfterTomorrowCountsAsTwoDaysEvenWhenLessThan48HoursAway() {
        // Thursday 09:00 -> Saturday 08:00 is 47 hours, but two calendar days.
        XCTAssertEqual(format(date(day: 6, hour: 8), now: date(day: 4, hour: 9)), "in 2 days")
    }

    func testTomorrowCountsAsOneDayEvenWhenLessThan24HoursAway() {
        XCTAssertEqual(format(date(day: 5, hour: 8), now: date(day: 4, hour: 9)), "in 1 day")
    }

    func testSameDayKeepsHourGranularity() {
        XCTAssertEqual(format(date(day: 4, hour: 15), now: date(day: 4, hour: 9)), "in 6 hours")
    }

    func testYesterdayEveningIsOneDayAgo() {
        // Wednesday 20:00 seen from Thursday 09:00 is 13 hours, but one calendar day.
        XCTAssertEqual(format(date(day: 3, hour: 20), now: date(day: 4, hour: 9)), "1 day ago")
    }

    func testLargerSpansStillUseWeeks() {
        XCTAssertEqual(format(date(day: 18, hour: 9), now: date(day: 4, hour: 9)), "in 2 weeks")
    }
}
