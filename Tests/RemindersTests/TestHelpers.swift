import ArgumentParser
import EventKit
@testable import RemindersLibrary
import XCTest

/// Asserts that parsing `arguments` fails with an error message containing `message`. A bare
/// `XCTAssertThrowsError(try CLI.parseAsRoot(...))` also passes when the arguments fail for another
/// reason, such as a misspelled option, so the test would no longer check the rule it's named after.
/// Only parses, so nothing reads or changes reminders.
func assertParseError(
    _ arguments: [String], contains message: String,
    file: StaticString = #filePath, line: UInt = #line
) {
    XCTAssertThrowsError(try CLI.parseAsRoot(arguments), file: file, line: line) { error in
        let rendered = CLI.message(for: error)
        XCTAssertTrue(
            rendered.contains(message), "expected '\(message)' in '\(rendered)'", file: file, line: line)
    }
}

/// Fixtures for tests of code that takes an `EKReminder`. Every reminder and list is built in memory
/// and never saved, so nothing reads or changes real reminders. Dates are in UTC.
class InMemoryReminderTestCase: XCTestCase {
    let store = EKEventStore()

    let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    /// Due date components the way `DateComponents(argument:)` produces them: carrying their own
    /// calendar, since `.date` is nil without one. No hour means a date-only due date.
    func due(_ year: Int, _ month: Int, _ day: Int, hour: Int? = nil) -> DateComponents {
        var components = DateComponents(
            year: year, month: month, day: day, hour: hour, minute: hour.map { _ in 0 })
        components.calendar = utc
        components.timeZone = utc.timeZone
        return components
    }

    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0)
        -> Date
    {
        utc.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    func makeReminder(title: String = "Water plants", listTitle: String = "Home") -> EKReminder {
        let reminder = EKReminder(eventStore: store)
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = listTitle
        reminder.calendar = calendar
        reminder.title = title
        return reminder
    }

    func alarmDates(of reminder: EKReminder) -> [Date?] {
        (reminder.alarms ?? []).map { $0.absoluteDate }
    }

    func assertCLIError<T>(
        _ expression: @autoclosure () throws -> T, code: CLIError.Code, message: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            let cliError = error as? CLIError
            XCTAssertEqual(cliError?.code, code, file: file, line: line)
            XCTAssertEqual(cliError?.message, message, file: file, line: line)
        }
    }
}
