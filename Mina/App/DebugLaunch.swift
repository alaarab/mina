import CoreData
import Foundation

/// Debug-only launch arguments: `-seed-demo` fills a fresh store with a
/// realistic day, `-tab calendar|guide|settings` opens on that tab. Used for
/// screenshots and quick manual checks in the simulator.
enum DebugLaunch {
    /// Screenshot runs skip the notification prompt so it doesn't cover the UI.
    static var isDemo: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-seed-demo")
        #else
        return false
        #endif
    }

    static var initialTab: String? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-tab"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
        #else
        return nil
        #endif
    }

    static func seedIfRequested(logbook: Logbook, context: NSManagedObjectContext) {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-seed-demo"),
              logbook.currentBaby(in: context) == nil else { return }
        let calendar = Calendar.current
        let now = Date.now
        let today = calendar.startOfDay(for: now)
        do {
            let baby = try logbook.createBaby(name: "Mina", birthDate: calendar.date(byAdding: .day, value: -23, to: today)!, in: context)
            func add(_ kind: EntryKind, day: Int, hour: Double, _ configure: (inout EntryDraft) -> Void = { _ in }) throws {
                let start = calendar.date(byAdding: .day, value: -day, to: today)!.addingTimeInterval(hour * 3600)
                guard start <= now else { return }
                var draft = EntryDraft(kind: kind, startedAt: start)
                draft.loggedBy = hour.truncatingRemainder(dividingBy: 2) == 0 ? "Dad" : "Mom"
                configure(&draft)
                try logbook.add(draft, to: baby, in: context)
            }
            let oz = VolumeUnit.millilitersPerOunce
            for day in 0..<12 {
                for (index, hour) in [1.0, 4.0, 7.0, 10.0, 13.0, 16.0, 19.0, 22.0].enumerated() {
                    if index % 3 == 1 {
                        try add(.nursing, day: day, hour: hour) { $0.side = index % 2 == 0 ? .left : .right; $0.endedAt = $0.startedAt.addingTimeInterval(15 * 60) }
                    } else {
                        try add(.bottle, day: day, hour: hour) { $0.amountML = [3.0, 3.5, 4.0][(index + day) % 3] * oz }
                    }
                    if index % 2 == 0 { try add(.diaper, day: day, hour: hour + 0.5) { $0.diaper = index % 4 == 0 ? .wet : .both } }
                    if index < 7 { try add(.sleep, day: day, hour: hour + 1) { $0.endedAt = $0.startedAt.addingTimeInterval(1.6 * 3600) } }
                }
            }
            try add(.note, day: 1, hour: 15) { $0.note = "Vitamin D drops" }
            try add(.note, day: 3, hour: 11) { $0.note = "First real smile at Mom" }
            try add(.sleep, day: 0, hour: Double(calendar.component(.hour, from: now)) - 0.7)
        } catch {
            assertionFailure("demo seed failed: \(error)")
        }
        #endif
    }
}
