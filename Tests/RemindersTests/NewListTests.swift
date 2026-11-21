@testable import RemindersLibrary
import XCTest

final class NewListTests: XCTestCase {
    // The setup from keith/reminders-cli#111: two sources titled "iCloud", where only the second
    // one (the reminders account) actually holds reminder lists.
    private let duplicateICloud = [
        ListSourceCandidate(title: "Subscribed Calendars", holdsReminderLists: false),
        ListSourceCandidate(title: "iCloud", holdsReminderLists: false),
        ListSourceCandidate(title: "Other", holdsReminderLists: false),
        ListSourceCandidate(title: "iCloud", holdsReminderLists: true),
    ]

    func testDuplicateTitlesResolveWithoutSourceOption() {
        XCTAssertEqual(selectListSource(requested: nil, from: duplicateICloud), .chosen(3))
    }

    func testRequestedTitlePicksTheReminderCapableDuplicate() {
        XCTAssertEqual(selectListSource(requested: "iCloud", from: duplicateICloud), .chosen(3))
    }

    func testRequestedTitleWithoutReminderListsIsNotFound() {
        XCTAssertEqual(
            selectListSource(requested: "Other", from: duplicateICloud), .notFound("Other"))
    }

    func testUnknownRequestedTitleIsNotFound() {
        XCTAssertEqual(
            selectListSource(requested: "Nope", from: duplicateICloud), .notFound("Nope"))
    }

    func testDistinctReminderCapableTitlesAreAmbiguous() {
        let candidates = [
            ListSourceCandidate(title: "iCloud", holdsReminderLists: true),
            ListSourceCandidate(title: "Subscribed Calendars", holdsReminderLists: false),
            ListSourceCandidate(title: "Exchange", holdsReminderLists: true),
        ]
        XCTAssertEqual(
            selectListSource(requested: nil, from: candidates), .ambiguous(["iCloud", "Exchange"]))
    }

    func testAmbiguityResolvedByRequestedTitle() {
        let candidates = [
            ListSourceCandidate(title: "iCloud", holdsReminderLists: true),
            ListSourceCandidate(title: "Exchange", holdsReminderLists: true),
        ]
        XCTAssertEqual(selectListSource(requested: "Exchange", from: candidates), .chosen(1))
    }

    func testNoReminderCapableSources() {
        let candidates = [
            ListSourceCandidate(title: "Subscribed Calendars", holdsReminderLists: false),
            ListSourceCandidate(title: "iCloud", holdsReminderLists: false),
        ]
        XCTAssertEqual(selectListSource(requested: nil, from: candidates), .noSources)
        XCTAssertEqual(selectListSource(requested: "iCloud", from: candidates), .noSources)
    }

    func testEmptyCandidates() {
        XCTAssertEqual(selectListSource(requested: nil, from: []), .noSources)
    }
}
