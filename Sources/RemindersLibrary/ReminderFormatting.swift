import EventKit
import Foundation

private let dateFormatter = RelativeDateTimeFormatter()
private let recurrenceDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}()

private func formattedDueDate(from reminder: EKReminder) -> String? {
    return reminder.dueDateComponents?.date.map {
        relativeDueDate(for: $0, relativeTo: Date())
    }
}

/// Describes `date` relative to `now`, counting whole calendar days rather than
/// elapsed 24-hour periods. Thursday 09:00 -> Saturday 08:00 is "in 2 days", not
/// "in 1 day". Same-day dates keep the hour granularity ("in 3 hours").
func relativeDueDate(
    for date: Date,
    relativeTo now: Date,
    calendar: Calendar = .current,
    formatter: RelativeDateTimeFormatter = dateFormatter
) -> String {
    if calendar.isDate(date, inSameDayAs: now) {
        return formatter.localizedString(for: date, relativeTo: now)
    }
    return formatter.localizedString(
        for: calendar.startOfDay(for: date),
        relativeTo: calendar.startOfDay(for: now))
}

private func formattedRecurrence(from reminder: EKReminder) -> String? {
    guard let rule = reminder.recurrenceRules?.first else {
        return nil
    }

    let frequency: String
    switch rule.frequency {
    case .daily: frequency = "daily"
    case .weekly: frequency = "weekly"
    case .monthly: frequency = "monthly"
    case .yearly: frequency = "yearly"
    @unknown default: frequency = "unknown"
    }

    var parts = ["repeats: \(frequency)"]
    if let weekdays = plainWeekdays(of: rule) {
        parts[0] += " on " + weekdays.map { shortName(of: $0).capitalized }.joined(separator: ", ")
    }
    if rule.interval > 1 {
        parts.append("interval: \(rule.interval)")
    }
    if let endDate = rule.recurrenceEnd?.endDate {
        parts.append("until: \(recurrenceDateFormatter.string(from: endDate))")
    } else if let count = rule.recurrenceEnd?.occurrenceCount, count > 0 {
        parts.append("count: \(count)")
    }
    return parts.joined(separator: ", ")
}

extension EKReminder {
    var mappedPriority: EKReminderPriority {
        UInt(exactly: self.priority).flatMap(EKReminderPriority.init) ?? EKReminderPriority.none
    }

    /// The ID the listings print, with a placeholder for the rare reminder EventKit gives none.
    var displayId: String {
        self.calendarItemExternalIdentifier ?? "<unknown-id>"
    }
}

func format(_ reminder: EKReminder, id: String, listName: String? = nil) -> String {
    let dateString = formattedDueDate(from: reminder).map { " (\($0))" } ?? ""
    let priorityString = Priority(reminder.mappedPriority).map { " (priority: \($0))" } ?? ""
    let listString = listName.map { "\($0): " } ?? ""
    // EventKit stores cleared notes as "" rather than nil; both mean "no notes".
    let notesString = reminder.notes.flatMap { $0.isEmpty ? nil : " (\($0))" } ?? ""
    let recurrenceString = formattedRecurrence(from: reminder).map { " (\($0))" } ?? ""
    let flaggedString = reminder.isFlagged ? " (flagged)" : ""
    return "\(listString)\(id): \(reminder.title ?? "<unknown>")"
        + "\(notesString)\(dateString)\(priorityString)\(recurrenceString)\(flaggedString)"
}

/// The one definition of "overdue" in the CLI, shared by `show --overdue` and the counts of
/// `show-lists` so the two views never disagree: a due date strictly before `now`, which the caller
/// resolves once per command invocation. A reminder without a due date is never overdue.
func isOverdue(_ reminder: EKReminder, now: Date) -> Bool {
    return isOverdue(dueDate: reminder.dueDateComponents?.date, now: now)
}

/// `isOverdue(_:now:)` on an already-resolved due date, for `pretty` output's `PrettyRow`.
func isOverdue(dueDate: Date?, now: Date) -> Bool {
    return dueDate.map { $0 < now } ?? false
}

// Additional, independently-composable filters for `show`/`show-all`, ANDed together and ANDed
// with the pre-existing day-granularity `--due-date`/`--include-overdue` filter. `now`,
// `dueBefore`, `dueAfter`, and `completedSince` are resolved to concrete `Date`s once per command
// invocation by the caller, not per reminder. Kept internal (not private) so it's directly
// unit-testable via `@testable import`, matching `recurrenceEndDate`/`nextOccurrence` elsewhere in
// this file. `isFlagged` is injectable because a test can't flag an `EKReminder` (the flag is not
// part of the public EventKit API, see `flaggedKeyPath`).
func matchesAdditionalFilters(
    _ reminder: EKReminder,
    now: Date,
    overdue: Bool,
    dueBefore: Date?,
    dueAfter: Date?,
    noDueDate: Bool,
    priorities: [Priority],
    search: String?,
    completedSince: Date? = nil,
    flagged: Bool = false,
    isFlagged: (EKReminder) -> Bool = { $0.isFlagged }
) -> Bool {
    let reminderDueDate = reminder.dueDateComponents?.date

    if flagged && !isFlagged(reminder) {
        return false
    }
    if noDueDate && reminderDueDate != nil {
        return false
    }
    if overdue && !isOverdue(reminder, now: now) {
        return false
    }
    if let dueBefore, !(reminderDueDate.map { $0 <= dueBefore } ?? false) {
        return false
    }
    if let dueAfter, !(reminderDueDate.map { $0 >= dueAfter } ?? false) {
        return false
    }
    if let completedSince, !(reminder.completionDate.map { $0 >= completedSince } ?? false) {
        return false
    }
    if !priorities.isEmpty {
        let reminderPriority = Priority(reminder.mappedPriority) ?? .none
        if !priorities.contains(reminderPriority) {
            return false
        }
    }
    if let search, !search.isEmpty {
        let inTitle = reminder.title?.localizedCaseInsensitiveContains(search) ?? false
        let inNotes = reminder.notes?.localizedCaseInsensitiveContains(search) ?? false
        if !(inTitle || inNotes) {
            return false
        }
    }
    return true
}

/// The day-granularity `--due-date` filter of `show`/`show-all`: with no `dueOn` every reminder
/// matches; otherwise a reminder due on the same day does, and with `includeOverdue` one due on an
/// earlier day too. A reminder without a due date never matches a `dueOn`.
func matchesDueOn(
    _ reminder: EKReminder, dueOn: Date?, includeOverdue: Bool, calendar: Calendar = .current
) -> Bool {
    guard let dueOn else {
        return true
    }
    guard let reminderDueDate = reminder.dueDateComponents?.date else {
        return false
    }
    switch calendar.compare(reminderDueDate, to: dueOn, toGranularity: .day) {
    case .orderedSame:
        return true
    case .orderedAscending:
        return includeOverdue
    case .orderedDescending:
        return false
    }
}
