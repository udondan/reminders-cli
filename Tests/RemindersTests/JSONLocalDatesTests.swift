import EventKit
@testable import RemindersLibrary
import XCTest

final class JSONLocalDatesTests: XCTestCase {
    private let berlin = TimeZone(identifier: "Europe/Berlin")!

    private func utc(_ string: String) throws -> Date {
        return try XCTUnwrap(ISO8601DateFormatter().date(from: string))
    }

    private func reminder() -> EKReminder {
        let store = EKEventStore()
        let reminder = EKReminder(eventStore: store)
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = "Test"
        reminder.calendar = calendar
        reminder.title = "Task"
        return reminder
    }

    private func encode(_ reminder: EKReminder) throws -> [String: Any] {
        let data = try JSONEncoder().encode(reminder)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testLocalISO8601UsesSummerOffset() throws {
        XCTAssertEqual(
            localISO8601(try utc("2026-09-14T22:00:00Z"), timeZone: berlin),
            "2026-09-15T00:00:00+02:00")
    }

    func testLocalISO8601UsesWinterOffset() throws {
        XCTAssertEqual(
            localISO8601(try utc("2026-01-14T23:00:00Z"), timeZone: berlin),
            "2026-01-15T00:00:00+01:00")
    }

    func testLocalISO8601WritesZeroOffsetAsZ() throws {
        XCTAssertEqual(
            localISO8601(try utc("2026-09-14T22:00:00Z"), timeZone: TimeZone(identifier: "UTC")!),
            "2026-09-14T22:00:00Z")
    }

    func testLocalISO8601IsNilWithoutDate() {
        XCTAssertNil(localISO8601(nil, timeZone: berlin))
    }

    func testDateOnlyDueDateIsAllDayAtLocalMidnight() throws {
        let reminder = reminder()
        reminder.dueDateComponents = DateComponents(year: 2026, month: 9, day: 15)

        let object = try encode(reminder)
        XCTAssertEqual(object["isAllDay"] as? Bool, true)
        let local = try XCTUnwrap(object["dueDateLocal"] as? String)
        XCTAssertTrue(local.hasPrefix("2026-09-15T00:00:00"), local)
    }

    func testTimedDueDateIsNotAllDay() throws {
        let reminder = reminder()
        reminder.dueDateComponents = DateComponents(year: 2026, month: 9, day: 15, hour: 9, minute: 30)

        let object = try encode(reminder)
        XCTAssertEqual(object["isAllDay"] as? Bool, false)
        let local = try XCTUnwrap(object["dueDateLocal"] as? String)
        XCTAssertTrue(local.hasPrefix("2026-09-15T09:30:00"), local)
        XCTAssertEqual(local, localISO8601(reminder.dueDateComponents?.date))
    }

    func testUTCDueDateIsUnchanged() throws {
        let reminder = reminder()
        reminder.dueDateComponents = DateComponents(year: 2026, month: 9, day: 15, hour: 9, minute: 30)

        let object = try encode(reminder)
        let dueDate = try XCTUnwrap(object["dueDate"] as? String)
        XCTAssertTrue(dueDate.hasSuffix("Z"), dueDate)
        XCTAssertEqual(try utc(dueDate), reminder.dueDateComponents?.date)
    }

    func testNoDueDateOmitsLocalDueDateAndIsAllDay() throws {
        let object = try encode(reminder())
        XCTAssertNil(object["dueDateLocal"])
        XCTAssertNil(object["isAllDay"])
    }

    func testIncompleteReminderHasNullCompletionDateLocal() throws {
        let object = try encode(reminder())
        XCTAssertTrue(object.keys.contains("completionDateLocal"))
        XCTAssertTrue(object["completionDateLocal"] is NSNull)
    }

    func testRecurringReminderIncludesNextDueDateLocal() throws {
        let reminder = reminder()
        reminder.dueDateComponents = DateComponents(year: 2026, month: 9, day: 15, hour: 9)
        reminder.addRecurrenceRule(Recurrence.daily.recurrenceRule(interval: 1, end: nil))

        let object = try encode(reminder)
        let next = try XCTUnwrap(object["nextDueDate"] as? String)
        XCTAssertEqual(object["nextDueDateLocal"] as? String, localISO8601(try utc(next)))
    }

    func testNonRecurringReminderOmitsNextDueDateLocal() throws {
        let reminder = reminder()
        reminder.dueDateComponents = DateComponents(year: 2026, month: 9, day: 15)

        XCTAssertNil(try encode(reminder)["nextDueDateLocal"])
    }
}
