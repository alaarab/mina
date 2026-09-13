import Foundation
import UserNotifications

/// One pending "feed is due" notification, replaced every time the log changes.
enum Reminders {
    static let feedKey = "feedReminders"
    private static let feedIdentifier = "next-feed"

    static var feedRemindersOn: Bool {
        get { Prefs.defaults.bool(forKey: feedKey) }
        set { Prefs.defaults.set(newValue, forKey: feedKey) }
    }

    static func scheduleFeed(_ prediction: FeedPrediction?, babyName: String, now: Date = .now) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [feedIdentifier])
        guard feedRemindersOn, let prediction, prediction.expectedAt > now.addingTimeInterval(60) else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(babyName) is probably getting hungry"
        content.body = "Last feed was \(Format.duration(prediction.interval)) ago, going by \(prediction.basis)."
        content.sound = .default
        content.threadIdentifier = "reminders"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: prediction.expectedAt.timeIntervalSince(now), repeats: false)
        center.add(UNNotificationRequest(identifier: feedIdentifier, content: content, trigger: trigger))
    }
}
