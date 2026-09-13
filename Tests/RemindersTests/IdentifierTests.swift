import EventKit
@testable import RemindersLibrary
import XCTest

final class IdentifierTests: XCTestCase {
    private let store = EKEventStore()

    private func makeCalendar(title: String) -> EKCalendar {
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = title
        return calendar
    }

    private func makeReminder(title: String = "Test", calendar: EKCalendar) -> EKReminder {
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = calendar
        return reminder
    }

    // MARK: - EKCalendar encoding

    func testCalendarEncodesTitleAndIdentifier() throws {
        let calendar = makeCalendar(title: "Groceries")
        let data = try JSONEncoder().encode(calendar)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["title"] as? String, "Groceries")
        XCTAssertEqual(json["calendarIdentifier"] as? String, calendar.calendarIdentifier)
    }

    // MARK: - EKReminder encoding

    func testReminderJsonIncludesListId() throws {
        let calendar = makeCalendar(title: "Groceries")
        let reminder = makeReminder(calendar: calendar)
        let data = try JSONEncoder().encode(reminder)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["listId"] as? String, calendar.calendarIdentifier)
    }

    // MARK: - List resolution

    func testCalendarMatchingResolvesByExactId() throws {
        let a = makeCalendar(title: "A")
        let b = makeCalendar(title: "B")
        let resolved = calendarMatching([a, b], nameOrId: b.calendarIdentifier)
        XCTAssertEqual(resolved?.calendarIdentifier, b.calendarIdentifier)
    }

    func testCalendarMatchingResolvesByCaseInsensitiveTitle() throws {
        let a = makeCalendar(title: "Groceries")
        let b = makeCalendar(title: "Work")
        let resolved = calendarMatching([a, b], nameOrId: "groceries")
        XCTAssertEqual(resolved?.calendarIdentifier, a.calendarIdentifier)
    }

    func testCalendarMatchingPrefersIdOverCollidingTitle() throws {
        // `a`'s title collides with `b`'s identifier; the ID match must win.
        let b = makeCalendar(title: "Work")
        let a = makeCalendar(title: b.calendarIdentifier)
        let resolved = calendarMatching([a, b], nameOrId: b.calendarIdentifier)
        XCTAssertEqual(resolved?.calendarIdentifier, b.calendarIdentifier)
    }

    func testCalendarMatchingReturnsNilWhenNotFound() throws {
        let a = makeCalendar(title: "Groceries")
        XCTAssertNil(calendarMatching([a], nameOrId: "does-not-exist"))
    }

    // MARK: - Reminder resolution

    func testGetReminderResolvesByIndexForNumericString() throws {
        let calendar = makeCalendar(title: "List")
        let first = makeReminder(title: "First", calendar: calendar)
        let second = makeReminder(title: "Second", calendar: calendar)
        let resolved = Reminders().getReminder(from: [first, second], atIndexOrId: "1")
        XCTAssertEqual(resolved?.title, "Second")
    }

    func testGetReminderResolvesByExternalIdForNonNumericString() throws {
        let calendar = makeCalendar(title: "List")
        let reminder = makeReminder(title: "Only", calendar: calendar)
        let resolved = Reminders().getReminder(
            from: [reminder], atIndexOrId: reminder.calendarItemExternalIdentifier)
        XCTAssertEqual(resolved?.title, "Only")
    }

    func testGetReminderReturnsNilForOutOfRangeIndex() throws {
        let calendar = makeCalendar(title: "List")
        let reminder = makeReminder(calendar: calendar)
        XCTAssertNil(Reminders().getReminder(from: [reminder], atIndexOrId: "5"))
    }

    func testGetReminderReturnsNilForUnknownExternalId() throws {
        let calendar = makeCalendar(title: "List")
        let reminder = makeReminder(calendar: calendar)
        XCTAssertNil(Reminders().getReminder(from: [reminder], atIndexOrId: "not-a-real-id"))
    }
}
