import Foundation

/// The reminder ID arguments of a mutating command (`complete`, `uncomplete`, `delete`, `edit`,
/// `postpone`), expanded into the IDs or prefixes to resolve. Every argument may be a single ID,
/// a comma-separated list, or `-` to read newline-separated IDs from standard input.
struct ReminderSelection: Equatable {
    static let standardInputMarker = "-"

    /// IDs or prefixes in argument order, with stdin expanded where `-` was given.
    let ids: [String]
    /// Whether the user asked for several reminders. Decided by the arguments alone, not by how
    /// many IDs they expanded to, so `--format json` prints an array for every batch (even a
    /// one-line stdin) and the single object for a plain single ID.
    let isBatch: Bool

    static func isBatch(arguments: [String]) -> Bool {
        arguments.count > 1
            || arguments.contains { $0 == standardInputMarker || $0.contains(",") }
    }

    init(
        arguments: [String],
        readStandardInput: () -> String = {
            // Lossy on purpose: invalid bytes still reach the ID lookup and are reported there.
            // swiftlint:disable:next optional_data_string_conversion
            String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        }
    ) throws {
        if arguments.filter({ $0 == Self.standardInputMarker }).count > 1 {
            throw CLIError.invalidArgument("'-' (read IDs from standard input) can only be given once")
        }

        var ids: [String] = []
        for argument in arguments {
            if argument == Self.standardInputMarker {
                let stdinIds = Self.clean(readStandardInput().components(separatedBy: .newlines))
                if stdinIds.isEmpty {
                    throw CLIError.invalidArgument("No reminder IDs on standard input")
                }
                ids += stdinIds
            } else {
                ids += Self.clean(argument.components(separatedBy: ","))
            }
        }
        if ids.isEmpty {
            throw CLIError.invalidArgument("No reminder IDs given")
        }

        self.ids = ids
        self.isBatch = Self.isBatch(arguments: arguments)
    }

    private static func clean(_ parts: [String]) -> [String] {
        parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}
