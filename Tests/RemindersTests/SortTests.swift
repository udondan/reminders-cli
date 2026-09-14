import EventKit
@testable import RemindersLibrary
import XCTest

final class SortTests: XCTestCase {
    private let store = EKEventStore()

    /// 2024-01-04 09:00 UTC; a fixed date keeps the due dates away from any day boundary.
    private let now = Date(timeIntervalSince1970: 1_704_358_800)

    private func makeReminder(
        title: String = "Test", due: Date? = nil, priority: Priority = .none, created: Date? = nil
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
        if let created {
            // `creationDate` is read-only and only set by the store on save; KVC sets it on this
            // unsaved, in-memory reminder.
            reminder.setValue(created, forKey: "creationDate")
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
        let earlier = makeReminder(title: "earlier", due: now, priority: .high)
        let later = makeReminder(title: "later", due: now.addingTimeInterval(3600), priority: .high)

        XCTAssertEqual(
            titles([later, earlier], sort: .priority, order: .ascending), ["earlier", "later"])
        XCTAssertEqual(
            titles([later, earlier], sort: .priority, order: .descending), ["earlier", "later"])
    }

    func testPriorityTieWithNoDueDateOnEitherSideIsATie() throws {
        let a = makeReminder(title: "a", priority: .none)
        let b = makeReminder(title: "b", priority: .none)

        for order in CustomSortOrder.allCases {
            let areInIncreasingOrder = Sort.priority.sortFunction(order: order)
            XCTAssertFalse(areInIncreasingOrder(a, b), "\(order)")
            XCTAssertFalse(areInIncreasingOrder(b, a), "\(order)")
        }
    }

    func testDueDateAscendingPutsReminderWithoutDueDateLast() throws {
        let due = makeReminder(title: "due", due: now)
        let noDue = makeReminder(title: "no-due")

        let result = titles([noDue, due], sort: .dueDate, order: .ascending)
        XCTAssertEqual(result, ["due", "no-due"])
    }

    func testDueDateDescendingPutsReminderWithoutDueDateLast() throws {
        let due = makeReminder(title: "due", due: now)
        let noDue = makeReminder(title: "no-due")

        let result = titles([noDue, due], sort: .dueDate, order: .descending)
        XCTAssertEqual(result, ["due", "no-due"])
    }

    func testDueDateOrdersDatedReminders() throws {
        let first = makeReminder(title: "first", due: now)
        let second = makeReminder(title: "second", due: now.addingTimeInterval(60))
        let third = makeReminder(title: "third", due: now.addingTimeInterval(86_400 * 3))
        let noDue = makeReminder(title: "no-due")
        let shuffled = [second, noDue, third, first]

        XCTAssertEqual(
            titles(shuffled, sort: .dueDate, order: .ascending), ["first", "second", "third", "no-due"])
        XCTAssertEqual(
            titles(shuffled, sort: .dueDate, order: .descending), ["third", "second", "first", "no-due"])
    }

    func testCreationDateOrdersBothWays() throws {
        let old = makeReminder(title: "old", created: now.addingTimeInterval(-86_400))
        let middle = makeReminder(title: "middle", created: now.addingTimeInterval(-60))
        let new = makeReminder(title: "new", created: now)
        let shuffled = [middle, new, old]

        XCTAssertEqual(titles(shuffled, sort: .creationDate, order: .ascending), ["old", "middle", "new"])
        XCTAssertEqual(titles(shuffled, sort: .creationDate, order: .descending), ["new", "middle", "old"])
    }

    func testPriorityMixedSetOrdersEndToEnd() throws {
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
