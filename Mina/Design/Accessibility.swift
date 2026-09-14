import Foundation

/// What VoiceOver says for the pieces that show abbreviations: "4 oz" is read
/// as "4 ounces", "1h 20m" as "1 hour 20 minutes", and a row's separate lines
/// become one sentence. Pure string work, so it's tested.
enum Spoken {
    /// Expands the log's shorthand for reading aloud.
    static func text(_ text: String) -> String {
        var out = text
        func replace(_ pattern: String, _ template: String) {
            out = out.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        replace(#"<1m\b"#, "under a minute")
        replace(#"\b1 oz\b"#, "1 ounce")
        replace(#"(\d+(?:\.\d+)?) oz\b"#, "$1 ounces")
        replace(#"(\d+(?:\.\d+)?) ml\b"#, "$1 milliliters")
        replace(#"\b1h\b"#, "1 hour")
        replace(#"(\d+(?:\.\d+)?)h\b"#, "$1 hours")
        replace(#"\b1m\b"#, "1 minute")
        replace(#"(\d+)m\b"#, "$1 minutes")
        replace(#"(\d+)d\b"#, "$1 days")
        replace(#"(\d)–(\d)"#, "$1 to $2")
        replace(#"(\d)\+"#, "$1 or more")
        replace(#"\s*×"#, " times")
        out = out.replacingOccurrences(of: " · ", with: ", ")
        out = out.replacingOccurrences(of: "★ ", with: "Milestone, ")
        return out
    }

    /// Joins the parts of a row into one sentence, skipping blanks.
    static func sentence(_ parts: [String?]) -> String {
        parts.compactMap { $0 }.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.map(text).joined(separator: ", ")
    }

    /// "Feeds, 5 of 8, on track"
    static func goal(_ goal: Goal) -> String {
        sentence([goal.title, goal.detail])
    }

    /// "Feeds, 5, 12 ounces, 2 nursed, expect 8 to 12 a day"
    static func tile(title: String, value: String, detail: String, expect: String?) -> String {
        sentence([title, value, detail, expect])
    }

    /// "Bottle, 4 ounces, by Mom, 10:00 AM"; a finished sleep adds "to 11:20 AM".
    static func entry(_ entry: LogEntry, unit: VolumeUnit, now: Date) -> String {
        var parts: [String?] = [entry.title(unit: unit, now: now), entry.subtitle]
        if entry.hasPhoto { parts.append("has a photo") }
        parts.append(Format.time(entry.startedAt ?? now))
        if entry.kind == .sleep, let endedAt = entry.endedAt { parts.append("to \(Format.time(endedAt))") }
        return sentence(parts)
    }

    /// "September 13, 5 feeds, 3 diapers, 2 hours sleep"; "nothing logged" on an empty day.
    static func day(_ day: Date, summary: DaySummary?, isToday: Bool) -> String {
        var parts: [String?] = [day.formatted(.dateTime.month(.wide).day())]
        if isToday { parts.append("today") }
        if let summary, summary.feeds + summary.diapers > 0 || summary.sleepSeconds > 0 {
            if summary.feeds > 0 { parts.append(Format.count(summary.feeds, "feed")) }
            if summary.diapers > 0 { parts.append(Format.count(summary.diapers, "diaper")) }
            if summary.sleepSeconds > 0 { parts.append("\(Format.duration(summary.sleepSeconds)) sleep") }
        } else {
            parts.append("nothing logged")
        }
        return sentence(parts)
    }
}
