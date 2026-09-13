import CoreData
import SwiftUI

struct TodayView: View {
    @ObservedObject var baby: Baby

    var body: some View {
        // Re-render every minute so "1h 20m ago" stays honest; a new day gets a fresh fetch.
        TimelineView(.everyMinute) { timeline in
            TodayContent(baby: baby, now: timeline.date)
                .id(Calendar.current.startOfDay(for: timeline.date))
        }
    }
}

private struct TodayContent: View {
    @ObservedObject var baby: Baby
    let now: Date

    @Environment(\.managedObjectContext) private var context
    @AppStorage(Prefs.unitKey, store: Prefs.defaults) private var unitRaw = VolumeUnit.ounces.rawValue
    @AppStorage(Prefs.lastBottleKey, store: Prefs.defaults) private var lastBottleML = 0.0
    @FetchRequest private var entries: FetchedResults<LogEntry>
    @State private var sheet: QuickSheet?
    @State private var editing: LogEntry?
    @State private var error: String?
    @State private var asking = false

    private var unit: VolumeUnit { VolumeUnit(rawValue: unitRaw) ?? .ounces }

    init(baby: Baby, now: Date) {
        _baby = ObservedObject(wrappedValue: baby)
        self.now = now
        let today = Calendar.current.startOfDay(for: now)
        let start = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
        _entries = FetchRequest(fetchRequest: LogEntry.request(for: baby, from: start), animation: .default)
    }

    private var sleeping: LogEntry? { entries.first { $0.isOngoingSleep } }
    private var lastFeed: LogEntry? { entries.first { $0.kind.isFeed } }
    private var summary: DaySummary { DaySummary(entries: Array(entries), day: now, now: now) }
    private var stage: GuideStage? { baby.ageDays(on: now).map(Guidance.stage(forAgeDays:)) }
    private var feedPrediction: FeedPrediction? {
        let times = entries.filter { $0.kind.isFeed }.compactMap(\.startedAt)
        return Predictor.nextFeed(feedTimes: times, stage: stage, now: now)
    }
    private var napPrediction: NapPrediction? {
        guard sleeping == nil else { return nil }
        let lastWake = entries.filter { $0.kind == .sleep && $0.endedAt != nil }.compactMap(\.endedAt).max()
        return Predictor.nextNap(lastWake: lastWake, ageDays: baby.ageDays(on: now), now: now)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    statusCard
                    statsRow
                    quickLog
                    timeline
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(MinaTheme.canvas.ignoresSafeArea())
            .navigationTitle(baby.displayName)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { asking = true } label: { Label("Ask", systemImage: "sparkles") }
                }
            }
            .sheet(isPresented: $asking) {
                AskView(baby: baby, stats: TrendMath.stats(entries: Array(entries), days: 2, now: now), recent: entries.prefix(12).map { "\(($0.startedAt ?? now).formatted(.dateTime.weekday(.abbreviated).hour().minute())): \($0.title(unit: unit, now: now))" }, unit: unit)
            }
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .bottle: BottleSheet(unit: unit) { log($0) }
                case .nursing: NursingSheet { log($0) }
                case .note: NoteSheet { log($0) }
                case .extra(let kind): ExtraSheet(kind: kind, unit: unit) { log($0) }
                }
            }
            .sheet(item: $editing) { EntryEditor(entry: $0) }
            .alert("Couldn't save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") {}
            } message: { Text(error ?? "") }
            .onAppear { Reminders.scheduleFeed(feedPrediction, babyName: baby.displayName, now: now) }
            .onChange(of: entries.count) { _, _ in Reminders.scheduleFeed(feedPrediction, babyName: baby.displayName, now: now) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(baby.ageDescription(on: now))
                .font(.mina(.title3, weight: .semibold))
                .foregroundStyle(MinaTheme.text)
            Text(now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.mina(.subheadline))
                .foregroundStyle(MinaTheme.textMuted)
        }
        .padding(.top, 4)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(MinaTheme.accent)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    if let lastFeed, let at = lastFeed.startedAt {
                        Text("Fed \(Format.ago(from: at, to: now))")
                            .font(.mina(.headline))
                        Text("\(lastFeed.title(unit: unit, now: now)) at \(Format.time(at))")
                            .font(.mina(.subheadline))
                            .foregroundStyle(MinaTheme.textSecondary)
                    } else {
                        Text("No feeds logged yet")
                            .font(.mina(.headline))
                        Text("Tap Bottle below, or say “Hey Siri, \(baby.displayName) ate 3 ounces.”")
                            .font(.mina(.subheadline))
                            .foregroundStyle(MinaTheme.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            if let prediction = feedPrediction, sleeping == nil || prediction.expectedAt > now {
                Divider()
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18))
                        .foregroundStyle(prediction.expectedAt < now.addingTimeInterval(-15 * 60) ? MinaTheme.warning : MinaTheme.textMuted)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Next feed \(Predictor.phrase(for: prediction.expectedAt, now: now))")
                            .font(.mina(.subheadline, weight: .semibold))
                        Text("around \(Format.time(prediction.expectedAt)), every \(Format.duration(prediction.interval)) going by \(prediction.basis)")
                            .font(.mina(.caption))
                            .foregroundStyle(MinaTheme.textMuted)
                    }
                    Spacer(minLength: 0)
                }
            }
            if let nap = napPrediction {
                Divider()
                HStack(spacing: 12) {
                    Image(systemName: "moon.zzz")
                        .font(.system(size: 18))
                        .foregroundStyle(nap.expectedAt < now ? MinaTheme.sleep : MinaTheme.textMuted)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(nap.expectedAt < now ? "Nap window is open" : "Nap window \(Predictor.phrase(for: nap.expectedAt, now: now))")
                            .font(.mina(.subheadline, weight: .semibold))
                        Text("about \(Format.duration(nap.wakeWindow)) awake is her limit at this age")
                            .font(.mina(.caption))
                            .foregroundStyle(MinaTheme.textMuted)
                    }
                    Spacer(minLength: 0)
                }
            }
            if let sleeping, let since = sleeping.startedAt {
                Divider()
                HStack(spacing: 12) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(MinaTheme.sleep)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Asleep for \(Format.duration(now.timeIntervalSince(since)))")
                            .font(.mina(.headline))
                        Text("since \(Format.time(since))")
                            .font(.mina(.subheadline))
                            .foregroundStyle(MinaTheme.textSecondary)
                    }
                    Spacer()
                    Button("Woke up") { endSleep(sleeping) }
                        .buttonStyle(.borderedProminent)
                        .tint(MinaTheme.sleep)
                        .font(.mina(.subheadline, weight: .semibold))
                }
            }
        }
        .minaCard()
    }

    private var statsRow: some View {
        let summary = summary
        return HStack(spacing: 10) {
            StatTile(title: "Feeds", value: "\(summary.feeds)", color: MinaTheme.bottle,
                     detail: feedDetail(summary),
                     expect: stage.map { "expect \($0.expectation.feedsText())" })
            StatTile(title: "Diapers", value: "\(summary.diapers)", color: MinaTheme.diaper,
                     detail: "\(summary.wet) wet · \(summary.dirty) dirty",
                     expect: stage.map { "expect \($0.expectation.wetText())" })
            StatTile(title: "Sleep", value: summary.sleepSeconds > 0 ? Format.duration(summary.sleepSeconds) : "0m", color: MinaTheme.sleep,
                     detail: "\(summary.sleeps) \(summary.sleeps == 1 ? "stretch" : "stretches")",
                     expect: stage.map { "expect \($0.expectation.sleepText())" })
        }
    }

    private func feedDetail(_ summary: DaySummary) -> String {
        var parts: [String] = []
        if summary.bottleML > 0 { parts.append(unit.format(ml: summary.bottleML)) }
        if summary.nursingCount > 0 { parts.append("\(summary.nursingCount) nursed") }
        return parts.isEmpty ? "nothing yet" : parts.joined(separator: " · ")
    }

    private var quickLog: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                QuickButton(title: "Bottle", subtitle: "Last \(unit.format(ml: Prefs.lastBottleML))", symbol: EntryKind.bottle.symbol, color: MinaTheme.bottle) {
                    sheet = .bottle
                }
                QuickButton(title: "Nurse", subtitle: "Left or right", symbol: EntryKind.nursing.symbol, color: MinaTheme.nursing) {
                    sheet = .nursing
                }
                Menu {
                    ForEach(DiaperKind.allCases) { kind in
                        Button(kind.title) { logDiaper(kind) }
                    }
                } label: {
                    QuickButtonLabel(title: "Diaper", subtitle: "Wet or dirty", symbol: EntryKind.diaper.symbol, color: MinaTheme.diaper)
                }
                if let sleeping, let since = sleeping.startedAt {
                    QuickButton(title: "Woke up", subtitle: "Asleep \(Format.duration(now.timeIntervalSince(since)))", symbol: "sun.max.fill", color: MinaTheme.sleep) {
                        endSleep(sleeping)
                    }
                } else {
                    QuickButton(title: "Sleep", subtitle: "Start a nap now", symbol: EntryKind.sleep.symbol, color: MinaTheme.sleep) {
                        log(EntryDraft(kind: .sleep, startedAt: now))
                    }
                }
            }
            HStack(spacing: 10) {
                Button {
                    sheet = .note
                } label: {
                    Label("Note", systemImage: "square.and.pencil").pillLabel()
                }
                .buttonStyle(.plain)
                Menu {
                    ForEach(EntryKind.extras) { kind in
                        Button(kind.title, systemImage: kind.symbol) {
                            if kind == .bath { log(EntryDraft(kind: .bath, startedAt: now)) } else { sheet = .extra(kind) }
                        }
                    }
                } label: {
                    Label("More", systemImage: "plus.circle").pillLabel()
                }
            }
        }
    }

    private var timeline: some View {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.startedAt ?? now) }
            .sorted { $0.key > $1.key }
        return VStack(alignment: .leading, spacing: 18) {
            if groups.isEmpty {
                VStack(spacing: 6) {
                    Text("Nothing logged yet")
                        .font(.mina(.headline))
                    Text("Every feed, diaper and nap you or your partner log shows up here on both phones.")
                        .font(.mina(.subheadline))
                        .foregroundStyle(MinaTheme.textMuted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
            ForEach(groups, id: \.key) { day, dayEntries in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Format.dayTitle(day, now: now))
                            .font(.mina(.headline))
                        Spacer()
                        Text(dayLine(dayEntries, day: day))
                            .font(.mina(.caption))
                            .foregroundStyle(MinaTheme.textMuted)
                    }
                    .padding(.horizontal, 4)
                    EntryList(entries: dayEntries, unit: unit, now: now, onEdit: { editing = $0 }, onDelete: delete)
                }
            }
        }
    }

    private func dayLine(_ dayEntries: [LogEntry], day: Date) -> String {
        let summary = DaySummary(entries: dayEntries, day: day, now: now)
        var parts: [String] = []
        if summary.feeds > 0 {
            parts.append("\(summary.feeds) \(summary.feeds == 1 ? "feed" : "feeds")" + (summary.bottleML > 0 ? " · \(unit.format(ml: summary.bottleML))" : ""))
        }
        if summary.diapers > 0 { parts.append("\(summary.diapers) \(summary.diapers == 1 ? "diaper" : "diapers")") }
        if summary.sleepSeconds > 0 { parts.append("\(Format.duration(summary.sleepSeconds)) sleep") }
        if summary.pumpedML > 0 { parts.append("\(unit.format(ml: summary.pumpedML)) pumped") }
        return parts.joined(separator: " · ")
    }

    // MARK: Actions

    private func log(_ draft: EntryDraft) {
        do {
            try Logbook.shared.add(draft, to: baby, in: context)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func logDiaper(_ kind: DiaperKind) {
        var draft = EntryDraft(kind: .diaper, startedAt: now)
        draft.diaper = kind
        log(draft)
    }

    private func endSleep(_ entry: LogEntry) {
        entry.endedAt = max(now, entry.startedAt ?? now)
        do { try context.save() } catch { self.error = error.localizedDescription }
    }

    private func delete(_ entry: LogEntry) {
        do { try Logbook.shared.delete(entry, in: context) } catch { self.error = error.localizedDescription }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let color: Color
    let detail: String
    let expect: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.mina(.caption, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.mina(.title, weight: .bold))
                .foregroundStyle(MinaTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(.mina(.caption2))
                .foregroundStyle(MinaTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let expect {
                Text(expect)
                    .font(.mina(.caption2))
                    .foregroundStyle(MinaTheme.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .minaCard(padding: 12)
    }
}

struct QuickButtonLabel: View {
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(color.opacity(0.18))
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(color)
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.mina(.headline))
                    .foregroundStyle(MinaTheme.text)
                Text(subtitle)
                    .font(.mina(.caption))
                    .foregroundStyle(MinaTheme.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MinaTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(MinaTheme.border, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct QuickButton: View {
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            QuickButtonLabel(title: title, subtitle: subtitle, symbol: symbol, color: color)
        }
        .buttonStyle(.plain)
    }
}


private extension View {
    func pillLabel() -> some View {
        self.font(.mina(.subheadline, weight: .semibold))
            .foregroundStyle(MinaTheme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(MinaTheme.cardTint, in: Capsule())
            .contentShape(Capsule())
    }
}
