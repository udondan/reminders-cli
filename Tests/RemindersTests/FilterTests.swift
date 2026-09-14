import EventKit
@testable import RemindersLibrary
import XCTest

final class FilterTests: XCTestCase {
    private let store = EKEventStore()

    /// `dueDateComponents` only stores whole seconds, so boundary comparisons need a
    /// cutoff without fractional seconds to avoid spurious off-by-a-fraction failures.
    private func wholeSecond(_ date: Date = Date()) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970))
    }

    private func makeReminder(
        title: String = "Test", notes: String? = nil, due: Date? = nil, priority: Priority = .none,
        completed: Date? = nil
    ) -> EKReminder {
        let reminder = EKReminder(eventStore: store)
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = "Test list"
        reminder.calendar = calendar
        reminder.title = title
        reminder.notes = notes
        reminder.priority = Int(priority.value.rawValue)
        if let due {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: due)
        }
        if let completed {
            reminder.isCompleted = true
            reminder.completionDate = completed
        }
        return reminder
    }

    private func matches(
        _ reminder: EKReminder,
        now: Date = Date(),
        overdue: Bool = false,
        dueBefore: Date? = nil,
        dueAfter: Date? = nil,
        noDueDate: Bool = false,
        priorities: [Priority] = [],
        search: String? = nil,
        completedSince: Date? = nil
    ) -> Bool {
        matchesAdditionalFilters(
            reminder, now: now, overdue: overdue, dueBefore: dueBefore, dueAfter: dueAfter,
            noDueDate: noDueDate, priorities: priorities, search: search, completedSince: completedSince)
    }

    func testNoFiltersMatchesEverything() throws {
        XCTAssertTrue(matches(makeReminder()))
        XCTAssertTrue(matches(makeReminder(due: Date())))
    }

    func testOverdueMatchesPastDueDate() throws {
        let now = Date()
        let reminder = makeReminder(due: now.addingTimeInterval(-3600))
        XCTAssertTrue(matches(reminder, now: now, overdue: true))
    }

    func testOverdueRejectsFutureDueDate() throws {
        let now = Date()
        let reminder = makeReminder(due: now.addingTimeInterval(3600))
        XCTAssertFalse(matches(reminder, now: now, overdue: true))
    }

    func testOverdueRejectsReminderWithNoDueDate() throws {
        let now = Date()
        XCTAssertFalse(matches(makeReminder(), now: now, overdue: true))
    }

    /// `show-lists` counts overdue reminders through the same predicate as `--overdue`, so pin
    /// its boundary here: strictly before `now`, never for a reminder without a due date.
    func testIsOverdueIsStrictlyBeforeNow() throws {
        let now = wholeSecond()
        XCTAssertTrue(isOverdue(makeReminder(due: now.addingTimeInterval(-1)), now: now))
        XCTAssertFalse(isOverdue(makeReminder(due: now), now: now))
        XCTAssertFalse(isOverdue(makeReminder(due: now.addingTimeInterval(1)), now: now))
        XCTAssertFalse(isOverdue(makeReminder(), now: now))
    }

    func testDueBeforeIncludesExactBoundary() throws {
        let cutoff = wholeSecond()
        let reminder = makeReminder(due: cutoff)
        XCTAssertTrue(matches(reminder, dueBefore: cutoff))
    }

    func testDueBeforeRejectsAfterBoundary() throws {
        let cutoff = wholeSecond()
        let reminder = makeReminder(due: cutoff.addingTimeInterval(1))
        XCTAssertFalse(matches(reminder, dueBefore: cutoff))
    }

    func testDueAfterIncludesExactBoundary() throws {
        let cutoff = wholeSecond()
        let reminder = makeReminder(due: cutoff)
        XCTAssertTrue(matches(reminder, dueAfter: cutoff))
    }

    func testDueAfterRejectsBeforeBoundary() throws {
        let cutoff = wholeSecond()
        let reminder = makeReminder(due: cutoff.addingTimeInterval(-1))
        XCTAssertFalse(matches(reminder, dueAfter: cutoff))
    }

    func testDueBeforeAndAfterRejectReminderWithNoDueDate() throws {
        let cutoff = wholeSecond()
        XCTAssertFalse(matches(makeReminder(), dueBefore: cutoff))
        XCTAssertFalse(matches(makeReminder(), dueAfter: cutoff))
    }

    func testCompletedSinceIncludesExactBoundary() throws {
        let cutoff = wholeSecond()
        let reminder = makeReminder(completed: cutoff)
        XCTAssertTrue(matches(reminder, completedSince: cutoff))
    }

    func testCompletedSinceRejectsBeforeBoundary() throws {
        let cutoff = wholeSecond()
        let reminder = makeReminder(completed: cutoff.addingTimeInterval(-1))
        XCTAssertFalse(matches(reminder, completedSince: cutoff))
    }

    func testCompletedSinceRejectsIncompleteReminder() throws {
        let cutoff = wholeSecond()
        XCTAssertFalse(matches(makeReminder(), completedSince: cutoff))
    }

    func testNoDueDateMatchesReminderWithoutDueDate() throws {
        XCTAssertTrue(matches(makeReminder(), noDueDate: true))
    }

    func testNoDueDateRejectsReminderWithDueDate() throws {
        XCTAssertFalse(matches(makeReminder(due: Date()), noDueDate: true))
    }

    func testPriorityMatchesListedValue() throws {
        let reminder = makeReminder(priority: .high)
        XCTAssertTrue(matches(reminder, priorities: [.medium, .high]))
    }

    func testPriorityRejectsUnlistedValue() throws {
        let reminder = makeReminder(priority: .low)
        XCTAssertFalse(matches(reminder, priorities: [.medium, .high]))
    }

    func testPriorityNoneIsNormalizedForFiltering() throws {
        let reminder = makeReminder(priority: .none)
        XCTAssertTrue(matches(reminder, priorities: [.none]))
        XCTAssertFalse(matches(reminder, priorities: [.high]))
    }

    func testSearchMatchesTitleCaseInsensitively() throws {
        let reminder = makeReminder(title: "Buy Groceries")
        XCTAssertTrue(matches(reminder, search: "groceries"))
    }

    func testSearchMatchesNotesCaseInsensitively() throws {
        let reminder = makeReminder(title: "Errand", notes: "Pick up Dry Cleaning")
        XCTAssertTrue(matches(reminder, search: "dry cleaning"))
    }

    func testSearchRejectsNonMatchingText() throws {
        let reminder = makeReminder(title: "Errand", notes: "Pick up dry cleaning")
        XCTAssertFalse(matches(reminder, search: "groceries"))
    }
}
