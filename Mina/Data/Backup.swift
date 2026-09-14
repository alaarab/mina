import CoreData
import Foundation

/// Whole-log export and import as plain JSON. Entries carry their ids, so
/// importing the same file twice changes nothing, and a file from another
/// phone merges instead of duplicating.
enum Backup {
    struct Entry: Codable {
        var id: UUID
        var kind: String
        var startedAt: Date
        var endedAt: Date?
        var amountML: Double
        var side: String?
        var diaper: String?
        var note: String?
        var loggedBy: String?
        var weightGrams: Double
        var lengthCM: Double
        var headCM: Double
        var temperatureC: Double
        var label: String?
        /// The full JPEG, base64 in the JSON (`Data` encodes that way). The
        /// thumbnail is rebuilt on import when it is missing.
        var photo: Data?
        var photoThumb: Data?
    }

    struct File: Codable {
        var version = 2
        var app = "Mina"
        var exportedAt = Date.now
        var babyName: String
        var birthDate: Date?
        /// How many entries carry a picture and how many bytes those add,
        /// before base64: a file with photos is megabytes, not kilobytes.
        var photoCount = 0
        var photoBytes = 0
        var entries: [Entry]
    }

    static func makeFile(baby: Baby, in context: NSManagedObjectContext) throws -> File {
        let request = LogEntry.request()
        request.predicate = NSPredicate(format: "baby == %@", baby)
        let entries = try context.fetch(request).map { entry in
            Entry(id: entry.id ?? UUID(), kind: entry.kind.rawValue, startedAt: entry.startedAt ?? .now, endedAt: entry.endedAt,
                  amountML: entry.amountML, side: entry.sideRaw, diaper: entry.diaperRaw, note: entry.note, loggedBy: entry.loggedBy,
                  weightGrams: entry.weightGrams, lengthCM: entry.lengthCM, headCM: entry.headCM, temperatureC: entry.temperatureC, label: entry.label,
                  photo: entry.photo, photoThumb: entry.photoThumb)
        }
        let photos = entries.compactMap(\.photo)
        return File(babyName: baby.displayName, birthDate: baby.birthDate,
                    photoCount: photos.count, photoBytes: photos.reduce(0) { $0 + $1.count }, entries: entries)
    }

    static func exportData(baby: Baby, in context: NSManagedObjectContext) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(try makeFile(baby: baby, in: context))
    }

    /// Adds entries whose ids aren't in the log yet. Returns how many were added.
    @discardableResult
    static func importData(_ data: Data, into baby: Baby, in context: NSManagedObjectContext) throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(File.self, from: data)
        let ids = file.entries.map(\.id)
        let existing = LogEntry.request()
        existing.predicate = NSPredicate(format: "baby == %@ AND id IN %@", baby, ids)
        let known = Set(try context.fetch(existing).compactMap(\.id))
        var added = 0
        for item in file.entries where !known.contains(item.id) {
            // The model names "LogEntry" as this exact class, so the cast holds.
            let entry = NSEntityDescription.insertNewObject(forEntityName: "LogEntry", into: context) as! LogEntry
            entry.id = item.id
            entry.createdAt = .now
            entry.deviceID = Prefs.deviceID
            entry.kindRaw = item.kind
            entry.startedAt = item.startedAt
            entry.endedAt = item.endedAt
            entry.amountML = item.amountML
            entry.sideRaw = item.side
            entry.diaperRaw = item.diaper
            entry.note = item.note
            entry.loggedBy = item.loggedBy
            entry.weightGrams = item.weightGrams
            entry.lengthCM = item.lengthCM
            entry.headCM = item.headCM
            entry.temperatureC = item.temperatureC
            entry.label = item.label
            if let photo = item.photo {
                entry.photo = photo
                entry.photoThumb = item.photoThumb ?? PhotoStore.prepare(data: photo)?.thumb
            }
            entry.baby = baby
            if let store = baby.objectID.persistentStore { context.assign(entry, to: store) }
            added += 1
        }
        var learnedBirthDate = false
        if baby.birthDate == nil, let birthDate = file.birthDate { baby.birthDate = birthDate; learnedBirthDate = true }
        if added > 0 || learnedBirthDate { try context.save() }
        // One pass of the after-save hooks for the whole file, not one per entry.
        if added > 0 { Logbook.shared.didChangeEntries(for: baby, in: context) }
        return added
    }

    /// Where a recovery build drops its export so it can be copied off the phone.
    static var autoExportURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("mina-export.json")
    }
}
