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

/// Subcommands that must run without requesting access. `doctor` reports the authorization
/// state, so requesting access first would change (or hang on) the very thing it diagnoses.
/// `help` is ArgumentParser's built-in subcommand and only prints usage, like `--help`.
private let accessFreeSubcommands: Set<String> = [
    "doctor",
    "help",
]

public enum AccessRequirement {
    public static func requiresReminderAccess(arguments: [String]) -> Bool {
        guard let first = arguments.first else {
            return false
        }
        // The root command has no options of its own, so a subcommand is always the first argument.
        if accessFreeSubcommands.contains(first) {
            return false
        }
        return !arguments.contains { accessFreeFlags.contains($0) }
    }
}
