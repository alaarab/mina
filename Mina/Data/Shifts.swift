import CoreData
import Foundation

/// Who is "on" for the baby: the person whose phone rings the feed alarm and
/// gets partner alerts. Either tapped by hand or set by a schedule.
struct ShiftBlock: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String          // "Ala" / "Kiley"; matched to Prefs.yourName, falls back to device id
    var deviceID: String?
    var startMinute: Int      // minutes after midnight
    var endMinute: Int        // may be less than start: wraps past midnight

    func contains(_ minute: Int) -> Bool {
        startMinute <= endMinute ? (minute >= startMinute && minute < endMinute) : (minute >= startMinute || minute < endMinute)
    }
}

enum Shifts {
    static func blocks(for baby: Baby) -> [ShiftBlock] {
        guard let json = baby.shiftsJSON, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([ShiftBlock].self, from: data)) ?? []
    }

    static func save(_ blocks: [ShiftBlock], to baby: Baby, in context: NSManagedObjectContext) throws {
        baby.shiftsJSON = String(data: try JSONEncoder().encode(blocks), encoding: .utf8)
        try context.save()
    }

    /// The block covering `date`, if any.
    static func scheduled(for baby: Baby, at date: Date = .now, calendar: Calendar = .current) -> ShiftBlock? {
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        return blocks(for: baby).first { $0.contains(minute) }
    }

    /// True if this phone should ring and be alerted right now.
    static func thisPhoneIsOn(for baby: Baby, at date: Date = .now) -> Bool {
        if let device = baby.onDutyDeviceID { return device == Prefs.deviceID }
        if let block = scheduled(for: baby, at: date) {
            if let device = block.deviceID { return device == Prefs.deviceID }
            return block.name.lowercased() == Prefs.yourName.lowercased()
        }
        return true   // nobody claimed it: everyone is on
    }

    static func onDutyLabel(for baby: Baby, at date: Date = .now) -> String? {
        if let name = baby.onDutyName, baby.onDutyDeviceID != nil { return name }
        return scheduled(for: baby, at: date)?.name
    }

    static func takeOver(_ baby: Baby, in context: NSManagedObjectContext) throws {
        baby.onDutyDeviceID = Prefs.deviceID
        baby.onDutyName = Prefs.yourName.isEmpty ? "Me" : Prefs.yourName
        baby.onDutySince = .now
        try context.save()
    }

    /// Back to "everyone" (or the schedule, if there is one).
    static func handOff(_ baby: Baby, in context: NSManagedObjectContext) throws {
        baby.onDutyDeviceID = nil
        baby.onDutyName = nil
        baby.onDutySince = nil
        try context.save()
    }
}
