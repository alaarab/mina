import CoreData
import Foundation

/// Device-local consent and eligibility; never changes the family's sleep log.
struct CareTimerPolicy {
    static let sleepKey = "liveActivity.sleep.enabled"
    static let nursingKey = "liveActivity.nursing.enabled"
    static let maximumAge: TimeInterval = 8 * 60 * 60

    let defaults: UserDefaults
    let deviceID: String

    func setEnabled(_ enabled: Bool, for kind: EntryKind, now: Date = .now) {
        let key = kind == .sleep ? Self.sleepKey : Self.nursingKey
        defaults.set(enabled ? now : nil, forKey: key + ".since")
        defaults.set(enabled, forKey: key)
    }

    func running(for baby: Baby?, in context: NSManagedObjectContext, now: Date = .now) -> [TimerSnapshot] {
        guard let baby else { return [] }
        return [EntryKind.sleep, .nursing].compactMap { kind in
            let key = kind == .sleep ? Self.sleepKey : Self.nursingKey
            guard defaults.bool(forKey: key), let since = defaults.object(forKey: key + ".since") as? Date else { return nil }
            let request = LogEntry.request()
            // A newer completed sleep supersedes an abandoned open record too.
            request.predicate = NSPredicate(format: "baby == %@ AND kindRaw == %@", baby, kind.rawValue)
            request.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: false)]
            request.fetchLimit = 1
            guard let entry = try? context.fetch(request).first,
                  entry.endedAt == nil, entry.deviceID == deviceID,
                  let start = entry.startedAt, start >= since, start <= now,
                  now.timeIntervalSince(start) < Self.maximumAge else { return nil }
            return TimerSnapshot(entry)
        }
    }
}
