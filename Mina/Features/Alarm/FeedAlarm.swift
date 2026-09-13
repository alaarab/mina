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

    /// Cancels the previous alarm and schedules the next, if there is one in the future.
    static func reschedule(lastFeed: Date?, prediction: FeedPrediction?, babyName: String, now: Date = .now) {
        #if canImport(AlarmKit)
        guard #available(iOS 26.0, *) else { return }
        Task {
            let manager = AlarmManager.shared
            if let old = Prefs.defaults.string(forKey: idKey).flatMap(UUID.init(uuidString:)) { try? manager.cancel(id: old) }
            guard isOn, let date = fireDate(lastFeed: lastFeed, prediction: prediction, now: now), date > now.addingTimeInterval(60) else {
                Prefs.defaults.removeObject(forKey: idKey); return
            }
            do {
                let status = try await manager.requestAuthorization()
                guard status == .authorized else { return }
                let alert = AlarmPresentation.Alert(
                    title: LocalizedStringResource(stringLiteral: "\(babyName)'s feed"),
                    stopButton: .init(text: "Log feed", textColor: .white, systemImageName: "waterbottle.fill"),
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
                    stopIntent: LogFeedFromAlarmIntent(), secondaryIntent: nil, sound: .default)
                let id = UUID()
                _ = try await manager.schedule(id: id, configuration: configuration)
                Prefs.defaults.set(id.uuidString, forKey: idKey)
            } catch {
                NSLog("feed alarm: \(error)")
            }
        }
        #endif
    }

    static func cancel() {
        #if canImport(AlarmKit)
        guard #available(iOS 26.0, *) else { return }
        if let old = Prefs.defaults.string(forKey: idKey).flatMap(UUID.init(uuidString:)) { try? AlarmManager.shared.cancel(id: old) }
        Prefs.defaults.removeObject(forKey: idKey)
        #endif
    }
}

/// The alarm's Stop button: logs a bottle at the last amount so the feed is on
/// the record before the phone is even unlocked. Edit it later if it was nursing.
struct LogFeedFromAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Log feed from alarm"
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        let milliliters = Prefs.lastBottleML
        _ = try? await Logbook.shared.perform { context, baby in
            var draft = EntryDraft(kind: .bottle)
            draft.amountML = milliliters
            draft.note = "Logged from the alarm"
            return try Logbook.shared.add(draft, to: baby, in: context)
        }
        return .result()
    }
}
