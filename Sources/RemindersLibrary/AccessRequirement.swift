/// Command-line flags that don't touch EventKit and therefore shouldn't block on
/// `Reminders.requestAccess()`. Requesting access unconditionally hangs forever on a
/// headless session (e.g. CI) where no one can answer the permission prompt, since
/// EventKit's completion handler then never fires.
private let accessFreeFlags: Set<String> = [
    "--generate-completion-script",
    "--version",
    "--help",
    "-h",
]

public enum AccessRequirement {
    public static func requiresReminderAccess(arguments: [String]) -> Bool {
        if arguments.isEmpty {
            return false
        }
        return !arguments.contains { accessFreeFlags.contains($0) }
    }
}
