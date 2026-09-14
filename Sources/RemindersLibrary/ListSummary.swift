import EventKit
import Foundation

/// One row of `show-lists`. A struct of its own rather than extra keys on the retroactive
/// `EKCalendar: Encodable`, which `new-list --format json` also uses and must keep returning only
/// `title` and `calendarIdentifier`.
struct ListSummary: Encodable, Equatable {
    let title: String
    let calendarIdentifier: String
    let openCount: Int
    let overdueCount: Int
    /// Only counted with `--include-completed`; the synthesized encoder omits the key when nil.
    let completedCount: Int?
}

/// Buckets `reminders` by `calendar.calendarIdentifier` and returns one summary per calendar, in
/// the order of `calendars`, with zero counts for lists that hold no reminders. Completed reminders
/// are never "open" or "overdue"; they only feed `completedCount` when `includeCompleted` is set.
/// Reminders on a calendar not in `calendars` are ignored. Free of any EventKit fetch so it's
/// directly unit-testable via `@testable import`, matching `matchesAdditionalFilters`.
func summarizeLists(
    _ calendars: [EKCalendar], reminders: [EKReminder], now: Date, includeCompleted: Bool
) -> [ListSummary] {
    var open: [String: Int] = [:]
    var overdue: [String: Int] = [:]
    var completed: [String: Int] = [:]
    for reminder in reminders {
        guard let id = reminder.calendar?.calendarIdentifier else {
            continue
        }
        if reminder.isCompleted {
            completed[id, default: 0] += 1
        } else {
            open[id, default: 0] += 1
            if isOverdue(reminder, now: now) {
                overdue[id, default: 0] += 1
            }
        }
    }
    return calendars.map { calendar in
        let id = calendar.calendarIdentifier
        return ListSummary(
            title: calendar.title,
            calendarIdentifier: id,
            openCount: open[id] ?? 0,
            overdueCount: overdue[id] ?? 0,
            completedCount: includeCompleted ? (completed[id] ?? 0) : nil)
    }
}

/// Plain rendering of `show-lists`, aligned so the output scans as a table: the title is padded to
/// the widest title, the ID follows in parentheses, then the open count is right-aligned to the
/// widest count. ", N overdue" is appended only when N > 0 and ", N completed" only when counted.
func formatListSummaries(_ summaries: [ListSummary]) -> [String] {
    let titleWidth = summaries.map { $0.title.count }.max() ?? 0
    let countWidth = summaries.map { String($0.openCount).count }.max() ?? 0
    return summaries.map { summary in
        let title = summary.title + String(repeating: " ", count: titleWidth - summary.title.count)
        let open = String(summary.openCount)
        var counts = String(repeating: " ", count: countWidth - open.count) + "\(open) open"
        if summary.overdueCount > 0 {
            counts += ", \(summary.overdueCount) overdue"
        }
        if let completedCount = summary.completedCount {
            counts += ", \(completedCount) completed"
        }
        return "\(title)  (\(summary.calendarIdentifier))   \(counts)"
    }
}
