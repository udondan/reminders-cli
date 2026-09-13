import EventKit
@testable import RemindersLibrary
import XCTest

final class SortTests: XCTestCase {
    private let store = EKEventStore()

    private func makeReminder(
        title: String = "Test", due: Date? = nil, priority: Priority = .none
    ) -> EKReminder {
        let reminder = EKReminder(eventStore: store)
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = "Test list"
        reminder.calendar = calendar
        reminder.title = title
        reminder.priority = Int(priority.value.rawValue)
        if let due {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: due)
        }
        return reminder
    }

    private func titles(_ reminders: [EKReminder], sort: Sort, order: CustomSortOrder) -> [String] {
        reminders.sorted(by: sort.sortFunction(order: order)).map { $0.title! }
    }

    func testPriorityAscendingOrdersHighMediumLowNone() throws {
        let high = makeReminder(title: "high", priority: .high)
        let medium = makeReminder(title: "medium", priority: .medium)
        let low = makeReminder(title: "low", priority: .low)
        let none = makeReminder(title: "none", priority: .none)

        let result = titles([none, low, high, medium], sort: .priority, order: .ascending)
        XCTAssertEqual(result, ["high", "medium", "low", "none"])
    }

    func testPriorityDescendingReversesOrder() throws {
        let high = makeReminder(title: "high", priority: .high)
        let medium = makeReminder(title: "medium", priority: .medium)
        let low = makeReminder(title: "low", priority: .low)
        let none = makeReminder(title: "none", priority: .none)

        let result = titles([none, low, high, medium], sort: .priority, order: .descending)
        XCTAssertEqual(result, ["none", "low", "medium", "high"])
    }

    func testPriorityTiesBreakByDueDateAscendingRegardlessOfSortOrder() throws {
        let now = Date()
        let earlier = makeReminder(title: "earlier", due: now, priority: .high)
        let later = makeReminder(title: "later", due: now.addingTimeInterval(3600), priority: .high)

        XCTAssertEqual(
            titles([later, earlier], sort: .priority, order: .ascending), ["earlier", "later"])
        XCTAssertEqual(
            titles([later, earlier], sort: .priority, order: .descending), ["earlier", "later"])
    }

    func testPriorityTieWithNoDueDateOnEitherSideDoesNotCrash() throws {
        let a = makeReminder(title: "a", priority: .none)
        let b = makeReminder(title: "b", priority: .none)

        XCTAssertEqual(titles([b, a], sort: .priority, order: .ascending).count, 2)
    }

    func testDueDateAscendingPutsReminderWithoutDueDateLast() throws {
        let due = makeReminder(title: "due", due: Date())
        let noDue = makeReminder(title: "no-due")

        let result = titles([noDue, due], sort: .dueDate, order: .ascending)
        XCTAssertEqual(result, ["due", "no-due"])
    }

    func testDueDateDescendingPutsReminderWithoutDueDateLast() throws {
        let due = makeReminder(title: "due", due: Date())
        let noDue = makeReminder(title: "no-due")

        let result = titles([noDue, due], sort: .dueDate, order: .descending)
        XCTAssertEqual(result, ["due", "no-due"])
    }

    func testPriorityMixedSetOrdersEndToEnd() throws {
        let now = Date()
        let highLater = makeReminder(title: "high-later", due: now.addingTimeInterval(3600), priority: .high)
        let highEarlier = makeReminder(title: "high-earlier", due: now, priority: .high)
        let highNoDue = makeReminder(title: "high-no-due", priority: .high)
        let medium = makeReminder(title: "medium", priority: .medium)
        let low = makeReminder(title: "low", priority: .low)
        let noneWithDue = makeReminder(title: "none-with-due", due: now, priority: .none)
        let noneNoDue = makeReminder(title: "none-no-due", priority: .none)

        let result = titles(
            [noneNoDue, low, highLater, medium, noneWithDue, highEarlier, highNoDue],
            sort: .priority, order: .ascending)

        XCTAssertEqual(
            result,
            ["high-earlier", "high-later", "high-no-due", "medium", "low", "none-with-due", "none-no-due"])
    }
}
