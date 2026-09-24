import CoreData
import XCTest
@testable import Mina

@MainActor
final class WatchBridgeTests: XCTestCase {
    func testActionsWriteToTheBabyShownOnWatch() async throws {
        let persistence = PersistenceController(inMemory: true)
        let logbook = Logbook(persistence: persistence)
        let context = persistence.container.viewContext
        let baby = try logbook.createBaby(name: "Mina", birthDate: .now, in: context)
        let other = try logbook.createBaby(name: "Other", birthDate: .now, in: context)
        let id = try XCTUnwrap(baby.id)
        for action in ["bottle", "pee", "poop"] {
            _ = try await WatchBridge.shared.perform(action, babyID: id, logbook: logbook)
        }
        let entries = logbook.entries(for: baby, from: .distantPast, in: context)
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries.filter { $0.kind == .bottle }.count, 1)
        XCTAssertEqual(entries.filter { $0.kind == .diaper && $0.diaper == .wet }.count, 1)
        XCTAssertEqual(entries.filter { $0.kind == .diaper && $0.diaper == .dirty }.count, 1)
        XCTAssertTrue(logbook.entries(for: other, from: .distantPast, in: context).isEmpty)
    }

    func testSleepActionClosesTheSameSleep() async throws {
        let persistence = PersistenceController(inMemory: true)
        let logbook = Logbook(persistence: persistence)
        let context = persistence.container.viewContext
        let baby = try logbook.createBaby(name: "Mina", birthDate: .now, in: context)
        let id = try XCTUnwrap(baby.id)
        let first = try await WatchBridge.shared.perform("sleep", babyID: id, logbook: logbook)
        XCTAssertEqual(first, "Started sleep")
        let second = try await WatchBridge.shared.perform("sleep", babyID: id, logbook: logbook)
        XCTAssertEqual(second, "Marked awake")
        context.refreshAllObjects()
        let entries = logbook.entries(for: baby, from: .distantPast, in: context)
        XCTAssertEqual(entries.count, 1)
        XCTAssertNotNil(entries.first?.endedAt)
    }

    func testStaleBabyCannotLogToAnotherBaby() async throws {
        let persistence = PersistenceController(inMemory: true)
        let logbook = Logbook(persistence: persistence)
        let context = persistence.container.viewContext
        let baby = try logbook.createBaby(name: "Mina", birthDate: .now, in: context)
        do {
            _ = try await WatchBridge.shared.perform("bottle", babyID: UUID(), logbook: logbook)
            XCTFail("A removed or stale baby must not fall back to a different baby's log")
        } catch {}
        XCTAssertTrue(logbook.entries(for: baby, from: .distantPast, in: context).isEmpty)
    }
}
