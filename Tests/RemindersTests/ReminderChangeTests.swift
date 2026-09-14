import EventKit
@testable import RemindersLibrary
import XCTest

final class SetDueDateTests: InMemoryReminderTestCase {
    func testTimedDueDateReplacesTheAlarmsWithOneAtTheDueTime() throws {
        let reminder = makeReminder()
        reminder.addAlarm(EKAlarm(absoluteDate: date(2026, 1, 1, 8)))
        reminder.addAlarm(EKAlarm(relativeOffset: -600))

        setDueDate(of: reminder, to: due(2026, 9, 15, hour: 18))

        XCTAssertEqual(reminder.dueDateComponents?.date, date(2026, 9, 15, 18))
        XCTAssertEqual(alarmDates(of: reminder), [date(2026, 9, 15, 18)])
    }

    func testDateOnlyDueDateRemovesTheAlarms() throws {
        let reminder = makeReminder()
        reminder.addAlarm(EKAlarm(absoluteDate: date(2026, 1, 1, 8)))

        setDueDate(of: reminder, to: due(2026, 9, 15))

        XCTAssertEqual(reminder.dueDateComponents?.date, date(2026, 9, 15))
        XCTAssertNil(reminder.dueDateComponents?.hour)
        XCTAssertEqual(alarmDates(of: reminder), [])
    }

    func testNilRemovesTheDueDateAndTheAlarms() throws {
        let reminder = makeReminder()
        setDueDate(of: reminder, to: due(2026, 9, 15, hour: 18))

        setDueDate(of: reminder, to: nil)

        XCTAssertNil(reminder.dueDateComponents)
        XCTAssertEqual(alarmDates(of: reminder), [])
    }
}

final class ConfigureNewReminderTests: InMemoryReminderTestCase {
    private func configure(
        dueDateComponents: DateComponents?, recurrence: Recurrence? = nil, interval: Int = 1,
        endDate: DateComponents? = nil, days: RepeatDays? = nil
    ) throws -> EKReminder {
        let reminder = makeReminder(title: "")
        try configureNewReminder(
            reminder, title: "Pay rent", notes: "Transfer", dueDateComponents: dueDateComponents,
            priority: .high, recurrence: recurrence, recurrenceInterval: interval,
            recurrenceEndDate: endDate, recurrenceDays: days)
        return reminder
    }

    func testTimedDueDateGetsAnAlarm() throws {
        let reminder = try configure(dueDateComponents: due(2026, 10, 1, hour: 9))

        XCTAssertEqual(reminder.title, "Pay rent")
        XCTAssertEqual(reminder.notes, "Transfer")
        XCTAssertEqual(reminder.priority, Int(EKReminderPriority.high.rawValue))
        XCTAssertEqual(reminder.dueDateComponents?.date, date(2026, 10, 1, 9))
        XCTAssertEqual(alarmDates(of: reminder), [date(2026, 10, 1, 9)])
        XCTAssertEqual(reminder.recurrenceRules ?? [], [])
    }

    func testDateOnlyDueDateGetsNoAlarm() throws {
        let reminder = try configure(dueDateComponents: due(2026, 10, 1))

        XCTAssertEqual(reminder.dueDateComponents?.date, date(2026, 10, 1))
        XCTAssertEqual(alarmDates(of: reminder), [])
    }

    func testNoDueDate() throws {
        let reminder = try configure(dueDateComponents: nil)

        XCTAssertNil(reminder.dueDateComponents)
        XCTAssertEqual(alarmDates(of: reminder), [])
    }

    func testRepeatRule() throws {
        let reminder = try configure(
            dueDateComponents: due(2026, 10, 1), recurrence: .weekly, interval: 2,
            endDate: due(2026, 12, 31), days: try RepeatDays(parsing: "mon,thu"))

        let rule = try XCTUnwrap(reminder.recurrenceRules?.first)
        XCTAssertEqual(reminder.recurrenceRules?.count, 1)
        XCTAssertEqual(rule.frequency, .weekly)
        XCTAssertEqual(rule.interval, 2)
        XCTAssertEqual(rule.daysOfTheWeek?.map(\.dayOfTheWeek), [.monday, .thursday])
        XCTAssertEqual(rule.recurrenceEnd?.endDate, date(2026, 12, 31, 23, 59, 59))
    }

    func testRepeatWithoutDueDateIsAnInvalidArgument() {
        assertCLIError(
            try configure(dueDateComponents: nil, recurrence: .daily),
            code: .invalidArgument, message: "A repeating reminder requires a due date")
    }

    func testRepeatEndBeforeTheDueDateIsAnInvalidArgument() {
        assertCLIError(
            try configure(dueDateComponents: due(2026, 10, 1), recurrence: .daily, endDate: due(2026, 9, 30)),
            code: .invalidArgument,
            message: "The repeat end date cannot be earlier than the reminder's due date")
    }

    func testRepeatDaysWithoutWeeklyIsAnInvalidArgument() throws {
        let days = try RepeatDays(parsing: "mon")
        assertCLIError(
            try configure(dueDateComponents: due(2026, 10, 1), recurrence: .monthly, days: days),
            code: .invalidArgument,
            message: "Repeat days only apply to a weekly repeat rule; pass --repeat weekly")
    }
}

final class ApplyEditTests: InMemoryReminderTestCase {
    /// A reminder with every field `edit` can change already set.
    private func fullReminder() -> EKReminder {
        let reminder = makeReminder()
        reminder.notes = "Balcony too"
        reminder.priority = Int(EKReminderPriority.medium.rawValue)
        setDueDate(of: reminder, to: due(2026, 9, 20, hour: 8))
        reminder.addRecurrenceRule(EKRecurrenceRule(
            recurrenceWith: .monthly, interval: 1, end: EKRecurrenceEnd(end: date(2027, 6, 30))))
        return reminder
    }

    func testNoChangesLeaveTheReminderAsIs() throws {
        let reminder = fullReminder()
        let calendar = reminder.calendar

        try applyEdit(to: reminder)

        XCTAssertEqual(reminder.title, "Water plants")
        XCTAssertEqual(reminder.notes, "Balcony too")
        XCTAssertEqual(reminder.priority, Int(EKReminderPriority.medium.rawValue))
        XCTAssertTrue(reminder.calendar === calendar)
        XCTAssertEqual(reminder.dueDateComponents?.date, date(2026, 9, 20, 8))
        XCTAssertEqual(alarmDates(of: reminder), [date(2026, 9, 20, 8)])
        XCTAssertEqual(reminder.recurrenceRules?.map(\.frequency), [.monthly])
        XCTAssertEqual(reminder.recurrenceRules?.first?.recurrenceEnd?.endDate, date(2027, 6, 30))
    }

    func testTitleNotesAndPriority() throws {
        let reminder = fullReminder()

        try applyEdit(to: reminder, newText: "Water all plants", newNotes: "And the herbs", priority: .high)

        XCTAssertEqual(reminder.title, "Water all plants")
        XCTAssertEqual(reminder.notes, "And the herbs")
        XCTAssertEqual(reminder.priority, Int(EKReminderPriority.high.rawValue))
    }

    func testClearNotesAndPriority() throws {
        let reminder = fullReminder()

        try applyEdit(to: reminder, clearNotes: true, clearPriority: true)

        XCTAssertEqual(reminder.notes ?? "", "")
        XCTAssertEqual(reminder.priority, Int(EKReminderPriority.none.rawValue))
    }

    func testMovesToTheNewList() throws {
        let reminder = fullReminder()
        let garden = EKCalendar(for: .reminder, eventStore: store)
        garden.title = "Garden"

        try applyEdit(to: reminder, newCalendar: garden)

        XCTAssertTrue(reminder.calendar === garden)
    }

    func testTimedDueDateReplacesTheAlarm() throws {
        let reminder = fullReminder()

        try applyEdit(to: reminder, newDueDateComponents: due(2026, 9, 21, hour: 19))

        XCTAssertEqual(reminder.dueDateComponents?.date, date(2026, 9, 21, 19))
        XCTAssertEqual(alarmDates(of: reminder), [date(2026, 9, 21, 19)])
    }

    func testDateOnlyDueDateRemovesTheAlarm() throws {
        let reminder = fullReminder()

        try applyEdit(to: reminder, newDueDateComponents: due(2026, 9, 21))

        XCTAssertEqual(reminder.dueDateComponents?.date, date(2026, 9, 21))
        XCTAssertEqual(alarmDates(of: reminder), [])
    }

    func testClearDueDateRemovesTheAlarm() throws {
        let reminder = makeReminder()
        setDueDate(of: reminder, to: due(2026, 9, 20, hour: 8))

        try applyEdit(to: reminder, clearDueDate: true)

        XCTAssertNil(reminder.dueDateComponents)
        XCTAssertEqual(alarmDates(of: reminder), [])
    }

    func testClearingTheDueDateOfARepeatingReminderIsAnInvalidArgument() {
        assertCLIError(
            try applyEdit(to: fullReminder(), clearDueDate: true),
            code: .invalidArgument, message: "A repeating reminder requires a due date")
    }

    func testRepeatAddsARule() throws {
        let reminder = makeReminder()
        setDueDate(of: reminder, to: due(2026, 9, 20))

        try applyEdit(to: reminder, newRecurrence: .weekly, newRecurrenceInterval: 2)

        XCTAssertEqual(reminder.recurrenceRules?.map(\.frequency), [.weekly])
        XCTAssertEqual(reminder.recurrenceRules?.first?.interval, 2)
    }

    func testIntervalAloneKeepsTheFrequencyAndEnd() throws {
        let reminder = fullReminder()

        try applyEdit(to: reminder, newRecurrenceInterval: 3)

        let rule = try XCTUnwrap(reminder.recurrenceRules?.first)
        XCTAssertEqual(reminder.recurrenceRules?.count, 1)
        XCTAssertEqual(rule.frequency, .monthly)
        XCTAssertEqual(rule.interval, 3)
        XCTAssertEqual(rule.recurrenceEnd?.endDate, date(2027, 6, 30))
    }

    func testRepeatEndDateMeansTheWholeDay() throws {
        let reminder = fullReminder()

        try applyEdit(to: reminder, newRecurrenceEndDate: due(2026, 12, 31))

        XCTAssertEqual(reminder.recurrenceRules?.map(\.frequency), [.monthly])
        XCTAssertEqual(reminder.recurrenceRules?.first?.recurrenceEnd?.endDate, date(2026, 12, 31, 23, 59, 59))
    }

    func testClearRepeatEnd() throws {
        let reminder = fullReminder()

        try applyEdit(to: reminder, clearRecurrenceEnd: true)

        XCTAssertEqual(reminder.recurrenceRules?.map(\.frequency), [.monthly])
        XCTAssertNil(reminder.recurrenceRules?.first?.recurrenceEnd)
    }

    func testRepeatDaysAndClearingThem() throws {
        let reminder = makeReminder()
        setDueDate(of: reminder, to: due(2026, 9, 21))
        reminder.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil))

        try applyEdit(to: reminder, newRecurrenceDays: try RepeatDays(parsing: "weekends"))
        XCTAssertEqual(reminder.recurrenceRules?.first?.daysOfTheWeek?.map(\.dayOfTheWeek), [.sunday, .saturday])

        try applyEdit(to: reminder, clearRecurrenceDays: true)
        XCTAssertEqual(reminder.recurrenceRules?.count, 1)
        XCTAssertEqual(reminder.recurrenceRules?.first?.daysOfTheWeek ?? [], [])
    }

    func testClearRepeatRemovesTheRule() throws {
        let reminder = fullReminder()

        try applyEdit(to: reminder, clearRecurrence: true)

        XCTAssertEqual(reminder.recurrenceRules ?? [], [])
        XCTAssertEqual(reminder.dueDateComponents?.date, date(2026, 9, 20, 8))
    }

    func testRepeatChangeWithoutARuleIsAnInvalidArgument() {
        let reminder = makeReminder()
        setDueDate(of: reminder, to: due(2026, 9, 20))

        assertCLIError(
            try applyEdit(to: reminder, newRecurrenceInterval: 2),
            code: .invalidArgument,
            message: "A repeat rule is required; pass --repeat or edit a repeating reminder")
    }

    func testRepeatWithoutDueDateIsAnInvalidArgument() {
        assertCLIError(
            try applyEdit(to: makeReminder(), newRecurrence: .daily),
            code: .invalidArgument, message: "A repeating reminder requires a due date")
    }

    func testRepeatEndBeforeTheDueDateIsAnInvalidArgument() {
        assertCLIError(
            try applyEdit(to: fullReminder(), newRecurrenceEndDate: due(2026, 9, 1)),
            code: .invalidArgument,
            message: "The repeat end date cannot be earlier than the reminder's due date")
    }

    /// A repeating reminder without a due date can come from another app. Editing only its text
    /// must still work, so the schedule is checked only when the due date or repeat changes.
    func testTextEditSkipsTheScheduleCheck() throws {
        let reminder = makeReminder()
        reminder.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil))

        try applyEdit(to: reminder, newText: "Water the cactus")

        XCTAssertEqual(reminder.title, "Water the cactus")
    }
}

final class ApplyPostponeTests: InMemoryReminderTestCase {
    func testNewTimedDueDateReplacesTheAlarmAndKeepsTheRepeat() throws {
        let reminder = makeReminder()
        setDueDate(of: reminder, to: due(2026, 9, 14, hour: 8))
        reminder.addRecurrenceRule(EKRecurrenceRule(
            recurrenceWith: .weekly, interval: 2, end: EKRecurrenceEnd(occurrenceCount: 5)))

        try applyPostpone(to: reminder, newDueDate: due(2026, 9, 16, hour: 17), toNextWeekday: false)

        XCTAssertEqual(reminder.dueDateComponents?.date, date(2026, 9, 16, 17))
        XCTAssertEqual(alarmDates(of: reminder), [date(2026, 9, 16, 17)])
        let rule = try XCTUnwrap(reminder.recurrenceRules?.first)
        XCTAssertEqual(reminder.recurrenceRules?.count, 1)
        XCTAssertEqual(rule.frequency, .weekly)
        XCTAssertEqual(rule.interval, 2)
        XCTAssertEqual(rule.recurrenceEnd?.occurrenceCount, 5)
    }

    func testNewDateOnlyDueDateRemovesTheAlarm() throws {
        let reminder = makeReminder()
        setDueDate(of: reminder, to: due(2026, 9, 14, hour: 8))

        try applyPostpone(to: reminder, newDueDate: due(2026, 9, 16), toNextWeekday: false)

        XCTAssertEqual(reminder.dueDateComponents?.date, date(2026, 9, 16))
        XCTAssertEqual(alarmDates(of: reminder), [])
    }

    func testNextWeekdayKeepsTheTimeAndMovesTheAlarm() throws {
        let reminder = makeReminder()
        // 2026-09-18 is a Friday.
        setDueDate(of: reminder, to: due(2026, 9, 18, hour: 8))

        try applyPostpone(to: reminder, newDueDate: nil, toNextWeekday: true, calendar: utc)

        XCTAssertEqual(reminder.dueDateComponents?.date, date(2026, 9, 21, 8))
        XCTAssertEqual(alarmDates(of: reminder), [date(2026, 9, 21, 8)])
    }

    func testNextWeekdayWithoutDueDateIsNoDueDate() {
        XCTAssertThrowsError(
            try applyPostpone(to: makeReminder(), newDueDate: nil, toNextWeekday: true, calendar: utc)
        ) { error in
            XCTAssertEqual((error as? CLIError)?.code, .noDueDate)
        }
    }

    func testDueDateAfterTheRepeatEndIsAnInvalidArgument() {
        let reminder = makeReminder()
        setDueDate(of: reminder, to: due(2026, 9, 14))
        reminder.addRecurrenceRule(EKRecurrenceRule(
            recurrenceWith: .daily, interval: 1, end: EKRecurrenceEnd(end: date(2026, 9, 30))))

        assertCLIError(
            try applyPostpone(to: reminder, newDueDate: due(2026, 10, 2), toNextWeekday: false),
            code: .invalidArgument,
            message: "The repeat end date cannot be earlier than the reminder's due date")
    }
}

final class MatchesDueOnTests: InMemoryReminderTestCase {
    private func matches(_ reminder: EKReminder, includeOverdue: Bool) -> Bool {
        matchesDueOn(reminder, dueOn: date(2026, 9, 14), includeOverdue: includeOverdue, calendar: utc)
    }

    private func reminder(due components: DateComponents?) -> EKReminder {
        let reminder = makeReminder()
        reminder.dueDateComponents = components
        return reminder
    }

    func testWithoutADayEverythingMatches() {
        for components in [nil, due(2026, 9, 1), due(2026, 9, 14, hour: 9)] {
            XCTAssertTrue(matchesDueOn(reminder(due: components), dueOn: nil, includeOverdue: false, calendar: utc))
        }
    }

    func testSameDayMatchesAtAnyTime() {
        XCTAssertTrue(matches(reminder(due: due(2026, 9, 14)), includeOverdue: false))
        XCTAssertTrue(matches(reminder(due: due(2026, 9, 14, hour: 23)), includeOverdue: false))
    }

    func testEarlierDayMatchesOnlyWithIncludeOverdue() {
        let earlier = reminder(due: due(2026, 9, 13, hour: 23))
        XCTAssertFalse(matches(earlier, includeOverdue: false))
        XCTAssertTrue(matches(earlier, includeOverdue: true))
    }

    func testLaterDayNeverMatches() {
        let later = reminder(due: due(2026, 9, 15))
        XCTAssertFalse(matches(later, includeOverdue: false))
        XCTAssertFalse(matches(later, includeOverdue: true))
    }

    func testNoDueDateNeverMatchesADay() {
        XCTAssertFalse(matches(reminder(due: nil), includeOverdue: false))
        XCTAssertFalse(matches(reminder(due: nil), includeOverdue: true))
    }
}

final class AffectedOutputTests: InMemoryReminderTestCase {
    private func output(
        _ reminders: [EKReminder], arguments: [String], format: OutputFormat
    ) throws -> String {
        let selection = try ReminderSelection(arguments: arguments, readStandardInput: { "AAAA\n" })
        return affectedOutput(reminders, selection: selection, outputFormat: format) { "Done '\($0.title!)'" }
    }

    private func json(_ string: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(string.utf8))
    }

    func testPlainPrintsOneLinePerReminder() throws {
        let reminders = [makeReminder(title: "One"), makeReminder(title: "Two")]

        XCTAssertEqual(try output(reminders, arguments: ["AAAA", "BBBB"], format: .plain), "Done 'One'\nDone 'Two'")
    }

    func testJSONForASingleIDIsTheObject() throws {
        let object = try json(output([makeReminder(title: "One")], arguments: ["AAAA"], format: .json))

        XCTAssertEqual((object as? [String: Any])?["title"] as? String, "One")
    }

    func testJSONForABatchIsAnArrayEvenWithOneReminder() throws {
        for arguments in [["AAAA,"], ["-"], ["AAAA", "BBBB"]] {
            let array = try json(output([makeReminder(title: "One")], arguments: arguments, format: .json))

            XCTAssertEqual((array as? [[String: Any]])?.map { $0["title"] as? String }, ["One"], "\(arguments)")
        }
    }
}
