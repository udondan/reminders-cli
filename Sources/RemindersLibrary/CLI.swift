import ArgumentParser
import Foundation

private let reminders = Reminders()

/// Every subcommand exposes its `--format` so the central error handler in `CLI.execute()`
/// can render a `CLIError` the same way the command would have rendered its output.
protocol FormattedCommand: ParsableCommand {
    var format: OutputFormat { get }
}

private struct ShowLists: FormattedCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print the lists to pass to other commands, with open and overdue reminder counts")
    @Option(
        name: .shortAndLong,
        help: "format, either of 'plain' or 'json'")
    var format: OutputFormat = .plain

    @Flag(
        name: .shortAndLong,
        help: "show only the default Reminders list")
    var defaultOnly: Bool = false

    @Flag(help: "Also count completed reminders per list (slower on large lists)")
    var includeCompleted = false

    @Option(
        name: .shortAndLong,
        help: "Show the lists in a specific order, one of: \(ListSort.commaSeparatedCases)")
    var sort: ListSort = .none

    func run() throws {
        try reminders.showLists(
            outputFormat: format, defaultOnly: defaultOnly, includeCompleted: includeCompleted,
            sort: sort)
    }
}

private let nextDueDateDiscussion = """
    In JSON output, a repeating reminder's nextDueDate is its first occurrence at or after now, \
    counted from dueDate in steps of the repeat rule; missed occurrences of an overdue reminder are \
    skipped. It is the date completing the reminder moves it to. EventKit never advances dueDate \
    itself. Omitted for completed reminders and for repeat rules this CLI can't compute.
    """

private struct ShowAll: FormattedCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print all reminders",
        discussion: nextDueDateDiscussion)

    @Flag(help: "Show completed items only")
    var onlyCompleted = false

    @Flag(help: "Include completed items in output")
    var includeCompleted = false

    @Flag(help: "When using --due-date, also include items due before the due date")
    var includeOverdue = false

    @Option(
        name: .shortAndLong,
        help: "Show the reminders in a specific order, one of: \(Sort.commaSeparatedCases)")
    var sort: Sort = .none

    @Option(
        name: [.customShort("o"), .long],
        help: "How the sort order should be applied, one of: \(CustomSortOrder.commaSeparatedCases)")
    var sortOrder: CustomSortOrder = .ascending

    @Option(
        name: .shortAndLong,
        help: "Show only reminders due on this date")
    var dueDate: DateComponents?

    @Flag(help: "Only show reminders with a due date in the past")
    var overdue = false

    @Option(help: "Only show reminders due on or before this date")
    var dueBefore: DateComponents?

    @Option(help: "Only show reminders due on or after this date")
    var dueAfter: DateComponents?

    @Flag(help: "Only show reminders with no due date")
    var noDueDate = false

    @Option(help: "Only show reminders with this priority; repeat to specify multiple")
    var priority: [Priority] = []

    @Option(
        parsing: .unconditional,
        help: "Only show reminders whose title or notes contain this text (case-insensitive)")
    var search: String?

    @Flag(help: "Only show flagged reminders")
    var flagged = false

    @Option(help: "Only show reminders from this list (name, unique part of a name, or ID); repeat to specify multiple")
    var list: [String] = []

    @Option(help: "Only show completed reminders completed on or after this date")
    var completedSince: DateComponents?

    @OptionGroup
    var listing: ListingOptions

    var format: OutputFormat {
        listing.errorFormat
    }

    func validate() throws {
        if self.onlyCompleted && self.includeCompleted {
            throw ValidationError(
                "Cannot specify both --include-completed and --only-completed")
        }
        if self.noDueDate
            && (self.dueDate != nil || self.dueBefore != nil || self.dueAfter != nil
                || self.overdue || self.includeOverdue)
        {
            throw ValidationError(
                "Cannot combine --no-due-date with --due-date, --due-before, --due-after, --overdue, "
                    + "or --include-overdue")
        }
        if self.completedSince != nil && !self.onlyCompleted && !self.includeCompleted {
            throw ValidationError(
                "--completed-since requires --only-completed or --include-completed")
        }
    }

    func run() throws {
        var displayOptions = DisplayOptions.incomplete
        if self.onlyCompleted {
            displayOptions = .complete
        } else if self.includeCompleted {
            displayOptions = .all
        }

        try reminders.showAllReminders(
            dueOn: self.dueDate, includeOverdue: self.includeOverdue,
            overdue: self.overdue, dueBefore: self.dueBefore, dueAfter: self.dueAfter,
            noDueDate: self.noDueDate, priorities: self.priority, search: self.search,
            lists: self.list, completedSince: self.completedSince, flagged: self.flagged,
            displayOptions: displayOptions, outputFormat: listing.resolvedFormat, verbose: listing.verbose,
            sort: sort, sortOrder: sortOrder)
    }
}

private struct Today: FormattedCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show reminders due today or overdue "
            + "(same as 'show-all --due-date today --include-overdue --sort due-date')")

    @Flag(help: "Only show reminders due today, without overdue ones")
    var noOverdue = false

    @Option(help: "Only show reminders from this list (name, unique part of a name, or ID); repeat to specify multiple")
    var list: [String] = []

    @Option(
        name: .shortAndLong,
        help: "Show the reminders in a specific order, one of: \(Sort.commaSeparatedCases)")
    var sort: Sort = .dueDate

    @Option(
        name: [.customShort("o"), .long],
        help: "How the sort order should be applied, one of: \(CustomSortOrder.commaSeparatedCases)")
    var sortOrder: CustomSortOrder = .ascending

    @OptionGroup
    var listing: ListingOptions

    var format: OutputFormat {
        listing.errorFormat
    }

    func run() throws {
        try reminders.showAllReminders(
            .today(includeOverdue: !self.noOverdue, lists: self.list, sort: sort, sortOrder: sortOrder),
            outputFormat: listing.resolvedFormat, verbose: listing.verbose)
    }
}

private struct Overdue: FormattedCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show reminders whose due date has passed (same as 'show-all --overdue --sort due-date')")

    @Option(help: "Only show reminders from this list (name, unique part of a name, or ID); repeat to specify multiple")
    var list: [String] = []

    @Option(
        name: .shortAndLong,
        help: "Show the reminders in a specific order, one of: \(Sort.commaSeparatedCases)")
    var sort: Sort = .dueDate

    @Option(
        name: [.customShort("o"), .long],
        help: "How the sort order should be applied, one of: \(CustomSortOrder.commaSeparatedCases)")
    var sortOrder: CustomSortOrder = .ascending

    @OptionGroup
    var listing: ListingOptions

    var format: OutputFormat {
        listing.errorFormat
    }

    func run() throws {
        try reminders.showAllReminders(
            .overdue(lists: self.list, sort: sort, sortOrder: sortOrder),
            outputFormat: listing.resolvedFormat, verbose: listing.verbose)
    }
}

private struct Upcoming: FormattedCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show reminders due from now through the next 7 days "
            + "(same as 'show-all --due-after <current time> --due-before \"in 7 days\" --sort due-date')")

    @Option(help: "How many days ahead to look, including the whole last day")
    var days: Int = 7

    @Flag(help: "Also include reminders whose due date has passed")
    var includeOverdue = false

    @Option(help: "Only show reminders from this list (name, unique part of a name, or ID); repeat to specify multiple")
    var list: [String] = []

    @Option(
        name: .shortAndLong,
        help: "Show the reminders in a specific order, one of: \(Sort.commaSeparatedCases)")
    var sort: Sort = .dueDate

    @Option(
        name: [.customShort("o"), .long],
        help: "How the sort order should be applied, one of: \(CustomSortOrder.commaSeparatedCases)")
    var sortOrder: CustomSortOrder = .ascending

    @OptionGroup
    var listing: ListingOptions

    var format: OutputFormat {
        listing.errorFormat
    }

    func validate() throws {
        if self.days < 1 {
            throw ValidationError("--days must be at least 1")
        }
    }

    func run() throws {
        try reminders.showAllReminders(
            .upcoming(
                days: self.days, includeOverdue: self.includeOverdue, lists: self.list, sort: sort,
                sortOrder: sortOrder),
            outputFormat: listing.resolvedFormat, verbose: listing.verbose)
    }
}

private struct Show: FormattedCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print the items on the given list",
        discussion: nextDueDateDiscussion)

    @Argument(
        help: "The list to print items from: a name, a unique part of a name, or an ID from 'show-lists'",
        completion: .custom(listNameCompletion))
    var listNameOrId: String

    @Flag(help: "Show completed items only")
    var onlyCompleted = false

    @Flag(help: "Include completed items in output")
    var includeCompleted = false

    @Flag(help: "When using --due-date, also include items due before the due date")
    var includeOverdue = false

    @Option(
        name: .shortAndLong,
        help: "Show the reminders in a specific order, one of: \(Sort.commaSeparatedCases)")
    var sort: Sort = .none

    @Option(
        name: [.customShort("o"), .long],
        help: "How the sort order should be applied, one of: \(CustomSortOrder.commaSeparatedCases)")
    var sortOrder: CustomSortOrder = .ascending

    @Option(
        name: .shortAndLong,
        help: "Show only reminders due on this date")
    var dueDate: DateComponents?

    @Flag(help: "Only show reminders with a due date in the past")
    var overdue = false

    @Option(help: "Only show reminders due on or before this date")
    var dueBefore: DateComponents?

    @Option(help: "Only show reminders due on or after this date")
    var dueAfter: DateComponents?

    @Flag(help: "Only show reminders with no due date")
    var noDueDate = false

    @Option(help: "Only show reminders with this priority; repeat to specify multiple")
    var priority: [Priority] = []

    @Option(
        parsing: .unconditional,
        help: "Only show reminders whose title or notes contain this text (case-insensitive)")
    var search: String?

    @Flag(help: "Only show flagged reminders")
    var flagged = false

    @Option(help: "Only show completed reminders completed on or after this date")
    var completedSince: DateComponents?

    @OptionGroup
    var listing: ListingOptions

    var format: OutputFormat {
        listing.errorFormat
    }

    func validate() throws {
        if self.onlyCompleted && self.includeCompleted {
            throw ValidationError(
                "Cannot specify both --include-completed and --only-completed")
        }
        if self.noDueDate
            && (self.dueDate != nil || self.dueBefore != nil || self.dueAfter != nil
                || self.overdue || self.includeOverdue)
        {
            throw ValidationError(
                "Cannot combine --no-due-date with --due-date, --due-before, --due-after, --overdue, "
                    + "or --include-overdue")
        }
        if self.completedSince != nil && !self.onlyCompleted && !self.includeCompleted {
            throw ValidationError(
                "--completed-since requires --only-completed or --include-completed")
        }
    }

    func run() throws {
        var displayOptions = DisplayOptions.incomplete
        if self.onlyCompleted {
            displayOptions = .complete
        } else if self.includeCompleted {
            displayOptions = .all
        }

        try reminders.showListItems(
            withNameOrId: self.listNameOrId, dueOn: self.dueDate, includeOverdue: self.includeOverdue,
            overdue: self.overdue, dueBefore: self.dueBefore, dueAfter: self.dueAfter,
            noDueDate: self.noDueDate, priorities: self.priority, search: self.search,
            completedSince: self.completedSince, flagged: self.flagged,
            displayOptions: displayOptions, outputFormat: listing.resolvedFormat, verbose: listing.verbose,
            sort: sort, sortOrder: sortOrder)
    }
}

private struct Add: FormattedCommand {
    static let configuration = CommandConfiguration(
        abstract: "Add a reminder to a list")

    @Argument(
        help: "The list to add to: a name, a unique part of a name, or an ID from 'show-lists'",
        completion: .custom(listNameCompletion))
    var listNameOrId: String

    @Argument(
        parsing: .remaining,
        help: "The reminder contents")
    var reminder: [String]

    @Option(
        name: .shortAndLong,
        help: "The date the reminder is due")
    var dueDate: DateComponents?

    @Option(
        name: .shortAndLong,
        help: "The priority of the reminder")
    var priority: Priority = .none

    @Option(
        name: .shortAndLong,
        help: "format, either of 'plain' or 'json'")
    var format: OutputFormat = .plain

    @Option(
        name: .shortAndLong,
        parsing: .unconditional,
        help: "The notes to add to the reminder")
    var notes: String?

    @Option(
        name: [.customLong("repeat")],
        help: "Repeat the reminder, one of: daily, weekly, monthly, yearly")
    var repeatFrequency: Recurrence?

    @Option(
        name: .long,
        help: "Repeat every N units of --repeat's frequency instead of every 1 (default: 1)")
    var repeatInterval: Int?

    @Option(
        name: .long,
        help: "Stop repeating after this date (default: repeats forever)")
    var repeatUntil: DateComponents?

    @Option(
        name: .long,
        help: ArgumentHelp("Repeat weekly on these days, comma-separated: mon..sun or full names, "
            + "or weekdays/weekends; implies --repeat weekly"),
        transform: RepeatDays.init(parsing:))
    var repeatOn: RepeatDays?

    /// `--repeat-on` on its own means a weekly repeat.
    private var recurrence: Recurrence? {
        repeatFrequency ?? (repeatOn != nil ? .weekly : nil)
    }

    func validate() throws {
        if let repeatFrequency = repeatFrequency, !repeatFrequency.isRepresentable {
            throw ValidationError(
                "--repeat \(repeatFrequency.rawValue) is not supported: EventKit reminders have no hourly "
                    + "recurrence frequency (Reminders.app itself doesn't expose this either). Use "
                    + "daily, weekly, monthly, or yearly.")
        }
        if let repeatFrequency, repeatOn != nil, repeatFrequency != .weekly {
            throw ValidationError("--repeat-on requires --repeat weekly")
        }
        if recurrence != nil && dueDate == nil {
            throw ValidationError(
                repeatFrequency != nil ? "--repeat requires --due-date" : "--repeat-on requires --due-date")
        }
        if let repeatUntil, let dueDate,
            let endDate = recurrenceEndDate(from: repeatUntil),
            let due = dueDate.date, endDate < due
        {
            throw ValidationError("--repeat-until cannot be earlier than --due-date")
        }
        if let repeatInterval, repeatInterval < 1 {
            throw ValidationError("--repeat-interval must be at least 1")
        }
        if recurrence == nil && (repeatInterval != nil || repeatUntil != nil) {
            throw ValidationError(
                "--repeat-interval and --repeat-until require --repeat or --repeat-on")
        }
    }

    func run() throws {
        try reminders.addReminder(
            string: self.reminder.joined(separator: " "),
            notes: self.notes,
            toListNameOrId: self.listNameOrId,
            dueDateComponents: self.dueDate,
            priority: priority,
            recurrence: self.recurrence,
            recurrenceInterval: self.repeatInterval ?? 1,
            recurrenceEndDate: self.repeatUntil,
            recurrenceDays: self.repeatOn,
            outputFormat: format)
    }
}

private struct Complete: FormattedCommand {
    static let configuration = CommandConfiguration(
        abstract: "Complete a reminder")

    @Argument(
        help: "The list to complete a reminder on: a name, a unique part of a name, or an ID from 'show-lists'",
        completion: .custom(listNameCompletion))
    var listNameOrId: String

    @Argument(
        help: ArgumentHelp("The ids of the reminders to complete, or unique prefixes of at least 4 characters, "
            + "see 'show' for IDs; \(batchIdsHelp)"))
    var ids: [String] = []

    @Option(
        name: .shortAndLong,
        help: "Output format (plain or json)")
    var format: OutputFormat = .plain

    func validate() throws {
        try requireIds(ids)
    }

    func run() throws {
        try reminders.setComplete(true, items: ReminderSelection(arguments: self.ids),
                            onListNamedOrId: self.listNameOrId,
                            outputFormat: format)
    }
}

private struct Uncomplete: FormattedCommand {
    static let configuration = CommandConfiguration(
        abstract: "Uncomplete a reminder")

    @Argument(
        help: "The list to uncomplete a reminder on: a name, a unique part of a name, or an ID from 'show-lists'",
        completion: .custom(listNameCompletion))
    var listNameOrId: String

    @Argument(
        help: ArgumentHelp("The ids of the reminders to uncomplete, or unique prefixes of at least 4 characters, "
            + "see 'show' for IDs; \(batchIdsHelp)"))
    var ids: [String] = []

    @Option(
        name: .shortAndLong,
        help: "Output format (plain or json)")
    var format: OutputFormat = .plain

    func validate() throws {
        try requireIds(ids)
    }

    func run() throws {
        try reminders.setComplete(false, items: ReminderSelection(arguments: self.ids),
                            onListNamedOrId: self.listNameOrId,
                            outputFormat: format)
    }
}

private struct Delete: FormattedCommand {
    static let configuration = CommandConfiguration(
        abstract: "Delete a reminder")

    @Argument(
        help: "The list to delete a reminder on: a name, a unique part of a name, or an ID from 'show-lists'",
        completion: .custom(listNameCompletion))
    var listNameOrId: String

    @Argument(
        help: ArgumentHelp("The ids of the reminders to delete, or unique prefixes of at least 4 characters, "
            + "see 'show' for IDs; \(batchIdsHelp)"))
    var ids: [String] = []

    @Option(
        name: .shortAndLong,
        help: "Output format (plain or json)")
    var format: OutputFormat = .plain

    func validate() throws {
        try requireIds(ids)
    }

    func run() throws {
        try reminders.delete(
            items: ReminderSelection(arguments: self.ids), onListNamedOrId: self.listNameOrId, outputFormat: format)
    }
}

/// How every mutating command's ID argument can name several reminders; see `ReminderSelection`.
private let batchIdsHelp =
    "several IDs can be given comma-separated, and '-' reads newline-separated IDs from standard input"

private func requireIds(_ ids: [String]) throws {
    if ids.isEmpty {
        throw ValidationError("Missing expected argument '<ids> ...'")
    }
}

func listNameCompletion(_ arguments: [String], _ position: Int, _ prefix: String) -> [String] {
    // NOTE: A list name with ':' was separated in zsh completion, there might be more of these or
    // this might break other shells
    return reminders.getListNames().map { $0.replacingOccurrences(of: ":", with: "\\:") }
}

private struct Edit: FormattedCommand {
    static let configuration = CommandConfiguration(
        abstract: "Edit the text of a reminder")

    @Argument(
        help: "The list to edit a reminder on: a name, a unique part of a name, or an ID from 'show-lists'",
        completion: .custom(listNameCompletion))
    var listNameOrId: String

    @Argument(
        help: ArgumentHelp("The id of the reminder to edit, or a unique prefix of at least 4 characters, "
            + "see 'show' for IDs; \(batchIdsHelp)"))
    var id: String

    @Option(
        name: .shortAndLong,
        help: "The new priority of the reminder")
    var priority: Priority?

    @Flag(help: "Remove the priority from the reminder")
    var clearPriority = false

    @Option(
        name: .long,
        help: "Move the reminder to a different list: a name, a unique part of a name, or an ID from 'show-lists'",
        completion: .custom(listNameCompletion))
    var list: String?

    @Option(
        name: .shortAndLong,
        parsing: .unconditional,
        help: "The notes to set on the reminder, overwriting previous notes")
    var notes: String?

    @Flag(help: "Remove the notes from the reminder")
    var clearNotes = false

    @Option(
        name: [.customLong("repeat")],
        help: "Set (or replace) the reminder's repeat, one of: daily, weekly, monthly, yearly")
    var repeatFrequency: Recurrence?

    @Option(
        name: .long,
        help: "Repeat every N units of the recurrence frequency")
    var repeatInterval: Int?

    @Option(
        name: .long,
        help: "Stop repeating after this date; preserves the existing repeat frequency")
    var repeatUntil: DateComponents?

    @Flag(
        name: .long,
        help: "Remove any repeat rule from the reminder")
    var clearRepeat = false

    @Flag(
        name: .long,
        help: "Keep repeating forever without changing the recurrence frequency")
    var clearRepeatEnd = false

    @Option(
        name: .long,
        help: ArgumentHelp("Repeat on these days, comma-separated: mon..sun or full names, or weekdays/weekends; "
            + "replaces only the days of a weekly repeat"),
        transform: RepeatDays.init(parsing:))
    var repeatOn: RepeatDays?

    @Flag(
        name: .long,
        help: "Remove the repeat days from a weekly repeat, keeping everything else")
    var clearRepeatOn = false

    @Option(
        name: .shortAndLong,
        help: "The new date the reminder is due")
    var dueDate: DateComponents?

    @Flag(help: "Remove the due date from the reminder")
    var clearDueDate = false

    @Argument(
        parsing: .remaining,
        help: "The new reminder contents")
    var reminder: [String] = []

    @Option(
        name: .shortAndLong,
        help: "Output format (plain or json)")
    var format: OutputFormat = .plain

    // A flat list of independent option conflicts, one check per rule.
    // swiftlint:disable:next cyclomatic_complexity
    func validate() throws {
        if !self.reminder.isEmpty && ReminderSelection.isBatch(arguments: [self.id]) {
            throw ValidationError("New reminder text can only be set on one reminder at a time")
        }
        if self.dueDate != nil && self.clearDueDate {
            throw ValidationError("Cannot specify both --due-date and --clear-due-date")
        }
        if self.priority != nil && self.clearPriority {
            throw ValidationError("Cannot specify both --priority and --clear-priority")
        }
        if self.notes != nil && self.clearNotes {
            throw ValidationError("Cannot specify both --notes and --clear-notes")
        }

        let changesRecurrence = self.repeatFrequency != nil || self.repeatInterval != nil
            || self.repeatUntil != nil || self.clearRepeatEnd
            || self.repeatOn != nil || self.clearRepeatOn

        if self.reminder.isEmpty && self.notes == nil && !self.clearNotes && self.dueDate == nil
            && !self.clearDueDate && !changesRecurrence && !self.clearRepeat
            && self.priority == nil && !self.clearPriority && self.list == nil
        {
            throw ValidationError(
                "Must specify new reminder content, a notes change, a due date change, "
                    + "a repeat change, a priority change, or a new list")
        }
        if self.clearRepeat && changesRecurrence {
            throw ValidationError("Cannot combine --clear-repeat with another repeat option")
        }
        if let repeatFrequency = repeatFrequency, !repeatFrequency.isRepresentable {
            throw ValidationError(
                "--repeat \(repeatFrequency.rawValue) is not supported: EventKit reminders have no hourly "
                    + "recurrence frequency (Reminders.app itself doesn't expose this either). Use "
                    + "daily, weekly, monthly, or yearly.")
        }
        if let repeatInterval, repeatInterval < 1 {
            throw ValidationError("--repeat-interval must be at least 1")
        }
        let endOptionCount = [repeatUntil != nil, clearRepeatEnd]
            .filter { $0 }.count
        if endOptionCount > 1 {
            throw ValidationError(
                "Specify only one of --repeat-until or --clear-repeat-end")
        }
        if self.repeatOn != nil && self.clearRepeatOn {
            throw ValidationError("Cannot specify both --repeat-on and --clear-repeat-on")
        }
        if let repeatFrequency, repeatFrequency != .weekly, self.repeatOn != nil || self.clearRepeatOn {
            throw ValidationError("--repeat-on and --clear-repeat-on require a weekly repeat")
        }
    }

    func run() throws {
        let newText = self.reminder.joined(separator: " ")
        try reminders.edit(
            items: ReminderSelection(arguments: [self.id]),
            onListNamedOrId: self.listNameOrId,
            newText: newText.isEmpty ? nil : newText,
            newNotes: self.notes,
            clearNotes: self.clearNotes,
            newDueDateComponents: self.dueDate,
            clearDueDate: self.clearDueDate,
            priority: self.priority,
            clearPriority: self.clearPriority,
            newListName: self.list,
            newRecurrence: self.repeatFrequency,
            newRecurrenceInterval: self.repeatInterval,
            newRecurrenceEndDate: self.repeatUntil,
            clearRecurrenceEnd: self.clearRepeatEnd,
            newRecurrenceDays: self.repeatOn,
            clearRecurrenceDays: self.clearRepeatOn,
            clearRecurrence: self.clearRepeat,
            outputFormat: format
        )
    }
}

private struct Postpone: FormattedCommand {
    static let configuration = CommandConfiguration(
        abstract: "Move a reminder's due date without changing its repeat rule")

    @Argument(
        help: "The list the reminder is on: a name, a unique part of a name, or an ID from 'show-lists'",
        completion: .custom(listNameCompletion))
    var listNameOrId: String

    @Argument(
        help: ArgumentHelp("The id of the reminder to postpone, or a unique prefix of at least 4 characters, "
            + "see 'show' for IDs; \(batchIdsHelp)"))
    var id: String

    @Argument(
        help: "The new due date for the reminder; omit this when using --next-weekday")
    var date: DateComponents?

    @Flag(
        name: .long,
        help: ArgumentHelp("Move the due date to the next weekday (Mon-Fri), preserving its time of day; "
            + "the reminder must already have a due date"))
    var nextWeekday = false

    @Option(
        name: .shortAndLong,
        help: "Output format (plain or json)")
    var format: OutputFormat = .plain

    func validate() throws {
        if self.date != nil && self.nextWeekday {
            throw ValidationError("Cannot specify both a new due date and --next-weekday")
        }
        if self.date == nil && !self.nextWeekday {
            throw ValidationError("Must specify either a new due date or --next-weekday")
        }
    }

    func run() throws {
        try reminders.postpone(
            items: ReminderSelection(arguments: [self.id]),
            onListNamedOrId: self.listNameOrId,
            to: self.date,
            toNextWeekday: self.nextWeekday,
            outputFormat: format
        )
    }
}

private struct NewList: FormattedCommand {
    static let configuration = CommandConfiguration(
        abstract: "Create a new list")

    @Argument(
        help: "The name of the new list")
    var listName: String

    @Option(
        name: .shortAndLong,
        help: "The name of the source of the list, if all your lists use the same source it will default to that")
    var source: String?

    @Option(
        name: .shortAndLong,
        help: "Output format (plain or json)")
    var format: OutputFormat = .plain

    func run() throws {
        try reminders.newList(with: self.listName, source: self.source, outputFormat: format)
    }
}

private struct DeleteList: FormattedCommand {
    static let configuration = CommandConfiguration(
        abstract: "Delete a list and every reminder on it (requires --confirm)")

    @Argument(
        help: "The list to delete: its full name or an ID from 'show-lists' (no partial names)",
        completion: .custom(listNameCompletion))
    var listNameOrId: String

    @Flag(help: "Actually delete the list; without it, only show what would be deleted")
    var confirm = false

    @Option(
        name: .shortAndLong,
        help: "Output format (plain or json)")
    var format: OutputFormat = .plain

    func run() throws {
        try reminders.deleteList(nameOrId: self.listNameOrId, confirm: self.confirm, outputFormat: format)
    }
}

private struct Doctor: FormattedCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check Reminders access and the environment, and suggest fixes (exits 1 when a check fails)")

    @Option(
        name: .shortAndLong,
        help: "Output format (plain or json)")
    var format: OutputFormat = .plain

    func run() throws {
        // The report is already on stdout; a failed check only changes the exit status.
        if !reminders.runDoctor(outputFormat: format) {
            throw ExitCode.failure
        }
    }
}

/// What happened when a command was run in-process, so tests can assert on it without the
/// process exiting.
enum CLIRunOutcome: Equatable {
    case completed
    case failed(CLIError, format: OutputFormat)
}

extension CLI {
    /// Parses and runs one command. A `CLIError` thrown by the command is returned together
    /// with the `--format` the user asked for; every other error (help, version, validation
    /// errors, ...) is rethrown so ArgumentParser's `exit(withError:)` handles it as before.
    static func runCommand(_ arguments: [String]? = nil) throws -> CLIRunOutcome {
        var command = try parseAsRoot(arguments)
        do {
            try command.run()
        } catch let error as CLIError {
            let format = (command as? FormattedCommand)?.format ?? .plain
            return .failed(error, format: format)
        }
        return .completed
    }

    /// Drop-in replacement for `CLI.main()`: the single place where a `CLIError` is written to
    /// stderr and turned into its exit status.
    public static func execute() {
        do {
            switch try runCommand() {
            case .completed:
                return
            case .failed(let error, let format):
                error.report(format: format)
                Self.exit(withError: error.exitCode)
            }
        } catch {
            Self.exit(withError: error)
        }
    }
}

public struct CLI: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "reminders",
        abstract: "Interact with macOS Reminders from the command line",
        version: version,
        subcommands: [
            Add.self,
            Complete.self,
            Uncomplete.self,
            Delete.self,
            Edit.self,
            Postpone.self,
            Show.self,
            ShowLists.self,
            NewList.self,
            DeleteList.self,
            ShowAll.self,
            Today.self,
            Overdue.self,
            Upcoming.self,
            Doctor.self,
        ]
    )

    public init() {}
}
