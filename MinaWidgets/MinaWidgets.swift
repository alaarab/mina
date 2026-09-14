import AppIntents
import CoreData
import SwiftUI
import WidgetKit

/// Everything a widget shows, read once per timeline refresh.
struct MinaSnapshot {
    var babyName = "Mina"
    var lastFeedAt: Date?
    var lastFeedTitle = ""
    var feeds = 0
    var bottleML = 0.0
    var wet = 0
    var dirty = 0
    var sleepingSince: Date?
    var sleepSeconds = 0.0
    var lastBottleML = Prefs.lastBottleML
    var unit = Prefs.unit
    var hasBaby = false
    var goalLine = ""          // "5/8 feeds · 4/6 wet · 9h/15h"

    static func load(now: Date = .now) -> MinaSnapshot {
        var snapshot = MinaSnapshot()
        let persistence = PersistenceController.shared
        let context = persistence.container.viewContext
        context.performAndWait {
            context.refreshAllObjects()
            guard let baby = Logbook.shared.currentBaby(in: context) else { return }
            snapshot.hasBaby = true
            snapshot.babyName = baby.displayName
            if let feed = Logbook.shared.lastFeed(for: baby, in: context) {
                snapshot.lastFeedAt = feed.startedAt
                snapshot.lastFeedTitle = feed.title(unit: snapshot.unit, now: now)
            }
            let start = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: now)) ?? now
            let entries = Logbook.shared.entries(for: baby, from: start, in: context)
            let summary = DaySummary(entries: entries, day: now, now: now)
            snapshot.feeds = summary.feeds
            snapshot.bottleML = summary.bottleML
            snapshot.wet = summary.wet
            snapshot.dirty = summary.dirty
            snapshot.sleepSeconds = summary.sleepSeconds
            snapshot.sleepingSince = Logbook.shared.ongoingSleep(for: baby, in: context)?.startedAt
            let goals = Goals.evaluate(summary: summary, lastFeed: snapshot.lastFeedAt, stage: baby.ageDays(on: now).map(Guidance.stage(forAgeDays:)), ageDays: baby.ageDays(on: now), weightGrams: Logbook.shared.latestWeightGrams(for: baby, in: context), now: now)
            snapshot.goalLine = goals.filter { $0.kind != .feedGap && $0.kind != .dirty }.map { g in
                switch g.kind {
                case .sleep: return "\(Format.duration(g.value * 3600))/\(VolumeUnit.trim(g.target))h"
                case .volume: return "\(VolumeUnit.trim(Prefs.unit.display(ml: g.value).rounded()))/\(VolumeUnit.trim(Prefs.unit.display(ml: g.target).rounded())) \(g.unit)"
                default: return "\(Int(g.value))/\(Int(g.target)) \(g.unit)"
                }
            }.joined(separator: " · ")
        }
        return snapshot
    }
}

struct MinaEntry: TimelineEntry {
    let date: Date
    let snapshot: MinaSnapshot
}

struct MinaProvider: TimelineProvider {
    /// Stand-in numbers only. The widget gallery, the placeholder that shows
    /// while a timeline loads, and any snapshot the system takes for a preview
    /// all come through here, and none of them may show a real entry.
    func placeholder(in context: Context) -> MinaEntry {
        var snapshot = MinaSnapshot()
        snapshot.hasBaby = true
        snapshot.lastFeedAt = Date.now.addingTimeInterval(-80 * 60)
        snapshot.lastFeedTitle = "Bottle · 4 oz"
        snapshot.feeds = 5; snapshot.bottleML = 18 * VolumeUnit.millilitersPerOunce; snapshot.wet = 4; snapshot.dirty = 2
        snapshot.sleepSeconds = 4 * 3600
        return MinaEntry(date: .now, snapshot: snapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (MinaEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : MinaEntry(date: .now, snapshot: MinaSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MinaEntry>) -> Void) {
        let now = Date.now
        let snapshot = MinaSnapshot.load(now: now)
        // The relative "ago" text updates itself; refresh every 30 minutes so
        // the day's counts roll over and stale data never lingers.
        let entries = stride(from: 0, through: 4 * 3600, by: 1800).map { offset in
            MinaEntry(date: now.addingTimeInterval(Double(offset)), snapshot: snapshot)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Views

private struct AgoText: View {
    let date: Date?
    let fallback: String
    var body: some View {
        if let date {
            Text(date, style: .relative)
        } else {
            Text(fallback)
        }
    }
}

struct StatusWidgetView: View {
    let entry: MinaEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let snap = entry.snapshot
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: snap.sleepingSince == nil ? "waterbottle.fill" : "moon.zzz.fill").font(.system(size: 13, weight: .semibold))
                    if let since = snap.sleepingSince {
                        Text(since, style: .timer).font(.system(size: 11, weight: .semibold, design: .rounded)).multilineTextAlignment(.center)
                    } else if let at = snap.lastFeedAt {
                        Text(at, style: .timer).font(.system(size: 11, weight: .semibold, design: .rounded)).multilineTextAlignment(.center)
                    } else {
                        Text("—").font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                }
            }
        case .accessoryInline:
            if let since = snap.sleepingSince {
                Label { Text("Asleep ") + Text(since, style: .relative) } icon: { Image(systemName: "moon.zzz.fill") }
            } else if let at = snap.lastFeedAt {
                Label { Text("Fed ") + Text(at, style: .relative) + Text(" ago") } icon: { Image(systemName: "waterbottle.fill") }
            } else {
                Label("No feeds yet", systemImage: "waterbottle.fill")
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                if let since = snap.sleepingSince {
                    Text("Asleep for ").font(.headline) + Text(since, style: .relative).font(.headline)
                    Text("since \(Format.time(since))")
                } else if let at = snap.lastFeedAt {
                    (Text("Fed ") + Text(at, style: .relative) + Text(" ago")).font(.headline)
                    Text(snap.lastFeedTitle)
                } else {
                    Text("No feeds yet").font(.headline)
                }
                Text(snap.goalLine.isEmpty ? "\(snap.feeds) feeds · \(snap.wet + snap.dirty) diapers · \(Format.duration(snap.sleepSeconds)) sleep" : snap.goalLine)
                    .font(.caption2)
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(snap.babyName).font(.mina(.headline)).foregroundStyle(MinaTheme.text)
                    Spacer()
                    Image(systemName: snap.sleepingSince == nil ? "waterbottle.fill" : "moon.zzz.fill")
                        .foregroundStyle(snap.sleepingSince == nil ? MinaTheme.bottle : MinaTheme.sleep)
                }
                Spacer(minLength: 0)
                if let since = snap.sleepingSince {
                    Text("Asleep").font(.mina(.caption, weight: .semibold)).foregroundStyle(MinaTheme.sleep)
                    Text(since, style: .relative).font(.mina(.title2, weight: .bold)).foregroundStyle(MinaTheme.text).minimumScaleFactor(0.6)
                } else if let at = snap.lastFeedAt {
                    Text("Fed").font(.mina(.caption, weight: .semibold)).foregroundStyle(MinaTheme.bottle)
                    (Text(at, style: .relative) + Text(" ago")).font(.mina(.title3, weight: .bold)).foregroundStyle(MinaTheme.text).minimumScaleFactor(0.6)
                    Text(snap.lastFeedTitle).font(.mina(.caption2)).foregroundStyle(MinaTheme.textSecondary).lineLimit(1)
                } else {
                    Text("No feeds yet").font(.mina(.headline)).foregroundStyle(MinaTheme.text)
                }
                Spacer(minLength: 0)
                Text("\(snap.feeds) feeds · \(snap.unit.format(ml: snap.bottleML))")
                    .font(.mina(.caption2)).foregroundStyle(MinaTheme.textMuted).lineLimit(1)
                Text("\(snap.wet) wet · \(snap.dirty) dirty · \(Format.duration(snap.sleepSeconds)) sleep")
                    .font(.mina(.caption2)).foregroundStyle(MinaTheme.textMuted).lineLimit(1)
            }
        }
    }
}

struct QuickLogWidgetView: View {
    let entry: MinaEntry

    var body: some View {
        let snap = entry.snapshot
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    if let since = snap.sleepingSince {
                        (Text("Asleep ") + Text(since, style: .relative)).font(.mina(.headline)).foregroundStyle(MinaTheme.text)
                        Text("since \(Format.time(since))").font(.mina(.caption2)).foregroundStyle(MinaTheme.textSecondary)
                    } else if let at = snap.lastFeedAt {
                        (Text("Fed ") + Text(at, style: .relative) + Text(" ago")).font(.mina(.headline)).foregroundStyle(MinaTheme.text)
                        Text(snap.lastFeedTitle).font(.mina(.caption2)).foregroundStyle(MinaTheme.textSecondary)
                    } else {
                        Text("No feeds yet").font(.mina(.headline)).foregroundStyle(MinaTheme.text)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(snap.feeds) feeds · \(snap.unit.format(ml: snap.bottleML))")
                    Text("\(snap.wet) wet · \(snap.dirty) dirty")
                }
                .font(.mina(.caption2)).foregroundStyle(MinaTheme.textMuted)
            }
            HStack(spacing: 8) {
                WidgetButton(intent: WidgetLogBottleIntent(), title: snap.unit.format(ml: snap.lastBottleML), symbol: "waterbottle.fill", color: MinaTheme.bottle)
                WidgetButton(intent: WidgetLogPeeIntent(), title: "Pee", symbol: "drop.fill", color: MinaTheme.diaper)
                WidgetButton(intent: WidgetLogPoopIntent(), title: "Poop", symbol: "drop.circle.fill", color: MinaTheme.diaperDirty)
                WidgetButton(intent: WidgetToggleSleepIntent(), title: snap.sleepingSince == nil ? "Sleep" : "Awake",
                             symbol: snap.sleepingSince == nil ? "moon.zzz.fill" : "sun.max.fill", color: MinaTheme.sleep)
            }
        }
    }
}

private struct WidgetButton<Intent: AppIntent>: View {
    let intent: Intent
    let title: String
    let symbol: String
    let color: Color

    var body: some View {
        Button(intent: intent) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.callout.weight(.semibold))
                Text(title).font(.mina(.caption2, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(color)
            .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Widgets

struct MinaStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MinaStatus", provider: MinaProvider()) { entry in
            StatusWidgetView(entry: entry)
                // Lock-screen and StandBy families render before the phone is
                // unlocked; redact the feed and sleep data there.
                .privacySensitive()
                .containerBackground(MinaTheme.card, for: .widget)
        }
        .configurationDisplayName("Last feed")
        .description("When she last ate, and today's totals.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct MinaQuickLogWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MinaQuickLog", provider: MinaProvider()) { entry in
            QuickLogWidgetView(entry: entry)
                .privacySensitive()
                .containerBackground(MinaTheme.card, for: .widget)
        }
        .configurationDisplayName("Quick log")
        .description("Log a bottle, pee, poop or sleep with one tap.")
        .supportedFamilies([.systemMedium])
    }
}

@main
struct MinaWidgetBundle: WidgetBundle {
    var body: some Widget {
        MinaQuickLogWidget()
        MinaStatusWidget()
        if #available(iOS 18.0, *) {
            LogBottleControl()
            NursingControl()
            SleepControl()
        }
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { FeedAlarmActivity() }
        #endif
    }
}
