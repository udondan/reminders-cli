import EventKit
@testable import RemindersLibrary
import XCTest

final class RecurrenceTests: XCTestCase {
    func testDailyFrequencyMapping() throws {
        let rule = Recurrence.daily.recurrenceRule(interval: 1, end: nil)
        XCTAssertEqual(rule.frequency, .daily)
        XCTAssertEqual(rule.interval, 1)
        XCTAssertNil(rule.recurrenceEnd)
    }

    func testWeeklyFrequencyMapping() throws {
        let rule = Recurrence.weekly.recurrenceRule(interval: 1, end: nil)
        XCTAssertEqual(rule.frequency, .weekly)
    }

    func testMonthlyFrequencyMapping() throws {
        let rule = Recurrence.monthly.recurrenceRule(interval: 1, end: nil)
        XCTAssertEqual(rule.frequency, .monthly)
    }

    func testYearlyFrequencyMapping() throws {
        let rule = Recurrence.yearly.recurrenceRule(interval: 1, end: nil)
        XCTAssertEqual(rule.frequency, .yearly)
    }

    func testCustomInterval() throws {
        let rule = Recurrence.monthly.recurrenceRule(interval: 2, end: nil)
        XCTAssertEqual(rule.interval, 2)
    }

    func testRecurrenceEndDate() throws {
        let end = Date()
        let rule = Recurrence.weekly.recurrenceRule(
            interval: 1,
            end: EKRecurrenceEnd(end: end))
        XCTAssertNotNil(rule.recurrenceEnd)
        XCTAssertEqual(
            rule.recurrenceEnd?.endDate?.timeIntervalSince1970 ?? 0,
            end.timeIntervalSince1970,
            accuracy: 1.0)
    }

    func testRecurrenceEndCount() throws {
        let rule = Recurrence.daily.recurrenceRule(
            interval: 1,
            end: EKRecurrenceEnd(occurrenceCount: 12))
        XCTAssertEqual(rule.recurrenceEnd?.occurrenceCount, 12)
        XCTAssertNil(rule.recurrenceEnd?.endDate)
    }

    func testChangingFrequencyPreservesExistingEnd() throws {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        let existing = Recurrence.daily.recurrenceRule(
            interval: 2,
            end: EKRecurrenceEnd(end: end))
        let result = try RecurrenceUpdate(
            recurrence: .weekly,
            interval: nil,
            end: .unchanged
        ).rule(replacing: existing)

        XCTAssertEqual(result.frequency, .weekly)
        XCTAssertEqual(result.interval, 1)
        XCTAssertEqual(
            result.recurrenceEnd?.endDate?.timeIntervalSince1970 ?? 0,
            end.timeIntervalSince1970,
            accuracy: 1.0)
    }

    func testChangingFrequencyUsesExplicitInterval() throws {
        let existing = Recurrence.daily.recurrenceRule(interval: 2, end: nil)
        let result = try RecurrenceUpdate(
            recurrence: .monthly,
            interval: 3,
            end: .unchanged
        ).rule(replacing: existing)

        XCTAssertEqual(result.frequency, .monthly)
        XCTAssertEqual(result.interval, 3)
    }

    func testEndOnlyUpdatePreservesComplexSelectors() throws {
        let existing = EKRecurrenceRule(
            recurrenceWith: .monthly,
            interval: 2,
            daysOfTheWeek: [EKRecurrenceDayOfWeek(.friday, weekNumber: -1)],
            daysOfTheMonth: nil,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: [-1],
            end: nil)
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        let result = try RecurrenceUpdate(
            recurrence: nil,
            interval: nil,
            end: .date(end)
        ).rule(replacing: existing)

        XCTAssertEqual(result.frequency, .monthly)
        XCTAssertEqual(result.interval, 2)
        XCTAssertEqual(result.daysOfTheWeek?.first?.dayOfTheWeek, .friday)
        XCTAssertEqual(result.daysOfTheWeek?.first?.weekNumber, -1)
        XCTAssertEqual(result.setPositions?.first?.intValue, -1)
        XCTAssertFalse(result === existing)
        XCTAssertEqual(result.calendarIdentifier, existing.calendarIdentifier)
        XCTAssertEqual(result.firstDayOfTheWeek, existing.firstDayOfTheWeek)
        XCTAssertNil(existing.recurrenceEnd)
        XCTAssertEqual(
            result.recurrenceEnd?.endDate?.timeIntervalSince1970 ?? 0,
            end.timeIntervalSince1970,
            accuracy: 1.0)
    }

    func testClearEndPreservesRecurrence() throws {
        let existing = Recurrence.monthly.recurrenceRule(
            interval: 3,
            end: EKRecurrenceEnd(occurrenceCount: 8))
        let result = try RecurrenceUpdate(
            recurrence: nil,
            interval: nil,
            end: .clear
        ).rule(replacing: existing)

        XCTAssertEqual(result.frequency, .monthly)
        XCTAssertEqual(result.interval, 3)
        XCTAssertNil(result.recurrenceEnd)
    }

    func testEndOnlyUpdateRequiresExistingRule() throws {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertThrowsError(
            try RecurrenceUpdate(
                recurrence: nil,
                interval: nil,
                end: .date(end)
            ).rule(replacing: nil))
    }

    func testDateOnlyEndIncludesWholeLocalDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Belgrade"))
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = 2026
        components.month = 9
        components.day = 10

        let end = try XCTUnwrap(recurrenceEndDate(from: components))
        let resolved = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: end)
        XCTAssertEqual(resolved.year, 2026)
        XCTAssertEqual(resolved.month, 9)
        XCTAssertEqual(resolved.day, 10)
        XCTAssertEqual(resolved.hour, 23)
        XCTAssertEqual(resolved.minute, 59)
        XCTAssertEqual(resolved.second, 59)
    }

    func testJSONIncludesDateEnd() throws {
        let store = EKEventStore()
        let reminder = EKReminder(eventStore: store)
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = "Test"
        reminder.calendar = calendar
        reminder.title = "Medicine"
        reminder.addRecurrenceRule(
            Recurrence.daily.recurrenceRule(
                interval: 1,
                end: EKRecurrenceEnd(end: Date(timeIntervalSince1970: 1_800_000_000))))

        let data = try JSONEncoder().encode(reminder)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["recurrence"] as? String, "daily")
        XCTAssertEqual(object["recurrenceInterval"] as? Int, 1)
        XCTAssertNotNil(object["recurrenceEnd"] as? String)
        XCTAssertNil(object["recurrenceCount"])
        XCTAssertEqual(object["hasRecurrence"] as? Bool, true)
    }

    func testJSONIncludesCountEnd() throws {
        let store = EKEventStore()
        let reminder = EKReminder(eventStore: store)
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = "Test"
        reminder.calendar = calendar
        reminder.title = "Medicine"
        reminder.addRecurrenceRule(
            Recurrence.daily.recurrenceRule(
                interval: 1,
                end: EKRecurrenceEnd(occurrenceCount: 7)))

        let data = try JSONEncoder().encode(reminder)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["recurrenceCount"] as? Int, 7)
        XCTAssertNil(object["recurrenceEnd"])
        XCTAssertEqual(object["hasRecurrence"] as? Bool, true)
    }

    func testJSONHasRecurrenceFalseWhenNotRecurring() throws {
        let store = EKEventStore()
        let reminder = EKReminder(eventStore: store)
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = "Test"
        reminder.calendar = calendar
        reminder.title = "One-off"

        let data = try JSONEncoder().encode(reminder)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["hasRecurrence"] as? Bool, false)
        XCTAssertNil(object["recurrence"])
        XCTAssertNil(object["nextDueDate"])
    }

    func testJSONIncludesNextDueDateForRecurringReminder() throws {
        let store = EKEventStore()
        let reminder = EKReminder(eventStore: store)
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = "Test"
        reminder.calendar = calendar
        reminder.title = "Medicine"
        reminder.dueDateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: Date(timeIntervalSince1970: 1_700_000_000))
        reminder.addRecurrenceRule(Recurrence.daily.recurrenceRule(interval: 1, end: nil))

        let data = try JSONEncoder().encode(reminder)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(object["nextDueDate"] as? String)
    }

    func testAddRejectsExplicitIntervalWithoutRecurrence() throws {
        XCTAssertThrowsError(
            try CLI.parseAsRoot([
                "add", "Soon", "Medicine", "--due-date", "2026-09-01 09:00",
                "--repeat-interval", "1",
            ]))
    }

    func testAddRequiresDueDateForRecurrence() throws {
        XCTAssertThrowsError(
            try CLI.parseAsRoot([
                "add", "Soon", "Medicine", "--repeat", "daily",
            ]))
    }

    func testAddRejectsRepeatEndBeforeDueDate() throws {
        XCTAssertThrowsError(
            try CLI.parseAsRoot([
                "add", "Soon", "Medicine", "--due-date", "2026-09-10 09:00",
                "--repeat", "daily", "--repeat-until", "2026-09-09",
            ]))
    }

    func testScheduleRequiresDueDateWhenRulesRemain() throws {
        let rule = Recurrence.daily.recurrenceRule(interval: 1, end: nil)

        XCTAssertThrowsError(
            try validateRecurrenceSchedule(dueDateComponents: nil, rules: [rule])
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                RecurrenceUpdateError.missingDueDate.localizedDescription)
        }
    }

    func testScheduleAllowsClearingDueDateAndRepeatTogether() throws {
        XCTAssertNoThrow(
            try validateRecurrenceSchedule(dueDateComponents: nil, rules: []))
    }

    func testScheduleRejectsEndBeforeDueDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Belgrade"))
        var due = DateComponents()
        due.calendar = calendar
        due.timeZone = calendar.timeZone
        due.year = 2026
        due.month = 9
        due.day = 10
        due.hour = 9
        let end = try XCTUnwrap(calendar.date(from: due)?.addingTimeInterval(-1))
        let rule = Recurrence.daily.recurrenceRule(
            interval: 1,
            end: EKRecurrenceEnd(end: end))

        XCTAssertThrowsError(
            try validateRecurrenceSchedule(dueDateComponents: due, rules: [rule])
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                RecurrenceUpdateError.endBeforeDueDate.localizedDescription)
        }
    }

    func testEditAcceptsEndOnlyUpdate() throws {
        XCTAssertNoThrow(
            try CLI.parseAsRoot([
                "edit", "Soon", "0", "--repeat-until", "2026-09-10",
            ]))
    }

    func testEditRejectsClearRepeatWithEndUpdate() throws {
        XCTAssertThrowsError(
            try CLI.parseAsRoot([
                "edit", "Soon", "0", "--clear-repeat", "--repeat-until", "2026-09-10",
            ]))
    }

    func testLocalizedRecurrenceErrorIsHumanReadable() throws {
        XCTAssertEqual(
            RecurrenceUpdateError.missingExistingRule.localizedDescription,
            "A repeat rule is required; pass --repeat or edit a repeating reminder")
    }

    func testHourlyIsNotRepresentable() throws {
        // EventKit has no hourly EKRecurrenceFrequency; this is asserted at the
        // model layer so CLI validation (which rejects it before ever building
        // a rule) has something concrete to check against.
        XCTAssertFalse(Recurrence.hourly.isRepresentable)
    }

    func testRepresentableFrequenciesAreAllRepresentable() throws {
        for frequency: Recurrence in [.daily, .weekly, .monthly, .yearly] {
            XCTAssertTrue(frequency.isRepresentable, "\(frequency.rawValue) should be representable")
        }
    }

    func testRecurrenceParsesFromArgument() throws {
        XCTAssertEqual(Recurrence(argument: "daily"), .daily)
        XCTAssertEqual(Recurrence(argument: "weekly"), .weekly)
        XCTAssertEqual(Recurrence(argument: "monthly"), .monthly)
        XCTAssertEqual(Recurrence(argument: "yearly"), .yearly)
        XCTAssertEqual(Recurrence(argument: "hourly"), .hourly)
        XCTAssertNil(Recurrence(argument: "biweekly"))
    }

    // MARK: - nextOccurrence

    private func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0)
        -> Date
    {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    func testNextOccurrenceDailyStepsForward() throws {
        let anchor = utcDate(2026, 1, 1)
        let rule = Recurrence.daily.recurrenceRule(interval: 1, end: nil)
        let next = nextOccurrence(of: rule, anchoredAt: anchor, onOrAfter: utcDate(2026, 1, 3, 12))
        XCTAssertEqual(next, utcDate(2026, 1, 4))
    }

    func testNextOccurrenceWeeklyStepsForward() throws {
        let anchor = utcDate(2026, 1, 1)
        let rule = Recurrence.weekly.recurrenceRule(interval: 1, end: nil)
        let next = nextOccurrence(of: rule, anchoredAt: anchor, onOrAfter: utcDate(2026, 1, 11))
        XCTAssertEqual(next, utcDate(2026, 1, 15))
    }

    func testNextOccurrenceMonthlyStepsForward() throws {
        let anchor = utcDate(2026, 1, 15)
        let rule = Recurrence.monthly.recurrenceRule(interval: 1, end: nil)
        let next = nextOccurrence(of: rule, anchoredAt: anchor, onOrAfter: utcDate(2026, 3, 1))
        XCTAssertEqual(next, utcDate(2026, 3, 15))
    }

    func testNextOccurrenceYearlyStepsForward() throws {
        let anchor = utcDate(2025, 6, 1)
        let rule = Recurrence.yearly.recurrenceRule(interval: 1, end: nil)
        let next = nextOccurrence(of: rule, anchoredAt: anchor, onOrAfter: utcDate(2027, 1, 1))
        XCTAssertEqual(next, utcDate(2027, 6, 1))
    }

    func testNextOccurrenceHonorsIntervalGreaterThanOne() throws {
        let anchor = utcDate(2026, 1, 1)
        let rule = Recurrence.daily.recurrenceRule(interval: 3, end: nil)
        let next = nextOccurrence(of: rule, anchoredAt: anchor, onOrAfter: utcDate(2026, 1, 5))
        XCTAssertEqual(next, utcDate(2026, 1, 7))
    }

    func testNextOccurrenceReturnsAnchorWhenReferenceDateIsBeforeIt() throws {
        let anchor = utcDate(2026, 1, 10)
        let rule = Recurrence.daily.recurrenceRule(interval: 1, end: nil)
        let next = nextOccurrence(of: rule, anchoredAt: anchor, onOrAfter: utcDate(2026, 1, 1))
        XCTAssertEqual(next, anchor)
    }

    func testNextOccurrenceReturnsNilPastEndDate() throws {
        let anchor = utcDate(2026, 1, 1)
        let rule = Recurrence.daily.recurrenceRule(
            interval: 1, end: EKRecurrenceEnd(end: utcDate(2026, 1, 3)))
        let next = nextOccurrence(of: rule, anchoredAt: anchor, onOrAfter: utcDate(2026, 1, 10))
        XCTAssertNil(next)
    }

    func testNextOccurrenceReturnsLastOccurrenceWithinEndDate() throws {
        let anchor = utcDate(2026, 1, 1)
        let rule = Recurrence.daily.recurrenceRule(
            interval: 1, end: EKRecurrenceEnd(end: utcDate(2026, 1, 5)))
        let next = nextOccurrence(of: rule, anchoredAt: anchor, onOrAfter: utcDate(2026, 1, 5))
        XCTAssertEqual(next, utcDate(2026, 1, 5))
    }

    func testNextOccurrenceReturnsNilPastOccurrenceCount() throws {
        let anchor = utcDate(2026, 1, 1)
        let rule = Recurrence.daily.recurrenceRule(
            interval: 1, end: EKRecurrenceEnd(occurrenceCount: 3))
        let next = nextOccurrence(of: rule, anchoredAt: anchor, onOrAfter: utcDate(2026, 1, 10))
        XCTAssertNil(next)
    }

    func testNextOccurrenceReturnsThirdOccurrenceWithinCount() throws {
        let anchor = utcDate(2026, 1, 1)
        let rule = Recurrence.daily.recurrenceRule(
            interval: 1, end: EKRecurrenceEnd(occurrenceCount: 3))
        let next = nextOccurrence(of: rule, anchoredAt: anchor, onOrAfter: utcDate(2026, 1, 3))
        XCTAssertEqual(next, utcDate(2026, 1, 3))
    }

    func testNextOccurrenceReturnsNilForComplexSelectors() throws {
        let anchor = utcDate(2026, 1, 1)
        let rule = EKRecurrenceRule(
            recurrenceWith: .monthly,
            interval: 1,
            daysOfTheWeek: [EKRecurrenceDayOfWeek(.friday, weekNumber: -1)],
            daysOfTheMonth: nil,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: nil)
        let next = nextOccurrence(of: rule, anchoredAt: anchor, onOrAfter: utcDate(2026, 3, 1))
        XCTAssertNil(next)
    }

    func testNextDueDateReturnsNilWithoutRecurrenceRule() throws {
        let store = EKEventStore()
        let reminder = EKReminder(eventStore: store)
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = "Test"
        reminder.calendar = calendar
        reminder.title = "One-off"

        XCTAssertNil(nextDueDate(from: reminder))
    }
}
