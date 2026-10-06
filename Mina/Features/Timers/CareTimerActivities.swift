import ActivityKit
import CoreData
import Foundation

/// Re-read saved state for every change, rather than replaying potentially stale
/// start/end callbacks. Serial jobs prevent a delayed start from undoing an end.
@MainActor
enum CareTimerActivities {
    private static let jobs = SerialTasks()
    private static var observers: [NSObjectProtocol] = []
    private static var expiry: Task<Void, Never>?

    static func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [Notification.Name.NSManagedObjectContextDidSave,
                     .NSManagedObjectContextDidMergeChangesObjectIDs,
                     UserDefaults.didChangeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: nil) { _ in
                Task { @MainActor in refresh() }
            })
        }
        refresh() // Also dismiss pre-upgrade activities when no baby is selected.
    }

    static func refresh() {
        jobs.enqueue { await reconcile() }
    }

    private static func reconcile() async {
        let context = PersistenceController.shared.container.viewContext
        let policy = CareTimerPolicy(defaults: Prefs.defaults, deviceID: Prefs.deviceID)
        let running = policy.running(for: Logbook.shared.currentBaby(in: context), in: context)
        let ids = Set(running.map(\.id))
        for activity in Activity<CareTimerAttributes>.activities where !ids.contains(activity.attributes.entryID) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        for snapshot in running {
            let deadline = snapshot.startedAt.addingTimeInterval(CareTimerPolicy.maximumAge)
            let content = ActivityContent(state: CareTimerAttributes.ContentState(startedAt: snapshot.startedAt, detail: snapshot.detail), staleDate: deadline)
            let matches = Activity<CareTimerAttributes>.activities.filter { $0.attributes.entryID == snapshot.id }
            if let activity = matches.first {
                await activity.update(content)
                for duplicate in matches.dropFirst() { await duplicate.end(nil, dismissalPolicy: .immediate) }
            } else if ActivityAuthorizationInfo().areActivitiesEnabled {
                let attributes = CareTimerAttributes(entryID: snapshot.id, babyName: snapshot.babyName, kind: snapshot.kind.rawValue)
                _ = try? Activity.request(attributes: attributes, content: content, pushType: nil)
            }
        }
        expiry?.cancel()
        if let deadline = running.map({ $0.startedAt.addingTimeInterval(CareTimerPolicy.maximumAge) }).min() {
            expiry = Task {
                do { try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow))) }
                catch { return }
                refresh()
            }
        }
    }
}
