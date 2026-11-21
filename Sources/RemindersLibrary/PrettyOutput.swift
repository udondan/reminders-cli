import ArgumentParser
import EventKit
import Foundation

/// The `--format` of the reminder listings (`show`, `show-all`, `today`, `overdue`, `upcoming`),
/// the only commands with a human-oriented `pretty` format. Kept apart from `OutputFormat` so the
/// other commands neither accept `pretty` nor need a branch for it.
public enum ListingFormat: String, ExpressibleByArgument, CaseIterable {
    case plain, json, pretty

    static let environmentVariable = "REMINDERS_FORMAT"

    /// An explicit `--format` wins, then a non-empty `REMINDERS_FORMAT`, then `plain`. An
    /// unrecognised environment value is an error rather than being silently ignored.
    static func resolve(explicit: ListingFormat?, environment: [String: String]) throws -> ListingFormat {
        if let explicit {
            return explicit
        }
        guard let value = environment[environmentVariable], !value.isEmpty else {
            return .plain
        }
        guard let format = ListingFormat(rawValue: value) else {
            throw ValidationError(
                "\(environmentVariable) must be one of 'plain', 'json' or 'pretty', got '\(value)'")
        }
        return format
    }

    /// How a `CLIError` is rendered for this format: `pretty` is for people, so errors are plain.
    var errorFormat: OutputFormat {
        self == .json ? .json : .plain
    }
}

/// `--format` and `--verbose`, shared by the reminder listings.
struct ListingOptions: ParsableArguments {
    @Option(
        name: .shortAndLong,
        help: ArgumentHelp("format, one of 'plain', 'json' or 'pretty' "
            + "(default: $\(ListingFormat.environmentVariable), else 'plain')"))
    var format: ListingFormat?

    @Flag(name: .shortAndLong, help: "With --format pretty, show the start of each reminder's notes")
    var verbose = false

    /// The format to print in. `validate()` has already rejected an invalid `REMINDERS_FORMAT` by
    /// the time a command runs, so the `plain` fallback is never used for output.
    var resolvedFormat: ListingFormat {
        (try? ListingFormat.resolve(explicit: format, environment: ProcessInfo.processInfo.environment))
            ?? .plain
    }

    var errorFormat: OutputFormat {
        resolvedFormat.errorFormat
    }

    func validate() throws {
        let format = try ListingFormat.resolve(
            explicit: format, environment: ProcessInfo.processInfo.environment)
        if verbose && format != .pretty {
            throw ValidationError("--verbose requires --format pretty")
        }
    }
}

/// ANSI styling for `pretty` output. With `enabled` false every call returns the text unchanged, so
/// the layout is identical with and without colour.
struct PrettyStyle {
    enum Attribute: String {
        case bold = "1"
        case dim = "2"
        case red = "31"
        case green = "32"
        case yellow = "33"
        case blue = "34"
    }

    let enabled: Bool

    func apply(_ text: String, _ attribute: Attribute?) -> String {
        guard enabled, let attribute, !text.isEmpty else {
            return text
        }
        return "\u{1B}[\(attribute.rawValue)m\(text)\u{1B}[0m"
    }

    /// Colour only on a terminal, unless `NO_COLOR` is set to a non-empty value
    /// (https://no-color.org) or the terminal is `dumb`.
    static func colorEnabled(isTTY: Bool, environment: [String: String]) -> Bool {
        isTTY && (environment["NO_COLOR"] ?? "").isEmpty && environment["TERM"] != "dumb"
    }

    static var standardOutput: PrettyStyle {
        PrettyStyle(
            enabled: colorEnabled(
                isTTY: isatty(STDOUT_FILENO) != 0, environment: ProcessInfo.processInfo.environment))
    }
}

/// What `pretty` shows of one reminder, as plain values so the formatter is testable without
/// setting up `EKReminder`s (whose flag and identifier can't be set in a test).
struct PrettyRow {
    var title: String
    var idPrefix: String
    var isCompleted = false
    var completionDate: Date?
    var dueDate: Date?
    /// A due date without a time ("today") rather than a timed one ("in 3h").
    var dueIsDateOnly = false
    var priority: Priority?
    var recurrence: (frequency: EKRecurrenceFrequency, interval: Int)?
    var isFlagged = false
    var notes: String?
}

extension PrettyRow {
    static let idPrefixLength = 8

    init(_ reminder: EKReminder) {
        self.init(
            title: reminder.title ?? "<unknown>",
            idPrefix: String(reminder.displayId.prefix(Self.idPrefixLength)),
            isCompleted: reminder.isCompleted,
            completionDate: reminder.completionDate,
            dueDate: reminder.dueDateComponents?.date,
            dueIsDateOnly: reminder.dueDateComponents.map(isDateOnly) ?? false,
            priority: Priority(reminder.mappedPriority),
            recurrence: reminder.recurrenceRules?.first.map { ($0.frequency, $0.interval) },
            isFlagged: reminder.isFlagged,
            // EventKit stores cleared notes as "" rather than nil; both mean "no notes".
            notes: reminder.notes.flatMap { $0.isEmpty ? nil : $0 })
    }
}

/// One list's section of `pretty` output.
struct PrettyGroup {
    let title: String
    let rows: [PrettyRow]
}

/// One group per list that has matching reminders, in the order of `calendars`, keeping the order
/// of `reminders` within each group.
func prettyGroups(_ reminders: [EKReminder], in calendars: [EKCalendar]) -> [PrettyGroup] {
    let byList = Dictionary(grouping: reminders) { $0.calendar.calendarIdentifier }
    var seen = Set<String>()
    return calendars.compactMap { calendar -> PrettyGroup? in
        guard seen.insert(calendar.calendarIdentifier).inserted,
              let reminders = byList[calendar.calendarIdentifier] else {
            return nil
        }
        return PrettyGroup(title: calendar.title, rows: reminders.map(PrettyRow.init))
    }
}

private let maximumTitleWidth = 40
private let verboseNotesLength = 60

private func prettyDateFormatter(_ format: String, calendar: Calendar) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = format
    return formatter
}

private func calendarDays(from start: Date, to end: Date, calendar: Calendar) -> Int {
    calendar.dateComponents(
        [.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)
    ).day ?? 0
}

/// `Jan 5`, or `Jan 5 2027` outside the year of `now`.
private func shortDate(_ date: Date, now: Date, calendar: Calendar) -> String {
    let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
    return prettyDateFormatter(sameYear ? "MMM d" : "MMM d yyyy", calendar: calendar).string(from: date)
}

/// `25m` or `3h`, never `0m`.
private func shortDuration(_ seconds: TimeInterval) -> String {
    let minutes = max(1, Int(seconds / 60))
    return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h"
}

/// The compact due column of `pretty` output and its colour: red when overdue (the same rule as
/// `isOverdue`), yellow when due later today, dim otherwise. Completed reminders show when they
/// were completed instead. `nil` when there's nothing to show.
func prettyDueText(
    for row: PrettyRow, now: Date, calendar: Calendar
) -> (text: String, attribute: PrettyStyle.Attribute)? {
    if row.isCompleted {
        guard let completed = row.completionDate else {
            return ("done", .dim)
        }
        let daysAgo = calendarDays(from: completed, to: now, calendar: calendar)
        switch daysAgo {
        case ...0:
            return ("done today", .dim)
        case 1...6:
            return ("done " + prettyDateFormatter("EEE", calendar: calendar).string(from: completed), .dim)
        default:
            return ("done " + shortDate(completed, now: now, calendar: calendar), .dim)
        }
    }

    guard let due = row.dueDate else {
        return nil
    }
    let overdue = isOverdue(dueDate: due, now: now)
    let attribute: PrettyStyle.Attribute = overdue ? .red : .yellow
    let days = calendarDays(from: now, to: due, calendar: calendar)
    switch days {
    case ..<0:
        return ("\(-days)d overdue", .red)
    case 0:
        if row.dueIsDateOnly {
            return ("today", attribute)
        }
        let seconds = due.timeIntervalSince(now)
        return seconds < 0
            ? ("\(shortDuration(-seconds)) overdue", attribute)
            : ("in \(shortDuration(seconds))", attribute)
    case 1:
        return ("tomorrow", .dim)
    case 2...7:
        return ("in \(days)d", .dim)
    default:
        return (shortDate(due, now: now, calendar: calendar), .dim)
    }
}

/// `weekly`, or `every 2 weeks` for an interval above 1.
func prettyRecurrenceText(frequency: EKRecurrenceFrequency, interval: Int) -> String {
    let (adjective, unit): (String, String)
    switch frequency {
    case .daily: (adjective, unit) = ("daily", "day")
    case .weekly: (adjective, unit) = ("weekly", "week")
    case .monthly: (adjective, unit) = ("monthly", "month")
    case .yearly: (adjective, unit) = ("yearly", "year")
    @unknown default: (adjective, unit) = ("repeating", "time")
    }
    return interval > 1 ? "every \(interval) \(unit)s" : adjective
}

/// Terminal columns taken by `text`: 2 for emoji and East Asian wide characters, 1 otherwise. An
/// approximation that covers the glyphs this format prints and common wide scripts, not a full
/// implementation of Unicode's East Asian Width.
func displayWidth(_ text: String) -> Int {
    text.reduce(0) { width, character in
        width + (isWide(character) ? 2 : 1)
    }
}

private func isWide(_ character: Character) -> Bool {
    character.unicodeScalars.contains { scalar in
        if scalar.properties.isEmojiPresentation {
            return true
        }
        switch scalar.value {
        case 0x1100...0x115F, 0x2E80...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE4F,
             0xFF00...0xFF60, 0xFFE0...0xFFE6, 0x20000...0x3FFFD:
            return true
        default:
            return false
        }
    }
}

/// Cuts `text` to at most `width` columns, ending in `…` when anything was removed.
private func truncate(_ text: String, toWidth width: Int) -> String {
    guard displayWidth(text) > width else {
        return text
    }
    var result = ""
    var used = 0
    for character in text {
        let characterWidth = isWide(character) ? 2 : 1
        if used + characterWidth > width - 1 {
            break
        }
        result.append(character)
        used += characterWidth
    }
    return result + "…"
}

/// Notes as a single line of at most `verboseNotesLength` characters, followed by `…` when cut.
private func notesExcerpt(_ notes: String) -> String {
    let singleLine = notes.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    return singleLine.count > verboseNotesLength
        ? String(singleLine.prefix(verboseNotesLength)) + "…"
        : singleLine
}

private func header(for group: PrettyGroup, now: Date) -> String {
    let open = group.rows.filter { !$0.isCompleted }
    let overdueCount = open.filter { isOverdue(dueDate: $0.dueDate, now: now) }.count
    let completedCount = group.rows.count - open.count
    var counts = "\(open.count) open"
    if overdueCount > 0 {
        counts += ", \(overdueCount) overdue"
    }
    if completedCount > 0 {
        counts += ", \(completedCount) completed"
    }
    return "\(group.title) (\(counts))"
}

/// The `pretty` rendering of reminder listings: per list a header with counts and a rule, then one
/// row per reminder with a checkbox glyph and aligned columns for title, due date, priority,
/// repeat, flag, notes and ID prefix. Columns are as wide as their widest value across all groups
/// (titles capped at `maximumTitleWidth`); a column that's empty in every row is left out. With
/// `verbose` the notes marker is replaced by an excerpt on its own line under the title.
func formatPretty(
    _ groups: [PrettyGroup], now: Date, calendar: Calendar = .current, style: PrettyStyle,
    verbose: Bool
) -> [String] {
    guard !groups.isEmpty else {
        return [style.apply("No reminders", .dim)]
    }

    let table = groups.map { group in
        group.rows.map { prettyCells(for: $0, now: now, calendar: calendar, verbose: verbose) }
    }
    let columns = PrettyColumns(table.flatMap { $0 })

    var lines: [String] = []
    for (group, rows) in zip(groups, table) {
        if !lines.isEmpty {
            lines.append("")
        }
        lines += prettyLines(
            for: group, cells: rows, columns: columns, now: now, style: style, verbose: verbose)
    }
    return lines
}

private typealias PrettyCell = (text: String, attribute: PrettyStyle.Attribute?)

private let priorityCells: [Priority: PrettyCell] = [
    .low: ("!", .blue), .medium: ("!!", .yellow), .high: ("!!!", .red),
]

/// One row's cells: title, due, priority, repeat, flag, the notes marker (without `verbose`), ID.
private func prettyCells(for row: PrettyRow, now: Date, calendar: Calendar, verbose: Bool) -> [PrettyCell] {
    let due = prettyDueText(for: row, now: now, calendar: calendar)
    let recurrence = row.recurrence.map {
        "↻ " + prettyRecurrenceText(frequency: $0.frequency, interval: $0.interval)
    }
    var cells: [PrettyCell] = [
        (truncate(row.title, toWidth: maximumTitleWidth), row.isCompleted ? .dim : nil),
        (due?.text ?? "", due?.attribute),
        row.priority.flatMap { priorityCells[$0] } ?? ("", nil),
        (recurrence ?? "", .dim),
        (row.isFlagged ? "⚑" : "", .yellow),
    ]
    if !verbose {
        cells.append((row.notes == nil ? "" : "📝", nil))
    }
    cells.append((row.idPrefix, .dim))
    return cells
}

/// The width of every column across all rows, and the columns that are shown.
private struct PrettyColumns {
    let widths: [Int]
    let visible: [Int]

    init(_ rows: [[PrettyCell]]) {
        let count = rows.first?.count ?? 0
        let widths = (0..<count).map { column in
            rows.map { displayWidth($0[column].text) }.max() ?? 0
        }
        self.widths = widths
        // The title and ID columns are always shown, even if every value happens to be empty.
        self.visible = (0..<count).filter { $0 == 0 || $0 == count - 1 || widths[$0] > 0 }
    }

    /// The row's visible cells, styled and padded to their column width (except the last one).
    func render(_ cells: [PrettyCell], style: PrettyStyle) -> String {
        visible.enumerated().map { position, column -> String in
            let cell = cells[column]
            let isLast = position == visible.count - 1
            let padding = isLast ? 0 : widths[column] - displayWidth(cell.text)
            return style.apply(cell.text, cell.attribute) + String(repeating: " ", count: padding)
        }.joined(separator: "  ")
    }
}

/// One group's header, rule and rows, or its "No reminders" line.
private func prettyLines(
    for group: PrettyGroup, cells: [[PrettyCell]], columns: PrettyColumns, now: Date, style: PrettyStyle,
    verbose: Bool
) -> [String] {
    let title = header(for: group, now: now)
    var lines = [style.apply(title, .bold), String(repeating: "─", count: displayWidth(title))]
    guard !cells.isEmpty else {
        return lines + [" " + style.apply("No reminders", .dim)]
    }
    for (row, rowCells) in zip(group.rows, cells) {
        let glyph = row.isCompleted ? style.apply("✓", .green) : "○"
        lines.append(" \(glyph) " + columns.render(rowCells, style: style))
        if verbose, let notes = row.notes {
            lines.append("   " + style.apply(notesExcerpt(notes), .dim))
        }
    }
    return lines
}
