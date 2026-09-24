import ActivityKit
import CoreData
import Foundation

/// Mirrors the two timers parents most need with the phone locked. There is at
/// most one activity per running entry and stale activities are dismissed when
/// the app next becomes active.
@MainActor
enum CareTimerActivities {
    static func handle(_ snapshot: TimerSnapshot, ended: Bool) async {
        let matches = Activity<CareTimerAttributes>.activities.filter { $0.attributes.entryID == snapshot.id }
        if ended {
            for activity in matches {
                await activity.end(ActivityContent(state: state(snapshot), staleDate: nil), dismissalPolicy: .immediate)
            }
            return
        }

        if let activity = matches.first {
            await activity.update(ActivityContent(state: state(snapshot), staleDate: nil))
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = CareTimerAttributes(entryID: snapshot.id, babyName: snapshot.babyName, kind: snapshot.kind.rawValue)
        _ = try? Activity.request(attributes: attributes,
                                  content: ActivityContent(state: state(snapshot), staleDate: nil),
                                  pushType: nil)
    }

    static func reconcile(for baby: Baby, in context: NSManagedObjectContext) async {
        let running = [Logbook.shared.ongoingSleep(for: baby, in: context),
                       Logbook.shared.ongoingNursing(for: baby, in: context)]
            .compactMap { $0 }
            .compactMap(TimerSnapshot.init)
        let ids = Set(running.map(\.id))
        for activity in Activity<CareTimerAttributes>.activities where !ids.contains(activity.attributes.entryID) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        for snapshot in running { await handle(snapshot, ended: false) }
    }

    private static func state(_ snapshot: TimerSnapshot) -> CareTimerAttributes.ContentState {
        .init(startedAt: snapshot.startedAt, detail: snapshot.detail)
    }
}
