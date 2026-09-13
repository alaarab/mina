import CoreData
import XCTest
@testable import Mina

/// One class per thing that can quietly go wrong: the pure value work
/// (formatting, guidance ranges, predictions, grouping) tested directly, and
/// the Core Data paths tested against an in-memory store.

final class UnitTests: XCTestCase {
    func testOunceFormatting() {
        XCTAssertEqual(VolumeUnit.ounces.format(ml: 4 * VolumeUnit.millilitersPerOunce), "4 oz")
        XCTAssertEqual(VolumeUnit.ounces.format(ml: 4.5 * VolumeUnit.millilitersPerOunce), "4.5 oz")
        XCTAssertEqual(VolumeUnit.ounces.format(ml: 4.3 * VolumeUnit.millilitersPerOunce), "4.25 oz")
        XCTAssertEqual(VolumeUnit.milliliters.format(ml: 118.3), "118 ml")
    }

    func testCountPluralises() {
        XCTAssertEqual(Format.count(1, "feed"), "1 feed")
        XCTAssertEqual(Format.count(0, "feed"), "0 feeds")
        XCTAssertEqual(Format.count(2, "diaper"), "2 diapers")
        XCTAssertEqual(Format.count(1, "stretch", "stretches"), "1 stretch")
        XCTAssertEqual(Format.count(3, "stretch", "stretches"), "3 stretches")
    }

    func testFeedAmountConversions() {
        XCTAssertEqual(FeedAmount.oz4.milliliters, 4 * VolumeUnit.millilitersPerOunce, accuracy: 0.001)
        XCTAssertEqual(FeedAmount.oz2_5.milliliters, 2.5 * VolumeUnit.millilitersPerOunce, accuracy: 0.001)
        XCTAssertEqual(FeedAmount.ml120.milliliters, 120)
        XCTAssertEqual(FeedAmount.ml37.milliliters, 37)
        XCTAssertEqual(FeedAmount.allCases.count, 19 + 291)
        XCTAssertEqual(VolumeUnit.milliliters.step, 1)
        for amount in FeedAmount.allCases {
            XCTAssertGreaterThan(amount.milliliters, 0, "\(amount.rawValue) has no volume")
            XCTAssertNotNil(FeedAmount.caseDisplayRepresentations[amount], "\(amount.rawValue) has no spoken form")
        }
    }
}

final class GuidanceTests: XCTestCase {
    func testStagesCoverEveryDayWithoutGaps() {
        var expectedStart = 0
        for stage in Guidance.stages {
            XCTAssertEqual(stage.ageDays.lowerBound, expectedStart, "\(stage.id) starts at \(stage.ageDays.lowerBound)")
            expectedStart = stage.ageDays.upperBound + 1
        }
        XCTAssertEqual(Guidance.stage(forAgeDays: 0).id, "days-1-3")
        XCTAssertEqual(Guidance.stage(forAgeDays: 20).id, "weeks-3-4")
        XCTAssertEqual(Guidance.stage(forAgeDays: 5000).id, Guidance.stages.last?.id)
        XCTAssertEqual(Guidance.stage(forAgeDays: -3).id, "days-1-3")
    }

    func testExpectationText() {
        let stage = Guidance.stage(forAgeDays: 20)
        XCTAssertEqual(stage.expectation.feedsText(), "7–10 a day")
        XCTAssertEqual(stage.expectation.perFeedText(unit: .ounces), "3–4 oz each")
        XCTAssertEqual(stage.expectation.perFeedText(unit: .milliliters), "90–120 ml each")
    }
}

final class CalendarTests: XCTestCase {
    func testMonthGridShape() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let september = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let cells = MonthGrid.cells(for: september, calendar: calendar)
        XCTAssertEqual(cells.count % 7, 0)
        XCTAssertEqual(cells.compactMap { $0 }.count, 30)
        // 1 September 2026 is a Tuesday, so two leading blanks with a Sunday start.
        XCTAssertNil(cells[0]); XCTAssertNil(cells[1]); XCTAssertEqual(cells[2], september)
        XCTAssertEqual(MonthGrid.weekdaySymbols(calendar: calendar).first, calendar.veryShortStandaloneWeekdaySymbols[0])
    }
}

final class LogbookTests: XCTestCase {
    private var persistence: PersistenceController!
    private var logbook: Logbook!
    private var context: NSManagedObjectContext!
    private var baby: Baby!
    private let calendar = Calendar.current
    private var day: Date { calendar.startOfDay(for: Date(timeIntervalSince1970: 1_780_000_000)) }

    override func setUpWithError() throws {
        persistence = PersistenceController(inMemory: true)
        XCTAssertNil(persistence.loadError)
        logbook = Logbook(persistence: persistence)
        context = persistence.container.viewContext
        baby = try logbook.createBaby(name: "Test", birthDate: calendar.date(byAdding: .day, value: -16, to: day)!, in: context)
    }

    private func add(_ kind: EntryKind, at offset: TimeInterval, configure: (inout EntryDraft) -> Void = { _ in }) throws {
        var draft = EntryDraft(kind: kind, startedAt: day.addingTimeInterval(offset))
        configure(&draft)
        try logbook.add(draft, to: baby, in: context)
    }

    func testDaySummaryCountsAndClipsSleep() throws {
        try add(.bottle, at: 2 * 3600) { $0.amountML = 120 }
        try add(.nursing, at: 5 * 3600) { $0.side = .left; $0.endedAt = self.day.addingTimeInterval(5 * 3600 + 900) }
        try add(.diaper, at: 6 * 3600) { $0.diaper = .both }
        try add(.diaper, at: 7 * 3600) { $0.diaper = .wet }
        try add(.sleep, at: -3600) { $0.endedAt = self.day.addingTimeInterval(3600) }
        try add(.note, at: 8 * 3600) { $0.note = "first smile" }
        try add(.bottle, at: 26 * 3600) { $0.amountML = 999 } // tomorrow, must not count

        let entries = logbook.entries(for: baby, from: day.addingTimeInterval(-86_400), in: context)
        let summary = DaySummary(entries: entries, day: day, now: day.addingTimeInterval(12 * 3600))
        XCTAssertEqual(summary.feeds, 2)
        XCTAssertEqual(summary.bottleML, 120)
        XCTAssertEqual(summary.nursingSeconds, 900)
        XCTAssertEqual(summary.diapers, 2)
        XCTAssertEqual(summary.wet, 2)
        XCTAssertEqual(summary.dirty, 1)
        XCTAssertEqual(summary.sleepSeconds, 3600, "overnight sleep is clipped to the day")
        XCTAssertEqual(summary.notes, 1)
        XCTAssertEqual(summary.lastFeedAt, day.addingTimeInterval(5 * 3600))
    }

    func testOngoingSleepStartsAndEnds() throws {
        XCTAssertNil(logbook.ongoingSleep(for: baby, in: context))
        try add(.sleep, at: 0)
        let sleeping = try XCTUnwrap(logbook.ongoingSleep(for: baby, in: context))
        XCTAssertTrue(sleeping.isOngoingSleep)
        let ended = try XCTUnwrap(logbook.endSleep(for: baby, at: day.addingTimeInterval(1800), in: context))
        XCTAssertEqual(ended.duration(), 1800)
        XCTAssertNil(logbook.ongoingSleep(for: baby, in: context))
        XCTAssertNil(try logbook.endSleep(for: baby, in: context))
    }

    func testLastFeedIgnoresDiapersAndTitles() throws {
        try add(.bottle, at: 1000) { $0.amountML = 4 * VolumeUnit.millilitersPerOunce }
        try add(.diaper, at: 2000) { $0.diaper = .dirty }
        let last = try XCTUnwrap(logbook.lastFeed(for: baby, in: context))
        XCTAssertEqual(last.kind, .bottle)
        XCTAssertEqual(last.title(unit: .ounces), "Bottle · 4 oz")
        XCTAssertEqual(baby.ageDescription(on: day), "2 weeks, 2 days old")
        XCTAssertEqual(baby.ageDays(on: day), 16)
    }

    func testBackgroundPerformFindsBabyAndDeleteRemoves() async throws {
        let snapshot = try await logbook.perform { context, baby in
            var draft = EntryDraft(kind: .bottle)
            draft.amountML = 90
            return EntrySnapshot(entry: try self.logbook.add(draft, to: baby, in: context))
        }
        XCTAssertEqual(snapshot.amountML, 90)
        XCTAssertEqual(snapshot.babyName, "Test")

        context.refreshAllObjects()
        let entries = logbook.entries(for: baby, from: .distantPast, in: context)
        XCTAssertEqual(entries.count, 1)
        try logbook.delete(entries[0], in: context)
        XCTAssertEqual(logbook.entries(for: baby, from: .distantPast, in: context).count, 0)
    }
}


final class MeasureTests: XCTestCase {
    func testWeightAndLengthFormatting() {
        XCTAssertEqual(Measure.weight(grams: (7 * 16 + 4) * Measure.gramsPerOunce, unit: .imperial), "7 lb 4 oz")
        XCTAssertEqual(Measure.weight(grams: 3290, unit: .metric), "3.29 kg")
        XCTAssertNil(Measure.weight(grams: 0, unit: .imperial))
        XCTAssertEqual(Measure.length(cm: 20 * Measure.cmPerInch, unit: .imperial, label: ""), "20 in")
        XCTAssertEqual(Measure.length(cm: 50.8, unit: .metric, label: "head"), "head 50.8 cm")
        XCTAssertEqual(Measure.temperature(celsius: 38, unit: .metric), "38 °C")
        XCTAssertEqual(Measure.celsius(fromDisplay: 100.4, unit: .imperial), 38, accuracy: 0.01)
    }
}

final class PartnerAlertTests: XCTestCase {
    func testMessagesNameThePartnerAndTheEntry() throws {
        let persistence = PersistenceController(inMemory: true)
        let logbook = Logbook(persistence: persistence)
        let context = persistence.container.viewContext
        let baby = try logbook.createBaby(name: "Mina", birthDate: .now, in: context)
        let at = Calendar.current.date(bySettingHour: 14, minute: 15, second: 0, of: .now)!

        var bottle = EntryDraft(kind: .bottle, startedAt: at)
        bottle.amountML = 4 * VolumeUnit.millilitersPerOunce
        bottle.loggedBy = "Mom"
        let bottleMessage = PartnerAlerts.message(for: try logbook.add(bottle, to: baby, in: context), unit: .ounces)
        XCTAssertEqual(bottleMessage.title, "Mom fed Mina")
        XCTAssertEqual(bottleMessage.body, "4 oz bottle at \(Format.time(at))")

        var diaper = EntryDraft(kind: .diaper, startedAt: at)
        diaper.diaper = .dirty
        diaper.loggedBy = ""
        let diaperMessage = PartnerAlerts.message(for: try logbook.add(diaper, to: baby, in: context), unit: .ounces)
        XCTAssertEqual(diaperMessage.title, "Your partner changed Mina")
        XCTAssertEqual(diaperMessage.body, "Dirty diaper at \(Format.time(at))")

        let sleep = try logbook.add(EntryDraft(kind: .sleep, startedAt: at), to: baby, in: context)
        XCTAssertEqual(PartnerAlerts.message(for: sleep, unit: .ounces).title, "Mina is asleep")

        var pumping = EntryDraft(kind: .pumping, startedAt: at)
        pumping.amountML = 90; pumping.side = .both
        let pumped = try logbook.add(pumping, to: baby, in: context)
        XCTAssertEqual(pumped.title(unit: .milliliters), "Pumped · 90 ml · both")
        XCTAssertFalse(pumped.isFromPartner, "entries made on this phone carry its own device id")
    }
}

final class PredictorTests: XCTestCase {
    func testMedianIntervalFromRecentFeeds() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let times = [0, 3, 6, 8.5, 12].map { now.addingTimeInterval(-$0 * 3600) }  // gaps 3h, 3h, 2.5h, 3.5h
        let prediction = try XCTUnwrap(Predictor.nextFeed(feedTimes: times, stage: nil, now: now))
        XCTAssertEqual(prediction.interval, 3 * 3600, accuracy: 1)
        XCTAssertEqual(prediction.expectedAt, now.addingTimeInterval(3 * 3600))
        XCTAssertEqual(prediction.basis, "her last 5 feeds")
    }

    func testFallsBackToAgeNormWithFewFeeds() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let stage = Guidance.stage(forAgeDays: 20)  // 7–10 feeds a day
        let prediction = try XCTUnwrap(Predictor.nextFeed(feedTimes: [now.addingTimeInterval(-3600)], stage: stage, now: now))
        XCTAssertEqual(prediction.interval, 86_400 / 8.5, accuracy: 1)
        XCTAssertTrue(prediction.basis.contains("typical"))
        XCTAssertNil(Predictor.nextFeed(feedTimes: [], stage: stage, now: now))
    }

    func testNapWindowGrowsWithAge() {
        XCTAssertEqual(Predictor.wakeWindow(ageDays: 10), 50 * 60)
        XCTAssertEqual(Predictor.wakeWindow(ageDays: 100), 105 * 60)
        let wake = Date(timeIntervalSince1970: 1_780_000_000)
        XCTAssertEqual(Predictor.nextNap(lastWake: wake, ageDays: 40, now: wake)?.expectedAt, wake.addingTimeInterval(75 * 60))
        XCTAssertNil(Predictor.nextNap(lastWake: nil, ageDays: 40))
        XCTAssertEqual(Predictor.phrase(for: wake.addingTimeInterval(35 * 60), now: wake), "in 35m")
        XCTAssertEqual(Predictor.phrase(for: wake.addingTimeInterval(-20 * 60), now: wake), "20m ago")
    }
}


final class NanitTests: XCTestCase {
    func testMessagesDecodeWithUnixTimeAndUnknownFields() throws {
        let json = """
        {"messages":[{"id":11,"baby_uid":"abc","user_id":5,"type":"SOUND","time":1780000000,"read_at":null,"data":{"x":1}},
                     {"id":12,"type":"ASLEEP","time":1780003600}]}
        """
        struct Payload: Decodable { let messages: [NanitMessage] }
        let messages = try JSONDecoder().decode(Payload.self, from: Data(json.utf8)).messages
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[1].type, "ASLEEP")
        XCTAssertEqual(messages[1].time, Date(timeIntervalSince1970: 1_780_003_600))
    }

    func testSleepEventsPairStartsWithWakes() {
        let base = Date(timeIntervalSince1970: 1_780_000_000)
        let messages = [
            NanitMessage(id: 1, type: "MOTION", time: base),
            NanitMessage(id: 2, type: "ASLEEP", time: base.addingTimeInterval(600)),
            NanitMessage(id: 3, type: "SOUND", time: base.addingTimeInterval(900)),
            NanitMessage(id: 4, type: "AWAKE", time: base.addingTimeInterval(4200)),
            NanitMessage(id: 5, type: "SLEEP_START", time: base.addingTimeInterval(9000)),
        ]
        let events = NanitEventMapper.sleepEvents(from: messages.shuffled())
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].startID, 2)
        XCTAssertEqual(events[0].endID, 4)
        XCTAssertEqual(events[0].end, base.addingTimeInterval(4200))
        XCTAssertEqual(events[1].startID, 5)
        XCTAssertNil(events[1].end)
        XCTAssertFalse(NanitEventMapper.isSleepStart("AWAKE"))
        XCTAssertTrue(NanitEventMapper.isWake("WOKE_UP"))
    }
}


final class BabyWeightTests: XCTestCase {
    func testGramsAndSpokenForms() {
        XCTAssertEqual(BabyWeight.lb7oz4.grams, (7 * 16 + 4) * Measure.gramsPerOunce, accuracy: 0.001)
        XCTAssertEqual(BabyWeight.lb5oz0.grams, 80 * Measure.gramsPerOunce, accuracy: 0.001)
        XCTAssertEqual(BabyWeight.allCases.count, 11 * 16)
        XCTAssertEqual(Measure.weight(grams: BabyWeight.lb7oz4.grams, unit: .imperial), "7 lb 4 oz")
        for weight in BabyWeight.allCases {
            XCTAssertNotNil(BabyWeight.caseDisplayRepresentations[weight], "\(weight.rawValue) has no spoken form")
        }
    }
}


final class AskContextTests: XCTestCase {
    func testContextListsStageAndDays() throws {
        let persistence = PersistenceController(inMemory: true)
        let logbook = Logbook(persistence: persistence)
        let context = persistence.container.viewContext
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let baby = try logbook.createBaby(name: "Test", birthDate: now.addingTimeInterval(-20 * 86_400), in: context)
        var draft = EntryDraft(kind: .bottle, startedAt: now.addingTimeInterval(-3600))
        draft.amountML = 120
        try logbook.add(draft, to: baby, in: context)
        let entries = logbook.entries(for: baby, from: .distantPast, in: context)
        let stats = TrendMath.stats(entries: entries, days: 3, now: now)
        let text = AskContext.build(babyName: "Test", age: baby.ageDescription(on: now), stage: Guidance.stage(forAgeDays: 20), stats: stats, recent: ["now: Bottle · 4 oz"], unit: .ounces)
        XCTAssertTrue(text.contains("Stage: Weeks 3–4"))
        XCTAssertTrue(text.contains("4 oz"), "today's bottle total should appear")
        XCTAssertEqual(text.components(separatedBy: "\n").filter { $0.contains(": ") && $0.contains(", ") }.count >= 3, true)
        XCTAssertTrue(AskContext.instructions.contains("Never diagnose"))
    }

    func testRelativeDay() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        XCTAssertEqual(RelativeDay.today.date(now: now), now)
        XCTAssertEqual(RelativeDay.yesterday.date(now: now), Calendar.current.date(byAdding: .day, value: -1, to: now))
    }
}


final class NursingTimerTests: XCTestCase {
    func testTimerSwitchesSidesAndSummarizes() throws {
        let persistence = PersistenceController(inMemory: true)
        let logbook = Logbook(persistence: persistence)
        let context = persistence.container.viewContext
        let baby = try logbook.createBaby(name: "Test", birthDate: .now, in: context)
        let start = Date(timeIntervalSince1970: 1_780_000_000)

        let entry = try logbook.startNursing(side: .left, for: baby, at: start, in: context)
        XCTAssertTrue(entry.isOngoingNursing)
        XCTAssertEqual(entry.duration(now: start.addingTimeInterval(300)), 300, "an open nursing counts up to now")
        XCTAssertEqual(try logbook.startNursing(side: .right, for: baby, at: start, in: context), entry, "only one timer at a time")

        try logbook.switchNursingSide(entry, at: start.addingTimeInterval(480), in: context)
        XCTAssertEqual(entry.side, .both)
        try logbook.endNursing(entry, at: start.addingTimeInterval(840), in: context)
        XCTAssertEqual(entry.label, "left 8m · right 6m")
        XCTAssertEqual(Prefs.lastNursingSide, .right)
        XCTAssertEqual(Prefs.suggestedNursingSide, .left)
        XCTAssertNil(logbook.ongoingNursing(for: baby, in: context))

        let summary = DaySummary(entries: [entry], day: start, now: start.addingTimeInterval(3600))
        XCTAssertEqual(summary.feeds, 1)
        XCTAssertEqual(summary.nursingSeconds, 840)
    }
}


final class DayGroupingTests: XCTestCase {
    private var persistence: PersistenceController!
    private var logbook: Logbook!
    private var context: NSManagedObjectContext!
    private var baby: Baby!
    private let calendar = Calendar.current
    private var day: Date { calendar.startOfDay(for: Date(timeIntervalSince1970: 1_780_000_000)) }
    private var yesterday: Date { calendar.date(byAdding: .day, value: -1, to: day)! }

    override func setUpWithError() throws {
        persistence = PersistenceController(inMemory: true)
        logbook = Logbook(persistence: persistence)
        context = persistence.container.viewContext
        baby = try logbook.createBaby(name: "Test", birthDate: day, in: context)
    }

    private func entry(_ kind: EntryKind, at date: Date) throws -> LogEntry {
        try logbook.add(EntryDraft(kind: kind, startedAt: date), to: baby, in: context)
    }

    /// Entries arrive newest first, the way every fetch in the app sorts them.
    private func fetchOrder() throws -> [LogEntry] {
        let morning = try entry(.bottle, at: day.addingTimeInterval(9 * 3600))
        let dawn = try entry(.diaper, at: day.addingTimeInterval(2 * 3600))
        let lastNight = try entry(.sleep, at: day.addingTimeInterval(-5 * 3600))
        return [morning, dawn, lastNight]
    }

    func testByDayBucketsOnTheStartOfTheDay() throws {
        let entries = try fetchOrder()
        let byDay = DayGrouping.byDay(entries, calendar: calendar)
        XCTAssertEqual(byDay.count, 2)
        XCTAssertEqual(byDay[day]?.count, 2)
        XCTAssertEqual(byDay[yesterday]?.count, 1)
        XCTAssertNil(byDay[calendar.date(byAdding: .day, value: 1, to: day)!])
    }

    func testDaysComeBackNewestFirstAndKeepTheirOrder() throws {
        let entries = try fetchOrder()
        let days = DayGrouping.days(entries, calendar: calendar)
        XCTAssertEqual(days.map(\.day), [day, yesterday])
        XCTAssertEqual(days[0].entries, [entries[0], entries[1]], "entries keep the order they arrived in")
        XCTAssertEqual(days[1].entries, [entries[2]])
    }

    func testDayRunsAreIndexRangesIntoTheCollection() throws {
        let entries = try fetchOrder()
        let runs = DayGrouping.dayRuns(entries, calendar: calendar)
        XCTAssertEqual(runs.map(\.day), [day, yesterday])
        XCTAssertEqual(runs[0].range, 0..<2)
        XCTAssertEqual(runs[1].range, 2..<3)
        XCTAssertEqual(runs.reduce(0) { $0 + $1.range.count }, entries.count, "every entry lands in exactly one run")
    }

    func testNothingToGroup() {
        XCTAssertTrue(DayGrouping.byDay([LogEntry](), calendar: calendar).isEmpty)
        XCTAssertTrue(DayGrouping.days([LogEntry](), calendar: calendar).isEmpty)
        XCTAssertTrue(DayGrouping.dayRuns([LogEntry](), calendar: calendar).isEmpty)
    }

    func testAnEntryWithNoStartFallsIntoTheMissingDay() throws {
        let orphan = try entry(.note, at: day)
        orphan.startedAt = nil
        XCTAssertEqual(DayGrouping.days([orphan], missing: day, calendar: calendar).first?.day, day)
        XCTAssertEqual(DayGrouping.days([orphan], calendar: calendar).first?.day,
                       calendar.startOfDay(for: .distantPast), "the default puts it at the far end of the list")
    }
}


final class BackupTests: XCTestCase {
    func testExportImportRoundTripIsIdempotent() throws {
        let persistence = PersistenceController(inMemory: true)
        let logbook = Logbook(persistence: persistence)
        let context = persistence.container.viewContext
        let baby = try logbook.createBaby(name: "Test", birthDate: .now, in: context)
        var bottle = EntryDraft(kind: .bottle); bottle.amountML = 120
        try logbook.add(bottle, to: baby, in: context)
        var growth = EntryDraft(kind: .growth); growth.weightGrams = 3400
        try logbook.add(growth, to: baby, in: context)
        let data = try Backup.exportData(baby: baby, in: context)

        let other = PersistenceController(inMemory: true)
        let target = try Logbook(persistence: other).createBaby(name: "Test", birthDate: .now, in: other.container.viewContext)
        XCTAssertEqual(try Backup.importData(data, into: target, in: other.container.viewContext), 2)
        XCTAssertEqual(try Backup.importData(data, into: target, in: other.container.viewContext), 0, "second import adds nothing")
        let entries = Logbook(persistence: other).entries(for: target, from: .distantPast, in: other.container.viewContext)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first { $0.kind == .growth }?.weightGrams, 3400)
    }
}


final class MultipleBabiesTests: XCTestCase {
    func testSelectionAndMerge() throws {
        let persistence = PersistenceController(inMemory: true)
        let logbook = Logbook(persistence: persistence)
        let context = persistence.container.viewContext
        let first = try logbook.createBaby(name: "First", birthDate: .now, in: context)
        let second = try logbook.createBaby(name: "Second", birthDate: .now, in: context)
        Prefs.selectedBabyID = nil
        XCTAssertEqual(persistence.preferredBaby(from: [first, second]), first)
        Prefs.selectedBabyID = second.id
        XCTAssertEqual(persistence.preferredBaby(from: [first, second]), second)
        Prefs.selectedBabyID = nil

        var bottle = EntryDraft(kind: .bottle); bottle.amountML = 90
        try logbook.add(bottle, to: first, in: context)
        try logbook.add(EntryDraft(kind: .diaper), to: first, in: context)
        XCTAssertEqual(try logbook.merge(first, into: second, in: context), 2)
        XCTAssertEqual(try context.fetch(Baby.request()).count, 1)
        XCTAssertEqual(logbook.entries(for: second, from: .distantPast, in: context).count, 2)
    }
}


final class ShiftTests: XCTestCase {
    func testBlocksWrapMidnightAndManualOverridesSchedule() throws {
        let persistence = PersistenceController(inMemory: true)
        let logbook = Logbook(persistence: persistence)
        let context = persistence.container.viewContext
        let baby = try logbook.createBaby(name: "Test", birthDate: .now, in: context)
        let mine = ShiftBlock(name: "Me", deviceID: Prefs.deviceID, startMinute: 21 * 60, endMinute: 2 * 60)
        let theirs = ShiftBlock(name: "Partner", deviceID: "other-phone", startMinute: 2 * 60, endMinute: 7 * 60)
        try Shifts.save([mine, theirs], to: baby, in: context)
        let cal = Calendar.current
        let at = { (h: Int) in cal.date(bySettingHour: h, minute: 30, second: 0, of: Date())! }
        XCTAssertTrue(Shifts.thisPhoneIsOn(for: baby, at: at(23)), "23:30 is in my 21:00-02:00 block")
        XCTAssertTrue(Shifts.thisPhoneIsOn(for: baby, at: at(1)), "01:30 wraps past midnight into my block")
        XCTAssertFalse(Shifts.thisPhoneIsOn(for: baby, at: at(4)), "04:30 is the partner's")
        XCTAssertTrue(Shifts.thisPhoneIsOn(for: baby, at: at(12)), "outside every block, everyone is on")
        XCTAssertEqual(Shifts.onDutyLabel(for: baby, at: at(4)), "Partner")
        try Shifts.takeOver(baby, in: context)
        XCTAssertTrue(Shifts.thisPhoneIsOn(for: baby, at: at(4)), "a manual take-over beats the schedule")
        try Shifts.handOff(baby, in: context)
        XCTAssertFalse(Shifts.thisPhoneIsOn(for: baby, at: at(4)))
    }
}


final class SpokenFormatTests: XCTestCase {
    func testSiriHearsWordsNotAbbreviations() {
        XCTAssertEqual(Format.spokenDuration(15 * 60), "15 minutes")
        XCTAssertEqual(Format.spokenDuration(60 * 60), "1 hour")
        XCTAssertEqual(Format.spokenDuration(80 * 60), "1 hour 20 minutes")
        XCTAssertEqual(Format.spokenDuration(30), "under a minute")
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        XCTAssertEqual(Format.spokenAgo(from: now.addingTimeInterval(-12 * 60), to: now), "12 minutes ago")
        XCTAssertEqual(Format.spokenAgo(from: now.addingTimeInterval(-2 * 86_400), to: now), "2 days ago")
    }
}


final class BabyChoiceTests: XCTestCase {
    func testPerformAsksWhenTwoBabiesAndNoneSelected() async throws {
        let persistence = PersistenceController(inMemory: true)
        let logbook = Logbook(persistence: persistence)
        let context = persistence.container.viewContext
        let a = try logbook.createBaby(name: "A", birthDate: .now, in: context)
        _ = try logbook.createBaby(name: "B", birthDate: .now, in: context)
        Prefs.selectedBabyID = nil
        do { _ = try await logbook.perform { _, baby in baby.displayName }; XCTFail("should ask") }
        catch let error as LogbookError { XCTAssertEqual(error.errorDescription, LogbookError.ambiguous.errorDescription) }
        let named = try await logbook.perform(babyID: a.id) { _, baby in baby.displayName }
        XCTAssertEqual(named, "A")
        Prefs.selectedBabyID = a.id
        let selected = try await logbook.perform { _, baby in baby.displayName }
        XCTAssertEqual(selected, "A")
        Prefs.selectedBabyID = nil
    }
}


final class ChangelogTests: XCTestCase {
    func testChangelogParsesAndMatchesAppVersion() throws {
        let sections = Changelog.sections
        XCTAssertFalse(sections.isEmpty, "CHANGELOG.md must be bundled")
        XCTAssertEqual(sections.first?.version, Changelog.current, "newest changelog entry must match MARKETING_VERSION")
        // A release with only fixes in it is a normal release, so this asks
        // for a group with something in it rather than for "New" by name.
        let newest = try XCTUnwrap(sections.first)
        XCTAssertTrue(newest.groups.contains { !$0.items.isEmpty }, "the newest entry must say something")
    }
}


final class GoalsTests: XCTestCase {
    func testGoalsJudgeByTimeOfDay() {
        let cal = Calendar.current
        let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let night = cal.date(bySettingHour: 22, minute: 0, second: 0, of: Date())!
        var s = DaySummary(); s.feeds = 4; s.wet = 3; s.dirty = 1; s.sleepSeconds = 7 * 3600
        let stage = Guidance.stage(forAgeDays: 20)   // 7–10 feeds, 6+ wet, 15–17h
        let atNoon = Goals.evaluate(summary: s, lastFeed: noon.addingTimeInterval(-3600), stage: stage, ageDays: 20, now: noon)
        XCTAssertEqual(atNoon.first { $0.kind == .wet }?.status, .onTrack, "3 wet by noon is fine")
        XCTAssertEqual(atNoon.first { $0.kind == .feedGap }?.status, .onTrack)
        let atNight = Goals.evaluate(summary: s, lastFeed: night.addingTimeInterval(-4.5 * 3600), stage: stage, ageDays: 10, now: night)
        XCTAssertEqual(atNight.first { $0.kind == .wet }?.status, .short, "3 wet at 10 PM is short")
        XCTAssertEqual(atNight.first { $0.kind == .feedGap }?.status, .short, "4.5h gap at 10 days old is past the wake-to-feed limit")
        XCTAssertNotNil(Goals.concern(atNight, ageDays: 10))
        Goals.setCustom([.wet: 2]); defer { Goals.setCustom([:]) }
        let custom = Goals.evaluate(summary: s, lastFeed: nil, stage: stage, ageDays: 20, now: night)
        XCTAssertEqual(custom.first { $0.kind == .wet }?.status, .done, "custom target wins")
    }
}

final class WeeklyDigestTests: XCTestCase {
    func testDigestTextAndComparison() {
        var this = WeeklyDigest.Summary(); this.feeds = 52; this.bottleML = 7 * 17 * VolumeUnit.millilitersPerOunce; this.wet = 41; this.dirty = 12; this.sleepSeconds = 7 * 14.5 * 3600; this.longestSleep = 5 * 3600 + 600; this.nights = 7
        var last = this; last.bottleML = 7 * 15 * VolumeUnit.millilitersPerOunce; last.longestSleep = 4 * 3600
        let text = WeeklyDigest.text(this: this, last: last, unit: .ounces, babyName: "Test")
        XCTAssertTrue(text.hasPrefix("Test this week: 52 feeds, 17 oz a day by bottle, 41 wet and 12 dirty diapers, 14h 30m of sleep a day, longest stretch 5h 10m."), text)
        XCTAssertTrue(text.contains("up 2 oz a day"), text)
        XCTAssertTrue(text.contains("longest stretch up 1h 10m"), text)
        let sunday = WeeklyDigest.nextFireDate(after: Date(timeIntervalSince1970: 1_780_000_000))
        XCTAssertEqual(Calendar.current.component(.weekday, from: sunday), 1)
        XCTAssertEqual(Calendar.current.component(.hour, from: sunday), 19)
    }
}


final class PartnerAlertBatchingTests: XCTestCase {
    func testBatchBecomesOneSummaryAndRateLimits() throws {
        let persistence = PersistenceController(inMemory: true)
        let logbook = Logbook(persistence: persistence)
        let context = persistence.container.viewContext
        let baby = try logbook.createBaby(name: "Mina", birthDate: .now, in: context)
        var entries: [LogEntry] = []
        for (i, kind) in [EntryKind.bottle, .diaper, .sleep, .note].enumerated() {
            var d = EntryDraft(kind: kind, startedAt: Date.now.addingTimeInterval(Double(-i * 600)))
            d.amountML = 120; d.diaper = .wet; d.loggedBy = "Kiley"; d.note = "hi"
            if kind == .sleep { d.endedAt = d.startedAt.addingTimeInterval(1800) }
            entries.append(try logbook.add(d, to: baby, in: context))
        }
        let summary = PartnerAlerts.summary(for: entries, unit: .ounces)
        XCTAssertEqual(summary.title, "Kiley logged 4 things for Mina")
        XCTAssertTrue(summary.body.contains("and 1 more"), summary.body)
        Prefs.defaults.removeObject(forKey: "partnerAlerts.posted")
        for _ in 0..<PartnerAlerts.maxAlertsPerHour { PartnerAlerts.recordAlertPosted(now: .now) }
        XCTAssertEqual(PartnerAlerts.alertsPostedRecently(now: .now), PartnerAlerts.maxAlertsPerHour)
        XCTAssertEqual(PartnerAlerts.alertsPostedRecently(now: .now.addingTimeInterval(3601)), 0)
        Prefs.defaults.removeObject(forKey: "partnerAlerts.posted")
    }
}


final class CoalescingTests: XCTestCase {
    /// Holds values written from a background queue.
    private final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [Int] = []
        func append(_ value: Int) { lock.lock(); stored.append(value); lock.unlock() }
        var values: [Int] { lock.lock(); defer { lock.unlock() }; return stored }
    }

    func testThrottleRunsTheFirstCallAtOnceAndFoldsTheRestIntoOne() {
        let log = Log()
        let throttle = Throttle(interval: 0.5, queue: DispatchQueue(label: "throttle-test"))
        let leading = expectation(description: "first call runs straight away")
        let trailing = expectation(description: "the burst runs once at the end")

        throttle.call { log.append(0); leading.fulfill() }
        for value in 1...5 { throttle.call { log.append(value); if value == 5 { trailing.fulfill() } } }

        wait(for: [leading, trailing], timeout: 5)
        XCTAssertEqual(log.values, [0, 5], "five calls inside the window become one, carrying the newest work")
    }

    func testSerialTasksRunOneAtATimeInOrder() async {
        let log = Log()
        let tasks = SerialTasks()
        let done = expectation(description: "all three ran")
        for value in 1...3 {
            tasks.enqueue {
                try? await Task.sleep(nanoseconds: 20_000_000)
                log.append(value)
                if value == 3 { done.fulfill() }
            }
        }
        await fulfillment(of: [done], timeout: 5)
        XCTAssertEqual(log.values, [1, 2, 3], "queued work never overlaps or reorders")
    }
}


final class BulkWriteTests: XCTestCase {
    /// A file of entries must refresh the digest, the alarm and the widgets
    /// once, not once per entry: that is what turned an import into a burst.
    func testImportRunsTheAfterSaveHooksOncePerFile() throws {
        let source = PersistenceController(inMemory: true)
        let logbook = Logbook(persistence: source)
        let context = source.container.viewContext
        let baby = try logbook.createBaby(name: "Test", birthDate: .now, in: context)
        for milliliters in [90.0, 120.0, 150.0] {
            var draft = EntryDraft(kind: .bottle)
            draft.amountML = milliliters
            try logbook.add(draft, to: baby, in: context)
        }
        let data = try Backup.exportData(baby: baby, in: context)

        let other = PersistenceController(inMemory: true)
        let target = try Logbook(persistence: other).createBaby(name: "Test", birthDate: .now, in: other.container.viewContext)
        let previousAny = Logbook.anyEntryLogged
        let previousFeed = Logbook.feedLogged
        defer { Logbook.anyEntryLogged = previousAny; Logbook.feedLogged = previousFeed }
        var digests = 0
        var alarms = 0
        Logbook.anyEntryLogged = { _, _ in digests += 1 }
        Logbook.feedLogged = { _, _ in alarms += 1 }

        XCTAssertEqual(try Backup.importData(data, into: target, in: other.container.viewContext), 3)
        XCTAssertEqual(digests, 1, "one digest rebuild for the whole file")
        XCTAssertEqual(alarms, 1, "one alarm re-arm for the whole file")
        XCTAssertEqual(try Backup.importData(data, into: target, in: other.container.viewContext), 0)
        XCTAssertEqual(digests, 1, "an import that adds nothing schedules nothing")
        XCTAssertEqual(alarms, 1)
    }

    /// Merging a local log into a shared one is the other bulk path.
    func testMergeRunsTheAfterSaveHooksOnce() throws {
        let persistence = PersistenceController(inMemory: true)
        let logbook = Logbook(persistence: persistence)
        let context = persistence.container.viewContext
        let local = try logbook.createBaby(name: "Local", birthDate: .now, in: context)
        let shared = try logbook.createBaby(name: "Shared", birthDate: .now, in: context)
        for _ in 0..<4 { try logbook.add(EntryDraft(kind: .diaper), to: local, in: context) }

        let previousAny = Logbook.anyEntryLogged
        defer { Logbook.anyEntryLogged = previousAny }
        var digests = 0
        Logbook.anyEntryLogged = { _, _ in digests += 1 }
        XCTAssertEqual(try logbook.merge(local, into: shared, in: context), 4)
        XCTAssertEqual(digests, 1, "four moved entries, one refresh")
        Prefs.selectedBabyID = nil
    }
}
