import ArgumentParser
import Foundation

private let calendar = Calendar.current
private let allComponents: Set<Calendar.Component> = [
    .era, .year, .yearForWeekOfYear, .quarter, .month,
    .weekOfYear, .weekOfMonth, .weekday, .weekdayOrdinal, .day,
    .hour, .minute, .second, .nanosecond,
    .calendar, .timeZone,
]
let timeComponents: Set<Calendar.Component> = [
    .hour, .minute, .second, .nanosecond,
]

func calendarComponents(except removedComponents: Set<Calendar.Component> = []) -> Set<Calendar.Component> {
    return allComponents.subtracting(removedComponents)
}

private func components(from string: String) -> DateComponents? {
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
        fatalError("error: failed to create NSDataDetector")
    }

    let range = NSRange(string.startIndex..<string.endIndex, in: string)

    let matches = detector.matches(in: string, options: .anchored, range: range)
    guard matches.count == 1, let match = matches.first, let date = match.date else {
        return nil
    }

    var includeTime = true
    if match.responds(to: NSSelectorFromString("timeIsSignificant")) {
        includeTime = match.value(forKey: "timeIsSignificant") as? Bool ?? true
    } else {
        print("warning: timeIsSignificant is unavailable, please report it at github.com/udondan/reminders-cli/issues")
    }

    var zonedCalendar = calendar
    zonedCalendar.timeZone = match.timeZone ?? calendar.timeZone
    let wantedComponents = includeTime ? calendarComponents() : calendarComponents(except: timeComponents)
    return zonedCalendar.dateComponents(wantedComponents, from: date)
}

/// Parses "weekend", "this weekend" and "next weekend", which `NSDataDetector` doesn't
/// recognise (FB8921206), as the first day of a weekend, without a time. "weekend" and
/// "this weekend" are today when `now` falls on a weekend, otherwise the coming weekend;
/// "next weekend" is always the first weekend that starts after `now`. The weekend days follow
/// `calendar`, so a locale with a Friday/Saturday weekend gets Friday.
func weekendComponents(from string: String, now: Date = Date(), calendar: Calendar = .current) -> DateComponents? {
    let phrase = string.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    let weekend: DateInterval?
    switch phrase {
    case "weekend", "this weekend":
        weekend = calendar.dateIntervalOfWeekend(containing: now) ?? calendar.nextWeekend(startingAfter: now)
    case "next weekend":
        weekend = calendar.nextWeekend(startingAfter: now)
    default:
        return nil
    }
    guard let start = weekend?.start else {
        return nil
    }
    // During a weekend, "this weekend" is today rather than its already passed first day.
    let day = max(start, calendar.startOfDay(for: now))
    return calendar.dateComponents(calendarComponents(except: timeComponents), from: day)
}

extension DateComponents: @retroactive ExpressibleByArgument {
      public init?(argument: String) {
          if let components = weekendComponents(from: argument) ?? components(from: argument) {
              self = components
          } else {
              return nil
          }
      }
}
