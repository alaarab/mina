import BackgroundTasks
import Combine
import CoreData
import Foundation
import UIKit

/// A sleep the camera saw: when she went down and, if known, when she woke.
struct NanitSleepEvent: Equatable {
    let startID: Int
    let start: Date
    var endID: Int?
    var end: Date?
}

/// Turns Nanit's message feed into sleep events. Nanit's type names for
/// sleep aren't documented, so anything with "sleep" in the name starts a
/// sleep and anything with "wake"/"awake"/"woke" ends it. Settings shows the
/// raw types the account actually sends so the mapping can be tightened.
enum NanitEventMapper {
    static func isSleepStart(_ type: String) -> Bool {
        let lower = type.lowercased()
        return (lower.contains("sleep") || lower.contains("asleep")) && !isWake(type)
    }

    static func isWake(_ type: String) -> Bool {
        let lower = type.lowercased()
        return lower.contains("wake") || lower.contains("awake") || lower.contains("woke")
    }

    static func sleepEvents(from messages: [NanitMessage]) -> [NanitSleepEvent] {
        var events: [NanitSleepEvent] = []
        for message in messages.sorted(by: { $0.time < $1.time }) {
            if isSleepStart(message.type) {
                events.append(NanitSleepEvent(startID: message.id, start: message.time))
            } else if isWake(message.type), let index = events.lastIndex(where: { $0.end == nil && $0.start < message.time }) {
                events[index].endID = message.id
                events[index].end = message.time
            }
        }
        return events
    }
}

@MainActor
final class NanitSync: ObservableObject {
    static let shared = NanitSync()
    static let refreshTaskID = "com.alaarab.mina.nanit-sync"
    static let source = "Nanit"

    private static let babyKey = "nanit.baby"
    private static let linkedAtKey = "nanit.linkedAt"
    private static let processedKey = "nanit.processed"
    private static let seenTypesKey = "nanit.seenTypes"
    private static let lastSyncKey = "nanit.lastSync"

    @Published private(set) var baby: NanitBaby?
    @Published private(set) var lastSync: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var seenTypes: [String] = []
    @Published private(set) var syncing = false

    let client = NanitClient()
    private let persistence = PersistenceController.shared

    var isLinked: Bool { baby != nil && tokens != nil }

    init() {
        if let data = Prefs.defaults.data(forKey: Self.babyKey) { baby = try? JSONDecoder().decode(NanitBaby.self, from: data) }
        lastSync = Prefs.defaults.object(forKey: Self.lastSyncKey) as? Date
        seenTypes = Prefs.defaults.stringArray(forKey: Self.seenTypesKey) ?? []
    }

    private(set) var tokens: NanitTokens? {
        get { Keychain.get("tokens").flatMap { try? JSONDecoder().decode(NanitTokens.self, from: $0) } }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) { Keychain.set(data, for: "tokens") } else { Keychain.delete("tokens") }
        }
    }

    // MARK: Linking

    func link(tokens: NanitTokens, baby: NanitBaby) {
        self.tokens = tokens
        self.baby = baby
        Prefs.defaults.set(try? JSONEncoder().encode(baby), forKey: Self.babyKey)
        Prefs.defaults.set(Date.now, forKey: Self.linkedAtKey)
        lastError = nil
        Task { await sync() }
    }

    func unlink() {
        tokens = nil
        baby = nil
        for key in [Self.babyKey, Self.linkedAtKey, Self.processedKey, Self.seenTypesKey, Self.lastSyncKey] { Prefs.defaults.removeObject(forKey: key) }
        seenTypes = []
        lastSync = nil
        lastError = nil
    }

    private func validToken() async throws -> String {
        guard var current = tokens else { throw NanitError.sessionExpired }
        if Date.now.timeIntervalSince(current.issuedAt) > 50 * 60 {
            current = try await client.refresh(current.refreshToken)
            tokens = current
        }
        return current.accessToken
    }

    // MARK: Sync

    func sync() async {
        guard let baby, !syncing else { return }
        syncing = true
        defer { syncing = false }
        do {
            let token = try await validToken()
            let messages = try await client.messages(babyUID: baby.uid, limit: 100, token: token)
            record(types: messages.map(\.type))
            try apply(NanitEventMapper.sleepEvents(from: messages))
            lastSync = .now
            Prefs.defaults.set(lastSync, forKey: Self.lastSyncKey)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func record(types: [String]) {
        var seen = Set(seenTypes)
        types.forEach { seen.insert($0) }
        seenTypes = seen.sorted()
        Prefs.defaults.set(seenTypes, forKey: Self.seenTypesKey)
    }

    /// Writes new sleep events into the log and closes ones that ended.
    private func apply(_ events: [NanitSleepEvent]) throws {
        var processed = Set(Prefs.defaults.array(forKey: Self.processedKey) as? [Int] ?? [])
        let linkedAt = Prefs.defaults.object(forKey: Self.linkedAtKey) as? Date ?? .distantPast
        let floor = linkedAt.addingTimeInterval(-24 * 3600)
        let context = persistence.container.viewContext
        guard let target = Logbook.shared.currentBaby(in: context) else { return }

        for event in events where event.start >= floor {
            if !processed.contains(event.startID) {
                var draft = EntryDraft(kind: .sleep, startedAt: event.start)
                draft.endedAt = event.end
                draft.loggedBy = Self.source
                draft.label = "nanit:\(event.startID)"
                try Logbook.shared.add(draft, to: target, in: context)
                processed.insert(event.startID)
                if let endID = event.endID { processed.insert(endID) }
            } else if let endID = event.endID, let end = event.end, !processed.contains(endID) {
                let request = LogEntry.request()
                request.predicate = NSPredicate(format: "baby == %@ AND label == %@", target, "nanit:\(event.startID)")
                request.fetchLimit = 1
                if let entry = try context.fetch(request).first, entry.endedAt == nil {
                    entry.endedAt = end
                    try context.save()
                    Logbook.widgetsChanged()
                }
                processed.insert(endID)
            }
        }
        Prefs.defaults.set(Array(processed.sorted().suffix(1000)), forKey: Self.processedKey)
    }

    // MARK: Background refresh

    nonisolated static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskID, using: nil) { task in
            Task { @MainActor in
                await NanitSync.shared.sync()
                NanitSync.scheduleBackgroundRefresh()
                task.setTaskCompleted(success: NanitSync.shared.lastError == nil)
            }
        }
    }

    static func scheduleBackgroundRefresh() {
        guard shared.isLinked else { return }
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date.now.addingTimeInterval(30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
