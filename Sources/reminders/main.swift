import Darwin
import RemindersLibrary

let arguments = Array(CommandLine.arguments.dropFirst())

if AccessRequirement.requiresReminderAccess(arguments: arguments) {
    switch Reminders.requestAccess() {
    case (true, _):
        CLI.main()
    case (false, let error):
        print("error: you need to grant reminders access")
        if let error {
            print("error: \(error.localizedDescription)")
        }
        exit(1)
    }
} else {
    CLI.main()
}
