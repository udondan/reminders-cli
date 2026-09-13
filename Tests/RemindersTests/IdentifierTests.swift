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

    func testResolveCalendarByExactId() throws {
        let a = makeCalendar(title: "A")
        let b = makeCalendar(title: "B")
        let resolved = try resolveCalendar([a, b], nameOrId: b.calendarIdentifier)
        XCTAssertEqual(resolved.calendarIdentifier, b.calendarIdentifier)
    }

    func testResolveCalendarPrefersIdOverCollidingTitle() throws {
        // `a`'s title collides with `b`'s identifier; the ID match must win.
        let b = makeCalendar(title: "Work")
        let a = makeCalendar(title: b.calendarIdentifier)
        let resolved = try resolveCalendar([a, b], nameOrId: b.calendarIdentifier)
        XCTAssertEqual(resolved.calendarIdentifier, b.calendarIdentifier)
    }

    func testResolveCalendarByExactTitleBeatsCaseInsensitiveTitle() throws {
        let lower = makeCalendar(title: "work")
        let upper = makeCalendar(title: "Work")
        let resolved = try resolveCalendar([lower, upper], nameOrId: "Work")
        XCTAssertEqual(resolved.calendarIdentifier, upper.calendarIdentifier)
    }

    func testResolveCalendarByCaseInsensitiveTitle() throws {
        let a = makeCalendar(title: "Groceries")
        let b = makeCalendar(title: "Work")
        let resolved = try resolveCalendar([a, b], nameOrId: "groceries")
        XCTAssertEqual(resolved.calendarIdentifier, a.calendarIdentifier)
    }

    func testResolveCalendarCaseInsensitiveTitleBeatsSubstring() throws {
        // "work" is also a substring of "Work – Side projects"; the whole-title match must win
        // rather than being reported as ambiguous.
        let work = makeCalendar(title: "Work")
        let side = makeCalendar(title: "Work – Side projects")
        let resolved = try resolveCalendar([side, work], nameOrId: "work")
        XCTAssertEqual(resolved.calendarIdentifier, work.calendarIdentifier)
    }

    func testResolveCalendarByUniqueSubstring() throws {
        let work = makeCalendar(title: "Work")
        let side = makeCalendar(title: "Work – Side projects")
        let groceries = makeCalendar(title: "Groceries")
        let resolved = try resolveCalendar([work, side, groceries], nameOrId: "SIDE")
        XCTAssertEqual(resolved.calendarIdentifier, side.calendarIdentifier)
    }

    func testResolveCalendarThrowsListAmbiguousForSharedSubstring() throws {
        let work = makeCalendar(title: "Work")
        let side = makeCalendar(title: "Work – Side projects")
        let groceries = makeCalendar(title: "Groceries")
        XCTAssertThrowsError(try resolveCalendar([work, side, groceries], nameOrId: "wor")) { error in
            XCTAssertEqual(
                error as? CLIError, .listAmbiguous("wor", matches: ["Work", "Work – Side projects"]))
        }
    }

    func testResolveCalendarThrowsListNotFoundWithAvailableLists() throws {
        let a = makeCalendar(title: "Groceries")
        let b = makeCalendar(title: "Work")
        let missing = UUID().uuidString
        XCTAssertThrowsError(try resolveCalendar([a, b], nameOrId: missing)) { error in
            XCTAssertEqual(error as? CLIError, .listNotFound(missing, available: ["Groceries", "Work"]))
        }
    }

    func testResolveCalendarThrowsListNotFoundWhenThereAreNoLists() throws {
        XCTAssertThrowsError(try resolveCalendar([], nameOrId: "Groceries")) { error in
            XCTAssertEqual(error as? CLIError, .listNotFound("Groceries"))
        }
    }

    func testResolveCalendarDoesNotSubstringMatchEmptyInput() throws {
        let a = makeCalendar(title: "Groceries")
        let b = makeCalendar(title: "Work")
        for input in ["", "  "] {
            XCTAssertThrowsError(try resolveCalendar([a, b], nameOrId: input), "input '\(input)'") { error in
                XCTAssertEqual((error as? CLIError)?.code, .listNotFound, "input '\(input)'")
            }
        }
    }

    // MARK: - Identifier matching

    private let ids = [
        "44C111DE-0B69-4E96-8C93-6A5D0A6C2A17",
        "44C1AAAA-1111-2222-3333-444444444444",
        "2A29C8B1-3D0F-4A9E-9C8D-5B6E7F8A9B0C",
        "ab",
    ]

    func testMatchIdentifierExact() {
        XCTAssertEqual(matchIdentifier(ids, idOrPrefix: "2A29C8B1-3D0F-4A9E-9C8D-5B6E7F8A9B0C"), .found(2))
    }

    func testMatchIdentifierExactMatchIgnoresMinimumLength() {
        XCTAssertEqual(matchIdentifier(ids, idOrPrefix: "ab"), .found(3))
    }

    func testMatchIdentifierExactMatchIsCaseSensitive() {
        // "AB" is shorter than the minimum prefix length, so it can't fall through to the
        // case-insensitive prefix step either.
        XCTAssertEqual(matchIdentifier(ids, idOrPrefix: "AB"), .notFound)
    }

    func testMatchIdentifierByPrefix() {
        XCTAssertEqual(matchIdentifier(ids, idOrPrefix: "2A29"), .found(2))
        XCTAssertEqual(matchIdentifier(ids, idOrPrefix: "44C111"), .found(0))
    }

    func testMatchIdentifierPrefixIsCaseInsensitive() {
        XCTAssertEqual(matchIdentifier(ids, idOrPrefix: "2a29c8"), .found(2))
    }

    func testMatchIdentifierPrefixMustBeAnchored() {
        XCTAssertEqual(matchIdentifier(ids, idOrPrefix: "0B69"), .notFound)
    }

    func testMatchIdentifierAmbiguousPrefix() {
        XCTAssertEqual(matchIdentifier(ids, idOrPrefix: "44C1"), .ambiguous([0, 1]))
    }

    func testMatchIdentifierPrefixShorterThanMinimumIsNotFound() {
        XCTAssertEqual(matchIdentifier(ids, idOrPrefix: "2A2"), .notFound)
        XCTAssertEqual(matchIdentifier(ids, idOrPrefix: "2A2", minimumPrefixLength: 3), .found(2))
    }

    func testMatchIdentifierUnknown() {
        XCTAssertEqual(matchIdentifier(ids, idOrPrefix: "FFFFFFFF"), .notFound)
        XCTAssertEqual(matchIdentifier([], idOrPrefix: "2A29"), .notFound)
    }

    // MARK: - Reminder resolution

    func testResolveReminderByExactId() throws {
        let calendar = makeCalendar(title: "List")
        let reminder = makeReminder(title: "Only", calendar: calendar)
        let other = makeReminder(title: "Other", calendar: calendar)
        let resolved = try resolveReminder(
            [other, reminder], idOrPrefix: reminder.calendarItemExternalIdentifier, onList: "List")
        XCTAssertEqual(resolved.title, "Only")
    }

    func testResolveReminderByPrefix() throws {
        let calendar = makeCalendar(title: "List")
        let reminder = makeReminder(title: "Only", calendar: calendar)
        let prefix = String(reminder.calendarItemExternalIdentifier.prefix(8)).lowercased()
        let resolved = try resolveReminder([reminder], idOrPrefix: prefix, onList: "List")
        XCTAssertEqual(resolved.title, "Only")
    }

    func testResolveReminderThrowsReminderNotFound() throws {
        let calendar = makeCalendar(title: "List")
        let reminder = makeReminder(calendar: calendar)
        XCTAssertThrowsError(
            try resolveReminder([reminder], idOrPrefix: "not-a-real-id", onList: "List")
        ) { error in
            XCTAssertEqual(
                error as? CLIError, .reminderNotFound(id: "not-a-real-id", listNameOrId: "List"))
        }
    }

    func testResolveReminderThrowsReminderNotFoundForShortPrefix() throws {
        let calendar = makeCalendar(title: "List")
        let reminder = makeReminder(calendar: calendar)
        let prefix = String(reminder.calendarItemExternalIdentifier.prefix(minimumIdPrefixLength - 1))
        XCTAssertThrowsError(try resolveReminder([reminder], idOrPrefix: prefix, onList: "List")) { error in
            XCTAssertEqual(error as? CLIError, .reminderNotFound(id: prefix, listNameOrId: "List"))
        }
    }

    // Two fresh `EKReminder`s only share an ID prefix by luck, so the ambiguous path is covered on
    // the string-based `resolveIdentifier` that `resolveReminder` delegates to.
    func testResolveIdentifierThrowsReminderAmbiguousWithIdsAndTitles() throws {
        let titles = ["Buy milk", "Buy eggs", "Ship it", "Short"]
        XCTAssertThrowsError(
            try resolveIdentifier(ids, titles: titles, idOrPrefix: "44c1", onList: "List")
        ) { error in
            XCTAssertEqual(
                error as? CLIError,
                .reminderAmbiguous(
                    id: "44c1",
                    matches: [
                        "44C111DE-0B69-4E96-8C93-6A5D0A6C2A17 (Buy milk)",
                        "44C1AAAA-1111-2222-3333-444444444444 (Buy eggs)",
                    ]))
        }
    }

    func testResolveIdentifierReturnsIndexOfUniquePrefix() throws {
        let titles = ["Buy milk", "Buy eggs", "Ship it", "Short"]
        XCTAssertEqual(try resolveIdentifier(ids, titles: titles, idOrPrefix: "2a29", onList: "List"), 2)
    }
}
