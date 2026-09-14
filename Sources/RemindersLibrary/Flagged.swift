import EventKit

/// Path from an `EKReminder` to its flagged state. EventKit has no public flag property; the flag
/// only exists on the ReminderKit object EventKit wraps: `backingObject` (`EKFrozenReminderReminder`)
/// → `_reminder` (`REMReminder`) → `flaggedContext` (`REMReminderFlaggedContext`) → `flagged`.
/// Every step is undocumented and may disappear in any macOS release, so it is only ever walked by
/// `readFlag(from:keyPath:)`. Writing is not possible this way, see
/// https://github.com/udondan/reminders-cli/issues/51 and
/// https://github.com/udondan/reminders-cli/issues/63.
let flaggedKeyPath = ["backingObject", "_reminder", "flaggedContext", "flagged"]

/// Walks `keyPath` via KVC and returns the final value as a `Bool`, or `false` if any step is
/// missing, `nil`, or not of the expected type. Each key is checked with `responds(to:)` before
/// `value(forKey:)` is called, because an unknown key raises `NSUndefinedKeyException`, which Swift
/// cannot catch.
func readFlag(from root: NSObject, keyPath: [String]) -> Bool {
    var current: Any = root
    for key in keyPath {
        guard let object = current as? NSObject,
              object.responds(to: NSSelectorFromString(key)),
              let next = object.value(forKey: key) else {
            return false
        }
        current = next
    }
    return (current as? NSNumber)?.boolValue ?? false
}

extension EKReminder {
    /// Whether the reminder is flagged in Reminders.app. Read-only, and `false` whenever the running
    /// macOS version doesn't expose the flag through `flaggedKeyPath`.
    var isFlagged: Bool {
        readFlag(from: self, keyPath: flaggedKeyPath)
    }
}
