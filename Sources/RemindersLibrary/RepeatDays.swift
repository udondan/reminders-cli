import ArgumentParser
import EventKit

/// The weekdays a weekly repeat fires on, as given to `--repeat-on`. Always de-duplicated and in
/// EventKit's Sunday-first order, so equal day sets compare equal however they were spelled.
struct RepeatDays: Equatable {
    let weekdays: [EKWeekday]

    init(_ weekdays: [EKWeekday]) {
        self.weekdays = Set(weekdays).sorted { $0.rawValue < $1.rawValue }
    }

    /// Parses a comma-separated list of day names: full names or three-letter abbreviations,
    /// case-insensitive, plus the `weekdays` and `weekends` aliases. Throws a `ValidationError`
    /// naming the accepted spellings, which ArgumentParser reports as a usage error.
    init(parsing argument: String) throws {
        var weekdays: [EKWeekday] = []
        for token in argument.split(separator: ",", omittingEmptySubsequences: false) {
            let name = token.trimmingCharacters(in: .whitespaces).lowercased()
            if let days = repeatDayAliases[name] {
                weekdays.append(contentsOf: days)
            } else if let day = weekdayNames.firstIndex(where: { name == $0.short || name == $0.full }) {
                weekdays.append(weekdayNames[day].weekday)
            } else {
                let shown = name.isEmpty ? "an empty day name" : "'\(name)'"
                throw ValidationError(
                    "Unknown day \(shown); use a comma-separated list of "
                        + weekdayNames.map { "\($0.short)/\($0.full)" }.joined(separator: ", ")
                        + ", or the aliases weekdays and weekends")
            }
        }
        self.init(weekdays)
    }

    var daysOfTheWeek: [EKRecurrenceDayOfWeek] {
        weekdays.map { EKRecurrenceDayOfWeek($0) }
    }
}

private let weekdayNames: [(weekday: EKWeekday, short: String, full: String)] = [
    (.sunday, "sun", "sunday"),
    (.monday, "mon", "monday"),
    (.tuesday, "tue", "tuesday"),
    (.wednesday, "wed", "wednesday"),
    (.thursday, "thu", "thursday"),
    (.friday, "fri", "friday"),
    (.saturday, "sat", "saturday"),
]

private let repeatDayAliases: [String: [EKWeekday]] = [
    "weekdays": [.monday, .tuesday, .wednesday, .thursday, .friday],
    "weekends": [.saturday, .sunday],
]

/// The days of a rule that repeats on plain weekdays ("every Monday and Friday"), in Sunday-first
/// order. Nil when the rule has no day selectors, or when any of them is tied to a week number
/// ("the last Friday of the month"), which a bare day list would misrepresent.
func plainWeekdays(of rule: EKRecurrenceRule) -> [EKWeekday]? {
    guard let days = rule.daysOfTheWeek, !days.isEmpty, days.allSatisfy({ $0.weekNumber == 0 })
    else {
        return nil
    }
    return RepeatDays(days.map { $0.dayOfTheWeek }).weekdays
}

/// Lowercase three-letter name (`mon`), as used in JSON output and accepted by `--repeat-on`.
func shortName(of weekday: EKWeekday) -> String {
    weekdayNames.first { $0.weekday == weekday }?.short ?? "unknown"
}
