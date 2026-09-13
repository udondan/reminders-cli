import ArgumentParser
import EventKit
import Foundation

private let Store = EKEventStore()
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
}

private func format(_ reminder: EKReminder, id: String, listName: String? = nil) -> String {
    let dateString = formattedDueDate(from: reminder).map { " (\($0))" } ?? ""
    let priorityString = Priority(reminder.mappedPriority).map { " (priority: \($0))" } ?? ""
    let listString = listName.map { "\($0): " } ?? ""
    // EventKit stores cleared notes as "" rather than nil; both mean "no notes".
    let notesString = reminder.notes.flatMap { $0.isEmpty ? nil : " (\($0))" } ?? ""
    let recurrenceString = formattedRecurrence(from: reminder).map { " (\($0))" } ?? ""
    return "\(listString)\(id): \(reminder.title ?? "<unknown>")\(notesString)\(dateString)\(priorityString)\(recurrenceString)"
}

// Additional, independently-composable filters for `show`/`show-all`, ANDed together and ANDed
// with the pre-existing day-granularity `--due-date`/`--include-overdue` filter. `now`,
// `dueBefore`, `dueAfter`, and `completedSince` are resolved to concrete `Date`s once per command
// invocation by the caller, not per reminder. Kept internal (not private) so it's directly
// unit-testable via `@testable import`, matching `recurrenceEndDate`/`nextOccurrence` elsewhere in
// this file.
func matchesAdditionalFilters(
    _ reminder: EKReminder,
    now: Date,
    overdue: Bool,
    dueBefore: Date?,
    dueAfter: Date?,
    noDueDate: Bool,
    priorities: [Priority],
    search: String?,
    completedSince: Date? = nil
) -> Bool {
    let reminderDueDate = reminder.dueDateComponents?.date

    if noDueDate && reminderDueDate != nil {
        return false
    }
    if overdue && !(reminderDueDate.map { $0 < now } ?? false) {
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

// Resolves a list argument that may be either a `calendarIdentifier` or a (case-insensitive)
// list title. ID matches take precedence, so a title that happens to collide with another
// list's ID still resolves to the list with that ID. Kept as a free function, separate from
// `Reminders.calendar(withNameOrId:)`, so it's directly unit-testable via `@testable import`
// without needing live access to Reminders.app, matching `matchesAdditionalFilters` above.
func calendarMatching(_ calendars: [EKCalendar], nameOrId: String) -> EKCalendar? {
    if let calendar = calendars.first(where: { $0.calendarIdentifier == nameOrId }) {
        return calendar
    } else {
        return calendars.first { $0.title.lowercased() == nameOrId.lowercased() }
    }
}

/// `calendarMatching` with the "not found" case turned into the error every command reports.
func resolveCalendar(_ calendars: [EKCalendar], nameOrId: String) throws -> EKCalendar {
    guard let calendar = calendarMatching(calendars, nameOrId: nameOrId) else {
        throw CLIError.listNotFound(nameOrId)
    }
    return calendar
}

public enum OutputFormat: String, ExpressibleByArgument {
    case json, plain

    /// Best-effort detection of `--format` from raw argv, for the one error that has to be
    /// reported before ArgumentParser has parsed anything: the Reminders access check in
    /// `main.swift`. Recognises `--format X`, `--format=X`, and `-f X`; stops at `--` since
    /// everything after it is positional text. Anything unrecognised means plain.
    public static func detect(in arguments: [String]) -> OutputFormat {
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            if argument == "--" {
                break
            }
            if argument == "--format" || argument == "-f" {
                return iterator.next().flatMap(OutputFormat.init(rawValue:)) ?? .plain
            }
            if argument.hasPrefix("--format=") {
                return OutputFormat(rawValue: String(argument.dropFirst("--format=".count))) ?? .plain
            }
        }
        return .plain
    }
}

public enum DisplayOptions: String, Decodable {
    case all
    case incomplete
    case complete
}

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

    func recurrenceRule(interval: Int, end: EKRecurrenceEnd?) -> EKRecurrenceRule {
        return EKRecurrenceRule(
            recurrenceWith: self.frequency,
            interval: interval,
            end: end)
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
        }
    }
}

struct RecurrenceUpdate {
    let recurrence: Recurrence?
    let interval: Int?
    let end: RecurrenceEndUpdate

    var isRequested: Bool {
        if recurrence != nil || interval != nil {
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

        let shouldPreserveInterval = recurrence == nil || existingRule?.frequency == frequency
        let inheritedInterval = shouldPreserveInterval ? existingRule?.interval : nil
        let resolvedInterval = interval ?? inheritedInterval ?? 1
        let resolvedEnd = end.applying(to: existingRule?.recurrenceEnd)

        // Changing only the end condition can preserve more than the public
        // initializer exposes, including provider-specific calendar metadata
        // and firstDayOfTheWeek. Copy the complete EventKit rule and modify its
        // sole writable recurrence property rather than reconstructing it.
        if let existingRule, recurrence == nil, interval == nil {
            guard let copiedRule = existingRule.copy() as? EKRecurrenceRule else {
                throw RecurrenceUpdateError.failedToCopyExistingRule
            }
            copiedRule.recurrenceEnd = resolvedEnd
            return copiedRule
        }

        // An interval edit must preserve every public selector in a complex
        // rule (for example, "the last Friday of every month"). The same
        // applies when the explicitly supplied frequency is unchanged.
        if let existingRule,
            recurrence == nil || existingRule.frequency == frequency
        {
            return EKRecurrenceRule(
                recurrenceWith: frequency,
                interval: resolvedInterval,
                daysOfTheWeek: existingRule.daysOfTheWeek,
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
// forward from its anchor date. It only handles the plain daily/weekly/
// monthly/yearly + interval rules this CLI itself creates and edits; a rule
// with EventKit-native selectors (`daysOfTheWeek`, `daysOfTheMonth`, etc. --
// only reachable by editing a rule this CLI didn't create) returns nil rather
// than guess.
private let maxRecurrenceSteps = 10_000

private func hasComplexSelectors(_ rule: EKRecurrenceRule) -> Bool {
    !(rule.daysOfTheWeek ?? []).isEmpty
        || !(rule.daysOfTheMonth ?? []).isEmpty
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
    of rule: EKRecurrenceRule, anchoredAt anchor: Date, onOrAfter referenceDate: Date
) -> Date? {
    guard !hasComplexSelectors(rule), let component = calendarComponent(for: rule.frequency) else {
        return nil
    }

    let interval = max(rule.interval, 1)
    let calendar = Calendar.current
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

func nextDueDate(from reminder: EKReminder, referenceDate: Date = Date()) -> Date? {
    guard let rule = reminder.recurrenceRules?.first,
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

public enum Priority: String, ExpressibleByArgument {
    case none
    case low
    case medium
    case high

    var value: EKReminderPriority {
        switch self {
            case .none: return .none
            case .low: return .low
            case .medium: return .medium
            case .high: return .high
        }
    }

    init?(_ priority: EKReminderPriority) {
        switch priority {
            case .none: return nil
            case .low: self = .low
            case .medium: self = .medium
            case .high: self = .high
        @unknown default:
            return nil
        }
    }
}

public final class Reminders {
    public static func requestAccess() -> (Bool, Error?) {
        let semaphore = DispatchSemaphore(value: 0)
        var grantedAccess = false
        var returnError: Error? = nil
        if #available(macOS 14.0, *) {
            Store.requestFullAccessToReminders { granted, error in
                grantedAccess = granted
                returnError = error
                semaphore.signal()
            }
        } else {
            Store.requestAccess(to: .reminder) { granted, error in
                grantedAccess = granted
                returnError = error
                semaphore.signal()
            }
        }

        semaphore.wait()
        return (grantedAccess, returnError)
    }

    func getListNames() -> [String] {
        return self.getCalendars().map { $0.title }
    }

    func getDefaultList() -> EKCalendar? {
        return Store.defaultCalendarForNewReminders()
    }

    func showLists(outputFormat: OutputFormat, defaultOnly: Bool = false) throws {
        let calendars: [EKCalendar]
        if defaultOnly {
            guard let defaultCalendar = self.getDefaultList() else {
                throw CLIError.noDefaultList()
            }
            calendars = [defaultCalendar]
        } else {
            calendars = self.getCalendars()
        }
        switch (outputFormat) {
        case .json:
            print(encodeToJson(data: calendars))
        default:
            for calendar in calendars {
                print("\(calendar.title) (\(calendar.calendarIdentifier))")
            }
        }
    }

    func showAllReminders(
        dueOn dueDate: DateComponents?, includeOverdue: Bool,
        overdue: Bool = false, dueBefore: DateComponents? = nil, dueAfter: DateComponents? = nil,
        noDueDate: Bool = false, priorities: [Priority] = [], search: String? = nil,
        lists: [String] = [], completedSince: DateComponents? = nil,
        displayOptions: DisplayOptions, outputFormat: OutputFormat, sort: Sort, sortOrder: CustomSortOrder
    ) throws {
        let calendar = Calendar.current
        let now = Date()
        // Date-only means the whole local day, same rule as --repeat-until; --due-after needs no
        // expansion since a date-only value's `.date` is already midnight, the correct inclusive
        // lower bound.
        let dueBeforeDate = dueBefore.flatMap { recurrenceEndDate(from: $0) }
        let dueAfterDate = dueAfter?.date
        let completedSinceDate = completedSince?.date
        // Resolving --list up front means an unknown list name or ID fails with `list_not_found`
        // before any reminders are fetched.
        let calendars = lists.isEmpty ? self.getCalendars() : try lists.map { try self.calendar(withNameOrId: $0) }

        let fetched = self.fetchReminders(on: calendars, displayOptions: displayOptions)
        var matchingReminders = [(EKReminder, String, String)]()
        let reminders = sort == .none ? fetched : fetched.sorted(by: sort.sortFunction(order: sortOrder))
        for reminder in reminders {
            let id = reminder.calendarItemExternalIdentifier ?? "<unknown-id>"
            let listName = reminder.calendar.title

            let matchesExistingDueDateFilter: Bool
            if let dueDate = dueDate?.date {
                guard let reminderDueDate = reminder.dueDateComponents?.date else {
                    continue
                }
                let sameDay = calendar.compare(
                    reminderDueDate, to: dueDate, toGranularity: .day) == .orderedSame
                let earlierDay = calendar.compare(
                    reminderDueDate, to: dueDate, toGranularity: .day) == .orderedAscending
                matchesExistingDueDateFilter = sameDay || (includeOverdue && earlierDay)
            } else {
                matchesExistingDueDateFilter = true
            }
            guard matchesExistingDueDateFilter else {
                continue
            }

            guard matchesAdditionalFilters(
                reminder, now: now, overdue: overdue, dueBefore: dueBeforeDate,
                dueAfter: dueAfterDate, noDueDate: noDueDate, priorities: priorities, search: search,
                completedSince: completedSinceDate
            ) else {
                continue
            }

            matchingReminders.append((reminder, id, listName))
        }

        switch outputFormat {
        case .json:
            print(encodeToJson(data: matchingReminders.map { $0.0 }))
        case .plain:
            for (reminder, id, listName) in matchingReminders {
                print(format(reminder, id: id, listName: listName))
            }
        }
    }

    func showListItems(
        withNameOrId nameOrId: String, dueOn dueDate: DateComponents?, includeOverdue: Bool,
        overdue: Bool = false, dueBefore: DateComponents? = nil, dueAfter: DateComponents? = nil,
        noDueDate: Bool = false, priorities: [Priority] = [], search: String? = nil,
        completedSince: DateComponents? = nil,
        displayOptions: DisplayOptions, outputFormat: OutputFormat, sort: Sort, sortOrder: CustomSortOrder)
        throws
    {
        let reminderCalendar = try self.calendar(withNameOrId: nameOrId)
        let calendar = Calendar.current
        let now = Date()
        let dueBeforeDate = dueBefore.flatMap { recurrenceEndDate(from: $0) }
        let dueAfterDate = dueAfter?.date
        let completedSinceDate = completedSince?.date

        let fetched = self.fetchReminders(on: [reminderCalendar], displayOptions: displayOptions)
        var matchingReminders = [(EKReminder, String)]()
        let reminders = sort == .none ? fetched : fetched.sorted(by: sort.sortFunction(order: sortOrder))
        for reminder in reminders {
            let id = reminder.calendarItemExternalIdentifier ?? "<unknown-id>"

            let matchesExistingDueDateFilter: Bool
            if let dueDate = dueDate?.date {
                guard let reminderDueDate = reminder.dueDateComponents?.date else {
                    continue
                }
                let sameDay = calendar.compare(
                    reminderDueDate, to: dueDate, toGranularity: .day) == .orderedSame
                let earlierDay = calendar.compare(
                    reminderDueDate, to: dueDate, toGranularity: .day) == .orderedAscending
                matchesExistingDueDateFilter = sameDay || (includeOverdue && earlierDay)
            } else {
                matchesExistingDueDateFilter = true
            }
            guard matchesExistingDueDateFilter else {
                continue
            }

            guard matchesAdditionalFilters(
                reminder, now: now, overdue: overdue, dueBefore: dueBeforeDate,
                dueAfter: dueAfterDate, noDueDate: noDueDate, priorities: priorities, search: search,
                completedSince: completedSinceDate
            ) else {
                continue
            }

            matchingReminders.append((reminder, id))
        }

        switch outputFormat {
        case .json:
            print(encodeToJson(data: matchingReminders.map { $0.0 }))
        case .plain:
            for (reminder, id) in matchingReminders {
                print(format(reminder, id: id))
            }
        }
    }

    func newList(with name: String, source requestedSourceName: String?, outputFormat: OutputFormat) throws {
        let store = EKEventStore()
        // EventKit can expose several sources with the same title (e.g. an iCloud calendar
        // account next to the iCloud reminders account). Only the ones that already hold
        // reminder lists can accept a new one, so restrict the selection to those.
        let reminderSourceIds = Set(
            store.calendars(for: .reminder).compactMap { $0.source?.sourceIdentifier })
        let candidates = store.sources.map {
            ListSourceCandidate(
                title: $0.title,
                holdsReminderLists: reminderSourceIds.contains($0.sourceIdentifier))
        }

        let source: EKSource
        switch selectListSource(requested: requestedSourceName, from: candidates) {
        case .chosen(let index):
            source = store.sources[index]
        case .noSources:
            throw CLIError.noSources()
        case .notFound(let requested):
            throw CLIError.sourceNotFound(requested)
        case .ambiguous(let titles):
            throw CLIError.sourceAmbiguous(titles)
        }

        let newList = EKCalendar(for: .reminder, eventStore: store)
        newList.title = name
        newList.source = source

        do {
            try store.saveCalendar(newList, commit: true)
        } catch let error {
            throw CLIError.saveFailed(action: "create list '\(name)'", underlying: error)
        }
        switch outputFormat {
        case .json:
            print(encodeToJson(data: newList))
        case .plain:
            print("Created new list '\(newList.title)'!")
        }
    }

    func edit(
        itemAtId id: String,
        onListNamedOrId nameOrId: String,
        newText: String?,
        newNotes: String?,
        clearNotes: Bool = false,
        newDueDateComponents: DateComponents? = nil,
        clearDueDate: Bool = false,
        priority: Priority? = nil,
        clearPriority: Bool = false,
        newListName: String? = nil,
        newRecurrence: Recurrence?, newRecurrenceInterval: Int?,
        newRecurrenceEndDate: DateComponents?,
        clearRecurrenceEnd: Bool,
        clearRecurrence: Bool,
        outputFormat: OutputFormat) throws
    {
        let calendar = try self.calendar(withNameOrId: nameOrId)
        let dueDateChangeRequested = clearDueDate || newDueDateComponents != nil
        let recurrenceChangeRequested = clearRecurrence || newRecurrence != nil
            || newRecurrenceInterval != nil || newRecurrenceEndDate != nil
            || clearRecurrenceEnd

        let reminder = try self.reminder(
            withId: id,
            in: self.fetchReminders(on: [calendar], displayOptions: .incomplete),
            onList: nameOrId)

        reminder.title = newText ?? reminder.title
        if clearNotes {
            reminder.notes = nil
        } else {
            reminder.notes = newNotes ?? reminder.notes
        }
        if clearPriority {
            reminder.priority = Int(EKReminderPriority.none.rawValue)
        } else if let priority {
            reminder.priority = Int(priority.value.rawValue)
        }

        if let newListName {
            reminder.calendar = try self.calendar(withNameOrId: newListName)
        }

        if clearDueDate {
            reminder.dueDateComponents = nil
            for alarm in reminder.alarms ?? [] {
                reminder.removeAlarm(alarm)
            }
        } else if let newDueDateComponents {
            reminder.dueDateComponents = newDueDateComponents
            for alarm in reminder.alarms ?? [] {
                reminder.removeAlarm(alarm)
            }

            if let dueDate = newDueDateComponents.date, newDueDateComponents.hour != nil {
                reminder.addAlarm(EKAlarm(absoluteDate: dueDate))
            }
        }

        do {
            if clearRecurrence {
                for rule in reminder.recurrenceRules ?? [] {
                    reminder.removeRecurrenceRule(rule)
                }
            } else {
                let endUpdate: RecurrenceEndUpdate
                if clearRecurrenceEnd {
                    endUpdate = .clear
                } else if let newRecurrenceEndDate {
                    guard let date = recurrenceEndDate(from: newRecurrenceEndDate) else {
                        throw RecurrenceUpdateError.invalidEndDate
                    }
                    endUpdate = .date(date)
                } else {
                    endUpdate = .unchanged
                }

                let update = RecurrenceUpdate(
                    recurrence: newRecurrence,
                    interval: newRecurrenceInterval,
                    end: endUpdate)
                if update.isRequested {
                    let existingRules = reminder.recurrenceRules ?? []
                    let replacements: [EKRecurrenceRule]
                    if newRecurrence == nil {
                        guard !existingRules.isEmpty else {
                            throw RecurrenceUpdateError.missingExistingRule
                        }
                        replacements = try existingRules.map {
                            try update.rule(replacing: $0)
                        }
                    } else {
                        replacements = [try update.rule(replacing: existingRules.first)]
                    }

                    for rule in existingRules {
                        reminder.removeRecurrenceRule(rule)
                    }
                    for replacement in replacements {
                        reminder.addRecurrenceRule(replacement)
                    }
                }
            }
            if dueDateChangeRequested || recurrenceChangeRequested {
                try validateRecurrenceSchedule(
                    dueDateComponents: reminder.dueDateComponents,
                    rules: reminder.recurrenceRules ?? [])
            }
        } catch let error as RecurrenceUpdateError {
            throw CLIError.invalidArgument(error.localizedDescription)
        }

        try self.save(reminder, action: "update reminder")
        switch outputFormat {
        case .json:
            print(encodeToJson(data: reminder))
        case .plain:
            print("Updated reminder '\(reminder.title!)'")
        }
    }

    func postpone(
        itemAtId id: String,
        onListNamedOrId nameOrId: String,
        to newDueDateComponents: DateComponents?,
        toNextWeekday: Bool,
        outputFormat: OutputFormat) throws
    {
        let calendar = try self.calendar(withNameOrId: nameOrId)
        let reminder = try self.reminder(
            withId: id,
            in: self.fetchReminders(on: [calendar], displayOptions: .incomplete),
            onList: nameOrId)

        let resolvedComponents: DateComponents
        if toNextWeekday {
            guard let currentDue = reminder.dueDateComponents,
                let shifted = nextWeekday(after: currentDue)
            else {
                throw CLIError.noDueDate()
            }
            resolvedComponents = shifted
        } else if let newDueDateComponents {
            resolvedComponents = newDueDateComponents
        } else {
            fatalError("postpone requires either a new due date or --next-weekday")
        }

        // recurrenceRules is never read or written here, so any
        // existing repeat rule passes through completely unchanged.
        reminder.dueDateComponents = resolvedComponents
        for alarm in reminder.alarms ?? [] {
            reminder.removeAlarm(alarm)
        }
        if let date = resolvedComponents.date, resolvedComponents.hour != nil {
            reminder.addAlarm(EKAlarm(absoluteDate: date))
        }

        do {
            try validateRecurrenceSchedule(
                dueDateComponents: reminder.dueDateComponents,
                rules: reminder.recurrenceRules ?? [])
        } catch let error as RecurrenceUpdateError {
            throw CLIError.invalidArgument(error.localizedDescription)
        }

        try self.save(reminder, action: "postpone reminder")
        switch outputFormat {
        case .json:
            print(encodeToJson(data: reminder))
        case .plain:
            print("Postponed reminder '\(reminder.title!)'")
        }
    }

    func setComplete(_ complete: Bool, itemAtId id: String, onListNamedOrId nameOrId: String, outputFormat: OutputFormat) throws {
        let calendar = try self.calendar(withNameOrId: nameOrId)
        let reminder = try self.reminder(
            withId: id,
            in: self.fetchReminders(on: [calendar], displayOptions: complete ? .incomplete : .complete),
            onList: nameOrId)

        reminder.isCompleted = complete
        try self.save(reminder, action: complete ? "complete reminder" : "uncomplete reminder")
        switch outputFormat {
        case .json:
            print(encodeToJson(data: reminder))
        case .plain:
            print("\(complete ? "Completed" : "Uncompleted") '\(reminder.title!)'")
        }
    }

    func delete(itemAtId id: String, onListNamedOrId nameOrId: String, outputFormat: OutputFormat) throws {
        let calendar = try self.calendar(withNameOrId: nameOrId)
        // External identifiers are stable regardless of completion state, so a
        // reminder already marked complete can still be found and deleted by its id.
        let reminder = try self.reminder(
            withId: id,
            in: self.fetchReminders(on: [calendar], displayOptions: .all),
            onList: nameOrId)

        // Encode before removing: the encoder reads `reminder.calendar`, which is
        // no longer meaningful once the reminder is gone from the store.
        let confirmation: String
        switch outputFormat {
        case .json:
            confirmation = encodeToJson(data: reminder)
        case .plain:
            confirmation = "Deleted '\(reminder.title!)'"
        }

        do {
            try Store.remove(reminder, commit: true)
        } catch let error {
            throw CLIError.saveFailed(action: "delete reminder", underlying: error)
        }
        print(confirmation)
    }

    func addReminder(
        string: String,
        notes: String?,
        toListNameOrId nameOrId: String,
        dueDateComponents: DateComponents?,
        priority: Priority,
        recurrence: Recurrence?,
        recurrenceInterval: Int,
        recurrenceEndDate: DateComponents?,
        outputFormat: OutputFormat) throws
    {
        let calendar = try self.calendar(withNameOrId: nameOrId)
        let reminder = EKReminder(eventStore: Store)
        reminder.calendar = calendar
        reminder.title = string
        reminder.notes = notes
        reminder.dueDateComponents = dueDateComponents
        reminder.priority = Int(priority.value.rawValue)
        if let dueDate = dueDateComponents, dueDate.hour != nil {
            if let absoluteDate = dueDate.date {
                reminder.addAlarm(EKAlarm(absoluteDate: absoluteDate))
            }
        }

        try self.save(reminder, action: "add reminder")
        switch outputFormat {
        case .json:
            print(encodeToJson(data: reminder))
        case .plain:
            print("Added reminder '\(reminder.title!)' to list '\(calendar.title)'")
        }
    }

    // MARK: - Private functions

    /// EventKit only offers a callback-based fetch; block on it once here so every command
    /// can be written as straight-line code that simply throws on failure (nothing can be
    /// thrown from inside EventKit's completion closure).
    private func fetchReminders(on calendars: [EKCalendar], displayOptions: DisplayOptions) -> [EKReminder] {
        let semaphore = DispatchSemaphore(value: 0)
        var fetched: [EKReminder] = []
        let predicate = Store.predicateForReminders(in: calendars)
        Store.fetchReminders(matching: predicate) { reminders in
            fetched = reminders?
                .filter { self.shouldDisplay(reminder: $0, displayOptions: displayOptions) } ?? []
            semaphore.signal()
        }
        semaphore.wait()
        return fetched
    }

    private func save(_ reminder: EKReminder, action: String) throws {
        do {
            try Store.save(reminder, commit: true)
        } catch let error {
            throw CLIError.saveFailed(action: action, underlying: error)
        }
    }

    private func shouldDisplay(reminder: EKReminder, displayOptions: DisplayOptions) -> Bool {
        switch displayOptions {
        case .all:
            return true
        case .incomplete:
            return !reminder.isCompleted
        case .complete:
            return reminder.isCompleted
        }
    }

    // Kept internal (not private) so the `list_not_found` path is directly unit-testable via
    // `@testable import`, matching `matchesAdditionalFilters` above.
    func calendar(withNameOrId nameOrId: String) throws -> EKCalendar {
        return try resolveCalendar(self.getCalendars(), nameOrId: nameOrId)
    }

    private func getCalendars() -> [EKCalendar] {
        return Store.calendars(for: .reminder)
                    .filter { $0.allowsContentModifications }
    }

    // Kept internal (not private) so it's directly unit-testable via `@testable import`,
    // matching `matchesAdditionalFilters` above.
    func getReminder(from reminders: [EKReminder], withId id: String) -> EKReminder? {
        return reminders.first { $0.calendarItemExternalIdentifier == id }
    }

    /// `getReminder` with the "not found" case turned into the error every command reports.
    func reminder(withId id: String, in reminders: [EKReminder], onList nameOrId: String) throws -> EKReminder {
        guard let reminder = self.getReminder(from: reminders, withId: id) else {
            throw CLIError.reminderNotFound(id: id, listNameOrId: nameOrId)
        }
        return reminder
    }

}

/// A list source as seen by `new-list`, reduced to what the selection logic needs so it can be
/// unit-tested without constructing `EKSource` (which EventKit doesn't allow).
struct ListSourceCandidate: Equatable {
    let title: String
    let holdsReminderLists: Bool
}

enum ListSourceSelection: Equatable {
    /// Index into the candidates array of the source to create the list in.
    case chosen(Int)
    /// No source holds reminder lists at all.
    case noSources
    /// `--source` named something that doesn't hold reminder lists.
    case notFound(String)
    /// Several differently-titled sources hold reminder lists and no `--source` was given.
    case ambiguous([String])
}

/// Picks the source for `new-list`, considering only sources that already hold reminder lists.
/// Sources are matched by title; when several reminder-capable sources share a title (rare, but
/// possible with multiple accounts of the same kind) the first one wins.
func selectListSource(requested: String?, from candidates: [ListSourceCandidate]) -> ListSourceSelection {
    let usable = candidates.enumerated().filter { $0.element.holdsReminderLists }
    guard let first = usable.first else {
        return .noSources
    }

    if let requested {
        guard let match = usable.first(where: { $0.element.title == requested }) else {
            return .notFound(requested)
        }
        return .chosen(match.offset)
    }

    var titles: [String] = []
    for (_, candidate) in usable where !titles.contains(candidate.title) {
        titles.append(candidate.title)
    }
    if titles.count > 1 {
        return .ambiguous(titles)
    }
    return .chosen(first.offset)
}

private func encodeToJson(data: Encodable) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let encoded = try! encoder.encode(data)
    return String(data: encoded, encoding: .utf8) ?? ""
}

