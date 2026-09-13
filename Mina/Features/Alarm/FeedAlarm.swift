import AppIntents
import Foundation
import SwiftUI
#if canImport(AlarmKit)
import AlarmKit
#endif

/// A real alarm for the next feed: rings through silent and Focus, shows the
/// lock-screen alarm UI, and its Stop button logs the feed. iOS 26 only; older
/// phones keep the notification reminder.
enum FeedAlarm {
    static let onKey = "feedAlarmOn"
    static let gapKey = "feedAlarmGapMinutes"    // 0 = use her predicted next feed
    static let idKey = "feedAlarmID"
    static let dismissedAtKey = "feedAlarmDismissedAt"
    static let armedForKey = "feedAlarmArmedForFeed"      // the last-feed time the current alarm was built from

    /// Set when the alarm was dismissed and no feed has been logged since.
    static var pendingDismissal: Date? {
        get { Prefs.defaults.object(forKey: dismissedAtKey) as? Date }
        set { Prefs.defaults.set(newValue, forKey: dismissedAtKey) }
    }
    static let gaps: [(minutes: Int, title: String)] = [(0, "Predicted"), (120, "2 h"), (150, "2½ h"), (180, "3 h"), (210, "3½ h"), (240, "4 h")]

    static var isSupported: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }
    static var isOn: Bool {
        get { Prefs.defaults.bool(forKey: onKey) }
        set { Prefs.defaults.set(newValue, forKey: onKey) }
    }
    static var gapMinutes: Int {
        get { Prefs.defaults.object(forKey: gapKey) as? Int ?? 180 }
        set { Prefs.defaults.set(newValue, forKey: gapKey) }
    }

    /// When the alarm should ring given the last feed and the prediction.
    static func fireDate(lastFeed: Date?, prediction: FeedPrediction?, now: Date = .now) -> Date? {
        if gapMinutes == 0 { return prediction?.expectedAt }
        guard let lastFeed else { return nil }
        return lastFeed.addingTimeInterval(Double(gapMinutes) * 60)
    }

    /// Runs the scheduling work one at a time. Today re-arms on appear, on
    /// every entry change and on every remote change, so two of these can
    /// easily overlap; without the queue both would pass the "already armed"
    /// check, and the alarm the loser scheduled would ring with no way to
    /// cancel it, since only the last id reaches `idKey`.
    private static let scheduling = SerialTasks()

    /// Schedules the next alarm once per feed. A screen refresh never re-arms
    /// an alarm that already fired; only a newer feed (or a settings change) does.
    static func reschedule(lastFeed: Date?, prediction: FeedPrediction?, babyName: String, now: Date = .now, force: Bool = false) {
        #if canImport(AlarmKit)
        guard #available(iOS 26.0, *) else { return }
        scheduling.enqueue {
            let manager = AlarmManager.shared
            let armedFor = Prefs.defaults.object(forKey: armedForKey) as? Date
            let hasAlarm = Prefs.defaults.string(forKey: idKey) != nil
            // Same feed as last time and an alarm already exists (or was dismissed): leave it alone.
            if !force, hasAlarm || pendingDismissal != nil, armedFor == lastFeed { return }
            // A newer feed than the one the alarm was built for: that alarm is stale, drop it.
            if let old = Prefs.defaults.string(forKey: idKey).flatMap(UUID.init(uuidString:)) { try? manager.cancel(id: old) }
            Prefs.defaults.removeObject(forKey: idKey)
            if let lastFeed, let dismissed = pendingDismissal, lastFeed > dismissed { pendingDismissal = nil }
            guard isOn, let date = fireDate(lastFeed: lastFeed, prediction: prediction, now: now), date > now.addingTimeInterval(60) else {
                Prefs.defaults.set(lastFeed, forKey: armedForKey); return
            }
            do {
                let status = try await manager.requestAuthorization()
                guard status == .authorized else { return }
                let alert = AlarmPresentation.Alert(
                    title: LocalizedStringResource(stringLiteral: "\(babyName)'s feed"),
                    stopButton: .init(text: "I'm up", textColor: .white, systemImageName: "sun.max.fill"),
                    secondaryButton: .init(text: "Snooze 10 min", textColor: .white, systemImageName: "zzz"),
                    secondaryButtonBehavior: .countdown)
                let countdown = AlarmPresentation.Countdown(title: LocalizedStringResource(stringLiteral: "Snoozed · \(babyName)'s feed"), pauseButton: nil)
                let attributes = AlarmAttributes<FeedAlarmMetadata>(
                    presentation: AlarmPresentation(alert: alert, countdown: countdown),
                    metadata: FeedAlarmMetadata(babyName: babyName, lastFeedAt: lastFeed),
                    tintColor: Color(hex: 0xE4826F))
                let configuration = AlarmManager.AlarmConfiguration<FeedAlarmMetadata>(
                    countdownDuration: .init(preAlert: nil, postAlert: 600),
                    schedule: .fixed(date), attributes: attributes,
                    stopIntent: DismissFeedAlarmIntent(), secondaryIntent: nil, sound: .default)
                let id = UUID()
                _ = try await manager.schedule(id: id, configuration: configuration)
                Prefs.defaults.set(id.uuidString, forKey: idKey)
                Prefs.defaults.set(lastFeed, forKey: armedForKey)
            } catch {
                NSLog("feed alarm: \(error)")
            }
        }
        #endif
    }

    /// Queued behind any scheduling already under way, so a cancel can't clear
    /// the stored id a half-finished `reschedule` is about to write.
    static func cancel() {
        #if canImport(AlarmKit)
        guard #available(iOS 26.0, *) else { return }
        scheduling.enqueue {
            if let old = Prefs.defaults.string(forKey: idKey).flatMap(UUID.init(uuidString:)) { try? AlarmManager.shared.cancel(id: old) }
            // Belt and braces: cancel anything of ours the system still holds.
            if let all = try? AlarmManager.shared.alarms { for alarm in all { try? AlarmManager.shared.cancel(id: alarm.id) } }
            Prefs.defaults.removeObject(forKey: idKey)
            Prefs.defaults.removeObject(forKey: armedForKey)
        }
        #endif
    }
}

/// The alarm's Stop button only dismisses the alarm. Stopping an alarm means
/// someone is up, not that the baby ate; the app asks to log the feed instead.
struct DismissFeedAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Dismiss feed alarm"
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        Prefs.defaults.set(Date.now, forKey: FeedAlarm.dismissedAtKey)
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *), let id = Prefs.defaults.string(forKey: FeedAlarm.idKey).flatMap(UUID.init(uuidString:)) {
            try? AlarmManager.shared.cancel(id: id)
        }
        #endif
        Prefs.defaults.removeObject(forKey: FeedAlarm.idKey)
        return .result()
    }
}
