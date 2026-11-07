import EventKit
import Foundation

/// The filters and order of the reminder listings: `show`, `show-all`, and through `ShowAllQuery`
/// the `today`, `overdue` and `upcoming` shortcuts. Every filter defaults to "show everything".
struct ReminderFilter: Equatable {
    var dueOn: DateComponents?
    var includeOverdue = false
    var overdue = false
    var dueBefore: DateComponents?
    var dueAfter: DateComponents?
    var noDueDate = false
    var priorities: [Priority] = []
    var search: String?
    var completedSince: DateComponents?
    var flagged = false
    var displayOptions: DisplayOptions = .incomplete
    var sort: Sort = .none
    var sortOrder: CustomSortOrder = .ascending

    /// The fetched reminders that pass every filter, in the requested order. A date-only
    /// `dueBefore` means the whole local day, same rule as `--repeat-until`; `dueAfter` needs no
    /// expansion since a date-only value's `.date` is already midnight, the correct inclusive lower
    /// bound.
    func apply(to fetched: [EKReminder], now: Date) -> [EKReminder] {
        let dueOnDate = dueOn?.date
        let dueBeforeDate = dueBefore.flatMap { recurrenceEndDate(from: $0) }
        let dueAfterDate = dueAfter?.date
        let completedSinceDate = completedSince?.date
        let reminders = sort == .none ? fetched : fetched.sorted(by: sort.sortFunction(order: sortOrder))
        return reminders.filter { reminder in
            matchesDueOn(reminder, dueOn: dueOnDate, includeOverdue: includeOverdue)
                && matchesAdditionalFilters(
                    reminder, now: now, overdue: overdue, dueBefore: dueBeforeDate,
                    dueAfter: dueAfterDate, noDueDate: noDueDate, priorities: priorities, search: search,
                    completedSince: completedSinceDate, flagged: flagged)
        }
    }
}
