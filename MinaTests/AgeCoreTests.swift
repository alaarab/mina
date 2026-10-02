import Foundation
import XCTest
#if MINA_AGE_CORE
@testable import MinaAgeCore
#else
@testable import Mina
#endif

final class AgeCoreTests: XCTestCase {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return result
    }

    func testCalendarTransitionsAtEachAnniversary() throws {
        for components in [DateComponents(year: 2024, month: 2, day: 29), DateComponents(year: 2025, month: 8, day: 31)] {
            let birth = try XCTUnwrap(calendar.date(from: components))
            let expected = [(6, "months-6-8"), (9, "months-9-11"), (12, "months-12-17"), (18, "months-18-23"), (24, "months-24-29"), (30, "months-30-35"), (36, "beyond-guide")]
            var prior = "month-4"
            for (month, id) in expected {
                let boundary = try XCTUnwrap(calendar.date(byAdding: .month, value: month, to: birth))
                let before = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: boundary))
                XCTAssertEqual(Guidance.stage(birthDate: birth, on: before, calendar: calendar).id, prior)
                XCTAssertEqual(Guidance.stage(birthDate: birth, on: boundary, calendar: calendar).id, id)
                prior = id
            }
        }
    }

    func testAgeDescriptionsAtLeapAndYearBoundaries() throws {
        let birth = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 2, day: 29)))
        let birthday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 28)))
        XCTAssertEqual(ChildAge.description(birthDate: birth, on: birthday, calendar: calendar), "2 years old")
        let later = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 29)))
        XCTAssertEqual(ChildAge.description(birthDate: birth, on: later, calendar: calendar), "2 years, 1 month old")
        XCTAssertEqual(ChildAge.description(birthDate: nil, on: birthday, calendar: calendar), "")
        XCTAssertEqual(ChildAge.description(birthDate: later, on: birthday, calendar: calendar), "Arriving soon")
        XCTAssertEqual(ChildAge.description(birthDate: birthday, on: birthday, calendar: calendar), "Born today")
    }

    func testFractionalMonthsDoNotDropTheSecondBirthday() throws {
        let birth = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 2, day: 29)))
        let birthday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 28)))
        XCTAssertEqual(ChildAge.months(birthDate: birth, on: birthday, calendar: calendar), 24)
        let next = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: birthday))
        XCTAssertGreaterThan(try XCTUnwrap(ChildAge.months(birthDate: birth, on: next, calendar: calendar)), 24)
        XCTAssertNil(ChildAge.months(birthDate: next, on: birthday, calendar: calendar))
    }

    func testMissingRangeAndFutureDateStaySafe() throws {
        let birth = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8)))
        XCTAssertEqual(Guidance.stage(birthDate: birth, on: birth.addingTimeInterval(-86400), calendar: calendar).id, "days-1-3")
        XCTAssertEqual(Guidance.stage(forAgeDays: Int.max).id, "beyond-guide")
        XCTAssertNil(Guidance.stage(forAgeDays: Int.max).expectation.sleepHours)
        XCTAssertEqual(Guidance.stage(forAgeDays: -1).id, "days-1-3")
    }

    func testDaylightSavingDoesNotMoveBirthdayStage() throws {
        let birth = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 9, day: 8, hour: 22)))
        let anniversary = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8)))
        XCTAssertEqual(Guidance.stage(birthDate: birth, on: anniversary, calendar: calendar).id, "months-6-8")
        XCTAssertEqual(Guidance.stage(birthDate: birth, on: anniversary.addingTimeInterval(-1), calendar: calendar).id, "month-4")
    }

    func testOlderStagesHaveNoNewbornIntakeOrDiaperDefaults() {
        let saved = Goals.custom()
        Goals.setCustom([:]); defer { Goals.setCustom(saved) }
        for days in [183, 274, 365, 548, 730, 913] {
            let stage = Guidance.stage(forAgeDays: days)
            let targets = Goals.targets(for: stage, ageDays: days, weightGrams: 14000)
            XCTAssertEqual(Set(targets.keys), [.sleep])
            XCTAssertEqual(targets[.sleep], days < 365 ? 12 : 11)
        }
        XCTAssertTrue(Goals.targets(for: Guidance.stage(forAgeDays: 1096), ageDays: 1096).isEmpty)
        XCTAssertTrue(Goals.targets(for: Guidance.stages[0], ageDays: nil).isEmpty)
        XCTAssertTrue(Goals.targets(for: Guidance.stages[0], ageDays: -1).isEmpty)
        XCTAssertEqual(Goals.targets(for: Guidance.stage(forAgeDays: 20), ageDays: 20, weightGrams: 4000)[.volume], 600)
    }

    func testPersonalTargetsSurviveAgeTransitions() {
        let saved = Goals.custom()
        defer { Goals.setCustom(saved) }
        Goals.setCustom([.feeds: 4, .volume: 300, .wet: 2, .feedGap: 8])
        let targets = Goals.targets(for: Guidance.stage(forAgeDays: 800), ageDays: 800, weightGrams: 16000)
        XCTAssertEqual(targets[.feeds], 4)
        XCTAssertEqual(targets[.volume], 300)
        XCTAssertEqual(targets[.wet], 2)
        XCTAssertEqual(targets[.feedGap], 8)
        let goals = Goals.evaluate(summary: DaySummary(), lastFeed: nil, stage: Guidance.stage(forAgeDays: 800), ageDays: 800)
        XCTAssertNil(Goals.concern(goals, ageDays: 800), "Newborn diaper thresholds must not be applied to toddlers")
    }

    func testOlderFeedPredictionsNeedLogEvidenceAndNapEstimateStops() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let toddler = Guidance.stage(forAgeDays: 800)
        XCTAssertNil(Predictor.nextFeed(feedTimes: [now], stage: toddler))
        let times = [0.0, 3, 6, 9].map { now.addingTimeInterval(-$0 * 3600) }
        XCTAssertEqual(Predictor.nextFeed(feedTimes: times, stage: toddler)?.interval, 3 * 3600)
        XCTAssertNil(Predictor.nextNap(lastWake: now, ageDays: 800, stage: toddler))
        XCTAssertNotNil(Predictor.nextNap(lastWake: now, ageDays: 182))
        XCTAssertNil(Predictor.nextNap(lastWake: now, ageDays: 183))
        // A short February can put the calendar six-month boundary before day 183.
        XCTAssertNil(Predictor.nextNap(lastWake: now, ageDays: 181, stage: Guidance.stage(forAgeDays: 183)))
    }
}
