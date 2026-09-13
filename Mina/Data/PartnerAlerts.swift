import CloudKit
import CoreData
import UIKit
import UserNotifications
import WidgetKit

/// Turns the other phone's entries into a notification on this one.
///
/// CloudKit delivers a silent push when the shared zone changes, the container
/// imports the records, and the store posts a remote-change notification. We
/// read the persistent history for those transactions, merge them into the UI
/// context (which also covers writes from this phone's widget), and post a
/// local notification for anything the partner logged recently.
final class PartnerAlerts {
    static let shared = PartnerAlerts()
    private static let tokenKey = "partnerAlerts.historyToken"

    private let persistence = PersistenceController.shared
    private let queue = DispatchQueue(label: "mina.partner-alerts")
    private var observer: NSObjectProtocol?
    /// An iCloud catch-up posts dozens of remote-change notifications in a row.
    /// The merge itself has to happen every time, but the work that follows it
    /// (re-arm the alarm, rebuild the digest, reload the widgets) runs once for
    /// the burst instead of once per notification.
    private let followUp = Throttle(interval: 2)

    func start() {
        guard observer == nil, !persistence.inMemory else { return }
        if lastToken == nil, let token = persistence.container.persistentStoreCoordinator.currentPersistentHistoryToken(fromStores: nil) {
            lastToken = token   // Don't replay the whole log on first launch.
        }
        observer = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: persistence.container.persistentStoreCoordinator, queue: nil
        ) { [weak self] _ in
            self?.queue.async { self?.processHistory() }
        }
    }

    private static let subscriptionKey = "partner.cloudSubscription.v1"

    /// Earlier builds saved a CloudKit query subscription on the owner's phone
    /// so alerts arrived with the app force-quit. Apple sends one push per
    /// record with no batching, so a catch-up sync became a hundred alerts.
    /// This removes it once; alerts now come only through the batched local
    /// path below.
    func removeCloudSubscriptionIfPresent() {
        guard Prefs.defaults.bool(forKey: Self.subscriptionKey) else { return }
        Task {
            let container = CKContainer(identifier: PersistenceController.cloudContainerIdentifier)
            _ = try? await container.privateCloudDatabase.deleteSubscription(withID: "partner-entries-v1")
            Prefs.defaults.set(false, forKey: Self.subscriptionKey)
        }
    }

    /// Kept so the local path can stay quiet if a future build brings the
    /// server-side subscription back; nothing sets it today.

    // MARK: Permission

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // MARK: History

    private var lastToken: NSPersistentHistoryToken? {
        get {
            guard let data = Prefs.defaults.data(forKey: Self.tokenKey) else { return nil }
            return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSPersistentHistoryToken.self, from: data)
        }
        set {
            let data = newValue.flatMap { try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) }
            Prefs.defaults.set(data, forKey: Self.tokenKey)
        }
    }

    private func processHistory() {
        let context = persistence.newBackgroundContext()
        context.performAndWait {
            let request = NSPersistentHistoryChangeRequest.fetchHistory(after: lastToken)
            let result: NSPersistentHistoryResult?
            do {
                result = try context.execute(request) as? NSPersistentHistoryResult
            } catch {
                // A token the store no longer recognises (history pruned, store
                // rebuilt) would fail on every change from here on. Start again
                // from now rather than re-reading the whole log.
                NSLog("partner alerts: history unreadable, restarting from now: \(error)")
                lastToken = persistence.container.persistentStoreCoordinator.currentPersistentHistoryToken(fromStores: nil)
                return
            }
            guard let transactions = result?.result as? [NSPersistentHistoryTransaction], !transactions.isEmpty else { return }
            lastToken = transactions.last?.token

            let foreign = transactions.filter { $0.author != PersistenceController.appAuthor }
            guard !foreign.isEmpty else { return }

            let viewContext = persistence.container.viewContext
            viewContext.perform {
                for transaction in foreign {
                    viewContext.mergeChanges(fromContextDidSave: transaction.objectIDNotification())
                }
            }
            // A feed from the other phone moves the alarm, even if Today isn't
            // on screen; the widgets and the digest follow the same entries.
            followUp.call {
                viewContext.perform {
                    if let baby = Logbook.shared.currentBaby(in: viewContext) {
                        Logbook.shared.didChangeEntries(for: baby, in: viewContext)
                    }
                }
            }

            var inserted: [NSManagedObjectID] = []
            for transaction in foreign {
                for change in transaction.changes ?? [] where change.changeType == .insert {
                    if change.changedObjectID.entity.name == "LogEntry" { inserted.append(change.changedObjectID) }
                }
            }
            guard !inserted.isEmpty, Prefs.partnerAlerts else { return }
            if let baby = Logbook.shared.currentBaby(in: context), !Shifts.thisPhoneIsOn(for: baby) { return }

            // Only entries that happened recently, judged by when they were logged,
            // not when they landed here: an iCloud catch-up re-inserts old entries.
            let now = Date.now
            let recent = inserted.compactMap { id -> LogEntry? in
                guard let entry = try? context.existingObject(with: id) as? LogEntry, entry.isFromPartner,
                      let at = entry.startedAt, now.timeIntervalSince(at) < Self.alertWindow, at <= now.addingTimeInterval(5 * 60) else { return nil }
                return entry
            }
            guard !recent.isEmpty else { return }
            // Never more than one notification per sync, and never more than a few per hour.
            let posts = Self.alertsPostedRecently(now: now)
            guard posts < Self.maxAlertsPerHour else { return }
            let message: Message
            if recent.count == 1 {
                message = Self.message(for: recent[0], unit: Prefs.unit, now: now)
            } else {
                message = Self.summary(for: recent, unit: Prefs.unit)
            }
            Self.recordAlertPosted(now: now)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard UIApplication.shared.applicationState != .active else { return }
                    Self.post(message)
                }
            }
        }
    }

    // MARK: Rate limiting

    /// Entries older than this never alert, however they arrived.
    static let alertWindow: TimeInterval = 90 * 60
    static let maxAlertsPerHour = 6
    private static let postedKey = "partnerAlerts.posted"

    static func alertsPostedRecently(now: Date) -> Int {
        let stamps = (Prefs.defaults.array(forKey: postedKey) as? [Date]) ?? []
        return stamps.filter { now.timeIntervalSince($0) < 3600 }.count
    }

    static func recordAlertPosted(now: Date) {
        var stamps = (Prefs.defaults.array(forKey: postedKey) as? [Date]) ?? []
        stamps = stamps.filter { now.timeIntervalSince($0) < 3600 } + [now]
        Prefs.defaults.set(stamps, forKey: postedKey)
    }

    /// One line for a batch: "Kiley logged 3 things for Mina: 4 oz bottle, wet diaper, sleep."
    static func summary(for entries: [LogEntry], unit: VolumeUnit) -> Message {
        let who = entries.compactMap { $0.loggedBy }.first { !$0.isEmpty } ?? "Your partner"
        let baby = entries.first?.baby?.displayName ?? "the baby"
        let sorted = entries.sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }
        let items = sorted.prefix(3).map { $0.title(unit: unit).lowercased() }
        var body = items.joined(separator: ", ")
        if sorted.count > 3 { body += " and \(sorted.count - 3) more" }
        return Message(title: "\(who) logged \(Format.count(sorted.count, "thing")) for \(baby)", body: clip(body), relevance: 0.8)
    }

    // MARK: Notifications

    struct Message: Equatable {
        let title: String
        let body: String
        /// How high this sits in a notification summary. A feed or a sleep is
        /// what the other parent is waiting on; a note can wait.
        var relevance: Double = 0.6
    }

    /// Notification text is visible on a locked screen, so free text never goes
    /// out whole: a long note is cut to a sentence's worth, and nothing else in
    /// a message is user-typed beyond a name.
    static let bodyLimit = 120

    static func clip(_ text: String, to limit: Int = bodyLimit) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return trimmed.prefix(limit - 1).trimmingCharacters(in: .whitespaces) + "…"
    }

    static func message(for entry: LogEntry, unit: VolumeUnit, now: Date = .now) -> Message {
        let who = entry.loggedBy.flatMap { $0.isEmpty ? nil : $0 } ?? "Your partner"
        let baby = entry.baby?.displayName ?? "the baby"
        let at = Format.time(entry.startedAt ?? now)
        switch entry.kind {
        case .bottle:
            return Message(title: "\(who) fed \(baby)", body: "\(unit.format(ml: entry.amountML)) bottle at \(at)", relevance: 0.9)
        case .nursing:
            var body = "Nursed"
            if let side = entry.side { body += " on the \(side.title.lowercased())" }
            if let seconds = entry.duration(now: now), seconds > 0 { body += " for \(Format.duration(seconds))" }
            return Message(title: "\(who) fed \(baby)", body: body + " at \(at)", relevance: 0.9)
        case .diaper:
            return Message(title: "\(who) changed \(baby)", body: "\(entry.diaper?.title ?? "Wet") diaper at \(at)")
        case .sleep:
            if entry.isOngoingSleep {
                return Message(title: "\(baby) is asleep", body: who == NanitSync.source ? "The camera saw her fall asleep at \(at)" : "\(who) put her down at \(at)")
            }
            return Message(title: "\(baby) slept \(Format.duration(entry.duration(now: now) ?? 0))", body: "Logged by \(who.lowercased() == "your partner" ? "your partner" : who)")
        case .note:
            return Message(title: "\(who) added a note", body: clip(entry.note ?? ""), relevance: 0.3)
        case .milestone:
            return Message(title: "\(baby) hit a milestone", body: clip("\(entry.label ?? "") · noted by \(who)"), relevance: 0.4)
        case .pumping, .growth, .medicine, .tummyTime, .bath, .temperature:
            return Message(title: "\(who) logged \(entry.kind.title.lowercased())",
                           body: clip("\(entry.title(unit: unit, now: now)) at \(at)"), relevance: 0.5)
        }
    }

    private static func post(_ message: Message) {
        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = clip(message.body)
        content.sound = .default
        content.threadIdentifier = "partner"
        // A partner's entry is news, not an emergency: it must never break
        // through a Focus or a silenced phone the way .timeSensitive would.
        content.interruptionLevel = .active
        content.relevanceScore = message.relevance
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
