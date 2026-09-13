import AppIntents
import CoreData
import WidgetKit

/// Buttons on the widget. These run in the widget's process against the
/// App Group store; the app exports them to iCloud the next time it runs.
/// Hidden from Shortcuts, where the app's own intents already cover this.
private func logFromWidget(_ draft: EntryDraft) {
    let context = PersistenceController.shared.container.viewContext
    context.performAndWait {
        guard let baby = Logbook.shared.currentBaby(in: context) else { return }
        _ = try? Logbook.shared.add(draft, to: baby, in: context)
    }
}

struct WidgetLogBottleIntent: AppIntent {
    static var title: LocalizedStringResource = "Log last bottle amount"
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        var draft = EntryDraft(kind: .bottle)
        draft.amountML = Prefs.lastBottleML
        logFromWidget(draft)
        return .result()
    }
}

struct WidgetLogPeeIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a pee"
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        var draft = EntryDraft(kind: .diaper)
        draft.diaper = .wet
        logFromWidget(draft)
        return .result()
    }
}

struct WidgetLogPoopIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a poop"
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        var draft = EntryDraft(kind: .diaper)
        draft.diaper = .dirty
        logFromWidget(draft)
        return .result()
    }
}

struct WidgetToggleSleepIntent: AppIntent {
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
