import ArgumentParser
import EventKit
@testable import RemindersLibrary
import XCTest

final class RepeatDaysTests: XCTestCase {
    func testParsesAbbreviations() throws {
        XCTAssertEqual(
            try RepeatDays(parsing: "mon,wed,fri").weekdays, [.monday, .wednesday, .friday])
    }

    func testParsesFullNames() throws {
        XCTAssertEqual(try RepeatDays(parsing: "tuesday,thursday").weekdays, [.tuesday, .thursday])
    }

    func testParsingIsCaseInsensitiveAndTrimsWhitespace() throws {
        XCTAssertEqual(
            try RepeatDays(parsing: " Mon, WEDNESDAY ,sAt").weekdays,
            [.monday, .wednesday, .saturday])
    }

    func testWeekdaysAlias() throws {
        XCTAssertEqual(
            try RepeatDays(parsing: "weekdays").weekdays,
            [.monday, .tuesday, .wednesday, .thursday, .friday])
    }

    func testWeekendsAliasIsSundayFirst() throws {
        XCTAssertEqual(try RepeatDays(parsing: "Weekends").weekdays, [.sunday, .saturday])
    }

    func testDuplicatesAreRemovedAndDaysSortedSundayFirst() throws {
        XCTAssertEqual(
            try RepeatDays(parsing: "fri,monday,mon,sun,weekends,friday").weekdays,
            [.sunday, .monday, .friday, .saturday])
    }

    func testUnknownDayIsRejectedWithAcceptedSpellings() {
        XCTAssertThrowsError(try RepeatDays(parsing: "mon,funday")) { error in
            let message = (error as? ValidationError)?.message ?? ""
            XCTAssertTrue(message.contains("'funday'"), message)
            XCTAssertTrue(message.contains("mon/monday"), message)
            XCTAssertTrue(message.contains("weekdays"), message)
        }
    }

    func testEmptyDayIsRejected() {
        XCTAssertThrowsError(try RepeatDays(parsing: ""))
        XCTAssertThrowsError(try RepeatDays(parsing: "mon,,fri"))
    }

    func testDaysOfTheWeekHaveNoWeekNumber() throws {
        let days = try RepeatDays(parsing: "mon,fri").daysOfTheWeek
        XCTAssertEqual(days.map { $0.dayOfTheWeek }, [.monday, .friday])
        XCTAssertEqual(days.map { $0.weekNumber }, [0, 0])
    }

    func testPlainWeekdaysOfRule() throws {
        let rule = Recurrence.weekly.recurrenceRule(
            interval: 1, end: nil, days: try RepeatDays(parsing: "fri,mon"))
        XCTAssertEqual(plainWeekdays(of: rule), [.monday, .friday])
        XCTAssertEqual(plainWeekdays(of: rule)?.map(shortName(of:)), ["mon", "fri"])
    }

    func testPlainWeekdaysIsNilWithoutDays() {
        XCTAssertNil(plainWeekdays(of: Recurrence.weekly.recurrenceRule(interval: 1, end: nil)))
    }

    func testPlainWeekdaysIsNilForWeekNumberedDays() {
        let rule = EKRecurrenceRule(
            recurrenceWith: .monthly,
            interval: 1,
            daysOfTheWeek: [EKRecurrenceDayOfWeek(.friday, weekNumber: -1)],
            daysOfTheMonth: nil,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: nil)
        XCTAssertNil(plainWeekdays(of: rule))
    }
}
