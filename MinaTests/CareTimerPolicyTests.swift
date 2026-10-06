import CoreData
import XCTest
@testable import Mina

final class CareTimerPolicyTests: XCTestCase {
    private var persistence: PersistenceController!
    private var logbook: Logbook!
    private var defaults: UserDefaults!
    private var domain: String!
    private var baby: Baby!
    private var policy: CareTimerPolicy!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var context: NSManagedObjectContext { persistence.container.viewContext }

    override func setUpWithError() throws {
        persistence = PersistenceController(inMemory: true)
        logbook = Logbook(persistence: persistence)
        domain = "CareTimerPolicyTests.\(UUID())"
        defaults = UserDefaults(suiteName: domain)!
        policy = CareTimerPolicy(defaults: defaults, deviceID: Prefs.deviceID)
        baby = try logbook.createBaby(name: "Test", birthDate: now, in: context)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: domain)
        baby = nil
        policy = nil
        logbook = nil
        persistence = nil
    }

    @discardableResult
    private func sleep(at start: Date, for target: Baby? = nil) throws -> LogEntry {
        try logbook.add(EntryDraft(kind: .sleep, startedAt: start), to: target ?? baby, in: context)
    }

    func testDefaultOffAndOptOutRemoveRunningTimers() throws {
        try sleep(at: now)
        try logbook.startNursing(side: .left, for: baby, at: now, in: context)
        XCTAssertTrue(policy.running(for: baby, in: context, now: now).isEmpty)
        policy.setEnabled(true, for: .sleep, now: now)
        XCTAssertEqual(policy.running(for: baby, in: context, now: now).map(\.kind), [.sleep])
        policy.setEnabled(false, for: .sleep, now: now)
        XCTAssertTrue(policy.running(for: baby, in: context, now: now).isEmpty)
        policy.setEnabled(true, for: .sleep, now: now.addingTimeInterval(1))
        XCTAssertTrue(policy.running(for: baby, in: context, now: now.addingTimeInterval(1)).isEmpty,
                      "Re-enabling must not resurrect a previously dismissed timer")
    }

    func testStaleFutureAndPreConsentSessionsAreNotRevived() throws {
        policy.setEnabled(true, for: .sleep, now: now.addingTimeInterval(-30 * 86400))
        let entry = try sleep(at: now.addingTimeInterval(-522 * 3600))
        for start in [now.addingTimeInterval(-522 * 3600), now.addingTimeInterval(-8 * 3600), now.addingTimeInterval(60)] {
            entry.startedAt = start
            try context.save()
            XCTAssertTrue(policy.running(for: baby, in: context, now: now).isEmpty)
        }
        entry.startedAt = now.addingTimeInterval(-60)
        try context.save()
        XCTAssertEqual(policy.running(for: baby, in: context, now: now).map(\.id), [entry.id!])
        policy.setEnabled(true, for: .sleep, now: now)
        XCTAssertTrue(policy.running(for: baby, in: context, now: now).isEmpty)
    }

    func testSelectedBabyLocalOriginAndNewerSleepDetermineEligibility() throws {
        policy.setEnabled(true, for: .sleep, now: now.addingTimeInterval(-3600))
        let entry = try sleep(at: now.addingTimeInterval(-60))
        let other = try logbook.createBaby(name: "Other", birthDate: now, in: context)
        XCTAssertTrue(policy.running(for: other, in: context, now: now).isEmpty)
        XCTAssertTrue(policy.running(for: nil, in: context, now: now).isEmpty)
        entry.deviceID = "partner-phone"
        try context.save()
        XCTAssertTrue(policy.running(for: baby, in: context, now: now).isEmpty)
        entry.deviceID = Prefs.deviceID
        try context.save()
        XCTAssertEqual(policy.running(for: baby, in: context, now: now).count, 1)
        let newer = try sleep(at: now)
        newer.endedAt = now
        try context.save()
        XCTAssertTrue(policy.running(for: baby, in: context, now: now).isEmpty,
                      "A finished newer session must not reveal an abandoned older timer")
    }

    func testEndEditDeleteAndRemoteMergeRemoveTimer() throws {
        policy.setEnabled(true, for: .sleep, now: now.addingTimeInterval(-60))
        let entry = try sleep(at: now)
        XCTAssertEqual(policy.running(for: baby, in: context, now: now).count, 1)
        try logbook.endSleep(for: baby, at: now, in: context)
        XCTAssertTrue(policy.running(for: baby, in: context, now: now).isEmpty)

        entry.endedAt = nil
        try context.save()
        let remote = persistence.newBackgroundContext()
        let id = entry.objectID
        var saveNotification: Notification?
        let observer = NotificationCenter.default.addObserver(forName: .NSManagedObjectContextDidSave, object: remote, queue: nil) {
            saveNotification = $0
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        try remote.performAndWait {
            let imported = try remote.existingObject(with: id) as! LogEntry
            imported.endedAt = now
            try remote.save()
        }
        context.mergeChanges(fromContextDidSave: try XCTUnwrap(saveNotification))
        XCTAssertTrue(policy.running(for: baby, in: context, now: now).isEmpty,
                      "A partner's end must be honored after the history merge")

        entry.endedAt = nil
        try context.save()
        var draft = EntryDraft(entry: entry)
        draft.kind = .note
        logbook.apply(draft, to: entry)
        try context.save()
        XCTAssertTrue(policy.running(for: baby, in: context, now: now).isEmpty)
        entry.kind = .sleep
        try context.save()
        XCTAssertEqual(policy.running(for: baby, in: context, now: now).count, 1)
        try logbook.delete(entry, in: context)
        XCTAssertTrue(policy.running(for: baby, in: context, now: now).isEmpty)
    }
}
