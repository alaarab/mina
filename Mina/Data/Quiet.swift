import Foundation

/// Silences this phone: no feed alarm, no feed reminder, no partner alerts.
/// Two ways in: a pause from Today ("quiet for 3 hours", "until 7 AM", "until
/// I turn it back on") and a nightly window in Settings. Per phone, so each
/// parent quiets their own; the Sunday digest is unaffected.
enum Quiet {
    static let untilKey = "quiet.until"
    static let hoursOnKey = "quiet.hours.on"
    static let hoursStartKey = "quiet.hours.start"
    static let hoursEndKey = "quiet.hours.end"
    static let morningHour = 7

    enum Pause: String, CaseIterable, Identifiable {
        case hour, threeHours, morning, indefinite
        var id: String { rawValue }
        var title: String {
            switch self {
            case .hour: return "1 hour"
            case .threeHours: return "3 hours"
            case .morning: return "Until \(morningHour) AM"
            case .indefinite: return "Until I turn it back on"
            }
        }
        func until(from now: Date, calendar: Calendar = .current) -> Date {
            switch self {
            case .hour: return now.addingTimeInterval(3600)
            case .threeHours: return now.addingTimeInterval(3 * 3600)
            case .morning: return calendar.nextDate(after: now, matching: DateComponents(hour: morningHour, minute: 0), matchingPolicy: .nextTime) ?? now.addingTimeInterval(8 * 3600)
            case .indefinite: return .distantFuture
            }
        }
    }

    /// End of a manual pause; `.distantFuture` means until resumed by hand.
    static var until: Date? {
        get { Prefs.defaults.object(forKey: untilKey) as? Date }
        set { Prefs.defaults.set(newValue, forKey: untilKey) }
    }
    static var hoursOn: Bool {
        get { Prefs.defaults.bool(forKey: hoursOnKey) }
        set { Prefs.defaults.set(newValue, forKey: hoursOnKey) }
    }
    /// Minutes after midnight; end may be before start (wraps past midnight).
    static var hoursStart: Int {
        get { Prefs.defaults.object(forKey: hoursStartKey) as? Int ?? 22 * 60 }
        set { Prefs.defaults.set(newValue, forKey: hoursStartKey) }
    }
    static var hoursEnd: Int {
        get { Prefs.defaults.object(forKey: hoursEndKey) as? Int ?? morningHour * 60 }
        set { Prefs.defaults.set(newValue, forKey: hoursEndKey) }
    }

    static func inHours(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard hoursOn else { return false }
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        return ShiftBlock(name: "", deviceID: "", startMinute: hoursStart, endMinute: hoursEnd).contains(minute)
    }

    /// True when nothing should ring or post at `date` on this phone.
    static func isQuiet(at date: Date = .now, calendar: Calendar = .current) -> Bool {
        if let until, until > date { return true }
        return inHours(date, calendar: calendar)
    }

    /// The banner text, or nil when this phone is not quiet right now.
    static func label(now: Date = .now, calendar: Calendar = .current) -> String? {
        if let until, until > now {
            return until == .distantFuture ? "Quiet until you turn it back on" : "Quiet until \(Format.time(until))"
        }
        if inHours(now, calendar: calendar) {
            let end = calendar.date(bySettingHour: hoursEnd / 60, minute: hoursEnd % 60, second: 0, of: now).map { $0 > now ? $0 : calendar.date(byAdding: .day, value: 1, to: $0) ?? $0 }
            return "Quiet hours until \(Format.time(end ?? now))"
        }
        return nil
    }

    static func pause(_ pause: Pause, now: Date = .now) {
        until = pause.until(from: now)
        FeedAlarm.cancel()
        Reminders.scheduleFeed(nil, babyName: "")
    }

    static func resume() {
        until = nil
    }
}
