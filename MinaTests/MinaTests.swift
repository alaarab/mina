import CoreData
import XCTest
@testable import Mina

final class UnitTests: XCTestCase {
    func testOunceFormatting() {
        XCTAssertEqual(VolumeUnit.ounces.format(ml: 4 * VolumeUnit.millilitersPerOunce), "4 oz")
        XCTAssertEqual(VolumeUnit.ounces.format(ml: 4.5 * VolumeUnit.millilitersPerOunce), "4.5 oz")
        XCTAssertEqual(VolumeUnit.ounces.format(ml: 4.3 * VolumeUnit.millilitersPerOunce), "4.25 oz")
        XCTAssertEqual(VolumeUnit.milliliters.format(ml: 118.3), "118 ml")
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
        XCTAssertEqual(Measure.weight(grams: (7 * 16 + 4) * Measure.gramsPerOunce, unit: .ounces), "7 lb 4 oz")
        XCTAssertEqual(Measure.weight(grams: 3290, unit: .milliliters), "3.29 kg")
        XCTAssertNil(Measure.weight(grams: 0, unit: .ounces))
        XCTAssertEqual(Measure.length(cm: 20 * Measure.cmPerInch, unit: .ounces, label: ""), "20 in")
        XCTAssertEqual(Measure.length(cm: 50.8, unit: .milliliters, label: "head"), "head 50.8 cm")
        XCTAssertEqual(Measure.temperature(celsius: 38, unit: .milliliters), "38 °C")
        XCTAssertEqual(Measure.celsius(fromDisplay: 100.4, unit: .ounces), 38, accuracy: 0.01)
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
        XCTAssertEqual(Measure.weight(grams: BabyWeight.lb7oz4.grams, unit: .ounces), "7 lb 4 oz")
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
