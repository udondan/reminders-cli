import ArgumentParser
import EventKit
import Foundation

/// Sets a reminder's due date and replaces its alarms with one at the due time, or none when the
/// new due date is date-only or nil. Shared by `add`, `edit` and `postpone`.
func setDueDate(of reminder: EKReminder, to components: DateComponents?) {
    reminder.dueDateComponents = components
    for alarm in reminder.alarms ?? [] {
        reminder.removeAlarm(alarm)
    }
    if let components, let date = components.date, components.hour != nil {
        reminder.addAlarm(EKAlarm(absoluteDate: date))
    }
}

/// Everything `add` sets on a new, unsaved reminder besides its list.
func configureNewReminder(
    _ reminder: EKReminder,
    title: String,
    notes: String?,
    dueDateComponents: DateComponents?,
    priority: Priority,
    recurrence: Recurrence?,
    recurrenceInterval: Int,
    recurrenceEndDate: DateComponents?,
    recurrenceDays: RepeatDays? = nil
) throws {
    reminder.title = title
    reminder.notes = notes
    reminder.priority = Int(priority.value.rawValue)
    setDueDate(of: reminder, to: dueDateComponents)

    do {
        if let rule = try newRecurrenceRule(
            recurrence, interval: recurrenceInterval, endDate: recurrenceEndDate,
            days: recurrenceDays)
        {
            reminder.addRecurrenceRule(rule)
        }
        try validateRecurrenceSchedule(
            dueDateComponents: reminder.dueDateComponents,
            rules: reminder.recurrenceRules ?? [])
    } catch let error as RecurrenceUpdateError {
        throw CLIError.invalidArgument(error.localizedDescription)
    }
}

/// One reminder's share of `edit`, changing it only in memory; `edit` saves the batch. Every change
/// defaults to "leave as is", and a failed repeat update or schedule check is `invalid_argument`.
func applyEdit(
    to reminder: EKReminder,
    newText: String? = nil,
    newNotes: String? = nil,
    clearNotes: Bool = false,
    newDueDateComponents: DateComponents? = nil,
    clearDueDate: Bool = false,
    priority: Priority? = nil,
    clearPriority: Bool = false,
    newCalendar: EKCalendar? = nil,
    newRecurrence: Recurrence? = nil, newRecurrenceInterval: Int? = nil,
    newRecurrenceEndDate: DateComponents? = nil,
    clearRecurrenceEnd: Bool = false,
    newRecurrenceDays: RepeatDays? = nil,
    clearRecurrenceDays: Bool = false,
    clearRecurrence: Bool = false
) throws {
    let dueDateChangeRequested = clearDueDate || newDueDateComponents != nil
    let recurrenceChangeRequested = clearRecurrence || newRecurrence != nil
        || newRecurrenceInterval != nil || newRecurrenceEndDate != nil
        || newRecurrenceDays != nil || clearRecurrenceDays
        || clearRecurrenceEnd

    applyFieldEdits(
        to: reminder, newText: newText, newNotes: newNotes, clearNotes: clearNotes, priority: priority,
        clearPriority: clearPriority, newCalendar: newCalendar)
    if dueDateChangeRequested {
        setDueDate(of: reminder, to: clearDueDate ? nil : newDueDateComponents)
    }

    do {
        if clearRecurrence {
            replaceRecurrenceRules(of: reminder, with: [])
        } else {
            let update = RecurrenceUpdate(
                recurrence: newRecurrence,
                interval: newRecurrenceInterval,
                end: try recurrenceEndUpdate(clear: clearRecurrenceEnd, date: newRecurrenceEndDate),
                days: recurrenceDaysUpdate(clear: clearRecurrenceDays, days: newRecurrenceDays))
            try applyRecurrenceUpdate(update, to: reminder)
        }
        if dueDateChangeRequested || recurrenceChangeRequested {
            try validateRecurrenceSchedule(
                dueDateComponents: reminder.dueDateComponents,
                rules: reminder.recurrenceRules ?? [])
        }
    } catch let error as RecurrenceUpdateError {
        throw CLIError.invalidArgument(error.localizedDescription)
    }
}

/// The plain fields of `edit`: title, notes, priority and list. A clear wins over a new value.
private func applyFieldEdits(
    to reminder: EKReminder, newText: String?, newNotes: String?, clearNotes: Bool, priority: Priority?,
    clearPriority: Bool, newCalendar: EKCalendar?
) {
    reminder.title = newText ?? reminder.title
    reminder.notes = clearNotes ? nil : newNotes ?? reminder.notes
    if clearPriority {
        reminder.priority = Int(EKReminderPriority.none.rawValue)
    } else if let priority {
        reminder.priority = Int(priority.value.rawValue)
    }
    if let newCalendar {
        reminder.calendar = newCalendar
    }
}

/// `--clear-repeat-until` or `--repeat-until` as an end update; an unparseable date is an error.
private func recurrenceEndUpdate(clear: Bool, date: DateComponents?) throws -> RecurrenceEndUpdate {
    if clear {
        return .clear
    }
    guard let date else {
        return .unchanged
    }
    guard let endDate = recurrenceEndDate(from: date) else {
        throw RecurrenceUpdateError.invalidEndDate
    }
    return .date(endDate)
}

/// `--clear-repeat-on` or `--repeat-on` as a days update.
private func recurrenceDaysUpdate(clear: Bool, days: RepeatDays?) -> RecurrenceDaysUpdate {
    if clear {
        return .clear
    }
    return days.map { .set($0) } ?? .unchanged
}

/// Replaces the reminder's repeat rules with `update` applied to them. Without a new repeat
/// frequency every existing rule is updated, and there has to be one; with one, the first existing
/// rule (if any) is the base of the single new rule.
private func applyRecurrenceUpdate(_ update: RecurrenceUpdate, to reminder: EKReminder) throws {
    guard update.isRequested else {
        return
    }
    let existingRules = reminder.recurrenceRules ?? []
    if update.recurrence != nil {
        replaceRecurrenceRules(of: reminder, with: [try update.rule(replacing: existingRules.first)])
        return
    }
    guard !existingRules.isEmpty else {
        throw RecurrenceUpdateError.missingExistingRule
    }
    replaceRecurrenceRules(of: reminder, with: try existingRules.map { try update.rule(replacing: $0) })
}

private func replaceRecurrenceRules(of reminder: EKReminder, with rules: [EKRecurrenceRule]) {
    for rule in reminder.recurrenceRules ?? [] {
        reminder.removeRecurrenceRule(rule)
    }
    for rule in rules {
        reminder.addRecurrenceRule(rule)
    }
}

/// Where `postpone` moves a due date: to a given date, or to the next weekday after the current one.
enum PostponeTarget: Equatable {
    case date(DateComponents)
    case nextWeekday

    /// The target from `postpone`'s arguments, which take exactly one of the two.
    init(date: DateComponents?, nextWeekday: Bool) throws {
        switch (date, nextWeekday) {
        case (.some, true):
            throw ValidationError("Cannot specify both a new due date and --next-weekday")
        case (nil, false):
            throw ValidationError("Must specify either a new due date or --next-weekday")
        case (.some(let date), false):
            self = .date(date)
        case (nil, true):
            self = .nextWeekday
        }
    }
}

/// One reminder's share of `postpone`: the new due date, or for `.nextWeekday` the next weekday
/// after its current one (`no_due_date` without one). Its repeat rules are never read or written,
/// so they pass through unchanged; the schedule is still checked against the new due date.
func applyPostpone(
    to reminder: EKReminder, target: PostponeTarget, calendar: Calendar = .current
) throws {
    let resolvedComponents: DateComponents
    switch target {
    case .date(let newDueDate):
        resolvedComponents = newDueDate
    case .nextWeekday:
        guard let currentDue = reminder.dueDateComponents,
            let shifted = nextWeekday(after: currentDue, calendar: calendar)
        else {
            throw CLIError.noDueDate()
        }
        resolvedComponents = shifted
    }

    setDueDate(of: reminder, to: resolvedComponents)

    do {
        try validateRecurrenceSchedule(
            dueDateComponents: reminder.dueDateComponents,
            rules: reminder.recurrenceRules ?? [])
    } catch let error as RecurrenceUpdateError {
        throw CLIError.invalidArgument(error.localizedDescription)
    }
}

/// The confirmation for the reminders a command changed: one plain line each, or JSON — the
/// single object for a single ID argument, an array for a batch.
func affectedOutput(
    _ reminders: [EKReminder], selection: ReminderSelection, outputFormat: OutputFormat,
    plainLine: (EKReminder) -> String
) -> String {
    switch outputFormat {
    case .json:
        if !selection.isBatch, let reminder = reminders.first {
            return encodeToJson(data: reminder)
        }
        return encodeToJson(data: reminders)
    case .plain:
        return reminders.map(plainLine).joined(separator: "\n")
    }
}
