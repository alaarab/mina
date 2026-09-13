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
            guard let result = try? context.execute(request) as? NSPersistentHistoryResult,
                  let transactions = result.result as? [NSPersistentHistoryTransaction], !transactions.isEmpty else { return }
            lastToken = transactions.last?.token

            let foreign = transactions.filter { $0.author != PersistenceController.appAuthor }
            guard !foreign.isEmpty else { return }

            let viewContext = persistence.container.viewContext
            viewContext.perform {
                for transaction in foreign {
                    viewContext.mergeChanges(fromContextDidSave: transaction.objectIDNotification())
                }
            }
            Logbook.widgetsChanged()

            var inserted: [NSManagedObjectID] = []
            for transaction in foreign {
                for change in transaction.changes ?? [] where change.changeType == .insert {
                    if change.changedObjectID.entity.name == "LogEntry" { inserted.append(change.changedObjectID) }
                }
            }
            guard !inserted.isEmpty, Prefs.partnerAlerts else { return }

            let cutoff = Date.now.addingTimeInterval(-6 * 3600)
            var entries: [LogEntry] = []
            for objectID in inserted {
                guard let entry = try? context.existingObject(with: objectID) as? LogEntry, entry.isFromPartner else { continue }
                let created: Date = entry.createdAt ?? entry.startedAt ?? .distantPast
                if created > cutoff { entries.append(entry) }
            }
            guard !entries.isEmpty else { return }
            let messages = entries.map { Self.message(for: $0, unit: Prefs.unit) }
            DispatchQueue.main.async {
                guard UIApplication.shared.applicationState != .active else { return }
                for message in messages { Self.post(message) }
            }
        }
    }

    // MARK: Notifications

    struct Message: Equatable {
        let title: String
        let body: String
    }

    static func message(for entry: LogEntry, unit: VolumeUnit, now: Date = .now) -> Message {
        let who = entry.loggedBy.flatMap { $0.isEmpty ? nil : $0 } ?? "Your partner"
        let baby = entry.baby?.displayName ?? "the baby"
        let at = Format.time(entry.startedAt ?? now)
        switch entry.kind {
        case .bottle:
            return Message(title: "\(who) fed \(baby)", body: "\(unit.format(ml: entry.amountML)) bottle at \(at)")
        case .nursing:
            var body = "Nursed"
            if let side = entry.side { body += " on the \(side.title.lowercased())" }
            if let seconds = entry.duration(now: now), seconds > 0 { body += " for \(Format.duration(seconds))" }
            return Message(title: "\(who) fed \(baby)", body: body + " at \(at)")
        case .diaper:
            return Message(title: "\(who) changed \(baby)", body: "\(entry.diaper?.title ?? "Wet") diaper at \(at)")
        case .sleep:
            if entry.isOngoingSleep {
                return Message(title: "\(baby) is asleep", body: who == NanitSync.source ? "The camera saw her fall asleep at \(at)" : "\(who) put her down at \(at)")
            }
            return Message(title: "\(baby) slept \(Format.duration(entry.duration(now: now) ?? 0))", body: "Logged by \(who.lowercased() == "your partner" ? "your partner" : who)")
        case .note:
            return Message(title: "\(who) added a note", body: entry.note ?? "")
        case .milestone:
            return Message(title: "\(baby) hit a milestone", body: "\(entry.label ?? "") · noted by \(who)")
        case .pumping, .growth, .medicine, .tummyTime, .bath, .temperature:
            return Message(title: "\(who) logged \(entry.kind.title.lowercased())", body: "\(entry.title(unit: unit, now: now)) at \(at)")
        }
    }

    private static func post(_ message: Message) {
        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = message.body
        content.sound = .default
        content.threadIdentifier = "partner"
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
