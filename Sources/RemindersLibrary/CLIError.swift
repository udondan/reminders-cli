import ArgumentParser
import Foundation

/// A failure the CLI can report to the user. Every failure path in `Reminders` throws one of
/// these instead of printing and exiting, so a single handler (`CLI.execute()`) can format it
/// according to `--format` and write it to stderr, keeping stdout clean for the actual output.
///
/// The `code` is the stable, machine-readable contract; `message` and `suggestion` are free-form
/// prose that may change between releases. Each code also maps 1:1 to a distinct exit status.
public struct CLIError: Error, Equatable, Encodable {
    public enum Code: String, Codable, CaseIterable {
        case listNotFound = "list_not_found"
        case listAmbiguous = "list_ambiguous"
        case reminderNotFound = "reminder_not_found"
        case reminderAmbiguous = "reminder_ambiguous"
        case noDueDate = "no_due_date"
        case noSources = "no_sources"
        case sourceNotFound = "source_not_found"
        case sourceAmbiguous = "source_ambiguous"
        case saveFailed = "save_failed"
        case accessDenied = "access_denied"
        case invalidArgument = "invalid_argument"
    }

    public let code: Code
    public let message: String
    public let suggestion: String?

    init(code: Code, message: String, suggestion: String? = nil) {
        self.code = code
        self.message = message
        self.suggestion = suggestion
    }

    // MARK: - Constructors

    /// `available` is the titles of every list that was searched; when known they're named in the
    /// suggestion so the user doesn't need a second command to find the right one.
    static func listNotFound(_ nameOrId: String, available: [String] = []) -> CLIError {
        let suggestion = available.isEmpty
            ? "Run 'reminders show-lists' to see available lists and their IDs"
            : "Available lists: \(available.joined(separator: ", ")) (run 'reminders show-lists' for IDs)"
        return CLIError(
            code: .listNotFound,
            message: "No reminders list matching '\(nameOrId)'",
            suggestion: suggestion)
    }

    static func noDefaultList() -> CLIError {
        CLIError(
            code: .listNotFound,
            message: "No default reminders list is configured",
            suggestion: "Choose a default list in Reminders.app settings")
    }

    /// A list name fragment was a substring of several list titles; see `resolveCalendar`.
    static func listAmbiguous(_ nameOrId: String, matches: [String]) -> CLIError {
        CLIError(
            code: .listAmbiguous,
            message: "Multiple reminders lists match '\(nameOrId)': \(matches.joined(separator: ", "))",
            suggestion: "Be more specific, or pass the list's ID from 'reminders show-lists'")
    }

    static func reminderNotFound(id: String, listNameOrId: String) -> CLIError {
        CLIError(
            code: .reminderNotFound,
            message: "No reminder with ID '\(id)' on list '\(listNameOrId)'",
            suggestion: "Run 'reminders show \(listNameOrId)' to see reminder IDs")
    }

    /// An ID prefix matched several reminders; `matches` are rendered as `<id> (<title>)` by
    /// `resolveReminder`.
    static func reminderAmbiguous(id: String, matches: [String]) -> CLIError {
        CLIError(
            code: .reminderAmbiguous,
            message: "Multiple reminders match ID '\(id)': \(matches.joined(separator: ", "))",
            suggestion: "Pass a longer prefix or the full reminder ID, see 'reminders show <list>'")
    }

    static func noDueDate() -> CLIError {
        CLIError(
            code: .noDueDate,
            message: "--next-weekday requires the reminder to already have a due date",
            suggestion: "Pass an explicit date instead")
    }

    static func noSources() -> CLIError {
        CLIError(
            code: .noSources,
            message: "No existing list sources were found",
            suggestion: "Create a list in Reminders.app first")
    }

    static func sourceNotFound(_ requested: String) -> CLIError {
        CLIError(
            code: .sourceNotFound,
            message: "No source named '\(requested)' holds reminder lists",
            suggestion: "Omit --source, or pass the name of an account that already has reminder lists")
    }

    static func sourceAmbiguous(_ titles: [String]) -> CLIError {
        CLIError(
            code: .sourceAmbiguous,
            message: "Multiple sources hold reminder lists: \(titles.joined(separator: ", "))",
            suggestion: "Specify one with --source")
    }

    static func saveFailed(action: String, underlying: Error) -> CLIError {
        CLIError(
            code: .saveFailed,
            message: "Failed to \(action): \(underlying.localizedDescription)")
    }

    public static func accessDenied(underlying: Error?) -> CLIError {
        let detail = underlying.map { ": \($0.localizedDescription)" } ?? ""
        return CLIError(
            code: .accessDenied,
            message: "Reminders access was not granted\(detail)",
            suggestion: "Grant access in System Settings > Privacy & Security > Reminders")
    }

    static func invalidArgument(_ message: String) -> CLIError {
        CLIError(code: .invalidArgument, message: message)
    }

    // MARK: - Exit status

    /// Each code has its own exit status so shell scripts can branch on `$?` without parsing
    /// output. `1` is deliberately unused: it's what anything that isn't a `CLIError` exits with.
    /// `64` (`EX_USAGE`) is ArgumentParser's own status for usage/validation errors.
    public var exitCode: ExitCode {
        switch code {
        case .listNotFound: return ExitCode(2)
        case .listAmbiguous: return ExitCode(3)
        case .reminderNotFound: return ExitCode(4)
        case .reminderAmbiguous: return ExitCode(5)
        case .noDueDate: return ExitCode(6)
        case .noSources: return ExitCode(7)
        case .sourceNotFound: return ExitCode(8)
        case .sourceAmbiguous: return ExitCode(9)
        case .saveFailed: return ExitCode(10)
        case .accessDenied: return ExitCode(11)
        case .invalidArgument: return ExitCode(12)
        }
    }

    // MARK: - Rendering

    /// The text written to stderr for this error, without a trailing newline. Plain mode is two
    /// human-readable lines at most; JSON mode is a single-line object so it can be parsed with
    /// one `read`.
    public func rendered(format: OutputFormat) -> String {
        switch format {
        case .plain:
            var lines = ["Error: \(message)"]
            if let suggestion {
                lines.append("Suggestion: \(suggestion)")
            }
            return lines.joined(separator: "\n")
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            guard let data = try? encoder.encode(ErrorEnvelope(error: self)),
                let json = String(data: data, encoding: .utf8)
            else {
                // Encoding three strings can't realistically fail; keep the contract anyway.
                return "{\"error\":{\"code\":\"\(code.rawValue)\",\"message\":\"\(message)\"}}"
            }
            return json
        }
    }

    public func report(format: OutputFormat) {
        FileHandle.standardError.write(Data((rendered(format: format) + "\n").utf8))
    }
}

extension CLIError: LocalizedError {
    /// Fallback so that, should a `CLIError` ever reach ArgumentParser's own handler
    /// unformatted, it still prints as `Error: <message>` rather than a struct dump.
    public var errorDescription: String? { message }
}

/// Wraps the error under an `error` key so the JSON output is unambiguous even when mixed
/// with other JSON on the same stream. Synthesized `Encodable` omits `suggestion` when nil.
private struct ErrorEnvelope: Encodable {
    let error: CLIError
}
