import EventKit

extension EKReminder: @retroactive Encodable {
    private enum EncodingKeys: String, CodingKey {
        case externalId
        case lastModified
        case creationDate
        case title
        case notes
        case url
        case location
        case locationTitle
        case completionDate
        case completionDateLocal
        case isCompleted
        case priority
        case startDate
        case dueDate
        case dueDateLocal
        case isAllDay
        case list
        case listId
        case recurrence
        case recurrenceInterval
        case recurrenceDays
        case recurrenceEnd
        case recurrenceCount
        case hasRecurrence
        case isFlagged
        case nextDueDate
        case nextDueDateLocal
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: EncodingKeys.self)
        try container.encode(self.calendarItemExternalIdentifier, forKey: .externalId)
        try container.encode(self.title, forKey: .title)
        try container.encode(self.isCompleted, forKey: .isCompleted)
        try container.encode(self.priority, forKey: .priority)
        try container.encode(self.calendar.title, forKey: .list)
        try container.encode(self.calendar.calendarIdentifier, forKey: .listId)
        // EventKit stores cleared notes as "" rather than nil; both mean "no notes".
        if let notes = self.notes, !notes.isEmpty {
            try container.encode(notes, forKey: .notes)
        }

        // url field is nil
        // https://developer.apple.com/forums/thread/128140
        try container.encodeIfPresent(self.url, forKey: .url)
        try container.encode(format(self.completionDate), forKey: .completionDate)
        try container.encode(localISO8601(self.completionDate), forKey: .completionDateLocal)

        for alarm in self.alarms ?? [] {
            if let location = alarm.structuredLocation {
                try container.encodeIfPresent(location.title, forKey: .locationTitle)
                if let geoLocation = location.geoLocation {
                    let geo = "\(geoLocation.coordinate.latitude), \(geoLocation.coordinate.longitude)"
                    try container.encode(geo, forKey: .location)
                }
                break
            }
        }

        if let startDateComponents = self.startDateComponents {
            try container.encodeIfPresent(format(startDateComponents.date), forKey: .startDate)
        }

        if let dueDateComponents = self.dueDateComponents {
            try container.encodeIfPresent(format(dueDateComponents.date), forKey: .dueDate)
            try container.encodeIfPresent(localISO8601(dueDateComponents.date), forKey: .dueDateLocal)
            try container.encode(isDateOnly(dueDateComponents), forKey: .isAllDay)
        }
        
        if let lastModifiedDate = self.lastModifiedDate {
            try container.encode(format(lastModifiedDate), forKey: .lastModified)
        }
        
        if let creationDate = self.creationDate {
            try container.encode(format(creationDate), forKey: .creationDate)
        }

        try container.encode(self.recurrenceRules?.first != nil, forKey: .hasRecurrence)
        try container.encode(self.isFlagged, forKey: .isFlagged)

        if let rule = self.recurrenceRules?.first {
            try container.encodeIfPresent(recurrenceName(for: rule.frequency), forKey: .recurrence)
            try container.encode(rule.interval, forKey: .recurrenceInterval)
            if let weekdays = plainWeekdays(of: rule) {
                try container.encode(weekdays.map(shortName(of:)), forKey: .recurrenceDays)
            }
            try container.encodeIfPresent(format(rule.recurrenceEnd?.endDate), forKey: .recurrenceEnd)
            if let count = rule.recurrenceEnd?.occurrenceCount, count > 0 {
                try container.encode(count, forKey: .recurrenceCount)
            }
            let next = nextDueDate(from: self)
            try container.encodeIfPresent(format(next), forKey: .nextDueDate)
            try container.encodeIfPresent(localISO8601(next), forKey: .nextDueDateLocal)
        }
    }

    private func recurrenceName(for frequency: EKRecurrenceFrequency) -> String? {
        switch frequency {
        case .daily: return "daily"
        case .weekly: return "weekly"
        case .monthly: return "monthly"
        case .yearly: return "yearly"
        @unknown default: return nil
        }
    }

    private func format(_ date: Date?) -> String? {
        if #available(macOS 12.0, *) {
            return date?.ISO8601Format()
        } else {
            return date?.description(with: .current)
        }
    }
}

/// ISO 8601 with the offset of `timeZone` (the machine's by default), e.g.
/// `2026-09-15T00:00:00+02:00`, backing the `...Local` JSON fields. A zero offset is written `Z`.
func localISO8601(_ date: Date?, timeZone: TimeZone = .current) -> String? {
    guard let date else {
        return nil
    }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    formatter.timeZone = timeZone
    return formatter.string(from: date)
}

/// Whether due date components carry only a day and no time, i.e. an all-day reminder.
func isDateOnly(_ components: DateComponents) -> Bool {
    return components.hour == nil
}
