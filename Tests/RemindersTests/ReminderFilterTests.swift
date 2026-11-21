import EventKit
@testable import RemindersLibrary
import XCTest

final class ReminderFilterTests: XCTestCase {
    private let store = EKEventStore()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeReminder(_ title: String, dueIn days: Int? = nil, priority: Priority = .none) -> EKReminder {
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = EKCalendar(for: .reminder, eventStore: store)
        reminder.title = title
        reminder.priority = Int(priority.value.rawValue)
        if let days {
            let due = now.addingTimeInterval(TimeInterval(days * 86_400))
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: due)
        }
        return reminder
    }

    private func titles(_ reminders: [EKReminder]) -> [String] {
        reminders.map { $0.title }
    }

    func testDefaultFilterKeepsEverythingInFetchedOrder() {
        let filter = ReminderFilter()
        XCTAssertEqual(filter.displayOptions, .incomplete)
        XCTAssertEqual(filter.sort, Sort.none)
        XCTAssertEqual(filter.sortOrder, .forward)

        let fetched = [makeReminder("b", dueIn: 2), makeReminder("a"), makeReminder("c", dueIn: -1)]
        XCTAssertEqual(titles(filter.apply(to: fetched, now: now)), ["b", "a", "c"])
    }

    func testSortsBeforeFiltering() {
        let fetched = [makeReminder("later", dueIn: 3), makeReminder("sooner", dueIn: 1)]
        XCTAssertEqual(
            titles(ReminderFilter(sort: .dueDate).apply(to: fetched, now: now)), ["sooner", "later"])
        XCTAssertEqual(
            titles(ReminderFilter(sort: .dueDate, sortOrder: .reverse).apply(to: fetched, now: now)),
            ["later", "sooner"])
    }

    func testOverdueKeepsOnlyPastDueReminders() {
        let fetched = [makeReminder("past", dueIn: -2), makeReminder("future", dueIn: 2), makeReminder("none")]
        XCTAssertEqual(titles(ReminderFilter(overdue: true).apply(to: fetched, now: now)), ["past"])
    }

    func testDueOnWithIncludeOverdueAddsEarlierReminders() {
        let fetched = [
            makeReminder("past", dueIn: -2), makeReminder("target", dueIn: 1), makeReminder("future", dueIn: 5),
        ]
        let target = Calendar.current.dateComponents(
            [.calendar, .year, .month, .day], from: now.addingTimeInterval(86_400))
        XCTAssertEqual(titles(ReminderFilter(dueOn: target).apply(to: fetched, now: now)), ["target"])
        XCTAssertEqual(
            titles(ReminderFilter(dueOn: target, includeOverdue: true).apply(to: fetched, now: now)),
            ["past", "target"])
    }

    func testCombinesFilters() {
        let fetched = [
            makeReminder("high past", dueIn: -1, priority: .high),
            makeReminder("low past", dueIn: -1, priority: .low),
            makeReminder("high future", dueIn: 1, priority: .high),
        ]
        let filter = ReminderFilter(overdue: true, priorities: [.high])
        XCTAssertEqual(titles(filter.apply(to: fetched, now: now)), ["high past"])
    }
}
