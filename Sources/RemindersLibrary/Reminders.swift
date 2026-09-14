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
}

func format(_ reminder: EKReminder, id: String, listName: String? = nil) -> String {
    let dateString = formattedDueDate(from: reminder).map { " (\($0))" } ?? ""
    let priorityString = Priority(reminder.mappedPriority).map { " (priority: \($0))" } ?? ""
    let listString = listName.map { "\($0): " } ?? ""
    // EventKit stores cleared notes as "" rather than nil; both mean "no notes".
    let notesString = reminder.notes.flatMap { $0.isEmpty ? nil : " (\($0))" } ?? ""
    let recurrenceString = formattedRecurrence(from: reminder).map { " (\($0))" } ?? ""
    let flaggedString = reminder.isFlagged ? " (flagged)" : ""
    return "\(listString)\(id): \(reminder.title ?? "<unknown>")\(notesString)\(dateString)\(priorityString)\(recurrenceString)\(flaggedString)"
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

/// Resolves a list argument that may be a `calendarIdentifier` or (part of) a list title. The
/// steps are tried in order and the first one that produces a hit wins, so exact input always
/// behaves as it did before forgiving matching existed:
///
/// 1. exact `calendarIdentifier` (so a title that collides with another list's ID still loses)
/// 2. exact title
/// 3. case-insensitive title
/// 4. case-insensitive substring of the title; exactly one hit resolves, several are reported as
///    `list_ambiguous` rather than guessed
///
/// Empty or whitespace-only input skips step 4 (it would match every list). Nothing matching is
/// `list_not_found`, with every available list name in the suggestion. Kept as a free function,
/// separate from `Reminders.calendar(withNameOrId:)`, so it's directly unit-testable via
/// `@testable import` without live access to Reminders.app, matching `matchesAdditionalFilters`.
func resolveCalendar(_ calendars: [EKCalendar], nameOrId: String) throws -> EKCalendar {
    if let calendar = calendars.first(where: { $0.calendarIdentifier == nameOrId }) {
        return calendar
    }
    if let calendar = calendars.first(where: { $0.title == nameOrId }) {
        return calendar
    }
    if let calendar = calendars.first(where: { $0.title.lowercased() == nameOrId.lowercased() }) {
        return calendar
    }
    if !nameOrId.trimmingCharacters(in: .whitespaces).isEmpty {
        let candidates = calendars.filter { $0.title.localizedCaseInsensitiveContains(nameOrId) }
        if candidates.count == 1 {
            return candidates[0]
        }
        if candidates.count > 1 {
            throw CLIError.listAmbiguous(nameOrId, matches: candidates.map { $0.title })
        }
    }
    throw CLIError.listNotFound(nameOrId, available: calendars.map { $0.title })
}

/// The stricter list lookup behind `delete-list`, where a guessed list would destroy the wrong
/// reminders. Steps 1–3 of `resolveCalendar`, without the substring step:
///
/// 1. exact `calendarIdentifier`
/// 2. exact title
/// 3. case-insensitive title
///
/// Unlike `resolveCalendar`, a title step that matches several lists (e.g. two "Groceries" in
/// different accounts) is `list_ambiguous` instead of picking the first one. A name that is only
/// part of a title is `list_not_found`, naming those titles in the suggestion.
func resolveCalendarExactly(_ calendars: [EKCalendar], nameOrId: String) throws -> EKCalendar {
    if let calendar = calendars.first(where: { $0.calendarIdentifier == nameOrId }) {
        return calendar
    }
    let titleSteps: [(EKCalendar) -> Bool] = [
        { $0.title == nameOrId },
        { $0.title.lowercased() == nameOrId.lowercased() },
    ]
    for matches in titleSteps {
        let candidates = calendars.filter(matches)
        if candidates.count == 1 {
            return candidates[0]
        }
        if candidates.count > 1 {
            throw CLIError.listAmbiguous(nameOrId, matches: candidates.map { $0.title })
        }
    }
    let partialMatches = nameOrId.trimmingCharacters(in: .whitespaces).isEmpty
        ? []
        : calendars.filter { $0.title.localizedCaseInsensitiveContains(nameOrId) }.map { $0.title }
    throw CLIError.listNotFoundExactly(nameOrId, partialMatches: partialMatches)
}

/// The rules `delete-list` applies before removing a list, free of EventKit so they're
/// unit-testable. Refusals come first, so a run without `--confirm` on a list that can't be
/// deleted reports why instead of asking for confirmation.
func checkListDeletion(
    title: String, isDefault: Bool, allowsModifications: Bool,
    reminderCount: Int, completedCount: Int, confirm: Bool
) throws {
    if isDefault {
        throw CLIError.invalidArgument(
            "Cannot delete '\(title)': it is the default list for new reminders. "
                + "Choose another default list in Reminders.app settings first")
    }
    if !allowsModifications {
        throw CLIError.invalidArgument("Cannot delete '\(title)': the list is read-only")
    }
    if !confirm {
        throw CLIError.confirmationRequired(
            title: title, reminderCount: reminderCount, completedCount: completedCount)
    }
}

/// The `delete-list --format json` output.
struct DeletedList: Encodable {
    let deleted = true
    let title: String
    let calendarIdentifier: String
    let reminderCount: Int
}

/// The shortest ID prefix that's accepted in place of a full reminder ID. Anything shorter only
/// matches exactly, so a stray one- or two-character argument can't act on the wrong reminder.
let minimumIdPrefixLength = 4

enum IdentifierMatch: Equatable {
    /// Index into the IDs array of the single match.
    case found(Int)
    /// Indices of every ID the prefix matched.
    case ambiguous([Int])
    case notFound
}

/// Matches an ID argument against a set of identifiers: an exact match always wins, otherwise a
/// case-insensitive prefix of at least `minimumPrefixLength` characters. Works on plain strings so
/// the ambiguity handling is unit-testable; `calendarItemExternalIdentifier` can't be set on a
/// test `EKReminder`.
func matchIdentifier(
    _ ids: [String], idOrPrefix: String, minimumPrefixLength: Int = minimumIdPrefixLength
) -> IdentifierMatch {
    if let index = ids.firstIndex(of: idOrPrefix) {
        return .found(index)
    }
    guard idOrPrefix.count >= minimumPrefixLength else {
        return .notFound
    }
    let matches = ids.indices.filter {
        ids[$0].range(of: idOrPrefix, options: [.caseInsensitive, .anchored]) != nil
    }
    switch matches.count {
    case 0: return .notFound
    case 1: return .found(matches[0])
    default: return .ambiguous(matches)
    }
}

/// `matchIdentifier` with the two failure cases turned into the errors every command reports;
/// returns the index of the one match. `titles` is parallel to `ids` and only used to make the
/// ambiguity message readable. Also string-based so the error rendering is unit-testable.
func resolveIdentifier(
    _ ids: [String], titles: [String], idOrPrefix: String, onList nameOrId: String
) throws -> Int {
    switch matchIdentifier(ids, idOrPrefix: idOrPrefix) {
    case .found(let index):
        return index
    case .ambiguous(let indices):
        let matches = indices.map { "\(ids[$0]) (\(titles[$0]))" }
        throw CLIError.reminderAmbiguous(id: idOrPrefix, matches: matches)
    case .notFound:
        throw CLIError.reminderNotFound(id: idOrPrefix, listNameOrId: nameOrId)
    }
}

/// `resolveIdentifier` over the reminders' external identifiers. The caller decides the search
/// scope by what it fetches (`complete` only looks at incomplete reminders, `delete` at all of
/// them, ...).
func resolveReminder(_ reminders: [EKReminder], idOrPrefix: String, onList nameOrId: String) throws -> EKReminder {
    let index = try resolveIdentifier(
        reminders.map { $0.calendarItemExternalIdentifier ?? "" },
        titles: reminders.map { $0.title ?? "<unknown>" },
        idOrPrefix: idOrPrefix, onList: nameOrId)
    return reminders[index]
}

/// `resolveIdentifier` for every ID of a batch, in argument order. Throws for the first ID that is
/// missing or ambiguous, so a batch either resolves completely or not at all. Several arguments
/// naming the same reminder (a full ID and its prefix, say) yield it once.
func resolveIdentifiers(
    _ ids: [String], titles: [String], idsOrPrefixes: [String], onList nameOrId: String
) throws -> [Int] {
    var indices: [Int] = []
    for idOrPrefix in idsOrPrefixes {
        let index = try resolveIdentifier(ids, titles: titles, idOrPrefix: idOrPrefix, onList: nameOrId)
        if !indices.contains(index) {
            indices.append(index)
        }
    }
    return indices
}

/// `resolveIdentifiers` over the reminders' external identifiers, see `resolveReminder`.
func resolveReminders(
    _ reminders: [EKReminder], idsOrPrefixes: [String], onList nameOrId: String
) throws -> [EKReminder] {
    try resolveIdentifiers(
        reminders.map { $0.calendarItemExternalIdentifier ?? "" },
        titles: reminders.map { $0.title ?? "<unknown>" },
        idsOrPrefixes: idsOrPrefixes, onList: nameOrId
    ).map { reminders[$0] }
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

    if let newCalendar {
        reminder.calendar = newCalendar
    }

    if clearDueDate {
        setDueDate(of: reminder, to: nil)
    } else if let newDueDateComponents {
        setDueDate(of: reminder, to: newDueDateComponents)
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

            let daysUpdate: RecurrenceDaysUpdate
            if clearRecurrenceDays {
                daysUpdate = .clear
            } else if let newRecurrenceDays {
                daysUpdate = .set(newRecurrenceDays)
            } else {
                daysUpdate = .unchanged
            }

            let update = RecurrenceUpdate(
                recurrence: newRecurrence,
                interval: newRecurrenceInterval,
                end: endUpdate,
                days: daysUpdate)
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
}

/// One reminder's share of `postpone`: the new due date, or with `toNextWeekday` the next weekday
/// after its current one (`no_due_date` without one). Its repeat rules are never read or written,
/// so they pass through unchanged; the schedule is still checked against the new due date.
func applyPostpone(
    to reminder: EKReminder, newDueDate: DateComponents?, toNextWeekday: Bool,
    calendar: Calendar = .current
) throws {
    let resolvedComponents: DateComponents
    if toNextWeekday {
        guard let currentDue = reminder.dueDateComponents,
            let shifted = nextWeekday(after: currentDue, calendar: calendar)
        else {
            throw CLIError.noDueDate()
        }
        resolvedComponents = shifted
    } else if let newDueDate {
        resolvedComponents = newDueDate
    } else {
        fatalError("postpone requires either a new due date or --next-weekday")
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

    func showLists(
        outputFormat: OutputFormat, defaultOnly: Bool = false, includeCompleted: Bool = false,
        sort: ListSort = .none
    ) throws {
        let calendars: [EKCalendar]
        if defaultOnly {
            guard let defaultCalendar = self.getDefaultList() else {
                throw CLIError.noDefaultList()
            }
            calendars = [defaultCalendar]
        } else {
            calendars = self.getCalendars()
        }
        let now = Date()
        // One fetch across every list, bucketed afterwards, rather than one fetch per list.
        // Completed reminders are only fetched on request: they dominate a store that has been in
        // use for a while and make the fetch noticeably slower.
        let reminders: [EKReminder]
        if calendars.isEmpty {
            reminders = []
        } else if includeCompleted {
            reminders = self.fetchReminders(on: calendars, displayOptions: .all)
        } else {
            reminders = self.fetchReminders(
                matching: Store.predicateForIncompleteReminders(
                    withDueDateStarting: nil, ending: nil, calendars: calendars),
                displayOptions: .incomplete)
        }
        let summaries = sort.apply(
            to: summarizeLists(
                calendars, reminders: reminders, now: now, includeCompleted: includeCompleted))
        switch outputFormat {
        case .json:
            print(encodeToJson(data: summaries))
        case .plain:
            for line in formatListSummaries(summaries) {
                print(line)
            }
        }
    }

    /// Prints the `doctor` report and returns whether it found no failures. Only reads the
    /// authorization status and never requests access; lists and reminders are read only with
    /// full access, since without it EventKit returns nothing useful.
    func runDoctor(outputFormat: OutputFormat) -> Bool {
        let authorization = ReminderAuthorization(
            rawStatus: EKEventStore.authorizationStatus(for: .reminder).rawValue)

        var data: DoctorData?
        if authorization == .fullAccess {
            let calendars = self.getCalendars()
            let openReminders = calendars.isEmpty
                ? []
                : self.fetchReminders(
                    matching: Store.predicateForIncompleteReminders(
                        withDueDateStarting: nil, ending: nil, calendars: calendars),
                    displayOptions: .incomplete)
            data = DoctorData(
                sources: summarizeSources(calendars.map { $0.source?.title ?? "Unknown" }),
                defaultList: self.getDefaultList().map {
                    DoctorDefaultList(title: $0.title, sourceTitle: $0.source?.title)
                },
                openReminderCount: openReminders.count)
        }

        let report = DoctorReport(
            version: version,
            macOS: formatOSVersion(ProcessInfo.processInfo.operatingSystemVersion),
            macOSBuild: macOSBuildNumber(),
            binary: currentExecutablePath(),
            architecture: currentArchitecture,
            authorization: authorization,
            accessRequestAPI: .current,
            parentProcess: detectParentProcess(),
            data: data)

        switch outputFormat {
        case .json:
            print(encodeToJson(data: report))
        case .plain:
            for line in formatDoctorReport(report) {
                print(line)
            }
        }
        return report.isHealthy
    }

    func showAllReminders(
        dueOn dueDate: DateComponents?, includeOverdue: Bool,
        overdue: Bool = false, dueBefore: DateComponents? = nil, dueAfter: DateComponents? = nil,
        noDueDate: Bool = false, priorities: [Priority] = [], search: String? = nil,
        lists: [String] = [], completedSince: DateComponents? = nil, flagged: Bool = false,
        displayOptions: DisplayOptions, outputFormat: ListingFormat, verbose: Bool = false, sort: Sort,
        sortOrder: CustomSortOrder
    ) throws {
        let now = Date()
        let dueOnDate = dueDate?.date
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

            guard matchesDueOn(reminder, dueOn: dueOnDate, includeOverdue: includeOverdue),
                  matchesAdditionalFilters(
                reminder, now: now, overdue: overdue, dueBefore: dueBeforeDate,
                dueAfter: dueAfterDate, noDueDate: noDueDate, priorities: priorities, search: search,
                completedSince: completedSinceDate, flagged: flagged
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
        case .pretty:
            // One section per list, in the order of `calendars`, keeping the sorted order within it.
            let byList = Dictionary(grouping: matchingReminders.map { $0.0 }) {
                $0.calendar.calendarIdentifier
            }
            var seen = Set<String>()
            let groups = calendars.compactMap { calendar -> PrettyGroup? in
                guard seen.insert(calendar.calendarIdentifier).inserted,
                      let reminders = byList[calendar.calendarIdentifier] else {
                    return nil
                }
                return PrettyGroup(title: calendar.title, rows: reminders.map(PrettyRow.init))
            }
            printPretty(groups, now: now, verbose: verbose)
        }
    }

    /// Entry point of the `today`, `overdue` and `upcoming` commands: the same incomplete-reminder
    /// query `show-all` runs, with the parameters `ShowAllQuery` built.
    func showAllReminders(_ query: ShowAllQuery, outputFormat: ListingFormat, verbose: Bool = false) throws {
        try self.showAllReminders(
            dueOn: query.dueOn, includeOverdue: query.includeOverdue, overdue: query.overdue,
            dueBefore: query.dueBefore, dueAfter: query.dueAfter, lists: query.lists,
            displayOptions: .incomplete, outputFormat: outputFormat, verbose: verbose, sort: query.sort,
            sortOrder: query.sortOrder)
    }

    func showListItems(
        withNameOrId nameOrId: String, dueOn dueDate: DateComponents?, includeOverdue: Bool,
        overdue: Bool = false, dueBefore: DateComponents? = nil, dueAfter: DateComponents? = nil,
        noDueDate: Bool = false, priorities: [Priority] = [], search: String? = nil,
        completedSince: DateComponents? = nil, flagged: Bool = false,
        displayOptions: DisplayOptions, outputFormat: ListingFormat, verbose: Bool = false, sort: Sort,
        sortOrder: CustomSortOrder)
        throws
    {
        let reminderCalendar = try self.calendar(withNameOrId: nameOrId)
        let now = Date()
        let dueOnDate = dueDate?.date
        let dueBeforeDate = dueBefore.flatMap { recurrenceEndDate(from: $0) }
        let dueAfterDate = dueAfter?.date
        let completedSinceDate = completedSince?.date

        let fetched = self.fetchReminders(on: [reminderCalendar], displayOptions: displayOptions)
        var matchingReminders = [(EKReminder, String)]()
        let reminders = sort == .none ? fetched : fetched.sorted(by: sort.sortFunction(order: sortOrder))
        for reminder in reminders {
            let id = reminder.calendarItemExternalIdentifier ?? "<unknown-id>"

            guard matchesDueOn(reminder, dueOn: dueOnDate, includeOverdue: includeOverdue),
                  matchesAdditionalFilters(
                reminder, now: now, overdue: overdue, dueBefore: dueBeforeDate,
                dueAfter: dueAfterDate, noDueDate: noDueDate, priorities: priorities, search: search,
                completedSince: completedSinceDate, flagged: flagged
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
        case .pretty:
            printPretty(
                [PrettyGroup(title: reminderCalendar.title, rows: matchingReminders.map { PrettyRow($0.0) })],
                now: now, verbose: verbose)
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

    func deleteList(nameOrId: String, confirm: Bool, outputFormat: OutputFormat) throws {
        // All reminder lists, including read-only ones, so those get a clear refusal from
        // `checkListDeletion` rather than `list_not_found`.
        let calendar = try resolveCalendarExactly(
            Store.calendars(for: .reminder), nameOrId: nameOrId)
        let reminders = self.fetchReminders(on: [calendar], displayOptions: .all)

        try checkListDeletion(
            title: calendar.title,
            isDefault: calendar.calendarIdentifier == self.getDefaultList()?.calendarIdentifier,
            allowsModifications: calendar.allowsContentModifications,
            reminderCount: reminders.count,
            completedCount: reminders.filter { $0.isCompleted }.count,
            confirm: confirm)

        // Build the output before removing, while the calendar is still in the store.
        let confirmation: String
        switch outputFormat {
        case .json:
            confirmation = encodeToJson(data: DeletedList(
                title: calendar.title,
                calendarIdentifier: calendar.calendarIdentifier,
                reminderCount: reminders.count))
        case .plain:
            let count = reminders.count == 1 ? "1 reminder" : "\(reminders.count) reminders"
            confirmation = "Deleted list '\(calendar.title)' (\(count))"
        }

        do {
            try Store.removeCalendar(calendar, commit: true)
        } catch let error {
            throw CLIError.saveFailed(action: "delete list '\(calendar.title)'", underlying: error)
        }
        print(confirmation)
    }

    func edit(
        items selection: ReminderSelection,
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
        newRecurrenceDays: RepeatDays? = nil,
        clearRecurrenceDays: Bool = false,
        clearRecurrence: Bool,
        outputFormat: OutputFormat) throws
    {
        let calendar = try self.calendar(withNameOrId: nameOrId)
        let reminders = try resolveReminders(
            self.fetchReminders(on: [calendar], displayOptions: .incomplete),
            idsOrPrefixes: selection.ids, onList: nameOrId)
        let newCalendar = try newListName.map { try self.calendar(withNameOrId: $0) }

        try self.discardingChangesOnError {
            for reminder in reminders {
                try applyEdit(
                    to: reminder, newText: newText, newNotes: newNotes, clearNotes: clearNotes,
                    newDueDateComponents: newDueDateComponents, clearDueDate: clearDueDate,
                    priority: priority, clearPriority: clearPriority, newCalendar: newCalendar,
                    newRecurrence: newRecurrence, newRecurrenceInterval: newRecurrenceInterval,
                    newRecurrenceEndDate: newRecurrenceEndDate, clearRecurrenceEnd: clearRecurrenceEnd,
                    newRecurrenceDays: newRecurrenceDays, clearRecurrenceDays: clearRecurrenceDays,
                    clearRecurrence: clearRecurrence)
            }
        }

        try self.saveAll(reminders, action: "update reminder")
        print(affectedOutput(reminders, selection: selection, outputFormat: outputFormat) {
            "Updated reminder '\($0.title!)'"
        })
    }

    func postpone(
        items selection: ReminderSelection,
        onListNamedOrId nameOrId: String,
        to newDueDateComponents: DateComponents?,
        toNextWeekday: Bool,
        outputFormat: OutputFormat) throws
    {
        let calendar = try self.calendar(withNameOrId: nameOrId)
        let reminders = try resolveReminders(
            self.fetchReminders(on: [calendar], displayOptions: .incomplete),
            idsOrPrefixes: selection.ids, onList: nameOrId)

        try self.discardingChangesOnError {
            for reminder in reminders {
                try applyPostpone(to: reminder, newDueDate: newDueDateComponents, toNextWeekday: toNextWeekday)
            }
        }

        try self.saveAll(reminders, action: "postpone reminder")
        print(affectedOutput(reminders, selection: selection, outputFormat: outputFormat) {
            "Postponed reminder '\($0.title!)'"
        })
    }

    func setComplete(
        _ complete: Bool, items selection: ReminderSelection, onListNamedOrId nameOrId: String,
        outputFormat: OutputFormat
    ) throws {
        let calendar = try self.calendar(withNameOrId: nameOrId)
        let reminders = try resolveReminders(
            self.fetchReminders(on: [calendar], displayOptions: complete ? .incomplete : .complete),
            idsOrPrefixes: selection.ids, onList: nameOrId)

        for reminder in reminders {
            reminder.isCompleted = complete
        }
        try self.saveAll(reminders, action: complete ? "complete reminder" : "uncomplete reminder")
        print(affectedOutput(reminders, selection: selection, outputFormat: outputFormat) {
            "\(complete ? "Completed" : "Uncompleted") '\($0.title!)'"
        })
    }

    func delete(items selection: ReminderSelection, onListNamedOrId nameOrId: String, outputFormat: OutputFormat) throws {
        let calendar = try self.calendar(withNameOrId: nameOrId)
        // External identifiers are stable regardless of completion state, so a
        // reminder already marked complete can still be found and deleted by its id.
        let reminders = try resolveReminders(
            self.fetchReminders(on: [calendar], displayOptions: .all),
            idsOrPrefixes: selection.ids, onList: nameOrId)

        // Encode before removing: the encoder reads `reminder.calendar`, which is
        // no longer meaningful once the reminder is gone from the store.
        let confirmation = affectedOutput(reminders, selection: selection, outputFormat: outputFormat) {
            "Deleted '\($0.title!)'"
        }

        try self.commitAll(action: "delete reminder", count: reminders.count) {
            for reminder in reminders {
                try Store.remove(reminder, commit: false)
            }
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
        recurrenceDays: RepeatDays? = nil,
        outputFormat: OutputFormat) throws
    {
        let calendar = try self.calendar(withNameOrId: nameOrId)
        let reminder = EKReminder(eventStore: Store)
        reminder.calendar = calendar
        try configureNewReminder(
            reminder, title: string, notes: notes, dueDateComponents: dueDateComponents,
            priority: priority, recurrence: recurrence, recurrenceInterval: recurrenceInterval,
            recurrenceEndDate: recurrenceEndDate, recurrenceDays: recurrenceDays)

        try self.save(reminder, action: "add reminder")
        switch outputFormat {
        case .json:
            print(encodeToJson(data: reminder))
        case .plain:
            print("Added reminder '\(reminder.title!)' to list '\(calendar.title)'")
        }
    }

    // MARK: - Private functions

    /// Every reminder on `calendars`. `show-lists` uses the predicate-taking overload below
    /// instead, to fetch only the incomplete ones.
    private func printPretty(_ groups: [PrettyGroup], now: Date, verbose: Bool) {
        for line in formatPretty(groups, now: now, style: .standardOutput, verbose: verbose) {
            print(line)
        }
    }

    private func fetchReminders(on calendars: [EKCalendar], displayOptions: DisplayOptions) -> [EKReminder] {
        return self.fetchReminders(
            matching: Store.predicateForReminders(in: calendars), displayOptions: displayOptions)
    }

    /// EventKit only offers a callback-based fetch; block on it once here so every command
    /// can be written as straight-line code that simply throws on failure (nothing can be
    /// thrown from inside EventKit's completion closure).
    private func fetchReminders(matching predicate: NSPredicate, displayOptions: DisplayOptions) -> [EKReminder] {
        let semaphore = DispatchSemaphore(value: 0)
        var fetched: [EKReminder] = []
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

    /// Saves every reminder of a batch in one commit.
    private func saveAll(_ reminders: [EKReminder], action: String) throws {
        try self.commitAll(action: action, count: reminders.count) {
            for reminder in reminders {
                try Store.save(reminder, commit: false)
            }
        }
    }

    /// Runs `stage` (saves or removes with `commit: false`), then commits them together. If
    /// anything fails, the staged changes are discarded so the store is left as it was.
    private func commitAll(action: String, count: Int, stage: () throws -> Void) throws {
        do {
            try stage()
            try Store.commit()
        } catch let error {
            Store.reset()
            throw CLIError.saveFailed(action: count > 1 ? action + "s" : action, underlying: error)
        }
    }

    /// For changes made in memory before a batch is saved: a failure for one reminder (say, no
    /// due date for `postpone --next-weekday`) discards the changes already made to the others.
    private func discardingChangesOnError(_ body: () throws -> Void) rethrows {
        do {
            try body()
        } catch {
            Store.reset()
            throw error
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

