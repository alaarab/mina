import AppIntents
import CoreData
import CoreSpotlight
import Foundation

/// The log as data rather than speech: entries and day totals shaped so
/// Shortcuts, Spotlight and Apple Intelligence can read them, query them and
/// pass them into other shortcuts.

// MARK: Entries

/// A log entry as Siri, Shortcuts and Apple Intelligence see it.
struct LogEntryEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Log entry")
    static var defaultQuery = LogEntryQuery()

    let id: UUID
    @Property(title: "Kind") var kind: String
    @Property(title: "Time") var time: Date
    @Property(title: "Ended") var ended: Date?
    @Property(title: "Summary") var summary: String
    @Property(title: "Amount (ml)") var milliliters: Double
    @Property(title: "Logged by") var loggedBy: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(summary)", subtitle: "\(time.formatted(date: .abbreviated, time: .shortened))")
    }

    init(entry: LogEntry, unit: VolumeUnit) {
        id = entry.id ?? UUID()
        kind = entry.kind.title
        time = entry.startedAt ?? .now
        ended = entry.endedAt
        summary = entry.title(unit: unit)
        milliliters = entry.amountML
        loggedBy = entry.loggedBy
    }
}

struct LogEntryQuery: EntityQuery, EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [LogEntryEntity] {
        try await fetch { request in request.predicate = NSPredicate(format: "id IN %@", identifiers) }
    }

    func entities(matching string: String) async throws -> [LogEntryEntity] {
        let all = try await fetch { $0.fetchLimit = 300 }
        let needle = string.lowercased()
        return all.filter { $0.summary.lowercased().contains(needle) || $0.kind.lowercased().contains(needle) }
    }

    func suggestedEntities() async throws -> [LogEntryEntity] {
        try await fetch { $0.fetchLimit = 10 }
    }

    private func fetch(_ configure: @escaping (NSFetchRequest<LogEntry>) -> Void) async throws -> [LogEntryEntity] {
        let unit = Prefs.unit
        return try await Logbook.shared.perform { context, baby in
            let request = LogEntry.request()
            request.predicate = NSPredicate(format: "baby == %@", baby)
            configure(request)
            if let extra = request.predicate, !(extra.predicateFormat.contains("baby")) {
                request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [NSPredicate(format: "baby == %@", baby), extra])
            }
            return try context.fetch(request).map { LogEntryEntity(entry: $0, unit: unit) }
        }
    }
}

// MARK: Days

/// "today" / "yesterday" in a Siri phrase.
enum RelativeDay: String, AppEnum {
    case today, yesterday

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Day")
    static var caseDisplayRepresentations: [RelativeDay: DisplayRepresentation] = [
        .today: "today", .yesterday: "yesterday",
    ]

    func date(now: Date = .now) -> Date {
        self == .today ? now : Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
    }
}

/// One day's totals, as a value Shortcuts and Apple Intelligence can read.
struct DaySummaryEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Day summary")
    static var defaultQuery = DaySummaryQuery()

    let id: String
    @Property(title: "Day") var day: Date
    @Property(title: "Feeds") var feeds: Int
    @Property(title: "Bottle total (ml)") var bottleML: Double
    @Property(title: "Bottle total") var bottleText: String
    @Property(title: "Nursing minutes") var nursingMinutes: Int
    @Property(title: "Wet diapers") var wet: Int
    @Property(title: "Dirty diapers") var dirty: Int
    @Property(title: "Sleep hours") var sleepHours: Double
    @Property(title: "Sleep") var sleepText: String
    @Property(title: "Spoken summary") var spoken: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(day.formatted(date: .abbreviated, time: .omitted))", subtitle: "\(spoken)")
    }

    init(day: Date, summary: DaySummary, unit: VolumeUnit, babyName: String, calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: day)
        id = ISO8601DateFormatter().string(from: start)
        self.day = start
        feeds = summary.feeds
        bottleML = summary.bottleML
        bottleText = unit.format(ml: summary.bottleML)
        nursingMinutes = Int(summary.nursingSeconds / 60)
        wet = summary.wet
        dirty = summary.dirty
        sleepHours = (summary.sleepSeconds / 360).rounded() / 10
        sleepText = Format.duration(summary.sleepSeconds)
        var parts = [Format.count(summary.feeds, "feed")]
        if summary.bottleML > 0 { parts.append("\(unit.format(ml: summary.bottleML)) by bottle") }
        if summary.nursingSeconds > 0 { parts.append("\(Int(summary.nursingSeconds / 60)) minutes nursing") }
        parts.append("\(summary.wet) wet and \(summary.dirty) dirty diapers")
        parts.append("\(Format.duration(summary.sleepSeconds)) of sleep")
        spoken = "\(babyName) had " + parts.joined(separator: ", ") + "."
    }

    static func load(day: Date, now: Date = .now) async throws -> DaySummaryEntity {
        let unit = Prefs.unit
        return try await Logbook.shared.perform { context, baby in
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: day)
            let from = calendar.date(byAdding: .day, value: -1, to: start) ?? start
            let to = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            let entries = Logbook.shared.entries(for: baby, from: from, to: to, in: context)
            return DaySummaryEntity(day: start, summary: DaySummary(entries: entries, day: start, now: now), unit: unit, babyName: baby.displayName)
        }
    }
}

struct DaySummaryQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [DaySummaryEntity] {
        var result: [DaySummaryEntity] = []
        for identifier in identifiers {
            if let day = ISO8601DateFormatter().date(from: identifier) {
                result.append(try await DaySummaryEntity.load(day: day))
            }
        }
        return result
    }

    func suggestedEntities() async throws -> [DaySummaryEntity] {
        [try await DaySummaryEntity.load(day: .now)]
    }
}

/// A building block for Shortcuts and Apple Intelligence: give it a day, get
/// the totals back as data. Not an App Shortcut itself; FeedStatusIntent
/// covers the spoken questions.
struct DaySummaryIntent: AppIntent {
    static var title: LocalizedStringResource = "Get a day's summary"
    static var description = IntentDescription("Feeds, diapers and sleep for one day, as values other shortcuts can use.")
    static var openAppWhenRun = false

    @Parameter(title: "Day", kind: .date)
    var day: Date

    static var parameterSummary: some ParameterSummary { Summary("Summary for \(\.$day)") }

    func perform() async throws -> some IntentResult & ReturnsValue<DaySummaryEntity> & ProvidesDialog {
        let entity = try await DaySummaryEntity.load(day: day)
        return .result(value: entity, dialog: "\(entity.spoken)")
    }
}

struct RecentEntriesIntent: AppIntent {
    static var title: LocalizedStringResource = "Get recent entries"
    static var description = IntentDescription("The most recent log entries, newest first.")
    static var openAppWhenRun = false

    @Parameter(title: "How many", default: 10)
    var count: Int

    func perform() async throws -> some IntentResult & ReturnsValue<[LogEntryEntity]> {
        let unit = Prefs.unit
        let count = max(1, min(count, 200))
        let entries = try await Logbook.shared.perform { context, baby in
            let request = LogEntry.request()
            request.predicate = NSPredicate(format: "baby == %@", baby)
            request.fetchLimit = count
            return try context.fetch(request).map { LogEntryEntity(entry: $0, unit: unit) }
        }
        return .result(value: entries)
    }
}

// MARK: Spotlight

/// Spotlight and Siri semantic search over recent entries (iOS 18+).
enum EntryIndex {
    static func refresh() {
        guard #available(iOS 18.0, *) else { return }
        Task.detached(priority: .utility) {
            let unit = Prefs.unit
            guard let entities = try? await Logbook.shared.perform({ context, baby in
                let request = LogEntry.request()
                request.predicate = NSPredicate(format: "baby == %@", baby)
                request.fetchLimit = 300
                return try context.fetch(request).map { LogEntryEntity(entry: $0, unit: unit) }
            }) else { return }
            try? await CSSearchableIndex.default().deleteAllSearchableItems()
            try? await CSSearchableIndex.default().indexAppEntities(entities)
        }
    }
}

@available(iOS 18.0, *)
extension LogEntryEntity: IndexedEntity {
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = summary
        attributes.contentDescription = "\(kind) at \(time.formatted(date: .abbreviated, time: .shortened))"
        attributes.keywords = [kind, "baby", "log"]
        return attributes
    }
}
