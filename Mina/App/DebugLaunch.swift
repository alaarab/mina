import CoreData
import Foundation
import UIKit

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

    static var initialTab: String? { argument("-tab") }

    /// The value after a named launch argument: `-open history` lands on
    /// History, `-history-query x` and `-history-filter feeds` preset it,
    /// `-seed-days 20` sets how much demo data to make.
    static func argument(_ name: String) -> String? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
        #else
        return nil
        #endif
    }

    static func seedIfRequested(logbook: Logbook, context: NSManagedObjectContext) {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-seed-demo"),
              logbook.currentBaby(in: context) == nil else { return }
        let clock = Date.now
        defer { NSLog("seed-demo: \(Int(Date.now.timeIntervalSince(clock) * 1000)) ms") }
        let calendar = Calendar.current
        // Pin the seed's "now" to mid-afternoon so Today always shows a full day, whatever the clock says.
        let now = calendar.date(bySettingHour: 15, minute: 10, second: 0, of: .now) ?? .now
        let today = calendar.startOfDay(for: now)
        let days = argument("-seed-days").flatMap(Int.init) ?? 12
        do {
            // The date force unwraps here and in `add` below: adding whole days
            // to a start-of-day date only fails for a calendar this app never uses.
            let birthDate = calendar.date(byAdding: .day, value: -max(23, days + 11), to: today)!
            let baby = try logbook.createBaby(name: "Mina", birthDate: birthDate, in: context)
            func add(_ kind: EntryKind, day: Int, hour: Double, _ configure: (inout EntryDraft) -> Void = { _ in }) throws {
                let start = calendar.date(byAdding: .day, value: -day, to: today)!.addingTimeInterval(hour * 3600)
                guard start <= now else { return }
                var draft = EntryDraft(kind: kind, startedAt: start)
                draft.loggedBy = hour.truncatingRemainder(dividingBy: 2) == 0 ? "Dad" : "Mom"
                configure(&draft)
                try logbook.add(draft, to: baby, in: context, save: false)
            }
            let oz = VolumeUnit.millilitersPerOunce
            for day in 0..<days {
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
            try add(.pumping, day: 0, hour: 9.5) { $0.amountML = 4 * oz; $0.side = .both }
            for day in stride(from: 3, to: days, by: 7) { try add(.growth, day: day, hour: 10) { $0.weightGrams = 3400 + Double(days - day) * 28 } }
            for day in stride(from: 0, to: days, by: 1) where day % 5 == 0 { try add(.medicine, day: day, hour: 8) { $0.label = "Vitamin D · 400 IU" } }
            try add(.note, day: 1, hour: 15) { $0.note = "Vitamin D drops" }
            try add(.note, day: 3, hour: 11) { $0.note = "First real smile at Mom"; $0.photo = demoPhoto(seed: 2) }
            try add(.note, day: 0, hour: 14.2) { $0.note = "Rash on her cheek, for Dr. Lee"; $0.photo = demoPhoto(seed: 1) }
            try add(.sleep, day: 0, hour: Double(calendar.component(.hour, from: now)) - 0.7)
            try context.save()
            logbook.didChangeEntries(for: baby, in: context)
        } catch {
            assertionFailure("demo seed failed: \(error)")
        }
        #endif
    }

    #if DEBUG
    /// A soft "photo" drawn in code (no bundled picture, nothing to license),
    /// run through the same preparation as a real one.
    private static func demoPhoto(seed: Int) -> EntryPhoto? {
        let size = CGSize(width: 1200, height: 900)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let colors: [UIColor] = seed == 1
                ? [UIColor(red: 0.98, green: 0.85, blue: 0.78, alpha: 1), UIColor(red: 0.93, green: 0.62, blue: 0.55, alpha: 1)]
                : [UIColor(red: 0.80, green: 0.88, blue: 0.98, alpha: 1), UIColor(red: 0.55, green: 0.66, blue: 0.90, alpha: 1)]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray, locations: [0, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            UIColor.white.withAlphaComponent(0.7).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: size.width * 0.3, y: size.height * 0.22, width: size.width * 0.4, height: size.width * 0.4))
            UIColor(red: 0.85, green: 0.45, blue: 0.4, alpha: 0.6).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: size.width * 0.52, y: size.height * 0.5, width: 90, height: 70))
        }
        return PhotoStore.prepare(image)
    }
    #endif
}
