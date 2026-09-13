import CoreData
import Foundation
import UserNotifications

/// Sunday evening: one notification with the week in numbers and how it
/// compares to the week before. Built on the phone from the log; nothing is
/// sent anywhere.
enum WeeklyDigest {
    static let onKey = "weeklyDigestOn"
    static let identifier = "weekly-digest"

    static var isOn: Bool {
        get { Prefs.defaults.object(forKey: onKey) == nil ? true : Prefs.defaults.bool(forKey: onKey) }
        set { Prefs.defaults.set(newValue, forKey: onKey) }
    }

    struct Summary: Equatable {
        var feeds = 0
        var bottleML = 0.0
        var wet = 0
        var dirty = 0
        var sleepSeconds = 0.0
        var longestSleep = 0.0
        var nights = 0
    }

    static func summary(entries: [LogEntry], from start: Date, days: Int, now: Date = .now, calendar: Calendar = .current) -> Summary {
        var s = Summary()
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let d = DaySummary(entries: entries, day: day, now: now, calendar: calendar)
            s.feeds += d.feeds; s.bottleML += d.bottleML; s.wet += d.wet; s.dirty += d.dirty; s.sleepSeconds += d.sleepSeconds
            s.nights += 1
        }
        s.longestSleep = entries.filter { $0.kind == .sleep && $0.endedAt != nil && ($0.startedAt ?? .distantPast) >= start }.map { $0.duration(now: now) ?? 0 }.max() ?? 0
        return s
    }

    /// "This week: 52 feeds (17 oz a day), 41 wet, 12 dirty, 14h 20m sleep a day, longest stretch 5h 10m. Up 2 oz a day on last week."
    static func text(this: Summary, last: Summary?, unit: VolumeUnit, babyName: String) -> String {
        let days = max(1, this.nights)
        var parts = ["\(this.feeds) feeds"]
        if this.bottleML > 0 { parts.append("\(unit.format(ml: this.bottleML / Double(days))) a day by bottle") }
        parts.append("\(this.wet) wet and \(this.dirty) dirty diapers")
        parts.append("\(Format.duration(this.sleepSeconds / Double(days))) of sleep a day")
        if this.longestSleep > 0 { parts.append("longest stretch \(Format.duration(this.longestSleep))") }
        var text = "\(babyName) this week: " + parts.joined(separator: ", ") + "."
        if let last, last.nights > 0 {
            var deltas: [String] = []
            let mlDelta = this.bottleML / Double(days) - last.bottleML / Double(max(1, last.nights))
            if abs(mlDelta) >= 15 { deltas.append("\(mlDelta > 0 ? "up" : "down") \(unit.format(ml: abs(mlDelta))) a day") }
            let sleepDelta = (this.sleepSeconds - last.sleepSeconds) / Double(days) / 60
            if abs(sleepDelta) >= 30 { deltas.append("\(sleepDelta > 0 ? "up" : "down") \(Format.duration(abs(sleepDelta) * 60)) of sleep a day") }
            let stretchDelta = this.longestSleep - last.longestSleep
            if abs(stretchDelta) >= 30 * 60 { deltas.append("longest stretch \(stretchDelta > 0 ? "up" : "down") \(Format.duration(abs(stretchDelta)))") }
            if !deltas.isEmpty { text += " Versus last week: " + deltas.joined(separator: ", ") + "." }
        }
        return text
    }

    /// Next Sunday at 7 PM (or today if it's Sunday before 7).
    static func nextFireDate(after now: Date = .now, calendar: Calendar = .current) -> Date {
        var components = DateComponents(); components.weekday = 1; components.hour = 19; components.minute = 0
        return calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime) ?? now.addingTimeInterval(7 * 86_400)
    }

    /// Builds this week's digest from the log and schedules it as a local
    /// notification for Sunday evening. Called whenever the log changes, so the
    /// numbers are as fresh as the last entry before it fires.
    static func schedule(for baby: Baby, in context: NSManagedObjectContext, now: Date = .now) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard isOn else { return }
        let calendar = Calendar.current
        let fire = nextFireDate(after: now, calendar: calendar)
        let weekStart = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: fire)) ?? fire
        let lastStart = calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
        let entries = Logbook.shared.entries(for: baby, from: calendar.date(byAdding: .day, value: -1, to: lastStart) ?? lastStart, in: context)
        let this = summary(entries: entries, from: weekStart, days: 7, now: now, calendar: calendar)
        let last = summary(entries: entries, from: lastStart, days: 7, now: now, calendar: calendar)
        guard this.feeds + this.wet + this.dirty > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(baby.displayName)'s week"
        content.body = text(this: this, last: last.feeds + last.wet > 0 ? last : nil, unit: Prefs.unit, babyName: baby.displayName)
        content.sound = .default
        content.threadIdentifier = "digest"
        content.interruptionLevel = .passive
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
    }
}
