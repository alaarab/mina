import CoreData
import Foundation

/// Splitting a run of entries into calendar days, which Today, Calendar and
/// History each need in a different shape: Today wants day sections newest
/// first, Calendar wants a lookup table to colour the month grid, and History
/// wants index ranges so its batched fetch is never fully materialised. Pure
/// functions over the fetched objects, so they're tested directly.
enum DayGrouping {
    /// Entries bucketed by the start of their day, for lookup by date.
    /// An entry with no start date falls into `missing`'s day.
    static func byDay<S: Sequence>(_ entries: S, missing: Date = .distantPast,
                                   calendar: Calendar = .current) -> [Date: [LogEntry]] where S.Element == LogEntry {
        Dictionary(grouping: entries) { calendar.startOfDay(for: $0.startedAt ?? missing) }
    }

    /// Day sections, newest day first, each keeping its entries in the order
    /// they arrived.
    static func days<S: Sequence>(_ entries: S, missing: Date = .distantPast,
                                  calendar: Calendar = .current) -> [(day: Date, entries: [LogEntry])] where S.Element == LogEntry {
        byDay(entries, missing: missing, calendar: calendar)
            .sorted { $0.key > $1.key }
            .map { (day: $0.key, entries: $0.value) }
    }

    /// Consecutive runs of the same day in a collection that is already sorted
    /// by date, as index ranges into it. Lets a list draw day headers without
    /// pulling every entry out of the fetch.
    static func dayRuns<C: RandomAccessCollection>(_ entries: C, missing: Date = .distantPast,
                                                   calendar: Calendar = .current) -> [(day: Date, range: Range<Int>)]
    where C.Element == LogEntry, C.Index == Int {
        var result: [(day: Date, range: Range<Int>)] = []
        var start = entries.startIndex
        var current: Date?
        for index in entries.indices {
            let day = calendar.startOfDay(for: entries[index].startedAt ?? missing)
            if let existing = current, existing != day {
                result.append((day: existing, range: start..<index))
                start = index
            }
            current = day
        }
        if let current { result.append((day: current, range: start..<entries.endIndex)) }
        return result
    }
}
