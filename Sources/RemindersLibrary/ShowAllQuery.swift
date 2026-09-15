import Foundation

/// The `show-all` parameters that the `today`, `overdue` and `upcoming` convenience commands set.
/// The commands only build one of these and hand it to `Reminders.showAllReminders(_:outputFormat:)`,
/// so they share every filter and sort rule with `show-all` and keep no logic of their own. The
/// builders take `now` and `calendar` so tests can pin the resulting dates.
struct ShowAllQuery: Equatable {
    var dueOn: DateComponents?
    var includeOverdue = false
    var overdue = false
    var dueBefore: DateComponents?
    var dueAfter: DateComponents?
    var lists: [String] = []
    var sort: Sort = .dueDate
    var sortOrder: CustomSortOrder = .ascending

    /// `show-all --due-date today --include-overdue --sort due-date`.
    static func today(
        includeOverdue: Bool = true, lists: [String] = [], sort: Sort = .dueDate,
        sortOrder: CustomSortOrder = .ascending, now: Date = Date(), calendar: Calendar = .current
    ) -> ShowAllQuery {
        return ShowAllQuery(
            dueOn: dateOnlyComponents(of: now, in: calendar), includeOverdue: includeOverdue,
            lists: lists, sort: sort, sortOrder: sortOrder)
    }

    /// `show-all --overdue --sort due-date`.
    static func overdue(
        lists: [String] = [], sort: Sort = .dueDate, sortOrder: CustomSortOrder = .ascending
    ) -> ShowAllQuery {
        return ShowAllQuery(overdue: true, lists: lists, sort: sort, sortOrder: sortOrder)
    }

    /// `show-all --due-after <current time> --due-before "in <days> days" --sort due-date`. The upper bound is
    /// date-only, so it covers the whole last day like any date-only `--due-before`. With
    /// `includeOverdue` the lower bound is dropped instead: the filters are ANDed, so that is what
    /// lets past-due reminders through, and the due-date sort lists them first.
    static func upcoming(
        days: Int = 7, includeOverdue: Bool = false, lists: [String] = [], sort: Sort = .dueDate,
        sortOrder: CustomSortOrder = .ascending, now: Date = Date(), calendar: Calendar = .current
    ) -> ShowAllQuery {
        let lastDay = calendar.date(byAdding: .day, value: days, to: now) ?? now
        return ShowAllQuery(
            dueBefore: dateOnlyComponents(of: lastDay, in: calendar),
            dueAfter: includeOverdue ? nil : calendar.dateComponents(calendarComponents(), from: now),
            lists: lists, sort: sort, sortOrder: sortOrder)
    }
}

/// Same shape as a parsed date-only argument such as `today`: the calendar and time zone are kept,
/// otherwise `DateComponents.date` is nil and the filter would silently match everything.
private func dateOnlyComponents(of date: Date, in calendar: Calendar) -> DateComponents {
    return calendar.dateComponents(calendarComponents(except: timeComponents), from: date)
}
