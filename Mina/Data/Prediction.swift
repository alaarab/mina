import Foundation

struct FeedPrediction: Equatable {
    let expectedAt: Date
    let interval: TimeInterval
    /// "her last 8 feeds" or "typical at 3 weeks".
    let basis: String
}

struct NapPrediction: Equatable {
    let expectedAt: Date
    let wakeWindow: TimeInterval
}

/// Learns her rhythm from the log and falls back to age norms until there's
/// enough of it. Pure functions, so they're tested directly.
enum Predictor {
    /// Feed start times, newest first.
    static func nextFeed(feedTimes: [Date], stage: GuideStage?, now: Date = .now) -> FeedPrediction? {
        guard let last = feedTimes.first else { return nil }
        let recent = Array(feedTimes.prefix(9))
        var intervals: [TimeInterval] = []
        for index in 0..<(recent.count - 1) {
            let gap = recent[index].timeIntervalSince(recent[index + 1])
            if gap >= 20 * 60, gap <= 6 * 3600 { intervals.append(gap) }
        }
        if intervals.count >= 3 {
            let sorted = intervals.sorted()
            let median = sorted.count % 2 == 0
                ? (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
                : sorted[sorted.count / 2]
            return FeedPrediction(expectedAt: last.addingTimeInterval(median), interval: median, basis: "her last \(intervals.count + 1) feeds")
        }
        guard let stage else { return nil }
        let perDay = Double(stage.expectation.feedsPerDay.lowerBound + stage.expectation.feedsPerDay.upperBound) / 2
        let interval = 86_400 / perDay
        return FeedPrediction(expectedAt: last.addingTimeInterval(interval), interval: interval, basis: "typical for \(stage.title.lowercased())")
    }

    /// How long she can comfortably stay awake at this age.
    static func wakeWindow(ageDays: Int) -> TimeInterval {
        switch ageDays {
        case ..<28: return 50 * 60
        case 28..<56: return 75 * 60
        case 56..<91: return 85 * 60
        default: return 105 * 60
        }
    }

    static func nextNap(lastWake: Date?, ageDays: Int?, now: Date = .now) -> NapPrediction? {
        guard let lastWake, let ageDays else { return nil }
        let window = wakeWindow(ageDays: ageDays)
        return NapPrediction(expectedAt: lastWake.addingTimeInterval(window), wakeWindow: window)
    }

    /// "in 35m", "now", or "20m ago".
    static func phrase(for date: Date, now: Date = .now) -> String {
        let delta = date.timeIntervalSince(now)
        if abs(delta) < 5 * 60 { return "about now" }
        return delta > 0 ? "in \(Format.duration(delta))" : "\(Format.duration(-delta)) ago"
    }
}
