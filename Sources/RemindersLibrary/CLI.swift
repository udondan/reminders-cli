import ArgumentParser
import Foundation

private let reminders = Reminders()

private struct ShowLists: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print the name of lists to pass to other commands")
    @Option(
        name: .shortAndLong,
        help: "format, either of 'plain' or 'json'")
    var format: OutputFormat = .plain

    func run() {
        reminders.showLists(outputFormat: format)
    }
}

private struct ShowAll: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print all reminders")

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

    @Option(help: "Only show reminders whose title or notes contain this text (case-insensitive)")
    var search: String?

    @Option(help: "Only show reminders from this list; repeat to specify multiple")
    var list: [String] = []

    @Option(
        name: .shortAndLong,
        help: "format, either of 'plain' or 'json'")
    var format: OutputFormat = .plain

    func validate() throws {
        if self.onlyCompleted && self.includeCompleted {
            throw ValidationError(
                "Cannot specify both --show-completed and --only-completed")
        }
        if self.noDueDate
            && (self.dueDate != nil || self.dueBefore != nil || self.dueAfter != nil
                || self.overdue || self.includeOverdue)
        {
            throw ValidationError(
                "Cannot combine --no-due-date with --due-date, --due-before, --due-after, --overdue, or --include-overdue")
        }
    }

    func run() {
        var displayOptions = DisplayOptions.incomplete
        if self.onlyCompleted {
            displayOptions = .complete
        } else if self.includeCompleted {
            displayOptions = .all
        }

        reminders.showAllReminders(
            dueOn: self.dueDate, includeOverdue: self.includeOverdue,
            overdue: self.overdue, dueBefore: self.dueBefore, dueAfter: self.dueAfter,
            noDueDate: self.noDueDate, priorities: self.priority, search: self.search,
            lists: self.list,
            displayOptions: displayOptions, outputFormat: format, sort: sort, sortOrder: sortOrder)
    }
}

private struct Show: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print the items on the given list")

    @Argument(
        help: "The list to print items from, see 'show-lists' for names or IDs",
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

    @Option(help: "Only show reminders whose title or notes contain this text (case-insensitive)")
    var search: String?

    @Option(
        name: .shortAndLong,
        help: "format, either of 'plain' or 'json'")
    var format: OutputFormat = .plain

    func validate() throws {
        if self.onlyCompleted && self.includeCompleted {
            throw ValidationError(
                "Cannot specify both --show-completed and --only-completed")
        }
        if self.noDueDate
            && (self.dueDate != nil || self.dueBefore != nil || self.dueAfter != nil
                || self.overdue || self.includeOverdue)
        {
            throw ValidationError(
                "Cannot combine --no-due-date with --due-date, --due-before, --due-after, --overdue, or --include-overdue")
        }
    }

    func run() {
        var displayOptions = DisplayOptions.incomplete
        if self.onlyCompleted {
            displayOptions = .complete
        } else if self.includeCompleted {
            displayOptions = .all
        }

        reminders.showListItems(
            withNameOrId: self.listNameOrId, dueOn: self.dueDate, includeOverdue: self.includeOverdue,
            overdue: self.overdue, dueBefore: self.dueBefore, dueAfter: self.dueAfter,
            noDueDate: self.noDueDate, priorities: self.priority, search: self.search,
            displayOptions: displayOptions, outputFormat: format, sort: sort, sortOrder: sortOrder)
    }
}

private struct Add: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Add a reminder to a list")

    @Argument(
        help: "The list to add to, see 'show-lists' for names or IDs",
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
        help: "The notes to add to the reminder")
    var notes: String?

    @Option(
        name: [.customLong("repeat")],
        help: "Repeat the reminder, one of: daily, weekly, monthly, yearly")
    var repeat_: Recurrence?

    @Option(
        name: .long,
        help: "Repeat every N units of --repeat's frequency instead of every 1 (default: 1)")
    var repeatInterval: Int?

    @Option(
        name: .long,
        help: "Stop repeating after this date (default: repeats forever)")
    var repeatUntil: DateComponents?

    func validate() throws {
        if let repeat_ = repeat_, !repeat_.isRepresentable {
            throw ValidationError(
                "--repeat \(repeat_.rawValue) is not supported: EventKit reminders have no hourly "
                    + "recurrence frequency (Reminders.app itself doesn't expose this either). Use "
                    + "daily, weekly, monthly, or yearly.")
        }
        if repeat_ != nil && dueDate == nil {
            throw ValidationError("--repeat requires --due-date")
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
        if repeat_ == nil && (repeatInterval != nil || repeatUntil != nil) {
            throw ValidationError(
                "--repeat-interval and --repeat-until require --repeat")
        }
    }

    func run() {
        reminders.addReminder(
            string: self.reminder.joined(separator: " "),
            notes: self.notes,
            toListNameOrId: self.listNameOrId,
            dueDateComponents: self.dueDate,
            priority: priority,
            recurrence: self.repeat_,
            recurrenceInterval: self.repeatInterval ?? 1,
            recurrenceEndDate: self.repeatUntil,
            outputFormat: format)
    }
}

private struct Complete: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Complete a reminder")

    @Argument(
        help: "The list to complete a reminder on, see 'show-lists' for names or IDs",
        completion: .custom(listNameCompletion))
    var listNameOrId: String

    @Argument(
        help: "The index or id of the reminder to delete, see 'show' for indexes and IDs")
    var indexOrId: String

    @Option(
        name: .shortAndLong,
        help: "Output format (plain or json)")
    var format: OutputFormat = .plain

    func run() {
        reminders.setComplete(true, itemAtIndexOrId: self.indexOrId,
                            onListNamedOrId: self.listNameOrId,
                            outputFormat: format)
    }
}

private struct Uncomplete: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Uncomplete a reminder")

    @Argument(
        help: "The list to uncomplete a reminder on, see 'show-lists' for names or IDs",
        completion: .custom(listNameCompletion))
    var listNameOrId: String

    @Argument(
        help: "The index or id of the reminder to delete, see 'show' for indexes and IDs")
    var indexOrId: String

    @Option(
        name: .shortAndLong,
        help: "Output format (plain or json)")
    var format: OutputFormat = .plain

    func run() {
        reminders.setComplete(false, itemAtIndexOrId: self.indexOrId,
                            onListNamedOrId: self.listNameOrId,
                            outputFormat: format)
    }
}

private struct Delete: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Delete a reminder")

    @Argument(
        help: "The list to delete a reminder on, see 'show-lists' for names or IDs",
        completion: .custom(listNameCompletion))
    var listNameOrId: String

    @Argument(
        help: "The index or id of the reminder to delete, see 'show' for indexes and IDs")
    var indexOrId: String

    func run() {
        reminders.delete(itemAtIndexOrId: self.indexOrId, onListNamedOrId: self.listNameOrId)
    }
}

func listNameCompletion(_ arguments: [String], _ position: Int, _ prefix: String) -> [String] {
    // NOTE: A list name with ':' was separated in zsh completion, there might be more of these or
    // this might break other shells
    return reminders.getListNames().map { $0.replacingOccurrences(of: ":", with: "\\:") }
}

private struct Edit: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Edit the text of a reminder")

    @Argument(
        help: "The list to edit a reminder on, see 'show-lists' for names or IDs",
        completion: .custom(listNameCompletion))
    var listNameOrId: String

    @Argument(
        help: "The index or id of the reminder to delete, see 'show' for indexes and IDs")
    var indexOrId: String

    @Option(
        name: .shortAndLong,
        help: "The new priority of the reminder")
    var priority: Priority?

    @Flag(help: "Remove the priority from the reminder")
    var clearPriority = false

    @Option(
        name: .long,
        help: "Move the reminder to a different list, see 'show-lists' for names",
        completion: .custom(listNameCompletion))
    var list: String?

    @Option(
        name: .shortAndLong,
        help: "The notes to set on the reminder, overwriting previous notes")
    var notes: String?

    @Option(
        name: [.customLong("repeat")],
        help: "Set (or replace) the reminder's repeat, one of: daily, weekly, monthly, yearly")
    var repeat_: Recurrence?

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

    func validate() throws {
        if self.dueDate != nil && self.clearDueDate {
            throw ValidationError("Cannot specify both --due-date and --clear-due-date")
        }
        if self.priority != nil && self.clearPriority {
            throw ValidationError("Cannot specify both --priority and --clear-priority")
        }

        let changesRecurrence = self.repeat_ != nil || self.repeatInterval != nil
            || self.repeatUntil != nil || self.clearRepeatEnd

        if self.reminder.isEmpty && self.notes == nil && self.dueDate == nil
            && !self.clearDueDate && !changesRecurrence && !self.clearRepeat
            && self.priority == nil && !self.clearPriority && self.list == nil
        {
            throw ValidationError(
                "Must specify new reminder content, new notes, a due date change, a repeat change, "
                    + "a priority change, or a new list")
        }
        if self.clearRepeat && changesRecurrence {
            throw ValidationError("Cannot combine --clear-repeat with another repeat option")
        }
        if let repeat_ = repeat_, !repeat_.isRepresentable {
            throw ValidationError(
                "--repeat \(repeat_.rawValue) is not supported: EventKit reminders have no hourly "
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
    }

    func run() {
        let newText = self.reminder.joined(separator: " ")
        reminders.edit(
            itemAtIndexOrId: self.indexOrId,
            onListNamedOrId: self.listNameOrId,
            newText: newText.isEmpty ? nil : newText,
            newNotes: self.notes,
            newDueDateComponents: self.dueDate,
            clearDueDate: self.clearDueDate,
            priority: self.priority,
            clearPriority: self.clearPriority,
            newListName: self.list,
            newRecurrence: self.repeat_,
            newRecurrenceInterval: self.repeatInterval,
            newRecurrenceEndDate: self.repeatUntil,
            clearRecurrenceEnd: self.clearRepeatEnd,
            clearRecurrence: self.clearRepeat,
            outputFormat: format
        )
    }
}


private struct NewList: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Create a new list")

    @Argument(
        help: "The name of the new list")
    var listName: String

    @Option(
        name: .shortAndLong,
        help: "The name of the source of the list, if all your lists use the same source it will default to that")
    var source: String?

    func run() {
        reminders.newList(with: self.listName, source: self.source)
    }
}

public struct CLI: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "reminders",
        abstract: "Interact with macOS Reminders from the command line",
        subcommands: [
            Add.self,
            Complete.self,
            Uncomplete.self,
            Delete.self,
            Edit.self,
            Show.self,
            ShowLists.self,
            NewList.self,
            ShowAll.self,
        ]
    )

    public init() {}
}
