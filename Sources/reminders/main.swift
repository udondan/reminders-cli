import Darwin
import RemindersLibrary

let arguments = Array(CommandLine.arguments.dropFirst())

if AccessRequirement.requiresReminderAccess(arguments: arguments) {
    switch Reminders.requestAccess() {
    case (true, _):
        CLI.execute()
    case (false, let underlying):
        // This runs before ArgumentParser has parsed anything, so `--format` is detected
        // from the raw arguments to keep the error machine-readable under `--format json`.
        let error = CLIError.accessDenied(underlying: underlying)
        error.report(format: OutputFormat.detect(in: arguments))
        exit(error.exitCode.rawValue)
    }
} else {
    CLI.execute()
}
