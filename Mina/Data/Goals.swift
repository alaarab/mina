import Foundation

/// Daily targets for her age, judged against the time of day, so "3 wet by
/// noon" is on track and "3 wet at 10 PM" is behind. Targets come from the
/// guide's ranges unless the parent has set their own in Settings (a
/// pediatrician's plan).
struct Goal: Identifiable, Equatable {
    enum Kind: String, CaseIterable { case feeds, wet, dirty, sleep, feedGap }
    enum Status { case onTrack, behind, short, done }

    let kind: Kind
    let title: String
    let value: Double          // so far today
    let target: Double         // for the whole day
    let unit: String           // "feeds", "wet", "h"
    let status: Status
    let detail: String         // "5 of 8 · on track"

    var id: String { kind.rawValue }
    var progress: Double { target > 0 ? min(1, value / target) : 0 }
}

enum Goals {
    static let customKey = "goals.custom"   // JSON [kind: target]

    static func custom() -> [Goal.Kind: Double] {
        guard let data = Prefs.defaults.data(forKey: customKey), let raw = try? JSONDecoder().decode([String: Double].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in Goal.Kind(rawValue: k).map { ($0, v) } })
    }

    static func setCustom(_ targets: [Goal.Kind: Double]) {
        let raw = Dictionary(uniqueKeysWithValues: targets.map { ($0.key.rawValue, $0.value) })
        Prefs.defaults.set(try? JSONEncoder().encode(raw), forKey: customKey)
    }

    /// Whole-day targets for a stage, with any custom overrides applied.
    static func targets(for stage: GuideStage?, ageDays: Int?) -> [Goal.Kind: Double] {
        var t: [Goal.Kind: Double] = [:]
        if let stage {
            let feeds = stage.expectation.feedsPerDay
            t[.feeds] = Double(feeds.lowerBound)
            t[.wet] = Double(stage.expectation.wetDiapersPerDay)
            t[.sleep] = stage.expectation.sleepHours.lowerBound
        }
        // Dirty diapers: 3+ a day in the first weeks, then it varies too much to be a goal.
        if let ageDays, ageDays < 28 { t[.dirty] = 3 }
        // Wake-to-feed limit until she's back to birth weight, roughly two weeks: 4 hours; then 5.
        t[.feedGap] = (ageDays ?? 0) < 14 ? 4 : 5
        for (kind, value) in custom() { t[kind] = value }
        return t
    }

    /// Fraction of the day that's passed, used to judge "behind" fairly.
    static func dayFraction(now: Date, calendar: Calendar = .current) -> Double {
        let start = calendar.startOfDay(for: now)
        return min(1, max(0, now.timeIntervalSince(start) / 86_400))
    }

    static func evaluate(summary: DaySummary, lastFeed: Date?, stage: GuideStage?, ageDays: Int?, now: Date = .now, calendar: Calendar = .current) -> [Goal] {
        let t = targets(for: stage, ageDays: ageDays)
        let fraction = dayFraction(now: now, calendar: calendar)
        var goals: [Goal] = []

        func status(_ value: Double, _ target: Double) -> Goal.Status {
            if value >= target { return .done }
            // Expected-by-now with a one-unit grace; after 9 PM anything short is "short".
            let hour = calendar.component(.hour, from: now)
            if hour >= 21 { return .short }
            let expected = target * fraction
            return value + 1 >= expected ? .onTrack : .behind
        }
        func word(_ s: Goal.Status) -> String {
            switch s { case .done: return "done"; case .onTrack: return "on track"; case .behind: return "a bit behind"; case .short: return "short today" }
        }

        if let target = t[.feeds] {
            let v = Double(summary.feeds); let s = status(v, target)
            goals.append(Goal(kind: .feeds, title: "Feeds", value: v, target: target, unit: "feeds", status: s, detail: "\(Int(v)) of \(Int(target)) · \(word(s))"))
        }
        if let target = t[.wet] {
            let v = Double(summary.wet); let s = status(v, target)
            goals.append(Goal(kind: .wet, title: "Wet diapers", value: v, target: target, unit: "wet", status: s, detail: "\(Int(v)) of \(Int(target)) · \(word(s))"))
        }
        if let target = t[.dirty] {
            let v = Double(summary.dirty); let s = status(v, target)
            goals.append(Goal(kind: .dirty, title: "Dirty diapers", value: v, target: target, unit: "dirty", status: s, detail: "\(Int(v)) of \(Int(target)) · \(word(s))"))
        }
        if let target = t[.sleep] {
            let v = summary.sleepSeconds / 3600; let s = status(v, target)
            goals.append(Goal(kind: .sleep, title: "Sleep", value: v, target: target, unit: "h", status: s, detail: "\(Format.duration(summary.sleepSeconds)) of \(VolumeUnit.trim(target))h · \(word(s))"))
        }
        if let limit = t[.feedGap] {
            let gap = lastFeed.map { now.timeIntervalSince($0) / 3600 } ?? 0
            let s: Goal.Status = lastFeed == nil ? .onTrack : (gap >= limit ? .short : (gap >= limit - 0.5 ? .behind : .onTrack))
            let detail = lastFeed == nil ? "no feed yet" : (gap >= limit ? "\(Format.duration(gap * 3600)) since the last feed · time to wake her" : "\(Format.duration(gap * 3600)) since the last feed · limit \(VolumeUnit.trim(limit))h")
            goals.append(Goal(kind: .feedGap, title: "Since last feed", value: min(gap, limit), target: limit, unit: "h", status: s, detail: detail))
        }
        return goals
    }

    /// The one-line worry for the day, or nil when there's nothing to say.
    static func concern(_ goals: [Goal], ageDays: Int?) -> String? {
        if let gap = goals.first(where: { $0.kind == .feedGap }), gap.status == .short, (ageDays ?? 99) < 14 {
            return "Newborns should be woken to feed every \(VolumeUnit.trim(gap.target)) hours until they're back to birth weight."
        }
        if let wet = goals.first(where: { $0.kind == .wet }), wet.status == .short, (ageDays ?? 0) >= 5 {
            return "Fewer than \(Int(wet.target)) wet diapers after day 5 is worth a call to the pediatrician."
        }
        return nil
    }

    /// "4 of 6 wet diapers, 5 of 8 feeds, 9 hours of 15 of sleep" for Siri.
    static func spoken(_ goals: [Goal]) -> String {
        let parts = goals.filter { $0.kind != .feedGap }.map { g -> String in
            switch g.kind {
            case .sleep: return "\(Format.spokenDuration(g.value * 3600)) of \(VolumeUnit.trim(g.target)) hours of sleep"
            default: return "\(Int(g.value)) of \(Int(g.target)) \(g.unit)"
            }
        }
        return parts.joined(separator: ", ")
    }
}
