import Foundation

/// Rolls a day's entries up into totals, and formats the small pieces of text
/// that those totals turn into. Both are pure value work shared by the app,
/// the widgets and the Siri answers, so every surface counts and phrases a day
/// the same way.

// MARK: Totals

/// Totals for one calendar day. Sleep is clipped to the day, so a nap that
/// crosses midnight counts on both sides, and an ongoing sleep counts up to now.
struct DaySummary {
    var feeds = 0
    var bottles = 0
    var bottleML = 0.0
    var nursingCount = 0
    var nursingSeconds = 0.0
    var diapers = 0
    var wet = 0
    var dirty = 0
    var sleeps = 0
    var sleepSeconds = 0.0
    var notes = 0
    var pumpedML = 0.0
    var tummySeconds = 0.0
    var others = 0
    var lastFeedAt: Date?

    init() {}

    init(entries: [LogEntry], day: Date, now: Date = .now, calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        for entry in entries {
            guard let startedAt = entry.startedAt else { continue }
            let inDay = startedAt >= start && startedAt < end
            switch entry.kind {
            case .bottle:
                guard inDay else { continue }
                feeds += 1
                bottles += 1
                bottleML += entry.amountML
                lastFeedAt = max(lastFeedAt ?? .distantPast, startedAt)
            case .nursing:
                guard inDay else { continue }
                feeds += 1
                nursingCount += 1
                nursingSeconds += max(0, (entry.endedAt ?? now).timeIntervalSince(startedAt))
                lastFeedAt = max(lastFeedAt ?? .distantPast, startedAt)
            case .diaper:
                guard inDay else { continue }
                diapers += 1
                switch entry.diaper {
                case .wet, .none: wet += 1
                case .dirty: dirty += 1
                case .both: wet += 1; dirty += 1
                }
            case .sleep:
                let sleepEnd = entry.endedAt ?? now
                let overlapStart = max(startedAt, start)
                let overlapEnd = min(sleepEnd, end)
                if overlapEnd > overlapStart {
                    sleepSeconds += overlapEnd.timeIntervalSince(overlapStart)
                    sleeps += 1
                }
            case .note:
                guard inDay else { continue }
                notes += 1
            case .pumping:
                guard inDay else { continue }
                pumpedML += entry.amountML
                others += 1
            case .tummyTime:
                guard inDay else { continue }
                tummySeconds += entry.endedAt.map { max(0, $0.timeIntervalSince(startedAt)) } ?? 0
                others += 1
            case .growth, .medicine, .bath, .temperature, .milestone:
                guard inDay else { continue }
                others += 1
            }
        }
    }
}

// MARK: Formatting

enum Format {
    /// "1 feed", "3 feeds", "2 stretches". Pass `plural` when it isn't just an s.
    static func count(_ value: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(value) \(value == 1 ? singular : plural ?? singular + "s")"
    }

    /// "1h 20m", "45m", "<1m".
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded(.down))
        if minutes < 1 { return "<1m" }
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest)m" }
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    /// "just now", "12m ago", "1h 20m ago", "2d ago".
    static func ago(from date: Date, to now: Date = .now) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 86_400 { return duration(seconds) + " ago" }
        let days = Int(seconds / 86_400)
        return "\(days)d ago"
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "Today", "Yesterday", or "Wed, Sep 10".
    static func dayTitle(_ day: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}
