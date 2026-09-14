import CoreData
import SwiftUI

/// The home screen: how long since the last feed, what's running right now, the
/// day's counts against what's typical for her age, the six one-tap log buttons,
/// and a timeline of today and yesterday. Everything on it is derived from a
/// single fetch of the last two days, re-rendered every minute so the relative
/// times stay honest.

// MARK: Screen

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
    @StoredVolumeUnit private var unit
    /// Read back through `Prefs`, but observed here so the Bottle button's
    /// "Last 4 oz" follows a feed logged by a widget or by Siri.
    @AppStorage(Prefs.lastBottleKey, store: Prefs.defaults) private var lastBottleML = 0.0
    @FetchRequest private var entries: FetchedResults<LogEntry>
    @State private var sheet: QuickSheet?
    @State private var editing: LogEntry?
    @State private var error: String?
    @State private var asking = DebugLaunch.argument("-open") == "ask"
    @State private var dismissedPromptTick = 0
    @State private var quietTick = 0

    init(baby: Baby, now: Date) {
        _baby = ObservedObject(wrappedValue: baby)
        self.now = now
        let today = Calendar.current.startOfDay(for: now)
        let start = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
        _entries = FetchRequest(fetchRequest: LogEntry.request(for: baby, from: start), animation: .default)
    }

    /// One pass over the fetch: everything the screen shows about today,
    /// worked out together instead of by six separate filters.
    private struct Day {
        var sleeping: LogEntry?
        var nursing: LogEntry?
        var lastFeed: LogEntry?
        var summary = DaySummary()
        var stage: GuideStage?
        var feedPrediction: FeedPrediction?
        var napPrediction: NapPrediction?
        var goals: [Goal] = []
        var sections: [(day: Date, entries: [LogEntry])] = []

        init(entries: FetchedResults<LogEntry>, baby: Baby, now: Date) {
            let all = Array(entries)
            var feedTimes: [Date] = []
            var lastWake: Date?
            // The fetch is newest first, so the first match of each kind is the
            // latest one and nothing needs sorting afterwards.
            for entry in all {
                switch entry.kind {
                case .sleep:
                    if entry.endedAt == nil {
                        if sleeping == nil { sleeping = entry }
                    } else if let ended = entry.endedAt, ended > lastWake ?? .distantPast {
                        lastWake = ended
                    }
                case .bottle, .nursing:
                    if entry.kind == .nursing, entry.endedAt == nil, nursing == nil { nursing = entry }
                    if lastFeed == nil { lastFeed = entry }
                    if let at = entry.startedAt { feedTimes.append(at) }
                default:
                    break
                }
            }
            let ageDays = baby.ageDays(on: now)
            summary = DaySummary(entries: all, day: now, now: now)
            stage = ageDays.map(Guidance.stage(forAgeDays:))
            feedPrediction = Predictor.nextFeed(feedTimes: feedTimes, stage: stage, now: now)
            napPrediction = sleeping == nil ? Predictor.nextNap(lastWake: lastWake, ageDays: ageDays, now: now) : nil
            goals = Goals.evaluate(summary: summary, lastFeed: lastFeed?.startedAt, stage: stage, ageDays: ageDays, now: now)
            sections = DayGrouping.days(all, missing: now)
        }
    }

    /// One publisher, made once: building it inline in `body` would resubscribe
    /// on every render, and this view renders every minute. An iCloud catch-up
    /// posts dozens of these in a row, so it settles for a second first and the
    /// screen refreshes once instead of once per record.
    private static let remoteChangePublisher = NotificationCenter.default
        .publisher(for: .NSPersistentStoreRemoteChange)
        .debounce(for: .seconds(1), scheduler: RunLoop.main)

    var body: some View {
        // Everything below is derived from the one fetch, so it is derived
        // once here rather than per subview: this runs every minute and on
        // every change, and the old computed properties walked the entries
        // half a dozen times each pass.
        let day = Day(entries: entries, baby: baby, now: now)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    statusCard(day)
                    statsRow(day)
                    goalsCard(day)
                    quickLog(day)
                    timeline(day)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .minaCanvas()
            .navigationTitle(baby.displayName)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { asking = true } label: { Label("Ask", systemImage: "sparkles") }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        if Quiet.label(now: now) != nil {
                            Button("Turn alerts back on", systemImage: "bell.fill") { resumeAlerts() }
                        } else {
                            Section("Quiet this phone for") {
                                ForEach(Quiet.Pause.allCases) { pause in
                                    Button(pause.title) { Quiet.pause(pause, now: now); quietTick &+= 1 }
                                }
                            }
                        }
                    } label: {
                        Label("Quiet", systemImage: Quiet.label(now: now) != nil ? "bell.slash.fill" : "bell")
                    }
                    .id(quietTick)
                }
            }
            .sheet(isPresented: $asking) {
                AskView(baby: baby, stats: TrendMath.stats(entries: Array(entries), days: 2, now: now), recent: entries.prefix(12).map { "\(($0.startedAt ?? now).formatted(.dateTime.weekday(.abbreviated).hour().minute())): \($0.title(unit: unit, now: now))" }, unit: unit)
            }
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .bottle: BottleSheet(unit: unit) { log($0) }
                case .nursing: NursingSheet(onStart: startNursing) { log($0) }
                case .note: NoteSheet { log($0) }
                case .extra(let kind): ExtraSheet(kind: kind, unit: unit) { log($0) }
                }
            }
            .sheet(item: $editing) { EntryEditor(entry: $0) }
            .errorAlert($error)
            .onAppear { scheduleFeedAlerts(day) }
            .onChange(of: entries.count) { _, _ in scheduleFeedAlerts(day) }
            .onChange(of: baby.onDutyDeviceID) { _, _ in scheduleFeedAlerts(day) }
            .onChange(of: baby.shiftsJSON) { _, _ in scheduleFeedAlerts(day) }
            // A partner's "I'm on" arrives through CloudKit; refresh the baby
            // row when the store changes. A catch-up sync posts dozens of these
            // in a row, so the refresh and the alarm work are coalesced.
            .onReceive(Self.remoteChangePublisher) { _ in
                context.refresh(baby, mergeChanges: true)
                scheduleFeedAlerts(day)
            }
        }
    }

    // MARK: Subviews

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

    private func statusCard(_ day: Day) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if quietTick >= 0, let quiet = Quiet.label(now: now) {
                HStack(spacing: 12) {
                    Image(systemName: "bell.slash.fill").font(.system(size: 20)).foregroundStyle(MinaTheme.textMuted).frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(quiet).font(.mina(.headline))
                        Text("No alarm, reminders or partner alerts on this phone").font(.mina(.subheadline)).foregroundStyle(MinaTheme.textSecondary)
                    }
                    Spacer()
                    if Quiet.until != nil {
                        Button("Resume") { resumeAlerts() }.buttonStyle(.bordered).font(.mina(.subheadline, weight: .semibold))
                    }
                }
                Divider()
            }
            if dismissedPromptTick >= 0, let dismissed = FeedAlarm.pendingDismissal, day.lastFeed.map({ ($0.startedAt ?? .distantPast) < dismissed }) ?? true {
                HStack(spacing: 12) {
                    Image(systemName: "alarm.fill").font(.system(size: 20)).foregroundStyle(MinaTheme.warning).frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Feed alarm went off \(Format.ago(from: dismissed, to: now))").font(.mina(.headline))
                        Text("Nothing logged since. Did she eat?").font(.mina(.subheadline)).foregroundStyle(MinaTheme.textSecondary)
                    }
                    Spacer()
                    Button("Log it") { sheet = .bottle }.buttonStyle(.borderedProminent).tint(MinaTheme.bottle).font(.mina(.subheadline, weight: .semibold))
                    Button {
                        FeedAlarm.pendingDismissal = nil
                        dismissedPromptTick &+= 1
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).foregroundStyle(MinaTheme.textMuted).accessibilityLabel("Dismiss")
                }
                Divider()
            }
            HStack(spacing: 12) {
                Image(systemName: Shifts.thisPhoneIsOn(for: baby, at: now) ? "person.fill.checkmark" : "person.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Shifts.thisPhoneIsOn(for: baby, at: now) ? MinaTheme.diaper : MinaTheme.textMuted)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    if let who = Shifts.onDutyLabel(for: baby, at: now) {
                        Text(Shifts.thisPhoneIsOn(for: baby, at: now) ? "You're on" : "\(who) is on").font(.mina(.headline))
                        Text(baby.onDutyDeviceID != nil ? "since \(Format.time(baby.onDutySince ?? now))" : "by schedule").font(.mina(.subheadline)).foregroundStyle(MinaTheme.textSecondary)
                    } else {
                        Text("Nobody's on").font(.mina(.headline))
                        Text("Alarms and alerts go to both phones").font(.mina(.subheadline)).foregroundStyle(MinaTheme.textSecondary)
                    }
                }
                Spacer()
                if baby.onDutyDeviceID == Prefs.deviceID {
                    Button("Hand off") { do { try Shifts.handOff(baby, in: context); scheduleFeedAlerts(day) } catch { self.error = error.localizedDescription } }
                        .buttonStyle(.bordered).tint(MinaTheme.textSecondary).font(.mina(.subheadline, weight: .semibold))
                } else {
                    Button("I'm on") { do { try Shifts.takeOver(baby, in: context); scheduleFeedAlerts(day) } catch { self.error = error.localizedDescription } }
                        .buttonStyle(.borderedProminent).tint(MinaTheme.diaper).font(.mina(.subheadline, weight: .semibold))
                }
            }
            Divider()
            HStack(spacing: 12) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(MinaTheme.accent)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    if let lastFeed = day.lastFeed, let at = lastFeed.startedAt {
                        Text("Fed \(Format.ago(from: at, to: now))")
                            .font(.mina(.headline))
                        Text("\(lastFeed.title(unit: unit, now: now)) at \(Format.time(at)) · tap to edit")
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
            .contentShape(Rectangle())
            .onTapGesture { if let lastFeed = day.lastFeed { editing = lastFeed } }
            if let nursing = day.nursing, let since = nursing.startedAt {
                Divider()
                HStack(spacing: 12) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(MinaTheme.nursing)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nursing · \(Format.duration(now.timeIntervalSince(since)))")
                            .font(.mina(.headline))
                        Text(nursingSideText(nursing))
                            .font(.mina(.subheadline))
                            .foregroundStyle(MinaTheme.textSecondary)
                    }
                    Spacer()
                    Button { switchSide(nursing) } label: { Image(systemName: "arrow.left.arrow.right").frame(width: 30, height: 30) }
                        .buttonStyle(.bordered).tint(MinaTheme.nursing)
                        .accessibilityLabel("Switch side")
                    Button("Done") { endNursing(nursing) }
                        .buttonStyle(.borderedProminent)
                        .tint(MinaTheme.nursing)
                        .font(.mina(.subheadline, weight: .semibold))
                }
            }
            if let prediction = day.feedPrediction, day.sleeping == nil || prediction.expectedAt > now {
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
            if let nap = day.napPrediction {
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
            if let sleeping = day.sleeping, let since = sleeping.startedAt {
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

    private func goalsCard(_ day: Day) -> some View {
        let goals = day.goals
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Today's goals").font(.mina(.headline))
                Spacer()
                Text("for \(day.stage?.title.lowercased() ?? "her age")").font(.mina(.caption)).foregroundStyle(MinaTheme.textMuted)
            }
            ForEach(goals) { goal in
                HStack(spacing: 12) {
                    GoalRing(progress: goal.progress, status: goal.status, kind: goal.kind)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal.title).font(.mina(.subheadline, weight: .semibold))
                        Text(goal.detail).font(.mina(.caption)).foregroundStyle(goal.status == .short ? MinaTheme.warning : MinaTheme.textMuted)
                    }
                    Spacer()
                }
            }
            if let concern = Goals.concern(goals, ageDays: baby.ageDays(on: now)) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.bubble.fill").foregroundStyle(MinaTheme.warning)
                    Text(concern).font(.mina(.footnote)).foregroundStyle(MinaTheme.textSecondary)
                }
                .padding(.top, 2)
            }
        }
        .minaCard()
    }

    private func statsRow(_ day: Day) -> some View {
        let summary = day.summary
        let stage = day.stage
        return HStack(spacing: 10) {
            NavigationLink { HistoryView(baby: baby, filter: .feeds) } label: {
                StatTile(title: "Feeds", value: "\(summary.feeds)", color: MinaTheme.bottle,
                         detail: feedDetail(summary),
                         expect: stage.map { "expect \($0.expectation.feedsText())" })
            }
            NavigationLink { HistoryView(baby: baby, filter: .diapers) } label: {
                StatTile(title: "Diapers", value: "\(summary.diapers)", color: MinaTheme.diaper,
                         detail: "\(summary.wet) wet · \(summary.dirty) dirty",
                         expect: stage.map { "expect \($0.expectation.wetText())" })
            }
            NavigationLink { HistoryView(baby: baby, filter: .sleep) } label: {
                StatTile(title: "Sleep", value: summary.sleepSeconds > 0 ? Format.duration(summary.sleepSeconds) : "0m", color: MinaTheme.sleep,
                         detail: Format.count(summary.sleeps, "stretch", "stretches"),
                         expect: stage.map { "expect \($0.expectation.sleepText())" })
            }
        }
        .buttonStyle(.plain)
    }

    private func quickLog(_ day: Day) -> some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                QuickButton(title: "Bottle", subtitle: "Last \(unit.format(ml: Prefs.lastBottleML))", symbol: EntryKind.bottle.symbol, color: MinaTheme.bottle) {
                    sheet = .bottle
                }
                if let nursing = day.nursing, let since = nursing.startedAt {
                    QuickButton(title: "Done nursing", subtitle: "\(Format.duration(now.timeIntervalSince(since))) so far", symbol: "heart.fill", color: MinaTheme.nursing) {
                        endNursing(nursing)
                    }
                } else {
                    QuickButton(title: "Nurse", subtitle: "Start on the \(Prefs.suggestedNursingSide.title.lowercased())", symbol: EntryKind.nursing.symbol, color: MinaTheme.nursing) {
                        sheet = .nursing
                    }
                }
                Menu {
                    ForEach(DiaperKind.allCases) { kind in
                        Button(kind.title) { logDiaper(kind) }
                    }
                } label: {
                    QuickButtonLabel(title: "Diaper", subtitle: "Wet or dirty", symbol: EntryKind.diaper.symbol, color: MinaTheme.diaper)
                }
                if let sleeping = day.sleeping, let since = sleeping.startedAt {
                    QuickButton(title: "Woke up", subtitle: "Asleep \(Format.duration(now.timeIntervalSince(since)))", symbol: "sun.max.fill", color: MinaTheme.sleep) {
                        endSleep(sleeping)
                    }
                } else {
                    QuickButton(title: "Sleep", subtitle: "Start a nap now", symbol: EntryKind.sleep.symbol, color: MinaTheme.sleep) {
                        log(EntryDraft(kind: .sleep, startedAt: now))
                    }
                }
                QuickButton(title: "Pump", subtitle: pumpSubtitle(day.summary), symbol: EntryKind.pumping.symbol, color: MinaTheme.nursing) {
                    sheet = .extra(.pumping)
                }
                QuickButton(title: "Note", subtitle: "Anything worth remembering", symbol: EntryKind.note.symbol, color: MinaTheme.note) {
                    sheet = .note
                }
            }
            Menu {
                ForEach(EntryKind.extras.filter { $0 != .pumping }) { kind in
                    Button(kind.title, systemImage: kind.symbol) {
                        if kind == .bath { log(EntryDraft(kind: .bath, startedAt: now)) } else { sheet = .extra(kind) }
                    }
                }
            } label: {
                Label("Growth, medicine, tummy time, bath, temperature", systemImage: "plus.circle").pillLabel()
            }
        }
    }

    private func timeline(_ day: Day) -> some View {
        let groups = day.sections
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
            ForEach(groups, id: \.day) { date, dayEntries in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Format.dayTitle(date, now: now))
                            .font(.mina(.headline))
                        Spacer()
                        Text(dayLine(dayEntries, day: date))
                            .font(.mina(.caption))
                            .foregroundStyle(MinaTheme.textMuted)
                    }
                    .padding(.horizontal, 4)
                    EntryList(entries: dayEntries, unit: unit, now: now, onEdit: { editing = $0 }, onDelete: delete)
                }
            }
        }
    }

    // MARK: Text

    private func pumpSubtitle(_ summary: DaySummary) -> String {
        let pumped = summary.pumpedML
        return pumped > 0 ? "\(unit.format(ml: pumped)) today" : "Amount and side"
    }

    private func feedDetail(_ summary: DaySummary) -> String {
        var parts: [String] = []
        if summary.bottleML > 0 { parts.append(unit.format(ml: summary.bottleML)) }
        if summary.nursingCount > 0 { parts.append("\(summary.nursingCount) nursed") }
        return parts.isEmpty ? "nothing yet" : parts.joined(separator: " · ")
    }

    /// The one-line recap beside a day header in the timeline.
    private func dayLine(_ dayEntries: [LogEntry], day: Date) -> String {
        let summary = DaySummary(entries: dayEntries, day: day, now: now)
        var parts: [String] = []
        if summary.feeds > 0 {
            parts.append(Format.count(summary.feeds, "feed") + (summary.bottleML > 0 ? " · \(unit.format(ml: summary.bottleML))" : ""))
        }
        if summary.diapers > 0 { parts.append(Format.count(summary.diapers, "diaper")) }
        if summary.sleepSeconds > 0 { parts.append("\(Format.duration(summary.sleepSeconds)) sleep") }
        if summary.pumpedML > 0 { parts.append("\(unit.format(ml: summary.pumpedML)) pumped") }
        return parts.joined(separator: " · ")
    }

    /// "On the left" while one side is running; the split once she's switched.
    private func nursingSideText(_ entry: LogEntry) -> String {
        let segments = (entry.label ?? "").split(separator: "|")
        if let last = segments.last, let side = NursingSide(rawValue: String(last.split(separator: ":").first ?? "")) {
            return segments.count > 1 ? "Now on the \(side.title.lowercased()) · switched \(segments.count - 1)×" : "On the \(side.title.lowercased())"
        }
        return entry.side.map { "On the \($0.title.lowercased())" } ?? ""
    }

    // MARK: Actions

    private func resumeAlerts() {
        Quiet.resume()
        quietTick &+= 1
        let last = Logbook.shared.lastFeed(for: baby, in: context)?.startedAt
        let prediction = Predictor.nextFeed(feedTimes: Logbook.shared.recentFeedTimes(for: baby, in: context), stage: baby.ageDays().map(Guidance.stage(forAgeDays:)))
        if Shifts.thisPhoneIsOn(for: baby, at: now) {
            Reminders.scheduleFeed(prediction, babyName: baby.displayName, now: now)
            FeedAlarm.reschedule(lastFeed: last, prediction: prediction, babyName: baby.displayName, now: now, force: true)
        }
    }

    private func scheduleFeedAlerts(_ day: Day) {
        let on = Shifts.thisPhoneIsOn(for: baby, at: now)
        Reminders.scheduleFeed(on ? day.feedPrediction : nil, babyName: baby.displayName, now: now)
        if on {
            FeedAlarm.reschedule(lastFeed: day.lastFeed?.startedAt, prediction: day.feedPrediction, babyName: baby.displayName, now: now)
        } else {
            FeedAlarm.cancel()
        }
        // A logged feed clears the "alarm dismissed, nothing logged" prompt.
        if let dismissed = FeedAlarm.pendingDismissal, let last = day.lastFeed?.startedAt, last > dismissed { FeedAlarm.pendingDismissal = nil }
    }

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

    private func startNursing(_ side: NursingSide) {
        do {
            try Logbook.shared.startNursing(side: side, for: baby, at: now, in: context)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch { self.error = error.localizedDescription }
    }

    private func switchSide(_ entry: LogEntry) {
        do { try Logbook.shared.switchNursingSide(entry, at: now, in: context) } catch { self.error = error.localizedDescription }
    }

    private func endNursing(_ entry: LogEntry) {
        do { try Logbook.shared.endNursing(entry, at: now, in: context) } catch { self.error = error.localizedDescription }
    }

    private func endSleep(_ entry: LogEntry) {
        entry.endedAt = max(now, entry.startedAt ?? now)
        do { try context.save() } catch { self.error = error.localizedDescription }
    }

    private func delete(_ entry: LogEntry) {
        do { try Logbook.shared.delete(entry, in: context) } catch { self.error = error.localizedDescription }
    }
}

// MARK: Pieces

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


/// A small progress ring coloured by the goal's kind and status.
struct GoalRing: View {
    let progress: Double
    let status: Goal.Status
    let kind: Goal.Kind

    private var color: Color {
        if status == .short { return MinaTheme.warning }
        switch kind {
        case .feeds, .feedGap: return MinaTheme.bottle
        case .wet: return MinaTheme.diaper
        case .dirty: return MinaTheme.diaperDirty
        case .sleep: return MinaTheme.sleep
        }
    }

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: 5)
            Circle().trim(from: 0, to: progress).stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
            if status == .done { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(color) }
        }
        .frame(width: 34, height: 34)
        .animation(.snappy, value: progress)
    }
}
