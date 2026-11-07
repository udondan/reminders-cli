import EventKit
import Foundation

/// The commands about lists rather than reminders: `show-lists`, `new-list`, `delete-list`, and
/// `doctor`, which reports on the lists and the access to them.
extension Reminders {
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
                matching: eventStore.predicateForIncompleteReminders(
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
                    matching: eventStore.predicateForIncompleteReminders(
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
            eventStore.calendars(for: .reminder), nameOrId: nameOrId)
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
            try eventStore.removeCalendar(calendar, commit: true)
        } catch let error {
            throw CLIError.saveFailed(action: "delete list '\(calendar.title)'", underlying: error)
        }
        print(confirmation)
    }
}
