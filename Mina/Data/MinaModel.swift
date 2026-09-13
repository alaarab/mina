import CoreData
import SwiftUI

/// The whole data model: the two managed object classes, the enums that give
/// their raw string columns meaning, the Core Data model built in code, and the
/// read-only conveniences every screen leans on to turn an entry into a title,
/// a colour and a duration. Compiled into the widget extension as well, so it
/// pulls in nothing the app alone has.

// MARK: Managed objects

@objc(Baby)
public final class Baby: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var birthDate: Date?
    @NSManaged public var entries: NSSet?
    /// Who's on right now (a device id) and since when; nil means everyone.
    @NSManaged public var onDutyDeviceID: String?
    @NSManaged public var onDutyName: String?
    @NSManaged public var onDutySince: Date?
    /// JSON list of shift blocks; see `Shifts`.
    @NSManaged public var shiftsJSON: String?
}

@objc(LogEntry)
public final class LogEntry: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var kindRaw: String?
    @NSManaged public var startedAt: Date?
    @NSManaged public var endedAt: Date?
    @NSManaged public var amountML: Double
    @NSManaged public var sideRaw: String?
    @NSManaged public var diaperRaw: String?
    @NSManaged public var note: String?
    @NSManaged public var loggedBy: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var deviceID: String?
    @NSManaged public var weightGrams: Double
    @NSManaged public var lengthCM: Double
    @NSManaged public var headCM: Double
    @NSManaged public var temperatureC: Double
    @NSManaged public var label: String?
    @NSManaged public var baby: Baby?
}

// MARK: Entry kinds

enum EntryKind: String, CaseIterable, Identifiable {
    case bottle, nursing, diaper, sleep, note
    case pumping, growth, medicine, tummyTime, bath, temperature, milestone

    var id: String { rawValue }
    var title: String {
        switch self {
        case .bottle: return "Bottle"
        case .nursing: return "Nursing"
        case .diaper: return "Diaper"
        case .sleep: return "Sleep"
        case .note: return "Note"
        case .pumping: return "Pumping"
        case .growth: return "Growth"
        case .medicine: return "Medicine"
        case .tummyTime: return "Tummy time"
        case .bath: return "Bath"
        case .temperature: return "Temperature"
        case .milestone: return "Milestone"
        }
    }
    var symbol: String {
        switch self {
        case .bottle: return "waterbottle.fill"
        case .nursing: return "heart.fill"
        case .diaper: return "drop.fill"
        case .sleep: return "moon.zzz.fill"
        case .note: return "note.text"
        case .pumping: return "arrow.down.to.line.circle.fill"
        case .growth: return "chart.line.uptrend.xyaxis"
        case .medicine: return "pills.fill"
        case .tummyTime: return "figure.child"
        case .bath: return "bathtub.fill"
        case .temperature: return "thermometer.medium"
        case .milestone: return "star.fill"
        }
    }
    var color: Color {
        switch self {
        case .bottle: return MinaTheme.bottle
        case .nursing: return MinaTheme.nursing
        case .diaper: return MinaTheme.diaper
        case .sleep: return MinaTheme.sleep
        case .note: return MinaTheme.note
        case .pumping: return MinaTheme.nursing
        case .growth: return MinaTheme.accent
        case .medicine: return MinaTheme.warning
        case .tummyTime: return MinaTheme.diaper
        case .bath: return MinaTheme.sleep
        case .temperature: return MinaTheme.danger
        case .milestone: return MinaTheme.warning
        }
    }
    var isFeed: Bool { self == .bottle || self == .nursing }
    /// Kinds with a start and an end.
    var isTimed: Bool { self == .sleep || self == .nursing || self == .tummyTime }
    /// The "More" menu on Today, in order.
    static let extras: [EntryKind] = [.pumping, .growth, .medicine, .tummyTime, .bath, .temperature]
}

// Sendable is spelled out here, not inferred: `AppEnum` in Intents.swift
// implies it, and Swift wants the conformance in the file that declares the
// enum. The enums have to stay in this file because the widget target compiles
// it and not Intents.swift.
enum NursingSide: String, CaseIterable, Identifiable, Sendable {
    case left, right, both
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum DiaperKind: String, CaseIterable, Identifiable, Sendable {
    case wet, dirty, both
    var id: String { rawValue }
    var title: String {
        switch self {
        case .wet: return "Wet"
        case .dirty: return "Dirty"
        case .both: return "Wet & dirty"
        }
    }
}

// MARK: The model

/// The Core Data model, built in code so there is no .xcdatamodeld to keep in
/// sync. Every attribute is optional or defaulted, which CloudKit requires.
enum MinaModel {
    static let model: NSManagedObjectModel = {
        let baby = NSEntityDescription()
        baby.name = "Baby"
        baby.managedObjectClassName = "Baby"

        let entry = NSEntityDescription()
        entry.name = "LogEntry"
        entry.managedObjectClassName = "LogEntry"

        func attribute(_ name: String, _ type: NSAttributeType, defaultValue: Any? = nil) -> NSAttributeDescription {
            let attribute = NSAttributeDescription()
            attribute.name = name
            attribute.attributeType = type
            attribute.isOptional = true
            attribute.defaultValue = defaultValue
            return attribute
        }

        let babyEntries = NSRelationshipDescription()
        babyEntries.name = "entries"
        babyEntries.destinationEntity = entry
        babyEntries.minCount = 0
        babyEntries.maxCount = 0
        babyEntries.deleteRule = .cascadeDeleteRule
        babyEntries.isOptional = true

        let entryBaby = NSRelationshipDescription()
        entryBaby.name = "baby"
        entryBaby.destinationEntity = baby
        entryBaby.minCount = 0
        entryBaby.maxCount = 1
        entryBaby.deleteRule = .nullifyDeleteRule
        entryBaby.isOptional = true

        babyEntries.inverseRelationship = entryBaby
        entryBaby.inverseRelationship = babyEntries

        baby.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("name", .stringAttributeType),
            attribute("birthDate", .dateAttributeType),
            attribute("onDutyDeviceID", .stringAttributeType),
            attribute("onDutyName", .stringAttributeType),
            attribute("onDutySince", .dateAttributeType),
            attribute("shiftsJSON", .stringAttributeType),
            babyEntries,
        ]
        entry.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("kindRaw", .stringAttributeType),
            attribute("startedAt", .dateAttributeType),
            attribute("endedAt", .dateAttributeType),
            attribute("amountML", .doubleAttributeType, defaultValue: 0.0),
            attribute("sideRaw", .stringAttributeType),
            attribute("diaperRaw", .stringAttributeType),
            attribute("note", .stringAttributeType),
            attribute("loggedBy", .stringAttributeType),
            attribute("createdAt", .dateAttributeType),
            attribute("deviceID", .stringAttributeType),
            attribute("weightGrams", .doubleAttributeType, defaultValue: 0.0),
            attribute("lengthCM", .doubleAttributeType, defaultValue: 0.0),
            attribute("headCM", .doubleAttributeType, defaultValue: 0.0),
            attribute("temperatureC", .doubleAttributeType, defaultValue: 0.0),
            attribute("label", .stringAttributeType),
            entryBaby,
        ]

        let model = NSManagedObjectModel()
        model.entities = [baby, entry]
        return model
    }()
}

// MARK: Baby

extension Baby {
    static func request() -> NSFetchRequest<Baby> {
        let request = NSFetchRequest<Baby>(entityName: "Baby")
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return request
    }

    var displayName: String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Baby" : trimmed
    }

    func ageDays(on date: Date = .now, calendar: Calendar = .current) -> Int? {
        guard let birthDate else { return nil }
        let from = calendar.startOfDay(for: birthDate)
        let to = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: from, to: to).day
    }

    /// "5 days old", "3 weeks, 2 days old", "4 months, 1 week old".
    func ageDescription(on date: Date = .now, calendar: Calendar = .current) -> String {
        guard let days = ageDays(on: date, calendar: calendar), let birthDate else { return "" }
        if days < 0 { return "Arriving soon" }
        if days == 0 { return "Born today" }
        if days < 7 { return Format.count(days, "day") + " old" }
        if days < 91 {
            let weeks = days / 7, rest = days % 7
            var text = Format.count(weeks, "week")
            if rest > 0 { text += ", " + Format.count(rest, "day") }
            return text + " old"
        }
        let components = calendar.dateComponents([.month, .day], from: calendar.startOfDay(for: birthDate), to: calendar.startOfDay(for: date))
        let months = components.month ?? 0
        let weeks = (components.day ?? 0) / 7
        var text = Format.count(months, "month")
        if weeks > 0 { text += ", " + Format.count(weeks, "week") }
        return text + " old"
    }
}

// MARK: Entries

extension LogEntry {
    static func request() -> NSFetchRequest<LogEntry> {
        let request = NSFetchRequest<LogEntry>(entityName: "LogEntry")
        request.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: false)]
        return request
    }

    /// Entries for one baby that started in [start, end). Pass no end for "onwards".
    static func request(for baby: Baby, from start: Date, to end: Date? = nil) -> NSFetchRequest<LogEntry> {
        let request = request()
        var predicates = [NSPredicate(format: "baby == %@", baby), NSPredicate(format: "startedAt >= %@", start as NSDate)]
        if let end { predicates.append(NSPredicate(format: "startedAt < %@", end as NSDate)) }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        return request
    }

    var kind: EntryKind {
        get { EntryKind(rawValue: kindRaw ?? "") ?? .note }
        set { kindRaw = newValue.rawValue }
    }
    var side: NursingSide? {
        get { sideRaw.flatMap(NursingSide.init(rawValue:)) }
        set { sideRaw = newValue?.rawValue }
    }
    var diaper: DiaperKind? {
        get { diaperRaw.flatMap(DiaperKind.init(rawValue:)) }
        set { diaperRaw = newValue?.rawValue }
    }
    var isOngoingSleep: Bool { kind == .sleep && endedAt == nil }
    var isOngoingNursing: Bool { kind == .nursing && endedAt == nil }
    var isOngoing: Bool { isOngoingSleep || isOngoingNursing }

    func duration(now: Date = .now) -> TimeInterval? {
        guard let startedAt, kind.isTimed else { return nil }
        let end = endedAt ?? ((kind == .sleep || kind == .nursing) ? now : startedAt)
        return max(0, end.timeIntervalSince(startedAt))
    }

    var color: Color {
        if kind == .diaper, diaper == .dirty { return MinaTheme.diaperDirty }
        return kind.color
    }

    /// "Bottle · 4 oz", "Nursed · left · 15m", "Wet diaper", "Sleep · 1h 20m".
    func title(unit: VolumeUnit, now: Date = .now) -> String {
        switch kind {
        case .bottle:
            return amountML > 0 ? "Bottle · \(unit.format(ml: amountML))" : "Bottle"
        case .nursing:
            var parts = [isOngoingNursing ? "Nursing" : "Nursed"]
            if let side { parts.append(side.title.lowercased()) }
            if let seconds = duration(now: now), seconds > 0 { parts.append(Format.duration(seconds)) }
            return parts.joined(separator: " · ")
        case .diaper:
            return "\(diaper?.title ?? "Wet") diaper"
        case .sleep:
            if isOngoingSleep { return "Sleeping · \(Format.duration(duration(now: now) ?? 0))" }
            return "Sleep · \(Format.duration(duration(now: now) ?? 0))"
        case .note:
            let text = (note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? "Note" : text
        case .pumping:
            var parts = ["Pumped"]
            if amountML > 0 { parts.append(unit.format(ml: amountML)) }
            if let side { parts.append(side.title.lowercased()) }
            return parts.joined(separator: " · ")
        case .growth:
            let parts = [Measure.weight(grams: weightGrams, unit: unit), Measure.length(cm: lengthCM, unit: unit, label: ""), Measure.length(cm: headCM, unit: unit, label: "head")]
                .compactMap { $0 }
            return parts.isEmpty ? "Growth" : parts.joined(separator: " · ")
        case .medicine:
            let name = (label ?? "").trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? "Medicine" : name
        case .tummyTime:
            if let seconds = duration(now: now), seconds > 0 { return "Tummy time · \(Format.duration(seconds))" }
            return "Tummy time"
        case .bath:
            return "Bath"
        case .temperature:
            return temperatureC > 0 ? "Temperature · \(Measure.temperature(celsius: temperatureC, unit: unit))" : "Temperature"
        case .milestone:
            let text = (label ?? "").trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? "Milestone" : "★ \(text)"
        }
    }

    /// The second line under a row: the note, or who logged it.
    var subtitle: String? {
        if kind == .nursing, !isOngoingNursing, let label, !label.isEmpty, !label.contains(":") { return label }
        if kind != .note, let note, !note.trimmingCharacters(in: .whitespaces).isEmpty { return note }
        if let loggedBy, !loggedBy.isEmpty { return "by \(loggedBy)" }
        if isFromPartner { return "by your partner" }
        return nil
    }

    var isFromPartner: Bool {
        guard let deviceID else { return false }
        return deviceID != Prefs.deviceID
    }
}

// `id` is the UUID attribute, set on every insert, which is all Identifiable needs.
extension LogEntry: Identifiable {}
extension Baby: Identifiable {}

// MARK: Measurements

/// Growth and temperature follow the bottle unit: ounces means lb/oz, inches
/// and °F; milliliters means kg, cm and °C.
enum Measure {
    static let gramsPerOunce = 28.3495
    static let cmPerInch = 2.54

    static func weight(grams: Double, unit: VolumeUnit) -> String? {
        guard grams > 0 else { return nil }
        if unit == .ounces {
            let totalOunces = grams / gramsPerOunce
            let pounds = Int(totalOunces / 16)
            let ounces = totalOunces - Double(pounds) * 16
            return "\(pounds) lb \(VolumeUnit.trim((ounces * 10).rounded() / 10)) oz"
        }
        return "\(VolumeUnit.trim((grams / 1000 * 100).rounded() / 100)) kg"
    }

    static func length(cm: Double, unit: VolumeUnit, label: String) -> String? {
        guard cm > 0 else { return nil }
        let text = unit == .ounces ? "\(VolumeUnit.trim((cm / cmPerInch * 4).rounded() / 4)) in" : "\(VolumeUnit.trim((cm * 10).rounded() / 10)) cm"
        return label.isEmpty ? text : "\(label) \(text)"
    }

    static func temperature(celsius: Double, unit: VolumeUnit) -> String {
        if unit == .ounces { return "\(VolumeUnit.trim((celsius * 9 / 5 + 32) * 10 / 10)) °F".replacingOccurrences(of: ".0 ", with: " ") }
        return "\(VolumeUnit.trim((celsius * 10).rounded() / 10)) °C"
    }

    /// Back from what a stepper shows to what the entry stores.
    static func celsius(fromDisplay value: Double, unit: VolumeUnit) -> Double { unit == .ounces ? (value - 32) * 5 / 9 : value }
    static func cm(fromDisplay value: Double, unit: VolumeUnit) -> Double { unit == .ounces ? value * cmPerInch : value }
}
