import ArgumentParser
import EventKit
import Foundation

public enum Sort: String, Decodable, ExpressibleByArgument, CaseIterable {
    case none
    case creationDate = "creation-date"
    case dueDate = "due-date"
    case priority

    public static let commaSeparatedCases = Self.allCases.map { $0.rawValue }.joined(separator: ", ")

    func sortFunction(order: SortOrder) -> (EKReminder, EKReminder) -> Bool {
        let comparison: (Date, Date) -> Bool = order == .forward ? (<) : (>)
        switch self {
        case .none: return { _, _ in fatalError() }
        case .creationDate: return { comparison($0.creationDate!, $1.creationDate!) }
        case .dueDate: return { dueDateComparison($0, $1, using: comparison) }
        case .priority: return {
            let rankA = priorityRank($0)
            let rankB = priorityRank($1)
            if rankA != rankB {
                return order == .forward ? rankA < rankB : rankA > rankB
            }
            // Ties are always broken by due date ascending, regardless of --sort-order.
            return dueDateComparison($0, $1, using: (<))
        }
        }
    }
}

/// Ranks a reminder's priority for sorting: lower rank sorts first in ascending order.
/// `Priority`'s declaration order doesn't match this ranking, so it's mapped explicitly here.
private func priorityRank(_ reminder: EKReminder) -> Int {
    switch Priority(reminder.mappedPriority) ?? .none {
    case .high: return 0
    case .medium: return 1
    case .low: return 2
    case .none: return 3
    }
}

/// Compares due dates for sorting, with reminders that have no due date always sorted last,
/// independent of `comparison`'s direction.
private func dueDateComparison(
    _ a: EKReminder, _ b: EKReminder, using comparison: (Date, Date) -> Bool
) -> Bool {
    switch (a.dueDateComponents, b.dueDateComponents) {
    case (.none, .none): return false
    case (.none, .some): return false
    case (.some, .none): return true
    case (.some, .some): return comparison(a.dueDateComponents!.date!, b.dueDateComponents!.date!)
    }
}

/// `--sort-order` reads Foundation's `SortOrder` as `ascending` (`.forward`) or `descending`
/// (`.reverse`). Qualifying both the type and the protocol with their modules declares the
/// conformance retroactive without `@retroactive` (which older compilers reject) and without the
/// newer compilers' warning about it, which would fail `-warnings-as-errors`.
extension Foundation.SortOrder: ArgumentParser.ExpressibleByArgument {
    public init?(argument: String) {
        switch argument {
        case "ascending": self = .forward
        case "descending": self = .reverse
        default: return nil
        }
    }

    public static var allValueStrings: [String] { ["ascending", "descending"] }

    public static var defaultCompletionKind: CompletionKind { .list(allValueStrings) }

    public var defaultValueDescription: String { self == .forward ? "ascending" : "descending" }

    public static var commaSeparatedCases: String { allValueStrings.joined(separator: ", ") }
}

/// Ordering for `show-lists`. `none` keeps EventKit's order, `name` sorts case-insensitively
/// ascending, and the count orders sort descending so the busiest list comes first, with the name
/// as the tie-breaker. There is deliberately no `--sort-order` for lists: "fewest open first" is
/// not a useful view.
enum ListSort: String, ExpressibleByArgument, CaseIterable {
    case none
    case name
    case open
    case overdue

    static let commaSeparatedCases = Self.allCases.map { $0.rawValue }.joined(separator: ", ")

    func apply(to summaries: [ListSummary]) -> [ListSummary] {
        switch self {
        case .none: return summaries
        case .name: return summaries.sorted(by: nameAscending)
        case .open: return summaries.sorted { descending($0.openCount, $1.openCount, thenBy: $0, $1) }
        case .overdue: return summaries.sorted { descending($0.overdueCount, $1.overdueCount, thenBy: $0, $1) }
        }
    }
}

private func nameAscending(_ a: ListSummary, _ b: ListSummary) -> Bool {
    return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
}

private func descending(_ countA: Int, _ countB: Int, thenBy a: ListSummary, _ b: ListSummary) -> Bool {
    if countA != countB {
        return countA > countB
    }
    return nameAscending(a, b)
}
