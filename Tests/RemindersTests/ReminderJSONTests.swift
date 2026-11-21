import CoreLocation
import EventKit
@testable import RemindersLibrary
import XCTest

/// The `--format json` fields of a reminder that `JSONLocalDatesTests` and `RecurrenceTests`
/// don't cover. Every reminder is built in memory and never saved.
final class ReminderJSONTests: XCTestCase {
    private let store = EKEventStore()

    private func utc(_ string: String) throws -> Date {
        return try XCTUnwrap(ISO8601DateFormatter().date(from: string))
    }

    private func reminder() -> EKReminder {
        let reminder = EKReminder(eventStore: store)
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = "Groceries"
        reminder.calendar = calendar
        reminder.title = "Buy milk"
        return reminder
    }

    private func encode(_ reminder: EKReminder) throws -> [String: Any] {
        let data = try JSONEncoder().encode(reminder)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testCoreFields() throws {
        let reminder = reminder()
        reminder.priority = Int(EKReminderPriority.medium.rawValue)

        let object = try encode(reminder)
        XCTAssertEqual(object["externalId"] as? String, reminder.calendarItemExternalIdentifier)
        XCTAssertEqual(object["title"] as? String, "Buy milk")
        XCTAssertEqual(object["isCompleted"] as? Bool, false)
        XCTAssertEqual(object["priority"] as? Int, 5)
        XCTAssertEqual(object["list"] as? String, "Groceries")
        XCTAssertEqual(object["listId"] as? String, reminder.calendar.calendarIdentifier)
        XCTAssertEqual(object["isFlagged"] as? Bool, false)
        XCTAssertNil(object["startDate"])
        XCTAssertNil(object["location"])
        XCTAssertNil(object["locationTitle"])
    }

    func testNotesAreIncluded() throws {
        let reminder = reminder()
        reminder.notes = "2 litres"

        XCTAssertEqual(try encode(reminder)["notes"] as? String, "2 litres")
    }

    /// EventKit stores cleared notes as "", which must look the same as no notes.
    func testEmptyNotesAreOmitted() throws {
        let reminder = reminder()
        reminder.notes = ""
        XCTAssertFalse(try encode(reminder).keys.contains("notes"))

        reminder.notes = nil
        XCTAssertFalse(try encode(reminder).keys.contains("notes"))
    }

    func testCompletionDate() throws {
        let reminder = reminder()
        let completed = try utc("2026-09-14T07:51:00Z")
        reminder.completionDate = completed

        let object = try encode(reminder)
        XCTAssertEqual(object["isCompleted"] as? Bool, true)
        XCTAssertEqual(object["completionDate"] as? String, "2026-09-14T07:51:00Z")
        XCTAssertEqual(object["completionDateLocal"] as? String, localISO8601(completed))
    }

    func testStartDate() throws {
        let reminder = reminder()
        var components = DateComponents(year: 2026, month: 9, day: 14, hour: 7)
        components.timeZone = TimeZone(identifier: "UTC")
        reminder.startDateComponents = components

        XCTAssertEqual(try encode(reminder)["startDate"] as? String, "2026-09-14T07:00:00Z")
    }

    func testCreationDate() throws {
        let reminder = reminder()
        // Only the store sets `creationDate`; KVC sets it on this unsaved reminder.
        reminder.setValue(try utc("2026-09-01T12:00:00Z"), forKey: "creationDate")

        XCTAssertEqual(try encode(reminder)["creationDate"] as? String, "2026-09-01T12:00:00Z")
    }

    func testLocationComesFromTheLocationAlarm() throws {
        let reminder = reminder()
        reminder.addAlarm(EKAlarm(absoluteDate: try utc("2026-09-14T07:00:00Z")))
        let home = EKStructuredLocation(title: "Home")
        home.geoLocation = CLLocation(latitude: 52.5, longitude: 13.25)
        let homeAlarm = EKAlarm()
        homeAlarm.structuredLocation = home
        homeAlarm.proximity = .enter
        reminder.addAlarm(homeAlarm)

        let object = try encode(reminder)
        XCTAssertEqual(object["locationTitle"] as? String, "Home")
        XCTAssertEqual(object["location"] as? String, "52.5, 13.25")
    }

    func testLocationWithoutCoordinatesHasOnlyATitle() throws {
        let reminder = reminder()
        let alarm = EKAlarm()
        alarm.structuredLocation = EKStructuredLocation(title: "Office")
        reminder.addAlarm(alarm)

        let object = try encode(reminder)
        XCTAssertEqual(object["locationTitle"] as? String, "Office")
        XCTAssertNil(object["location"])
    }
}
