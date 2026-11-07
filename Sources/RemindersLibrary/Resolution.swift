import EventKit
import Foundation

/// Resolves a list argument that may be a `calendarIdentifier` or (part of) a list title. The
/// steps are tried in order and the first one that produces a hit wins, so exact input always
/// behaves as it did before forgiving matching existed:
///
/// 1. exact `calendarIdentifier` (so a title that collides with another list's ID still loses)
/// 2. exact title
/// 3. case-insensitive title
/// 4. case-insensitive substring of the title; exactly one hit resolves, several are reported as
///    `list_ambiguous` rather than guessed
///
/// Empty or whitespace-only input skips step 4 (it would match every list). Nothing matching is
/// `list_not_found`, with every available list name in the suggestion. Kept as a free function,
/// separate from `Reminders.calendar(withNameOrId:)`, so it's directly unit-testable via
/// `@testable import` without live access to Reminders.app, matching `matchesAdditionalFilters`.
func resolveCalendar(_ calendars: [EKCalendar], nameOrId: String) throws -> EKCalendar {
    if let calendar = calendars.first(where: { $0.calendarIdentifier == nameOrId }) {
        return calendar
    }
    if let calendar = calendars.first(where: { $0.title == nameOrId }) {
        return calendar
    }
    if let calendar = calendars.first(where: { $0.title.lowercased() == nameOrId.lowercased() }) {
        return calendar
    }
    if !nameOrId.trimmingCharacters(in: .whitespaces).isEmpty {
        let candidates = calendars.filter { $0.title.localizedCaseInsensitiveContains(nameOrId) }
        if candidates.count == 1 {
            return candidates[0]
        }
        if candidates.count > 1 {
            throw CLIError.listAmbiguous(nameOrId, matches: candidates.map { $0.title })
        }
    }
    throw CLIError.listNotFound(nameOrId, available: calendars.map { $0.title })
}

/// The stricter list lookup behind `delete-list`, where a guessed list would destroy the wrong
/// reminders. Steps 1–3 of `resolveCalendar`, without the substring step:
///
/// 1. exact `calendarIdentifier`
/// 2. exact title
/// 3. case-insensitive title
///
/// Unlike `resolveCalendar`, a title step that matches several lists (e.g. two "Groceries" in
/// different accounts) is `list_ambiguous` instead of picking the first one. A name that is only
/// part of a title is `list_not_found`, naming those titles in the suggestion.
func resolveCalendarExactly(_ calendars: [EKCalendar], nameOrId: String) throws -> EKCalendar {
    if let calendar = calendars.first(where: { $0.calendarIdentifier == nameOrId }) {
        return calendar
    }
    let titleSteps: [(EKCalendar) -> Bool] = [
        { $0.title == nameOrId },
        { $0.title.lowercased() == nameOrId.lowercased() },
    ]
    for matches in titleSteps {
        let candidates = calendars.filter(matches)
        if candidates.count == 1 {
            return candidates[0]
        }
        if candidates.count > 1 {
            throw CLIError.listAmbiguous(nameOrId, matches: candidates.map { $0.title })
        }
    }
    let partialMatches = nameOrId.trimmingCharacters(in: .whitespaces).isEmpty
        ? []
        : calendars.filter { $0.title.localizedCaseInsensitiveContains(nameOrId) }.map { $0.title }
    throw CLIError.listNotFoundExactly(nameOrId, partialMatches: partialMatches)
}

/// The rules `delete-list` applies before removing a list, free of EventKit so they're
/// unit-testable. Refusals come first, so a run without `--confirm` on a list that can't be
/// deleted reports why instead of asking for confirmation.
func checkListDeletion(
    title: String, isDefault: Bool, allowsModifications: Bool,
    reminderCount: Int, completedCount: Int, confirm: Bool
) throws {
    if isDefault {
        throw CLIError.invalidArgument(
            "Cannot delete '\(title)': it is the default list for new reminders. "
                + "Choose another default list in Reminders.app settings first")
    }
    if !allowsModifications {
        throw CLIError.invalidArgument("Cannot delete '\(title)': the list is read-only")
    }
    if !confirm {
        throw CLIError.confirmationRequired(
            title: title, reminderCount: reminderCount, completedCount: completedCount)
    }
}

/// The `delete-list --format json` output.
struct DeletedList: Encodable {
    let deleted = true
    let title: String
    let calendarIdentifier: String
    let reminderCount: Int
}

/// The shortest ID prefix that's accepted in place of a full reminder ID. Anything shorter only
/// matches exactly, so a stray one- or two-character argument can't act on the wrong reminder.
let minimumIdPrefixLength = 4

enum IdentifierMatch: Equatable {
    /// Index into the IDs array of the single match.
    case found(Int)
    /// Indices of every ID the prefix matched.
    case ambiguous([Int])
    case notFound
}

/// Matches an ID argument against a set of identifiers: an exact match always wins, otherwise a
/// case-insensitive prefix of at least `minimumPrefixLength` characters. Works on plain strings so
/// the ambiguity handling is unit-testable; `calendarItemExternalIdentifier` can't be set on a
/// test `EKReminder`.
func matchIdentifier(
    _ ids: [String], idOrPrefix: String, minimumPrefixLength: Int = minimumIdPrefixLength
) -> IdentifierMatch {
    if let index = ids.firstIndex(of: idOrPrefix) {
        return .found(index)
    }
    guard idOrPrefix.count >= minimumPrefixLength else {
        return .notFound
    }
    let matches = ids.indices.filter {
        ids[$0].range(of: idOrPrefix, options: [.caseInsensitive, .anchored]) != nil
    }
    switch matches.count {
    case 0: return .notFound
    case 1: return .found(matches[0])
    default: return .ambiguous(matches)
    }
}

/// `matchIdentifier` with the two failure cases turned into the errors every command reports;
/// returns the index of the one match. `titles` is parallel to `ids` and only used to make the
/// ambiguity message readable. Also string-based so the error rendering is unit-testable.
func resolveIdentifier(
    _ ids: [String], titles: [String], idOrPrefix: String, onList nameOrId: String
) throws -> Int {
    switch matchIdentifier(ids, idOrPrefix: idOrPrefix) {
    case .found(let index):
        return index
    case .ambiguous(let indices):
        let matches = indices.map { "\(ids[$0]) (\(titles[$0]))" }
        throw CLIError.reminderAmbiguous(id: idOrPrefix, matches: matches)
    case .notFound:
        throw CLIError.reminderNotFound(id: idOrPrefix, listNameOrId: nameOrId)
    }
}

/// `resolveIdentifier` over the reminders' external identifiers. The caller decides the search
/// scope by what it fetches (`complete` only looks at incomplete reminders, `delete` at all of
/// them, ...).
func resolveReminder(_ reminders: [EKReminder], idOrPrefix: String, onList nameOrId: String) throws -> EKReminder {
    let index = try resolveIdentifier(
        reminders.map { $0.calendarItemExternalIdentifier ?? "" },
        titles: reminders.map { $0.title ?? "<unknown>" },
        idOrPrefix: idOrPrefix, onList: nameOrId)
    return reminders[index]
}

/// `resolveIdentifier` for every ID of a batch, in argument order. Throws for the first ID that is
/// missing or ambiguous, so a batch either resolves completely or not at all. Several arguments
/// naming the same reminder (a full ID and its prefix, say) yield it once.
func resolveIdentifiers(
    _ ids: [String], titles: [String], idsOrPrefixes: [String], onList nameOrId: String
) throws -> [Int] {
    var indices: [Int] = []
    for idOrPrefix in idsOrPrefixes {
        let index = try resolveIdentifier(ids, titles: titles, idOrPrefix: idOrPrefix, onList: nameOrId)
        if !indices.contains(index) {
            indices.append(index)
        }
    }
    return indices
}

/// `resolveIdentifiers` over the reminders' external identifiers, see `resolveReminder`.
func resolveReminders(
    _ reminders: [EKReminder], idsOrPrefixes: [String], onList nameOrId: String
) throws -> [EKReminder] {
    try resolveIdentifiers(
        reminders.map { $0.calendarItemExternalIdentifier ?? "" },
        titles: reminders.map { $0.title ?? "<unknown>" },
        idsOrPrefixes: idsOrPrefixes, onList: nameOrId
    ).map { reminders[$0] }
}

/// A list source as seen by `new-list`, reduced to what the selection logic needs so it can be
/// unit-tested without constructing `EKSource` (which EventKit doesn't allow).
struct ListSourceCandidate: Equatable {
    let title: String
    let holdsReminderLists: Bool
}

enum ListSourceSelection: Equatable {
    /// Index into the candidates array of the source to create the list in.
    case chosen(Int)
    /// No source holds reminder lists at all.
    case noSources
    /// `--source` named something that doesn't hold reminder lists.
    case notFound(String)
    /// Several differently-titled sources hold reminder lists and no `--source` was given.
    case ambiguous([String])
}

/// Picks the source for `new-list`, considering only sources that already hold reminder lists.
/// Sources are matched by title; when several reminder-capable sources share a title (rare, but
/// possible with multiple accounts of the same kind) the first one wins.
func selectListSource(requested: String?, from candidates: [ListSourceCandidate]) -> ListSourceSelection {
    let usable = candidates.enumerated().filter { $0.element.holdsReminderLists }
    guard let first = usable.first else {
        return .noSources
    }

    if let requested {
        guard let match = usable.first(where: { $0.element.title == requested }) else {
            return .notFound(requested)
        }
        return .chosen(match.offset)
    }

    var titles: [String] = []
    for (_, candidate) in usable where !titles.contains(candidate.title) {
        titles.append(candidate.title)
    }
    if titles.count > 1 {
        return .ambiguous(titles)
    }
    return .chosen(first.offset)
}
