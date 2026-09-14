import CoreData
import Foundation

/// What the Control Center buttons show, read once per reload the way the
/// widgets' timeline provider reads its snapshot. The wording lives here, in
/// a file both the app and the widget extension compile, so the app's tests
/// can check it without a widget process.
struct ControlState: Equatable {
    var hasBaby = false
    var nursingSince: Date?
    /// The side she is on right now while the timer runs.
    var nursingSide: NursingSide?
    var sleepingSince: Date?
    var lastBottleML = Prefs.lastBottleML
    var unit = Prefs.unit
    var suggestedSide = Prefs.suggestedNursingSide

    var isNursing: Bool { nursingSince != nil }
    var isSleeping: Bool { sleepingSince != nil }

    static func load(logbook: Logbook = .shared, context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) -> ControlState {
        var state = ControlState()
        context.performAndWait {
            context.refreshAllObjects()
            guard let baby = logbook.currentBaby(in: context) else { return }
            state.hasBaby = true
            if let nursing = logbook.ongoingNursing(for: baby, in: context) {
                state.nursingSince = nursing.startedAt
                state.nursingSide = Self.currentSide(of: nursing)
            }
            state.sleepingSince = logbook.ongoingSleep(for: baby, in: context)?.startedAt
        }
        return state
    }

    /// The side a running timer is on: the last segment of the side log, or
    /// the entry's side before any switch.
    static func currentSide(of entry: LogEntry) -> NursingSide? {
        let segments = (entry.label ?? "").split(separator: "|")
        if let last = segments.last, let side = NursingSide(rawValue: String(last.split(separator: ":").first ?? "")) { return side }
        return entry.side
    }

    // MARK: Text

    /// "4 oz": the amount the bottle button logs.
    var bottleValue: String { unit.format(ml: lastBottleML) }

    /// "Left since 2:15 PM" while the timer runs; "Start on the left" when it isn't.
    var nursingValue: String {
        if let since = nursingSince {
            let side = (nursingSide ?? .left).title
            return "\(side) since \(Format.time(since))"
        }
        return "Start on the \(suggestedSide.title.lowercased())"
    }

    /// "Asleep since 2:15 PM" or "Awake".
    var sleepValue: String {
        if let since = sleepingSince { return "Asleep since \(Format.time(since))" }
        return "Awake"
    }
}
