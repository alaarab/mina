import CoreData
import Foundation
import WidgetKit

/// What a new or edited entry looks like before it touches Core Data.
struct EntryDraft {
    var kind: EntryKind
    var startedAt: Date = .now
    var endedAt: Date? = nil
    var amountML: Double = 0
    var side: NursingSide? = nil
    var diaper: DiaperKind? = nil
    var note: String = ""
    var loggedBy: String = Prefs.yourName
    var weightGrams: Double = 0
    var lengthCM: Double = 0
    var headCM: Double = 0
    var temperatureC: Double = 0
    var label: String = ""

    init(kind: EntryKind, startedAt: Date = .now) {
        self.kind = kind
        self.startedAt = startedAt
    }

    init(entry: LogEntry) {
        kind = entry.kind
        startedAt = entry.startedAt ?? .now
        endedAt = entry.endedAt
        amountML = entry.amountML
        side = entry.side
        diaper = entry.diaper
        note = entry.note ?? ""
        loggedBy = entry.loggedBy ?? ""
        weightGrams = entry.weightGrams
        lengthCM = entry.lengthCM
        headCM = entry.headCM
        temperatureC = entry.temperatureC
        label = entry.label ?? ""
    }
}

/// A value copy of an entry, safe to carry out of a Core Data context.
struct EntrySnapshot {
    let kind: EntryKind
    let startedAt: Date
    let endedAt: Date?
    let amountML: Double
    let side: NursingSide?
    let diaper: DiaperKind?
    let babyName: String

    init(entry: LogEntry) {
        kind = entry.kind
        startedAt = entry.startedAt ?? .now
        endedAt = entry.endedAt
        amountML = entry.amountML
        side = entry.side
        diaper = entry.diaper
        babyName = entry.baby?.displayName ?? "Baby"
    }
}

enum LogbookError: Error, LocalizedError, CustomLocalizedStringResourceConvertible {
    case notSetUp

    var errorDescription: String? { "Open Mina and set up your baby first." }
    var localizedStringResource: LocalizedStringResource { "Open Mina and set up your baby first." }
}

/// Every write goes through here so the app and Siri agree on how entries are
/// made, which store they live in, and who gets credit for the 3 AM feed.
final class Logbook {
    static let shared = Logbook(persistence: .shared)

    let persistence: PersistenceController
    init(persistence: PersistenceController) { self.persistence = persistence }

    // MARK: Baby

    func currentBaby(in context: NSManagedObjectContext) -> Baby? {
        let babies = (try? context.fetch(Baby.request())) ?? []
        return persistence.preferredBaby(from: babies)
    }

    @discardableResult
    func createBaby(name: String, birthDate: Date, in context: NSManagedObjectContext) throws -> Baby {
        let baby = NSEntityDescription.insertNewObject(forEntityName: "Baby", into: context) as! Baby
        baby.id = UUID()
        baby.name = name
        baby.birthDate = birthDate
        if let store = persistence.privateStore { context.assign(baby, to: store) }
        try context.save()
        return baby
    }

    // MARK: Entries

    @discardableResult
    func add(_ draft: EntryDraft, to baby: Baby, in context: NSManagedObjectContext) throws -> LogEntry {
        let entry = NSEntityDescription.insertNewObject(forEntityName: "LogEntry", into: context) as! LogEntry
        entry.id = UUID()
        entry.createdAt = .now
        entry.deviceID = Prefs.deviceID
        apply(draft, to: entry)
        entry.baby = baby
        // A shared baby lives in the shared store; its entries must too.
        if let store = baby.objectID.persistentStore { context.assign(entry, to: store) }
        try context.save()
        Self.widgetsChanged()
        return entry
    }

    func apply(_ draft: EntryDraft, to entry: LogEntry) {
        entry.kind = draft.kind
        entry.startedAt = draft.startedAt
        entry.endedAt = draft.endedAt
        entry.amountML = draft.amountML
        entry.side = draft.kind == .nursing || draft.kind == .pumping ? draft.side : nil
        entry.diaper = draft.kind == .diaper ? draft.diaper : nil
        entry.weightGrams = draft.weightGrams
        entry.lengthCM = draft.lengthCM
        entry.headCM = draft.headCM
        entry.temperatureC = draft.temperatureC
        let label = draft.label.trimmingCharacters(in: .whitespaces)
        entry.label = label.isEmpty ? nil : label
        let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.note = note.isEmpty ? nil : note
        let by = draft.loggedBy.trimmingCharacters(in: .whitespaces)
        entry.loggedBy = by.isEmpty ? nil : by
    }

    func delete(_ entry: LogEntry, in context: NSManagedObjectContext) throws {
        context.delete(entry)
        try context.save()
        Self.widgetsChanged()
    }

    /// Widgets show the last feed and today's counts; tell them when those move.
    static func widgetsChanged() {
        WidgetCenter.shared.reloadAllTimelines()
        if !PersistenceController.isExtension { EntryIndex.refresh() }
    }

    func entries(for baby: Baby, from start: Date, to end: Date? = nil, in context: NSManagedObjectContext) -> [LogEntry] {
        (try? context.fetch(LogEntry.request(for: baby, from: start, to: end))) ?? []
    }

    func ongoingSleep(for baby: Baby, in context: NSManagedObjectContext) -> LogEntry? {
        let request = LogEntry.request()
        request.predicate = NSPredicate(format: "baby == %@ AND kindRaw == %@ AND endedAt == nil", baby, EntryKind.sleep.rawValue)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    @discardableResult
    func endSleep(for baby: Baby, at date: Date = .now, in context: NSManagedObjectContext) throws -> LogEntry? {
        guard let sleep = ongoingSleep(for: baby, in: context) else { return nil }
        sleep.endedAt = max(date, sleep.startedAt ?? date)
        try context.save()
        Self.widgetsChanged()
        return sleep
    }

    func lastFeed(for baby: Baby, in context: NSManagedObjectContext) -> LogEntry? {
        let request = LogEntry.request()
        request.predicate = NSPredicate(format: "baby == %@ AND kindRaw IN %@", baby, [EntryKind.bottle.rawValue, EntryKind.nursing.rawValue])
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    func lastDirtyDiaper(for baby: Baby, in context: NSManagedObjectContext) -> LogEntry? {
        let request = LogEntry.request()
        request.predicate = NSPredicate(format: "baby == %@ AND kindRaw == %@ AND diaperRaw IN %@", baby, EntryKind.diaper.rawValue, [DiaperKind.dirty.rawValue, DiaperKind.both.rawValue])
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    func milestone(labelled label: String, for baby: Baby, in context: NSManagedObjectContext) -> LogEntry? {
        let request = LogEntry.request()
        request.predicate = NSPredicate(format: "baby == %@ AND kindRaw == %@ AND label == %@", baby, EntryKind.milestone.rawValue, label)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    /// Tick or untick a milestone from the guide.
    func toggleMilestone(_ label: String, for baby: Baby, in context: NSManagedObjectContext) throws {
        if let existing = milestone(labelled: label, for: baby, in: context) {
            try delete(existing, in: context)
        } else {
            var draft = EntryDraft(kind: .milestone)
            draft.label = label
            try add(draft, to: baby, in: context)
        }
    }

    /// Start times of the most recent feeds, newest first.
    func recentFeedTimes(for baby: Baby, limit: Int = 12, in context: NSManagedObjectContext) -> [Date] {
        let request = LogEntry.request()
        request.predicate = NSPredicate(format: "baby == %@ AND kindRaw IN %@", baby, [EntryKind.bottle.rawValue, EntryKind.nursing.rawValue])
        request.fetchLimit = limit
        return ((try? context.fetch(request)) ?? []).compactMap(\.startedAt)
    }

    /// When she last woke from a finished sleep.
    func lastWake(for baby: Baby, in context: NSManagedObjectContext) -> Date? {
        let request = LogEntry.request()
        request.predicate = NSPredicate(format: "baby == %@ AND kindRaw == %@ AND endedAt != nil", baby, EntryKind.sleep.rawValue)
        request.sortDescriptors = [NSSortDescriptor(key: "endedAt", ascending: false)]
        request.fetchLimit = 1
        return (try? context.fetch(request).first)?.endedAt
    }

    // MARK: Background work (Siri)

    /// Runs `work` on a fresh background context with the current baby.
    func perform<T>(_ work: @escaping (NSManagedObjectContext, Baby) throws -> T) async throws -> T {
        let context = persistence.newBackgroundContext()
        return try await context.perform {
            guard let baby = self.currentBaby(in: context) else { throw LogbookError.notSetUp }
            return try work(context, baby)
        }
    }
}
