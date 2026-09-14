import Foundation
@testable import RemindersLibrary
import XCTest

final class NaturalLanguageTests: XCTestCase {
    func testYesterday() throws {
        let components = try XCTUnwrap(DateComponents(argument: "yesterday"))
        let yesterday = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: Date()))
        let expectedComponents = Calendar.current.dateComponents(
            calendarComponents(except: timeComponents), from: yesterday)

        XCTAssertEqual(components, expectedComponents)
    }

    func testTodayString() throws {
        let components = try XCTUnwrap(DateComponents(argument: "today"))
        let expectedComponents = Calendar.current.dateComponents(
            calendarComponents(except: timeComponents), from: Date())

        XCTAssertEqual(components, expectedComponents)
    }

    func testTodayNoon() throws {
        let components = try XCTUnwrap(DateComponents(argument: "12:00"))
        let today = try XCTUnwrap(Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date()))
        let expectedComponents = Calendar.current.dateComponents(calendarComponents(), from: today)

        XCTAssertEqual(components, expectedComponents)
    }

    func testTonight() throws {
        // NOTE: The exact hour NSDataDetector picks for "tonight" is an OS/locale-dependent
        // implementation detail (it has changed between macOS versions), so only assert it
        // resolves to today, in the evening, on the hour.
        let components = try XCTUnwrap(DateComponents(argument: "tonight"))
        let date = try XCTUnwrap(Calendar.current.date(from: components))

        XCTAssertTrue(Calendar.current.isDateInToday(date))
        XCTAssertEqual(components.minute, 0)
        XCTAssertEqual(components.second, 0)
        let hour = try XCTUnwrap(components.hour)
        XCTAssertTrue((17...23).contains(hour), "expected an evening hour, got \(hour)")
    }

    func testTomorrow() throws {
        let components = try XCTUnwrap(DateComponents(argument: "tomorrow"))
        let tomorrow = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: Date()))
        let expectedComponents = Calendar.current.dateComponents(
            calendarComponents(except: timeComponents), from: tomorrow)

        XCTAssertEqual(components, expectedComponents)
    }

    func testTomorrowAtTime() throws {
        let components = try XCTUnwrap(DateComponents(argument: "tomorrow 9pm"))
        let tomorrow = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: Date()))
        let tomorrowAt9 = try XCTUnwrap(
            Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: tomorrow))
        let expectedComponents = Calendar.current.dateComponents(calendarComponents(), from: tomorrowAt9)

        XCTAssertEqual(components, expectedComponents)
    }

    func testRelativeDayCount() throws {
        let components = try XCTUnwrap(DateComponents(argument: "in 2 days"))
        let inTwoDays = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 2, to: Date()))
        let expectedComponents = Calendar.current.dateComponents(
            calendarComponents(except: timeComponents), from: inTwoDays)

        XCTAssertEqual(components, expectedComponents)
    }

    /// Asserts that `argument` resolves to the given weekday within the next two weeks. Whether
    /// "next saturday" means the coming one or the one after is up to `NSDataDetector`, so only
    /// that window is pinned, not the exact day.
    private func assertUpcoming(
        _ argument: String, weekday: Int, hour: Int? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let components = try XCTUnwrap(DateComponents(argument: argument), file: file, line: line)
        let date = try XCTUnwrap(Calendar.current.date(from: components), file: file, line: line)
        let today = Calendar.current.startOfDay(for: Date())
        let twoWeeks = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 15, to: today))

        XCTAssertEqual(Calendar.current.component(.weekday, from: date), weekday, argument, file: file, line: line)
        XCTAssertGreaterThanOrEqual(date, today, argument, file: file, line: line)
        XCTAssertLessThan(date, twoWeeks, argument, file: file, line: line)
        XCTAssertEqual(components.hour, hour, argument, file: file, line: line)
    }

    func testNextSaturday() throws {
        try assertUpcoming("next saturday", weekday: 7)
    }

    // FB8921206
    func testNextWeekend() throws {
        // TODO: This should be inverted but DataDetector doesn't support it right now
        XCTAssertNil(DateComponents(argument: "next weekend"))
        // let components = try XCTUnwrap(DateComponents(argument: "next weekend"))
        // let date = try XCTUnwrap(Calendar.current.date(from: components))

        // XCTAssertTrue(Calendar.current.isDateInWeekend(date))
    }

    func testSpecificDays() throws {
        try assertUpcoming("next monday", weekday: 2)
        try assertUpcoming("on monday at 9pm", weekday: 2, hour: 21)
    }

    func testIgnoreRandomString() {
        XCTAssertNil(DateComponents(argument: "blah tomorrow 9pm"))
    }
}
