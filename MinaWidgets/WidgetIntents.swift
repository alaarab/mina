import AppIntents
import CoreData
import WidgetKit

/// Buttons on the widgets and Control Center. They conform to
/// `LiveActivityIntent`, which makes the system perform them in the app's
/// process (launched in the background if needed) rather than the widget's:
/// that is where the feed alarm is re-armed and where CloudKit exports at
/// once. Run in the widget's process instead, a bottle logged from the widget
/// left the alarm armed for the previous feed and it rang anyway.
/// Hidden from Shortcuts, where the app's own intents already cover this.
private func logFromWidget(_ draft: EntryDraft) {
    let context = PersistenceController.shared.container.viewContext
    context.performAndWait {
        guard let baby = Logbook.shared.currentBaby(in: context) else { return }
        _ = try? Logbook.shared.add(draft, to: baby, in: context)
    }
}

struct WidgetLogBottleIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Log last bottle amount"
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        var draft = EntryDraft(kind: .bottle)
        draft.amountML = Prefs.lastBottleML
        logFromWidget(draft)
        return .result()
    }
}

struct WidgetLogPeeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Log a pee"
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        var draft = EntryDraft(kind: .diaper)
        draft.diaper = .wet
        logFromWidget(draft)
        return .result()
    }
}

struct WidgetLogPoopIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Log a poop"
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        var draft = EntryDraft(kind: .diaper)
        draft.diaper = .dirty
        logFromWidget(draft)
        return .result()
    }
}

struct WidgetToggleSleepIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Start or end sleep"
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        let context = PersistenceController.shared.container.viewContext
        context.performAndWait {
            guard let baby = Logbook.shared.currentBaby(in: context) else { return }
            if (try? Logbook.shared.endSleep(for: baby, in: context)) ?? nil != nil { return }
            _ = try? Logbook.shared.add(EntryDraft(kind: .sleep), to: baby, in: context)
        }
        return .result()
    }
}

// MARK: Control Center

/// The Control Center toggles set a state rather than flip one: the system
/// fills in `value` with the side of the switch the parent just tapped, so a
/// stale control can't end a sleep that was meant to start.

struct WidgetSetSleepIntent: SetValueIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Start or end sleep"
    static var isDiscoverable = false

    @Parameter(title: "Asleep")
    var value: Bool

    func perform() async throws -> some IntentResult {
        let context = PersistenceController.shared.container.viewContext
        context.performAndWait {
            guard let baby = Logbook.shared.currentBaby(in: context) else { return }
            if value {
                guard Logbook.shared.ongoingSleep(for: baby, in: context) == nil else { return }
                _ = try? Logbook.shared.add(EntryDraft(kind: .sleep), to: baby, in: context)
            } else {
                _ = try? Logbook.shared.endSleep(for: baby, in: context)
            }
        }
        return .result()
    }
}

struct WidgetSetNursingIntent: SetValueIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Start or stop nursing"
    static var isDiscoverable = false

    @Parameter(title: "Nursing")
    var value: Bool

    func perform() async throws -> some IntentResult {
        let context = PersistenceController.shared.container.viewContext
        context.performAndWait {
            guard let baby = Logbook.shared.currentBaby(in: context) else { return }
            if value {
                _ = try? Logbook.shared.startNursing(side: Prefs.suggestedNursingSide, for: baby, in: context)
            } else if let running = Logbook.shared.ongoingNursing(for: baby, in: context) {
                _ = try? Logbook.shared.endNursing(running, in: context)
            }
        }
        return .result()
    }
}
