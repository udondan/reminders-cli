import EventKit
@testable import RemindersLibrary
import XCTest

/// Stand-ins for the undocumented EventKit/ReminderKit objects `flaggedKeyPath` walks through, so
/// every way the chain can break is exercised without depending on the real private classes.
private final class FakeFlaggedContext: NSObject {
    @objc let flagged: Any?

    init(flagged: Any?) {
        self.flagged = flagged
    }
}

private final class FakeRemReminder: NSObject {
    @objc let flaggedContext: NSObject?

    init(flaggedContext: NSObject?) {
        self.flaggedContext = flaggedContext
    }
}

private final class FakeBackingObject: NSObject {
    @objc let _reminder: NSObject?

    init(reminder: NSObject?) {
        self._reminder = reminder
    }
}

private final class FakeReminder: NSObject {
    @objc let backingObject: NSObject?

    init(backingObject: NSObject?) {
        self.backingObject = backingObject
    }
}

final class FlaggedTests: XCTestCase {
    private func chain(flagged: Any?) -> NSObject {
        FakeReminder(backingObject: FakeBackingObject(reminder: FakeRemReminder(
            flaggedContext: FakeFlaggedContext(flagged: flagged))))
    }

    func testReadsTrueFlag() throws {
        XCTAssertTrue(readFlag(from: chain(flagged: true), keyPath: flaggedKeyPath))
    }

    func testReadsFalseFlag() throws {
        XCTAssertFalse(readFlag(from: chain(flagged: false), keyPath: flaggedKeyPath))
    }

    func testMissingSelectorReadsAsNotFlagged() throws {
        // `FakeBackingObject` has no `flaggedContext`; without the `responds(to:)` guard this would
        // raise NSUndefinedKeyException and crash the test run.
        let root = FakeReminder(backingObject: FakeBackingObject(reminder: FakeBackingObject(reminder: nil)))
        XCTAssertFalse(readFlag(from: root, keyPath: flaggedKeyPath))
    }

    func testNilIntermediateReadsAsNotFlagged() throws {
        let root = FakeReminder(backingObject: FakeBackingObject(reminder: nil))
        XCTAssertFalse(readFlag(from: root, keyPath: flaggedKeyPath))
    }

    func testNilLeafReadsAsNotFlagged() throws {
        XCTAssertFalse(readFlag(from: chain(flagged: nil), keyPath: flaggedKeyPath))
    }

    func testNonBooleanLeafReadsAsNotFlagged() throws {
        XCTAssertFalse(readFlag(from: chain(flagged: "yes"), keyPath: flaggedKeyPath))
    }

    func testUnsavedReminderIsNotFlagged() throws {
        let store = EKEventStore()
        XCTAssertFalse(EKReminder(eventStore: store).isFlagged)
    }

    func testJSONAlwaysIncludesIsFlagged() throws {
        let store = EKEventStore()
        let reminder = EKReminder(eventStore: store)
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = "Test"
        reminder.calendar = calendar
        reminder.title = "Unflagged"

        let data = try JSONEncoder().encode(reminder)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["isFlagged"] as? Bool, false)
    }
}
