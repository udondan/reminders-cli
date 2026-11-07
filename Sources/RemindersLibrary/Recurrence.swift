import ArgumentParser
import EventKit
import Foundation

public enum Recurrence: String, ExpressibleByArgument {
    case hourly
    case daily
    case weekly
    case monthly
    case yearly

    var frequency: EKRecurrenceFrequency {
        switch self {
        case .hourly: return .daily  // EventKit has no hourly frequency; see interval note below.
        case .daily: return .daily
        case .weekly: return .weekly
        case .monthly: return .monthly
        case .yearly: return .yearly
        }
    }

    /// EventKit's `EKRecurrenceFrequency` has no hourly case, so `.hourly` is
    /// modeled as a daily rule with a 1-day interval and 24 hourly recurrences
    /// per day is not representable via `EKRecurrenceRule` alone. Since
    /// reminders don't carry a native hourly repeat concept in EventKit (the
    /// Reminders.app UI itself doesn't expose "hourly" either), `.hourly` is
    /// intentionally rejected at parse time in `RecurrenceOption` rather than
    /// silently degrading to daily. See CLI.swift for the actual validation;
    /// this case is kept in the enum only so `--repeat hourly` produces a
    /// clear, on-brand error message instead of an ArgumentParser "invalid
    /// value" message with no explanation.
    var isRepresentable: Bool {
        self != .hourly
    }

    func recurrenceRule(interval: Int, end: EKRecurrenceEnd?, days: RepeatDays? = nil) -> EKRecurrenceRule {
        guard let days else {
            return EKRecurrenceRule(
                recurrenceWith: self.frequency,
                interval: interval,
                end: end)
        }
        return EKRecurrenceRule(
            recurrenceWith: self.frequency,
            interval: interval,
            daysOfTheWeek: days.daysOfTheWeek,
            daysOfTheMonth: nil,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: end)
    }
}

enum RecurrenceDaysUpdate: Equatable {
    case unchanged
    case set(RepeatDays)
    case clear

    func applying(to existingDays: [EKRecurrenceDayOfWeek]?) -> [EKRecurrenceDayOfWeek]? {
        switch self {
        case .unchanged:
            return existingDays
        case .set(let days):
            return days.daysOfTheWeek
        case .clear:
            return nil
        }
    }
}

enum RecurrenceEndUpdate {
    case unchanged
    case date(Date)
    case clear

    func applying(to existingEnd: EKRecurrenceEnd?) -> EKRecurrenceEnd? {
        switch self {
        case .unchanged:
            return existingEnd
        case .date(let date):
            return EKRecurrenceEnd(end: date)
        case .clear:
            return nil
        }
    }
}

enum RecurrenceUpdateError: LocalizedError {
    case invalidEndDate
    case missingExistingRule
    case missingDueDate
    case endBeforeDueDate
    case failedToCopyExistingRule
    case repeatOnRequiresWeekly

    var errorDescription: String? {
        switch self {
        case .invalidEndDate:
            return "The repeat end date could not be parsed"
        case .missingExistingRule:
            return "A repeat rule is required; pass --repeat or edit a repeating reminder"
        case .missingDueDate:
            return "A repeating reminder requires a due date"
        case .endBeforeDueDate:
            return "The repeat end date cannot be earlier than the reminder's due date"
        case .failedToCopyExistingRule:
            return "The existing repeat rule could not be copied safely"
        case .repeatOnRequiresWeekly:
            return "Repeat days only apply to a weekly repeat rule; pass --repeat weekly"
        }
    }
}

struct RecurrenceUpdate {
    let recurrence: Recurrence?
    let interval: Int?
    let end: RecurrenceEndUpdate
    var days: RecurrenceDaysUpdate = .unchanged

    var isRequested: Bool {
        if recurrence != nil || interval != nil || days != .unchanged {
            return true
        }
        if case .unchanged = end {
            return false
        }
        return true
    }

    func rule(replacing existingRule: EKRecurrenceRule?) throws -> EKRecurrenceRule {
        guard let frequency = recurrence?.frequency ?? existingRule?.frequency else {
            throw RecurrenceUpdateError.missingExistingRule
        }
        if days != .unchanged && frequency != .weekly {
            throw RecurrenceUpdateError.repeatOnRequiresWeekly
        }

        let shouldPreserveInterval = recurrence == nil || existingRule?.frequency == frequency
        let inheritedInterval = shouldPreserveInterval ? existingRule?.interval : nil
        let resolvedInterval = interval ?? inheritedInterval ?? 1
        let resolvedEnd = end.applying(to: existingRule?.recurrenceEnd)

        // Changing only the end condition can preserve more than the public
        // initializer exposes, including provider-specific calendar metadata
        // and firstDayOfTheWeek. Copy the complete EventKit rule and modify its
        // sole writable recurrence property rather than reconstructing it.
        if let existingRule, recurrence == nil, interval == nil, days == .unchanged {
            guard let copiedRule = existingRule.copy() as? EKRecurrenceRule else {
                throw RecurrenceUpdateError.failedToCopyExistingRule
            }
            copiedRule.recurrenceEnd = resolvedEnd
            return copiedRule
        }

        // An interval edit must preserve every public selector in a complex
        // rule (for example, "the last Friday of every month"). The same
        // applies when the explicitly supplied frequency is unchanged. A days
        // edit replaces only the weekday selectors.
        if let existingRule,
            recurrence == nil || existingRule.frequency == frequency
        {
            return EKRecurrenceRule(
                recurrenceWith: frequency,
                interval: resolvedInterval,
                daysOfTheWeek: days.applying(to: existingRule.daysOfTheWeek),
                daysOfTheMonth: existingRule.daysOfTheMonth,
                monthsOfTheYear: existingRule.monthsOfTheYear,
                weeksOfTheYear: existingRule.weeksOfTheYear,
                daysOfTheYear: existingRule.daysOfTheYear,
                setPositions: existingRule.setPositions,
                end: resolvedEnd)
        }

        return EKRecurrenceRule(
            recurrenceWith: frequency,
            interval: resolvedInterval,
            daysOfTheWeek: days.applying(to: nil),
            daysOfTheMonth: nil,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: resolvedEnd)
    }
}

func recurrenceEndDate(from components: DateComponents) -> Date? {
    var calendar = components.calendar ?? Calendar.current
    if let timeZone = components.timeZone {
        calendar.timeZone = timeZone
    }

    guard let date = calendar.date(from: components) else {
        return nil
    }

    // A date-only value means the whole local day. Using midnight would make
    // a morning or evening occurrence on the requested final day disappear.
    guard components.hour == nil && components.minute == nil && components.second == nil else {
        return date
    }
    guard let nextDay = calendar.date(byAdding: .day, value: 1, to: date) else {
        return nil
    }
    return nextDay.addingTimeInterval(-1)
}

private func recurrenceEnd(dateComponents: DateComponents?) throws -> EKRecurrenceEnd? {
    guard let dateComponents else {
        return nil
    }
    guard let date = recurrenceEndDate(from: dateComponents) else {
        throw RecurrenceUpdateError.invalidEndDate
    }
    return EKRecurrenceEnd(end: date)
}

/// The repeat rule `add` attaches to a new reminder, or nil when `--repeat` wasn't given. Kept free
/// of the event store so it's unit-testable, since `addReminder` itself needs Reminders access.
func newRecurrenceRule(
    _ recurrence: Recurrence?, interval: Int, endDate: DateComponents?, days: RepeatDays? = nil
) throws -> EKRecurrenceRule? {
    guard let recurrence else {
        return nil
    }
    if days != nil && recurrence != .weekly {
        throw RecurrenceUpdateError.repeatOnRequiresWeekly
    }
    return recurrence.recurrenceRule(
        interval: interval, end: try recurrenceEnd(dateComponents: endDate), days: days)
}

func validateRecurrenceEnd(
    dueDateComponents: DateComponents?,
    rules: [EKRecurrenceRule]
) throws {
    guard let dueDate = dueDateComponents?.date else {
        return
    }
    if rules.contains(where: { rule in
        guard let endDate = rule.recurrenceEnd?.endDate else {
            return false
        }
        return endDate < dueDate
    }) {
        throw RecurrenceUpdateError.endBeforeDueDate
    }
}

func validateRecurrenceSchedule(
    dueDateComponents: DateComponents?,
    rules: [EKRecurrenceRule]
) throws {
    if !rules.isEmpty && dueDateComponents == nil {
        throw RecurrenceUpdateError.missingDueDate
    }
    try validateRecurrenceEnd(dueDateComponents: dueDateComponents, rules: rules)
}

// EventKit doesn't advance `dueDateComponents` on a repeating EKReminder as
// occurrences pass -- it stays at whatever it was last set to, and can end up
// arbitrarily far overdue. `nextOccurrence` computes what the next actionable
// due date would be instead, by stepping the rule's frequency/interval
// forward from its anchor date to the first occurrence at or after the
// reference date, skipping every missed one -- the date Reminders.app moves a
// reminder to when it's completed. It handles the rules this CLI itself creates
// and edits: plain daily/weekly/monthly/yearly + interval, and weekly rules
// on a set of weekdays (`--repeat-on`). Any other EventKit-native selector
// (`daysOfTheMonth`, a week-numbered day such as "the last Friday", etc. --
// only reachable by editing a rule this CLI didn't create) returns nil rather
// than guess.
private let maxRecurrenceSteps = 10_000

private func hasComplexSelectors(_ rule: EKRecurrenceRule) -> Bool {
    !(rule.daysOfTheMonth ?? []).isEmpty
        || !(rule.monthsOfTheYear ?? []).isEmpty
        || !(rule.weeksOfTheYear ?? []).isEmpty
        || !(rule.daysOfTheYear ?? []).isEmpty
        || !(rule.setPositions ?? []).isEmpty
}

private func calendarComponent(for frequency: EKRecurrenceFrequency) -> Calendar.Component? {
    switch frequency {
    case .daily: return .day
    case .weekly: return .weekOfYear
    case .monthly: return .month
    case .yearly: return .year
    @unknown default: return nil
    }
}

func nextOccurrence(
    of rule: EKRecurrenceRule, anchoredAt anchor: Date, onOrAfter referenceDate: Date,
    calendar: Calendar = .current
) -> Date? {
    guard !hasComplexSelectors(rule), let component = calendarComponent(for: rule.frequency) else {
        return nil
    }

    let interval = max(rule.interval, 1)
    let endDate = rule.recurrenceEnd?.endDate
    let occurrenceLimit = rule.recurrenceEnd?.occurrenceCount

    func isWithinBounds(_ date: Date, occurrenceNumber: Int) -> Bool {
        if let endDate, date > endDate {
            return false
        }
        if let occurrenceLimit, occurrenceLimit > 0, occurrenceNumber > occurrenceLimit {
            return false
        }
        return true
    }

    if !(rule.daysOfTheWeek ?? []).isEmpty {
        guard rule.frequency == .weekly, let weekdays = plainWeekdays(of: rule) else {
            return nil
        }
        var weekCalendar = calendar
        if rule.firstDayOfTheWeek > 0 {
            weekCalendar.firstWeekday = rule.firstDayOfTheWeek
        }
        return nextWeekdayOccurrence(
            on: Set(weekdays.map { $0.rawValue }), everyWeeks: interval, anchoredAt: anchor,
            onOrAfter: referenceDate, calendar: weekCalendar, isWithinBounds: isWithinBounds)
    }

    var occurrence = anchor
    var occurrenceNumber = 1

    while occurrence < referenceDate {
        guard isWithinBounds(occurrence, occurrenceNumber: occurrenceNumber),
            let next = calendar.date(byAdding: component, value: interval, to: occurrence)
        else {
            return nil
        }
        occurrence = next
        occurrenceNumber += 1

        if occurrenceNumber > maxRecurrenceSteps {
            return nil
        }
    }

    return isWithinBounds(occurrence, occurrenceNumber: occurrenceNumber) ? occurrence : nil
}

// A weekly rule on a set of weekdays: the anchor (the due date) is the first
// occurrence, whatever day it falls on, as for iCalendar's DTSTART. After it,
// every day at the anchor's time of day is an occurrence when its weekday is in
// the set and its week is a whole number of intervals after the anchor's week.
private func nextWeekdayOccurrence(
    on weekdays: Set<Int>, everyWeeks interval: Int, anchoredAt anchor: Date,
    onOrAfter referenceDate: Date, calendar: Calendar,
    isWithinBounds: (Date, Int) -> Bool
) -> Date? {
    guard let anchorWeek = calendar.dateInterval(of: .weekOfYear, for: anchor)?.start else {
        return nil
    }

    var occurrence = anchor
    var occurrenceNumber = 1
    var dayOffset = 0

    while occurrence < referenceDate {
        guard isWithinBounds(occurrence, occurrenceNumber) else {
            return nil
        }
        var isOccurrence = false
        while !isOccurrence {
            dayOffset += 1
            guard dayOffset <= maxRecurrenceSteps * 7,
                let day = calendar.date(byAdding: .day, value: dayOffset, to: anchor),
                let week = calendar.dateInterval(of: .weekOfYear, for: day)?.start
            else {
                return nil
            }
            let weeksSinceAnchor = calendar.dateComponents(
                [.weekOfYear], from: anchorWeek, to: week
            ).weekOfYear ?? 0
            occurrence = day
            isOccurrence = weekdays.contains(calendar.component(.weekday, from: day))
                && weeksSinceAnchor % interval == 0
        }
        occurrenceNumber += 1
    }

    return isWithinBounds(occurrence, occurrenceNumber) ? occurrence : nil
}

// Completing a repeating reminder moves it to its next occurrence and leaves a
// completed copy without a rule behind. A completed reminder that still has a
// rule is one whose repeat ran out, so it has no next due date.
func nextDueDate(from reminder: EKReminder, referenceDate: Date = Date()) -> Date? {
    guard !reminder.isCompleted,
        let rule = reminder.recurrenceRules?.first,
        let anchor = reminder.dueDateComponents?.date
    else {
        return nil
    }
    return nextOccurrence(of: rule, anchoredAt: anchor, onOrAfter: referenceDate)
}

// Used by `postpone --next-weekday`. Always advances at least one calendar
// day from `anchor` -- a Wednesday lands on Thursday, not a no-op -- then
// keeps stepping while the candidate falls on a weekend, so Friday, Saturday,
// and Sunday all land on the following Monday. Preserves `anchor`'s
// time-of-day when it had one; a date-only (all-day) anchor stays date-only.
func nextWeekday(after anchor: DateComponents, calendar: Calendar = Calendar.current) -> DateComponents? {
    guard let anchorDate = anchor.date else {
        return nil
    }

    var candidate = anchorDate
    repeat {
        guard let next = calendar.date(byAdding: .day, value: 1, to: candidate) else {
            return nil
        }
        candidate = next
    } while calendar.isDateInWeekend(candidate)

    let wantedComponents = anchor.hour != nil
        ? calendarComponents()
        : calendarComponents(except: timeComponents)
    return calendar.dateComponents(wantedComponents, from: candidate)
}
