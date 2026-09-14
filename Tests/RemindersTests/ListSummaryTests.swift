import EventKit
@testable import RemindersLibrary
import XCTest

/// Covers the fetch-free half of `show-lists`: bucketing reminders into per-list counts, the JSON
/// shape, the aligned plain rendering and `--sort`. Constructing EventKit objects in-process needs
/// no Reminders access; only fetching does.
final class ListSummaryTests: XCTestCase {
    private let store = EKEventStore()

    /// `dueDateComponents` only stores whole seconds, so boundary comparisons need a
    /// cutoff without fractional seconds to avoid spurious off-by-a-fraction failures.
    private func wholeSecond(_ date: Date = Date()) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970))
    }

    private func makeCalendar(title: String) -> EKCalendar {
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = title
        return calendar
    }

    private func makeReminder(
        on calendar: EKCalendar, due: Date? = nil, completed: Bool = false
    ) -> EKReminder {
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = calendar
        reminder.title = "Test"
        if let due {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: due)
        }
        reminder.isCompleted = completed
        return reminder
    }

    private func summary(
        _ title: String, id: String = "ID", open: Int = 0, overdue: Int = 0, completed: Int? = nil
    ) -> ListSummary {
        ListSummary(
            title: title, calendarIdentifier: id, openCount: open, overdueCount: overdue,
            completedCount: completed)
    }

    // MARK: - Counting

    func testCountsOpenAndOverduePerList() throws {
        let now = Date()
        let soon = makeCalendar(title: "Soon")
        let eventually = makeCalendar(title: "Eventually")
        let reminders = [
            makeReminder(on: soon, due: now.addingTimeInterval(-3600)),
            makeReminder(on: soon, due: now.addingTimeInterval(3600)),
            makeReminder(on: soon),
            makeReminder(on: eventually, due: now.addingTimeInterval(-86400)),
        ]

        let summaries = summarizeLists(
            [soon, eventually], reminders: reminders, now: now, includeCompleted: false)

        XCTAssertEqual(summaries, [
            summary("Soon", id: soon.calendarIdentifier, open: 3, overdue: 1),
            summary("Eventually", id: eventually.calendarIdentifier, open: 1, overdue: 1),
        ])
    }

    func testListWithoutRemindersReportsZeroCounts() throws {
        let empty = makeCalendar(title: "Someday")
        let summaries = summarizeLists([empty], reminders: [], now: Date(), includeCompleted: false)
        XCTAssertEqual(summaries, [summary("Someday", id: empty.calendarIdentifier)])
    }

    func testRemindersOnUnknownCalendarAreIgnored() throws {
        let known = makeCalendar(title: "Known")
        let other = makeCalendar(title: "Other")
        let summaries = summarizeLists(
            [known], reminders: [makeReminder(on: other)], now: Date(), includeCompleted: false)
        XCTAssertEqual(summaries, [summary("Known", id: known.calendarIdentifier)])
    }

    func testDueExactlyNowIsNotOverdue() throws {
        let now = wholeSecond()
        let list = makeCalendar(title: "List")
        let reminders = [
            makeReminder(on: list, due: now),
            makeReminder(on: list, due: now.addingTimeInterval(-1)),
        ]
        let summaries = summarizeLists(
            [list], reminders: reminders, now: now, includeCompleted: false)
        XCTAssertEqual(summaries.first?.openCount, 2)
        XCTAssertEqual(summaries.first?.overdueCount, 1)
    }

    func testCompletedRemindersAreNeitherOpenNorOverdue() throws {
        let now = Date()
        let list = makeCalendar(title: "List")
        let reminders = [
            makeReminder(on: list, due: now.addingTimeInterval(-3600), completed: true),
            makeReminder(on: list, completed: true),
            makeReminder(on: list),
        ]
        let summaries = summarizeLists(
            [list], reminders: reminders, now: now, includeCompleted: true)
        XCTAssertEqual(summaries, [
            summary("List", id: list.calendarIdentifier, open: 1, overdue: 0, completed: 2),
        ])
    }

    func testCompletedCountOnlyWithIncludeCompleted() throws {
        let list = makeCalendar(title: "List")
        let reminders = [makeReminder(on: list, completed: true)]

        let without = summarizeLists(
            [list], reminders: reminders, now: Date(), includeCompleted: false)
        XCTAssertNil(without.first?.completedCount)

        let with = summarizeLists([list], reminders: reminders, now: Date(), includeCompleted: true)
        XCTAssertEqual(with.first?.completedCount, 1)
    }

    // MARK: - JSON

    func testJsonOmitsCompletedCountWhenNotCounted() throws {
        let data = try JSONEncoder().encode(summary("Soon", id: "ABC", open: 12, overdue: 3))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["title"] as? String, "Soon")
        XCTAssertEqual(json["calendarIdentifier"] as? String, "ABC")
        XCTAssertEqual(json["openCount"] as? Int, 12)
        XCTAssertEqual(json["overdueCount"] as? Int, 3)
        XCTAssertNil(json["completedCount"])
        XCTAssertEqual(json.count, 4)
    }

    func testJsonIncludesCompletedCountWhenCounted() throws {
        let data = try JSONEncoder().encode(summary("Soon", open: 1, completed: 40))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["completedCount"] as? Int, 40)
    }

    // MARK: - Plain output

    func testPlainOutputAlignsColumns() throws {
        let lines = formatListSummaries([
            summary("Soon", id: "2A29C8B1-3D0F-4A9E-9C8D-5B6E7F8A9B0C", open: 12, overdue: 3),
            summary("Eventually", id: "7E1F2A3B-4C5D-6E7F-8A9B-0C1D2E3F4A5B", open: 4),
            summary("Someday", id: "9F0A1B2C-3D4E-5F60-7182-93A4B5C6D7E8"),
        ])
        XCTAssertEqual(lines, [
            "Soon        (2A29C8B1-3D0F-4A9E-9C8D-5B6E7F8A9B0C)   12 open, 3 overdue",
            "Eventually  (7E1F2A3B-4C5D-6E7F-8A9B-0C1D2E3F4A5B)    4 open",
            "Someday     (9F0A1B2C-3D4E-5F60-7182-93A4B5C6D7E8)    0 open",
        ])
    }

    func testPlainOutputAppendsCompletedCount() throws {
        let lines = formatListSummaries([
            summary("Soon", open: 2, overdue: 1, completed: 40),
            summary("Done", completed: 0),
        ])
        XCTAssertEqual(lines, [
            "Soon  (ID)   2 open, 1 overdue, 40 completed",
            "Done  (ID)   0 open, 0 completed",
        ])
    }

    // MARK: - Sorting

    func testSortNoneKeepsOrder() throws {
        let summaries = [summary("b", open: 1), summary("a", open: 2)]
        XCTAssertEqual(ListSort.none.apply(to: summaries), summaries)
    }

    func testSortByNameIsCaseInsensitive() throws {
        let sorted = ListSort.name.apply(
            to: [summary("banana"), summary("Cherry"), summary("apple")])
        XCTAssertEqual(sorted.map { $0.title }, ["apple", "banana", "Cherry"])
    }

    func testSortByOpenIsDescendingWithNameTieBreak() throws {
        let sorted = ListSort.open.apply(to: [
            summary("Zeta", open: 4), summary("Alpha", open: 4), summary("Busy", open: 12),
            summary("Empty", open: 0),
        ])
        XCTAssertEqual(sorted.map { $0.title }, ["Busy", "Alpha", "Zeta", "Empty"])
    }

    func testSortByOverdueIsDescending() throws {
        let sorted = ListSort.overdue.apply(to: [
            summary("Fine", open: 20, overdue: 0), summary("Late", open: 3, overdue: 3),
            summary("Slipping", open: 8, overdue: 1),
        ])
        XCTAssertEqual(sorted.map { $0.title }, ["Late", "Slipping", "Fine"])
    }
}
