import CoreData
import Foundation
import WidgetKit

/// The one door into the log. Drafts and snapshots carry entries in and out of
/// Core Data as plain values, and `Logbook` owns every write so the app, the
/// widgets and Siri agree on how an entry is made, which store it lands in, and
/// who gets credit for the 3 AM feed.

// MARK: Values

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

// MARK: Errors

enum LogbookError: Error, LocalizedError, CustomLocalizedStringResourceConvertible {
    case notSetUp

    var errorDescription: String? { "Open Mina and set up your baby first." }
    var localizedStringResource: LocalizedStringResource { "Open Mina and set up your baby first." }
}

// MARK: Logbook

/// Every write goes through here so the app and Siri agree on how entries are
/// made, which store they live in, and who gets credit for the 3 AM feed.
///
/// Unchecked because its only stored property is a `let`, and the Core Data
/// work it hands off is already confined by `context.perform`. Siri runs its
/// intents off the main actor, so the type has to cross that boundary.
final class Logbook: @unchecked Sendable {
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
        // The model above names "Baby" as this exact class, so the cast holds.
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
    func add(_ draft: EntryDraft, to baby: Baby, in context: NSManagedObjectContext, save: Bool = true) throws -> LogEntry {
        // The model above names "LogEntry" as this exact class, so the cast holds.
        let entry = NSEntityDescription.insertNewObject(forEntityName: "LogEntry", into: context) as! LogEntry
        entry.id = UUID()
        entry.createdAt = .now
        entry.deviceID = Prefs.deviceID
        apply(draft, to: entry)
        entry.baby = baby
        // A shared baby lives in the shared store; its entries must too.
        if let store = baby.objectID.persistentStore { context.assign(entry, to: store) }
        guard save else { return entry }
        try context.save()
        if draft.kind == .nursing, draft.endedAt != nil, let side = draft.side, side != .both { Prefs.lastNursingSide = side }
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

    // MARK: Nursing timer

    func ongoingNursing(for baby: Baby, in context: NSManagedObjectContext) -> LogEntry? {
        let request = LogEntry.request()
        request.predicate = NSPredicate(format: "baby == %@ AND kindRaw == %@ AND endedAt == nil", baby, EntryKind.nursing.rawValue)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    /// Starts the timer on one side. `label` accumulates the per-side split.
    @discardableResult
    func startNursing(side: NursingSide, for baby: Baby, at date: Date = .now, in context: NSManagedObjectContext) throws -> LogEntry {
        if let running = ongoingNursing(for: baby, in: context) { return running }
        var draft = EntryDraft(kind: .nursing, startedAt: date)
        draft.side = side
        draft.label = "\(side.rawValue):\(Int(date.timeIntervalSince1970))"
        return try add(draft, to: baby, in: context)
    }

    /// Records the side change; the entry's side becomes `both`.
    func switchNursingSide(_ entry: LogEntry, at date: Date = .now, in context: NSManagedObjectContext) throws {
        guard entry.isOngoingNursing, let current = entry.side else { return }
        let next: NursingSide = current == .left ? .right : .left
        entry.label = (entry.label ?? "") + "|\(next.rawValue):\(Int(date.timeIntervalSince1970))"
        entry.side = .both
        try context.save()
    }

    @discardableResult
    func endNursing(_ entry: LogEntry, at date: Date = .now, in context: NSManagedObjectContext) throws -> LogEntry {
        guard entry.isOngoingNursing else { return entry }
        entry.endedAt = max(date, entry.startedAt ?? date)
        // Turn the raw side log into "left 8m · right 6m" and remember the last side.
        let segments = (entry.label ?? "").split(separator: "|").compactMap { part -> (NursingSide, Date)? in
            let bits = part.split(separator: ":")
            guard bits.count == 2, let side = NursingSide(rawValue: String(bits[0])), let stamp = Double(bits[1]) else { return nil }
            return (side, Date(timeIntervalSince1970: stamp))
        }
        if !segments.isEmpty {
            var totals: [NursingSide: TimeInterval] = [:]
            for (index, segment) in segments.enumerated() {
                let end = index + 1 < segments.count ? segments[index + 1].1 : entry.endedAt ?? date
                totals[segment.0, default: 0] += max(0, end.timeIntervalSince(segment.1))
            }
            entry.label = [NursingSide.left, .right].compactMap { side in totals[side].map { "\(side.rawValue) \(Format.duration($0))" } }.joined(separator: " · ")
            Prefs.lastNursingSide = segments.last?.0
        } else {
            entry.label = nil
            Prefs.lastNursingSide = entry.side == .both ? nil : entry.side
        }
        try context.save()
        Self.widgetsChanged()
        return entry
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

    /// Moves every entry of `local` into `target` (a shared baby) and deletes
    /// `local`. Used when someone accepts a share after starting their own log.
    @discardableResult
    func merge(_ local: Baby, into target: Baby, in context: NSManagedObjectContext) throws -> Int {
        guard local != target else { return 0 }
        let entries = self.entries(for: local, from: .distantPast, in: context)
        for entry in entries {
            var draft = EntryDraft(entry: entry)
            draft.loggedBy = entry.loggedBy ?? ""
            let copy = try add(draft, to: target, in: context, save: false)
            copy.id = entry.id
            copy.createdAt = entry.createdAt
        }
        if target.birthDate == nil { target.birthDate = local.birthDate }
        context.delete(local)
        try context.save()
        if Prefs.selectedBabyID == local.id { Prefs.selectedBabyID = nil }
        Self.widgetsChanged()
        return entries.count
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
