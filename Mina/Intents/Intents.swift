import AppIntents
import Foundation

/// Spoken amounts. Each case is a phrase Siri can match without the app
/// running, so the list is a literal rather than something computed.
enum FeedAmount: String, AppEnum {
    case oz1, oz1_5, oz2, oz2_5, oz3, oz3_5, oz4, oz4_5, oz5, oz5_5, oz6, oz6_5, oz7, oz7_5, oz8, oz9, oz10
    case ml30, ml40, ml50, ml60, ml70, ml80, ml90, ml100, ml110, ml120, ml130, ml140, ml150, ml160, ml180, ml200, ml210, ml240, ml270, ml300

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Amount")

    static var caseDisplayRepresentations: [FeedAmount: DisplayRepresentation] = [
        .oz1: DisplayRepresentation(title: "1 ounce", synonyms: ["1 oz", "one ounce"]),
        .oz1_5: DisplayRepresentation(title: "1.5 ounces", synonyms: ["1.5 oz", "one and a half ounces"]),
        .oz2: DisplayRepresentation(title: "2 ounces", synonyms: ["2 oz", "two ounces"]),
        .oz2_5: DisplayRepresentation(title: "2.5 ounces", synonyms: ["2.5 oz", "two and a half ounces"]),
        .oz3: DisplayRepresentation(title: "3 ounces", synonyms: ["3 oz", "three ounces"]),
        .oz3_5: DisplayRepresentation(title: "3.5 ounces", synonyms: ["3.5 oz", "three and a half ounces"]),
        .oz4: DisplayRepresentation(title: "4 ounces", synonyms: ["4 oz", "four ounces"]),
        .oz4_5: DisplayRepresentation(title: "4.5 ounces", synonyms: ["4.5 oz", "four and a half ounces"]),
        .oz5: DisplayRepresentation(title: "5 ounces", synonyms: ["5 oz", "five ounces"]),
        .oz5_5: DisplayRepresentation(title: "5.5 ounces", synonyms: ["5.5 oz", "five and a half ounces"]),
        .oz6: DisplayRepresentation(title: "6 ounces", synonyms: ["6 oz", "six ounces"]),
        .oz6_5: DisplayRepresentation(title: "6.5 ounces", synonyms: ["6.5 oz", "six and a half ounces"]),
        .oz7: DisplayRepresentation(title: "7 ounces", synonyms: ["7 oz", "seven ounces"]),
        .oz7_5: DisplayRepresentation(title: "7.5 ounces", synonyms: ["7.5 oz", "seven and a half ounces"]),
        .oz8: DisplayRepresentation(title: "8 ounces", synonyms: ["8 oz", "eight ounces"]),
        .oz9: DisplayRepresentation(title: "9 ounces", synonyms: ["9 oz", "nine ounces"]),
        .oz10: DisplayRepresentation(title: "10 ounces", synonyms: ["10 oz", "ten ounces"]),
        .ml30: DisplayRepresentation(title: "30 milliliters", synonyms: ["30 ml", "thirty milliliters"]),
        .ml40: DisplayRepresentation(title: "40 milliliters", synonyms: ["40 ml", "forty milliliters"]),
        .ml50: DisplayRepresentation(title: "50 milliliters", synonyms: ["50 ml", "fifty milliliters"]),
        .ml60: DisplayRepresentation(title: "60 milliliters", synonyms: ["60 ml", "sixty milliliters"]),
        .ml70: DisplayRepresentation(title: "70 milliliters", synonyms: ["70 ml", "seventy milliliters"]),
        .ml80: DisplayRepresentation(title: "80 milliliters", synonyms: ["80 ml", "eighty milliliters"]),
        .ml90: DisplayRepresentation(title: "90 milliliters", synonyms: ["90 ml", "ninety milliliters"]),
        .ml100: DisplayRepresentation(title: "100 milliliters", synonyms: ["100 ml", "one hundred milliliters"]),
        .ml110: DisplayRepresentation(title: "110 milliliters", synonyms: ["110 ml"]),
        .ml120: DisplayRepresentation(title: "120 milliliters", synonyms: ["120 ml"]),
        .ml130: DisplayRepresentation(title: "130 milliliters", synonyms: ["130 ml"]),
        .ml140: DisplayRepresentation(title: "140 milliliters", synonyms: ["140 ml"]),
        .ml150: DisplayRepresentation(title: "150 milliliters", synonyms: ["150 ml"]),
        .ml160: DisplayRepresentation(title: "160 milliliters", synonyms: ["160 ml"]),
        .ml180: DisplayRepresentation(title: "180 milliliters", synonyms: ["180 ml"]),
        .ml200: DisplayRepresentation(title: "200 milliliters", synonyms: ["200 ml"]),
        .ml210: DisplayRepresentation(title: "210 milliliters", synonyms: ["210 ml"]),
        .ml240: DisplayRepresentation(title: "240 milliliters", synonyms: ["240 ml"]),
        .ml270: DisplayRepresentation(title: "270 milliliters", synonyms: ["270 ml"]),
        .ml300: DisplayRepresentation(title: "300 milliliters", synonyms: ["300 ml"]),
    ]

    var milliliters: Double {
        if rawValue.hasPrefix("oz") {
            let number = Double(rawValue.dropFirst(2).replacingOccurrences(of: "_", with: ".")) ?? 0
            return number * VolumeUnit.millilitersPerOunce
        }
        return Double(rawValue.dropFirst(2)) ?? 0
    }
}

extension NursingSide: AppEnum {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Side")
    static var caseDisplayRepresentations: [NursingSide: DisplayRepresentation] = [
        .left: "left", .right: "right", .both: "both",
    ]
}

extension DiaperKind: AppEnum {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Diaper")
    static var caseDisplayRepresentations: [DiaperKind: DisplayRepresentation] = [
        .wet: DisplayRepresentation(title: "wet", synonyms: ["pee"]),
        .dirty: DisplayRepresentation(title: "dirty", synonyms: ["poopy", "poop", "poo"]),
        .both: DisplayRepresentation(title: "wet and dirty", synonyms: ["both", "full"]),
    ]
}

struct LogBottleIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a bottle"
    static var description = IntentDescription("Records how much she drank from a bottle, right now.")
    static var openAppWhenRun = false

    @Parameter(title: "Amount", requestValueDialog: "How much did she drink?")
    var amount: FeedAmount

    static var parameterSummary: some ParameterSummary { Summary("Log a \(\.$amount) bottle") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let milliliters = amount.milliliters
        let snapshot = try await Logbook.shared.perform { context, baby in
            var draft = EntryDraft(kind: .bottle)
            draft.amountML = milliliters
            return EntrySnapshot(entry: try Logbook.shared.add(draft, to: baby, in: context))
        }
        Prefs.rememberBottle(ml: milliliters)
        let amountText = Prefs.unit.format(ml: milliliters)
        return .result(dialog: "Logged \(amountText) for \(snapshot.babyName) at \(Format.time(snapshot.startedAt)).")
    }
}

struct LogNursingIntent: AppIntent {
    static var title: LocalizedStringResource = "Log nursing"
    static var description = IntentDescription("Records a nursing session that just finished.")
    static var openAppWhenRun = false

    @Parameter(title: "Side", requestValueDialog: "Which side?")
    var side: NursingSide

    @Parameter(title: "Minutes")
    var minutes: Int?

    static var parameterSummary: some ParameterSummary { Summary("Log nursing on the \(\.$side) for \(\.$minutes) minutes") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let side = side
        let minutes = minutes
        let snapshot = try await Logbook.shared.perform { context, baby in
            let now = Date.now
            var draft = EntryDraft(kind: .nursing, startedAt: minutes.map { now.addingTimeInterval(-Double($0) * 60) } ?? now)
            draft.side = side
            draft.endedAt = minutes == nil ? nil : now
            return EntrySnapshot(entry: try Logbook.shared.add(draft, to: baby, in: context))
        }
        var text = "Logged nursing on the \(side.title.lowercased())"
        if let minutes { text += " for \(minutes) minutes" }
        return .result(dialog: "\(text) for \(snapshot.babyName).")
    }
}

struct LogDiaperIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a diaper"
    static var description = IntentDescription("Records a diaper change.")
    static var openAppWhenRun = false

    @Parameter(title: "Diaper", requestValueDialog: "Wet, dirty, or both?")
    var kind: DiaperKind

    static var parameterSummary: some ParameterSummary { Summary("Log a \(\.$kind) diaper") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "\(try await logDiaper(kind))")
    }
}

/// Shared by the diaper intents so "Mina peed" and "Mina had a wet diaper" do the same thing.
private func logDiaper(_ kind: DiaperKind) async throws -> String {
    let snapshot = try await Logbook.shared.perform { context, baby in
        var draft = EntryDraft(kind: .diaper)
        draft.diaper = kind
        return EntrySnapshot(entry: try Logbook.shared.add(draft, to: baby, in: context))
    }
    return "Logged a \(kind.title.lowercased()) diaper for \(snapshot.babyName) at \(Format.time(snapshot.startedAt))."
}

struct LogPeeIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a pee"
    static var description = IntentDescription("Records a wet diaper.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "\(try await logDiaper(.wet))")
    }
}

struct LogPoopIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a poop"
    static var description = IntentDescription("Records a dirty diaper.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "\(try await logDiaper(.dirty))")
    }
}

struct LogPeeAndPoopIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a pee and poop"
    static var description = IntentDescription("Records a diaper that was both wet and dirty.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "\(try await logDiaper(.both))")
    }
}

struct StartSleepIntent: AppIntent {
    static var title: LocalizedStringResource = "Start sleep"
    static var description = IntentDescription("Marks her as asleep from now.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let (name, ongoingSince) = try await Logbook.shared.perform { context, baby -> (String, Date?) in
            if let sleeping = Logbook.shared.ongoingSleep(for: baby, in: context) {
                return (baby.displayName, sleeping.startedAt)
            }
            try Logbook.shared.add(EntryDraft(kind: .sleep), to: baby, in: context)
            return (baby.displayName, nil)
        }
        if let ongoingSince {
            return .result(dialog: "\(name) has already been asleep for \(Format.duration(Date.now.timeIntervalSince(ongoingSince))).")
        }
        return .result(dialog: "\(name)'s sleep started at \(Format.time(.now)).")
    }
}

struct EndSleepIntent: AppIntent {
    static var title: LocalizedStringResource = "End sleep"
    static var description = IntentDescription("Marks her as awake and closes the current sleep.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let (name, slept) = try await Logbook.shared.perform { context, baby -> (String, TimeInterval?) in
            let ended = try Logbook.shared.endSleep(for: baby, in: context)
            return (baby.displayName, ended?.duration())
        }
        guard let slept else { return .result(dialog: "\(name) wasn't marked as asleep.") }
        return .result(dialog: "\(name) is up. She slept \(Format.duration(slept)).")
    }
}

struct LogWeightIntent: AppIntent {
    static var title: LocalizedStringResource = "Log weight"
    static var description = IntentDescription("Records a weight as a growth entry.")
    static var openAppWhenRun = false

    @Parameter(title: "Weight", requestValueDialog: "How much does she weigh?")
    var weight: BabyWeight

    static var parameterSummary: some ParameterSummary { Summary("Log a weight of \(\.$weight)") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let grams = weight.grams
        let snapshot = try await Logbook.shared.perform { context, baby in
            var draft = EntryDraft(kind: .growth)
            draft.weightGrams = grams
            return EntrySnapshot(entry: try Logbook.shared.add(draft, to: baby, in: context))
        }
        return .result(dialog: "Logged \(Measure.weight(grams: grams, unit: Prefs.unit) ?? "") for \(snapshot.babyName).")
    }
}

struct FeedStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Last feed"
    static var description = IntentDescription("Says when she last ate and how today is going.")
    static var openAppWhenRun = false

    @Parameter(title: "Day")
    var day: RelativeDay?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        if let day, day == .yesterday {
            let entity = try await DaySummaryEntity.load(day: day.date())
            return .result(dialog: "Yesterday, \(entity.spoken)")
        }
        let now = Date.now
        let (name, last, lastPoop, summary) = try await Logbook.shared.perform { context, baby -> (String, EntrySnapshot?, Date?, DaySummary) in
            let last = Logbook.shared.lastFeed(for: baby, in: context).map(EntrySnapshot.init)
            let lastPoop = Logbook.shared.lastDirtyDiaper(for: baby, in: context)?.startedAt
            let start = Calendar.current.startOfDay(for: now)
            let entries = Logbook.shared.entries(for: baby, from: Calendar.current.date(byAdding: .day, value: -1, to: start) ?? start, in: context)
            return (baby.displayName, last, lastPoop, DaySummary(entries: entries, day: now, now: now))
        }
        let unit = Prefs.unit
        var text: String
        if let last {
            text = "\(name) last ate \(Format.ago(from: last.startedAt, to: now))"
            if last.kind == .bottle, last.amountML > 0 { text += ", a \(unit.format(ml: last.amountML)) bottle" }
            else if last.kind == .nursing { text += ", nursing" + (last.side.map { " on the \($0.title.lowercased())" } ?? "") }
            text += " at \(Format.time(last.startedAt))."
        } else {
            text = "No feeds logged for \(name) yet."
        }
        if summary.feeds > 0 {
            text += " Today: \(summary.feeds) \(summary.feeds == 1 ? "feed" : "feeds")"
            if summary.bottleML > 0 { text += ", \(unit.format(ml: summary.bottleML)) by bottle" }
            text += ", \(summary.wet) wet and \(summary.dirty) dirty \(summary.diapers == 1 ? "diaper" : "diapers")."
        }
        if let lastPoop { text += " Last poop \(Format.ago(from: lastPoop, to: now))." }
        return .result(dialog: "\(text)")
    }
}

struct MinaShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .pink

    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogBottleIntent(), phrases: [
            "\(.applicationName) ate \(\.$amount)",
            "\(.applicationName) just ate \(\.$amount)",
            "\(.applicationName) drank \(\.$amount)",
            "\(.applicationName) just drank \(\.$amount)",
            "\(.applicationName) had \(\.$amount)",
            "\(.applicationName) just had \(\.$amount)",
            "\(.applicationName) took \(\.$amount)",
            "We fed \(.applicationName) \(\.$amount)",
            "Log \(\.$amount) in \(.applicationName)",
            "\(.applicationName) ate",
        ], shortTitle: "Log a bottle", systemImageName: "waterbottle.fill")

        AppShortcut(intent: LogNursingIntent(), phrases: [
            "\(.applicationName) nursed on the \(\.$side)",
            "\(.applicationName) nursed \(\.$side)",
            "\(.applicationName) fed on the \(\.$side)",
            "\(.applicationName) nursed",
            "Log nursing in \(.applicationName)",
        ], shortTitle: "Log nursing", systemImageName: "heart.fill")

        AppShortcut(intent: LogDiaperIntent(), phrases: [
            "\(.applicationName) had a \(\.$kind) diaper",
            "\(.applicationName) has a \(\.$kind) diaper",
            "Log a \(\.$kind) diaper in \(.applicationName)",
            "\(.applicationName) had a diaper",
            "Log a diaper in \(.applicationName)",
        ], shortTitle: "Log a diaper", systemImageName: "drop.fill")

        AppShortcut(intent: LogPeeIntent(), phrases: [
            "\(.applicationName) just peed",
            "\(.applicationName) peed",
            "\(.applicationName) had a pee",
            "\(.applicationName) did a pee",
            "\(.applicationName) is wet",
        ], shortTitle: "Log a pee", systemImageName: "drop.fill")

        AppShortcut(intent: LogPoopIntent(), phrases: [
            "\(.applicationName) just pooped",
            "\(.applicationName) pooped",
            "\(.applicationName) had a poop",
            "\(.applicationName) did a poo",
            "\(.applicationName) had a poopy diaper",
        ], shortTitle: "Log a poop", systemImageName: "drop.circle.fill")

        AppShortcut(intent: LogPeeAndPoopIntent(), phrases: [
            "\(.applicationName) peed and pooped",
            "\(.applicationName) pooped and peed",
            "\(.applicationName) just peed and pooped",
            "\(.applicationName) did both",
        ], shortTitle: "Log pee and poop", systemImageName: "drop.triangle.fill")

        AppShortcut(intent: StartSleepIntent(), phrases: [
            "\(.applicationName) is asleep",
            "\(.applicationName) fell asleep",
            "\(.applicationName) is napping",
            "\(.applicationName) went down",
            "Start sleep in \(.applicationName)",
        ], shortTitle: "Start sleep", systemImageName: "moon.zzz.fill")

        AppShortcut(intent: EndSleepIntent(), phrases: [
            "\(.applicationName) is awake",
            "\(.applicationName) woke up",
            "\(.applicationName) is up",
            "End sleep in \(.applicationName)",
        ], shortTitle: "End sleep", systemImageName: "sun.max.fill")

        AppShortcut(intent: LogWeightIntent(), phrases: [
            "\(.applicationName) weighs \(\.$weight)",
            "\(.applicationName) is \(\.$weight)",
            "\(.applicationName) weighed \(\.$weight)",
            "\(.applicationName) weighs",
            "Log \(.applicationName)'s weight",
        ], shortTitle: "Log weight", systemImageName: "scalemass.fill")

        AppShortcut(intent: FeedStatusIntent(), phrases: [
            "When did \(.applicationName) last eat",
            "When did \(.applicationName) eat",
            "When was \(.applicationName) fed",
            "How much has \(.applicationName) eaten today",
            "How is \(.applicationName) doing today",
            "When did \(.applicationName) last poop",
            "How many diapers has \(.applicationName) had today",
            "How much did \(.applicationName) eat \(\.$day)",
            "How did \(.applicationName) sleep \(\.$day)",
            "How was \(.applicationName)'s day \(\.$day)",
        ], shortTitle: "Last feed", systemImageName: "clock.fill")
    }
}
