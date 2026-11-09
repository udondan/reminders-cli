import ArgumentParser
import EventKit
import Foundation

let eventStore = EKEventStore()

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
        var returnError: Error?
        eventStore.requestFullAccessToReminders { granted, error in
            grantedAccess = granted
            returnError = error
            semaphore.signal()
        }

        semaphore.wait()
        return (grantedAccess, returnError)
    }

    func getListNames() -> [String] {
        return self.getCalendars().map { $0.title }
    }

    func getDefaultList() -> EKCalendar? {
        return eventStore.defaultCalendarForNewReminders()
    }

    /// Entry point of `show-all`: the reminders of every list, or of `lists`, that pass `filter`.
    func showAllReminders(
        lists: [String] = [], filter: ReminderFilter, outputFormat: ListingFormat, verbose: Bool = false
    ) throws {
        let now = Date()
        // Resolving --list up front means an unknown list name or ID fails with `list_not_found`
        // before any reminders are fetched.
        let calendars = lists.isEmpty ? self.getCalendars() : try lists.map { try self.calendar(withNameOrId: $0) }
        let matching = filter.apply(
            to: self.fetchReminders(on: calendars, displayOptions: filter.displayOptions), now: now)

        switch outputFormat {
        case .json:
            print(encodeToJson(data: matching))
        case .plain:
            for reminder in matching {
                print(format(reminder, id: reminder.displayId, listName: reminder.calendar.title))
            }
        case .pretty:
            printPretty(prettyGroups(matching, in: calendars), now: now, verbose: verbose)
        }
    }

    /// Entry point of the `today`, `overdue` and `upcoming` commands: the same incomplete-reminder
    /// query `show-all` runs, with the parameters `ShowAllQuery` built.
    func showAllReminders(_ query: ShowAllQuery, outputFormat: ListingFormat, verbose: Bool = false) throws {
        try self.showAllReminders(
            lists: query.lists, filter: query.filter, outputFormat: outputFormat, verbose: verbose)
    }

    /// Entry point of `show`: the reminders of one list that pass `filter`.
    func showListItems(
        withNameOrId nameOrId: String, filter: ReminderFilter, outputFormat: ListingFormat, verbose: Bool = false
    ) throws {
        let reminderCalendar = try self.calendar(withNameOrId: nameOrId)
        let now = Date()
        let matching = filter.apply(
            to: self.fetchReminders(on: [reminderCalendar], displayOptions: filter.displayOptions), now: now)

        switch outputFormat {
        case .json:
            print(encodeToJson(data: matching))
        case .plain:
            for reminder in matching {
                print(format(reminder, id: reminder.displayId))
            }
        case .pretty:
            printPretty(
                [PrettyGroup(title: reminderCalendar.title, rows: matching.map(PrettyRow.init))],
                now: now, verbose: verbose)
        }
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
        to target: PostponeTarget,
        outputFormat: OutputFormat) throws
    {
        let calendar = try self.calendar(withNameOrId: nameOrId)
        let reminders = try resolveReminders(
            self.fetchReminders(on: [calendar], displayOptions: .incomplete),
            idsOrPrefixes: selection.ids, onList: nameOrId)

        try self.discardingChangesOnError {
            for reminder in reminders {
                try applyPostpone(to: reminder, target: target)
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

    func delete(
        items selection: ReminderSelection, onListNamedOrId nameOrId: String, outputFormat: OutputFormat
    ) throws {
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
                try eventStore.remove(reminder, commit: false)
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
        let reminder = EKReminder(eventStore: eventStore)
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

    /// The reminders on `calendars`. For incomplete ones only, EventKit's incomplete-reminders
    /// predicate keeps completed reminders out of the fetch, which is noticeably faster on a store
    /// that has been in use for a while.
    func fetchReminders(on calendars: [EKCalendar], displayOptions: DisplayOptions) -> [EKReminder] {
        // EventKit reads an empty calendar list as every list.
        guard !calendars.isEmpty else {
            return []
        }
        let predicate = displayOptions == .incomplete
            ? eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars)
            : eventStore.predicateForReminders(in: calendars)
        return self.fetchReminders(matching: predicate, displayOptions: displayOptions)
    }

    /// EventKit only offers a callback-based fetch; block on it once here so every command
    /// can be written as straight-line code that simply throws on failure (nothing can be
    /// thrown from inside EventKit's completion closure).
    private func fetchReminders(matching predicate: NSPredicate, displayOptions: DisplayOptions) -> [EKReminder] {
        let semaphore = DispatchSemaphore(value: 0)
        var fetched: [EKReminder] = []
        eventStore.fetchReminders(matching: predicate) { reminders in
            fetched = reminders?
                .filter { self.shouldDisplay(reminder: $0, displayOptions: displayOptions) } ?? []
            semaphore.signal()
        }
        semaphore.wait()
        return fetched
    }

    private func save(_ reminder: EKReminder, action: String) throws {
        try reportingSaveFailure(action: action) {
            try eventStore.save(reminder, commit: true)
        }
    }

    /// Saves every reminder of a batch in one commit.
    private func saveAll(_ reminders: [EKReminder], action: String) throws {
        try self.commitAll(action: action, count: reminders.count) {
            for reminder in reminders {
                try eventStore.save(reminder, commit: false)
            }
        }
    }

    /// Runs `stage` (saves or removes with `commit: false`), then commits them together. If
    /// anything fails, the staged changes are discarded so the store is left as it was.
    private func commitAll(action: String, count: Int, stage: () throws -> Void) throws {
        try self.discardingChangesOnError {
            try reportingSaveFailure(action: count > 1 ? action + "s" : action) {
                try stage()
                try eventStore.commit()
            }
        }
    }

    /// For changes made in memory before a batch is saved: a failure for one reminder (say, no
    /// due date for `postpone --next-weekday`) discards the changes already made to the others.
    private func discardingChangesOnError(_ body: () throws -> Void) rethrows {
        do {
            try body()
        } catch {
            eventStore.reset()
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

    func getCalendars() -> [EKCalendar] {
        return eventStore.calendars(for: .reminder)
                    .filter { $0.allowsContentModifications }
    }

}

func encodeToJson(data: Encodable) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    // Encoding the CLI's own Encodable values can't fail; crashing beats printing nothing.
    // swiftlint:disable:next force_try
    let encoded = try! encoder.encode(data)
    return String(data: encoded, encoding: .utf8) ?? ""
}
