import Foundation
@testable import RemindersLibrary
import XCTest

final class ShowAllQueryTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    /// 2026-09-14 10:30:15 in Berlin, a whole second so it survives a round trip through components.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 10, minute: 30, second: 15))!
    }

    private func date(day: Int, hour: Int, minute: Int, second: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute, second: second))!
    }

    func testTodayIncludesOverdueByDefault() throws {
        let query = ShowAllQuery.today(now: now, calendar: calendar)
        let dueOn = try XCTUnwrap(query.dueOn)
        XCTAssertEqual(dueOn.date, date(day: 14, hour: 0, minute: 0, second: 0))
        XCTAssertNil(dueOn.hour)
        XCTAssertTrue(query.includeOverdue)
        XCTAssertFalse(query.overdue)
        XCTAssertNil(query.dueBefore)
        XCTAssertNil(query.dueAfter)
        XCTAssertEqual(query.lists, [])
        XCTAssertEqual(query.sort, .dueDate)
        XCTAssertEqual(query.sortOrder, .ascending)
    }

    func testTodayWithoutOverdue() {
        XCTAssertFalse(ShowAllQuery.today(includeOverdue: false, now: now, calendar: calendar).includeOverdue)
    }

    func testOverdue() {
        XCTAssertEqual(ShowAllQuery.overdue(), ShowAllQuery(overdue: true))
    }

    func testUpcomingDefaultsToSevenDaysFromNow() throws {
        let query = ShowAllQuery.upcoming(now: now, calendar: calendar)
        let dueBefore = try XCTUnwrap(query.dueBefore)
        XCTAssertEqual(recurrenceEndDate(from: dueBefore), date(day: 21, hour: 23, minute: 59, second: 59))
        XCTAssertEqual(try XCTUnwrap(query.dueAfter).date, now)
        XCTAssertNil(query.dueOn)
        XCTAssertFalse(query.includeOverdue)
        XCTAssertFalse(query.overdue)
        XCTAssertEqual(query.sort, .dueDate)
        XCTAssertEqual(query.sortOrder, .ascending)
    }

    func testUpcomingWithCustomDays() throws {
        let query = ShowAllQuery.upcoming(days: 1, now: now, calendar: calendar)
        let dueBefore = try XCTUnwrap(query.dueBefore)
        XCTAssertEqual(recurrenceEndDate(from: dueBefore), date(day: 15, hour: 23, minute: 59, second: 59))
    }

    func testUpcomingIncludeOverdueDropsLowerBound() throws {
        let query = ShowAllQuery.upcoming(includeOverdue: true, now: now, calendar: calendar)
        XCTAssertNil(query.dueAfter)
        XCTAssertNotNil(query.dueBefore)
        XCTAssertFalse(query.overdue, "--overdue would exclude the upcoming reminders")
    }

    func testListsAndSortArePassedThrough() {
        let lists = ["Work", "Soon"]
        for query in [
            ShowAllQuery.today(lists: lists, sort: .priority, sortOrder: .descending, now: now, calendar: calendar),
            ShowAllQuery.overdue(lists: lists, sort: .priority, sortOrder: .descending),
            ShowAllQuery.upcoming(lists: lists, sort: .priority, sortOrder: .descending, now: now, calendar: calendar),
        ] {
            XCTAssertEqual(query.lists, lists)
            XCTAssertEqual(query.sort, .priority)
            XCTAssertEqual(query.sortOrder, .descending)
        }
    }
}
