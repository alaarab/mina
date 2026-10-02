import CoreData
import XCTest
@testable import Mina

final class AgePersistenceTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return value
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }

    private func stack(at url: URL) throws -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "AgeSupport", managedObjectModel: MinaModel.model)
        let description = NSPersistentStoreDescription(url: url)
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var failure: Error?
        container.loadPersistentStores { _, error in failure = error }
        if let failure { throw failure }
        return container
    }

    func testCorrectedBirthdayAndFamilyHistorySurviveSQLiteReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("age.sqlite")
        let first = try stack(at: url)
        let context = first.viewContext
        let now = try date(2026, 10, 2)
        let baby = Baby(context: context)
        let babyID = UUID(); baby.id = babyID; baby.name = "Mina"
        baby.birthDate = try date(2026, 7, 2)
        let sibling = Baby(context: context); sibling.id = UUID(); sibling.name = "Sibling"; sibling.birthDate = now
        let label = SolidMetadata.encode(food: "Oatmeal", allergens: ["Milk", "Wheat"])
        let kinds: [EntryKind] = [.bottle, .nursing, .diaper, .sleep, .solid, .growth, .note, .milestone, .checkup]
        var entryIDs = Set<UUID>()
        for (offset, kind) in kinds.enumerated() {
            let entry = LogEntry(context: context)
            let id = UUID(); entryIDs.insert(id); entry.id = id; entry.baby = baby; entry.kind = kind
            entry.startedAt = now.addingTimeInterval(-Double(offset) * 86400)
            entry.label = kind == .solid ? label : "Earlier family memory"
            entry.loggedBy = offset % 2 == 0 ? "Mom" : "Dad"
            entry.note = "Keep this history"
        }
        XCTAssertEqual(baby.guideStage(on: now, calendar: calendar)?.id, "month-4")
        baby.birthDate = try date(2024, 10, 2)
        XCTAssertEqual(baby.guideStage(on: now, calendar: calendar)?.id, "months-24-29")
        try context.save()
        context.reset()
        for store in first.persistentStoreCoordinator.persistentStores { try first.persistentStoreCoordinator.remove(store) }
        let reopened = try stack(at: url)
        let babies = try reopened.viewContext.fetch(Baby.request())
        let saved = try XCTUnwrap(babies.first { $0.id == babyID })
        XCTAssertEqual(saved.birthDate, try date(2024, 10, 2))
        XCTAssertEqual(saved.ageDescription(on: now, calendar: calendar), "2 years old")
        XCTAssertEqual(saved.guideStage(on: now, calendar: calendar)?.id, "months-24-29")
        let request = LogEntry.request(); request.predicate = NSPredicate(format: "baby == %@", saved)
        let entries = try reopened.viewContext.fetch(request)
        XCTAssertEqual(Set(entries.compactMap(\.id)), entryIDs)
        XCTAssertEqual(entries.first { $0.kind == .solid }?.label, label)
        XCTAssertTrue(entries.allSatisfy { $0.note == "Keep this history" })
        XCTAssertEqual(babies.first { $0.name == "Sibling" }?.birthDate, now)
        reopened.viewContext.reset()
        for store in reopened.persistentStoreCoordinator.persistentStores { try reopened.persistentStoreCoordinator.remove(store) }
    }

    func testFoodSummaryTrendsAndBackupKeepMilkSeparate() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let log = Logbook(persistence: persistence)
        let today = try date(2026, 3, 8) // DST day, 23 hours long
        let baby = try log.createBaby(name: "Mina", birthDate: try date(2024, 3, 8), in: context)
        for offset in [-3600.0, 3600, 7200, 23 * 3600] {
            var food = EntryDraft(kind: .solid, startedAt: today.addingTimeInterval(offset))
            food.label = SolidMetadata.encode(food: "Egg on toast", allergens: ["Egg", "Wheat"])
            try log.add(food, to: baby, in: context, save: false)
        }
        var bottle = EntryDraft(kind: .bottle, startedAt: today.addingTimeInterval(3600)); bottle.amountML = 120
        try log.add(bottle, to: baby, in: context, save: false)
        try context.save()
        let entries = log.entries(for: baby, from: .distantPast, in: context)
        let summary = DaySummary(entries: entries, day: today, now: today.addingTimeInterval(22 * 3600), calendar: calendar)
        XCTAssertEqual(summary.foods, 2)
        XCTAssertEqual(summary.feeds, 1)
        XCTAssertEqual(summary.bottleML, 120)
        let stats = TrendMath.stats(entries: entries, days: 2, now: today.addingTimeInterval(22 * 3600), calendar: calendar)
        XCTAssertEqual(stats.map(\.summary.foods), [1, 2])
        XCTAssertEqual(stats.map(\.summary.feeds), [0, 1])
        let digest = WeeklyDigest.summary(entries: entries, from: today, days: 1, now: today.addingTimeInterval(22 * 3600), calendar: calendar)
        XCTAssertEqual(digest.foods, 2)
        XCTAssertTrue(WeeklyDigest.text(this: digest, last: nil, unit: .ounces, babyName: "Mina").contains("2 food entries"))
        let data = try Backup.exportData(baby: baby, in: context)
        let other = PersistenceController(inMemory: true)
        let target = try Logbook(persistence: other).createBaby(name: "Mina", birthDate: baby.birthDate, in: other.container.viewContext)
        XCTAssertEqual(try Backup.importData(data, into: target, in: other.container.viewContext), 5)
        XCTAssertEqual(try Backup.importData(data, into: target, in: other.container.viewContext), 0)
        let imported = Logbook(persistence: other).entries(for: target, from: .distantPast, in: other.container.viewContext)
        XCTAssertEqual(Set(entries.compactMap(\.id)), Set(imported.compactMap(\.id)))
        XCTAssertEqual(imported.filter { $0.kind == .solid }.count, 4)
        XCTAssertEqual(SolidMetadata.decode(try XCTUnwrap(imported.first { $0.kind == .solid }?.label)).allergens, ["Egg", "Wheat"])
    }

    func testAgeDescriptionAndGrowthBoundariesUseCorrectedBirthday() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let baby = Baby(context: context)
        XCTAssertNil(baby.guideStage())
        baby.birthDate = try date(2024, 2, 29)
        let entry = LogEntry(context: context); entry.kind = .growth; entry.weightGrams = 12000; entry.lengthCM = 85; entry.headCM = 47
        entry.startedAt = try date(2026, 2, 28)
        XCTAssertEqual(baby.ageDescription(on: try date(2026, 2, 28), calendar: calendar), "2 years old")
        XCTAssertEqual(GrowthStandards.results(for: entry, birthDate: baby.birthDate, calendar: calendar).count, 3)
        entry.startedAt = try date(2026, 3, 1)
        XCTAssertTrue(GrowthStandards.results(for: entry, birthDate: baby.birthDate, calendar: calendar).isEmpty)
        baby.birthDate = try date(2026, 3, 2)
        XCTAssertEqual(baby.ageDescription(on: try date(2026, 3, 1), calendar: calendar), "Arriving soon")
        XCTAssertTrue(GrowthStandards.results(for: entry, birthDate: baby.birthDate, calendar: calendar).isEmpty)
    }

    func testToddlerVisitRemindersMoveWithBirthdayAndExcludePastDates() throws {
        let birth = try date(2024, 1, 31)
        let item = try XCTUnwrap(CareSchedule.items.first { $0.id == "checkup-30m" })
        let threeYears = try XCTUnwrap(CareSchedule.items.first { $0.id == "checkup-36m" })
        XCTAssertEqual(item.due(from: birth, calendar: calendar), try date(2026, 7, 31))
        XCTAssertEqual(threeYears.due(from: birth, calendar: calendar), try date(2027, 1, 31))
        let fire = try XCTUnwrap(CareSchedule.reminderDate(for: item, birthDate: birth, now: birth, calendar: calendar))
        XCTAssertEqual(calendar.component(.hour, from: fire), 9)
        XCTAssertEqual(calendar.startOfDay(for: fire), try date(2026, 7, 30))
        XCTAssertNil(CareSchedule.reminderDate(for: item, birthDate: birth, now: fire, calendar: calendar))
        let corrected = try date(2024, 2, 1)
        let moved = try XCTUnwrap(CareSchedule.reminderDate(for: item, birthDate: corrected, now: birth, calendar: calendar))
        XCTAssertEqual(calendar.startOfDay(for: moved), try date(2026, 7, 31))
        XCTAssertEqual(Set(CareSchedule.items.map(\.id)).count, CareSchedule.items.count)
    }
}
