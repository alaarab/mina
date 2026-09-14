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
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StoredVolumeUnit private var unit
    /// Read back through `Prefs`, but observed here so the Bottle button's
    /// "Last 4 oz" follows a feed logged by a widget or by Siri.
    @AppStorage(Prefs.lastBottleKey, store: Prefs.defaults) private var lastBottleML = 0.0
    @FetchRequest private var entries: FetchedResults<LogEntry>
    @State private var sheet: QuickSheet? = DebugLaunch.argument("-open") == "bottle" ? .bottle : nil
    @State private var editing: LogEntry?
    @State private var error: String?
    @State private var asking = DebugLaunch.argument("-open") == "ask"
    @State private var dismissedPromptTick = 0
    @State private var promptShown = 0
    /// A light tap for a one-tap log, a success tap for a saved sheet.
    @State private var haptic = Haptic()

    private struct Haptic: Equatable {
        enum Kind { case tap, success }
        var kind = Kind.tap
        var tick = 0
        mutating func play(_ kind: Kind) { self.kind = kind; tick &+= 1 }
    }
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

        init(entries: FetchedResults<LogEntry>, baby: Baby, weightGrams: Double?, now: Date) {
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
            goals = Goals.evaluate(summary: summary, lastFeed: lastFeed?.startedAt, stage: stage, ageDays: ageDays, weightGrams: all.first { $0.kind == .growth && $0.weightGrams > 0 }?.weightGrams ?? weightGrams, now: now)
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
        // Her latest weight rarely changes; the fetch covers only two days, so look it up once per body.
        let day = Day(entries: entries, baby: baby, weightGrams: Logbook.shared.latestWeightGrams(for: baby, in: context), now: now)
        NavigationStack {
            ScrollView {
                Group {
                    if sizeClass == .regular {
                        // iPad: the day's state and the buttons on the left, the timeline beside them.
                        HStack(alignment: .top, spacing: 20) {
                            VStack(alignment: .leading, spacing: 16) {
                                header
                                statusCard(day)
                                statsRow(day)
                                goalsCard(day)
                                quickLog(day)
                            }
                            .frame(maxWidth: .infinity)
                            timeline(day)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 8)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            header
                            statusCard(day)
                            statsRow(day)
                            goalsCard(day)
                            quickLog(day)
                            timeline(day)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .readableWidth(1100)
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
                    .accessibilityValue(Quiet.label(now: now) ?? "Off")
                    .id(quietTick)
                }
            }
            .sheet(isPresented: $asking) {
                AskView(baby: baby, stats: TrendMath.stats(entries: Array(entries), days: 2, now: now), recent: entries.prefix(12).map { "\(($0.startedAt ?? now).formatted(.dateTime.weekday(.abbreviated).hour().minute())): \($0.title(unit: unit, now: now))" }, unit: unit)
            }
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .bottle: BottleSheet(unit: unit) { log($0, feel: .success) }.minaSheet()
                case .nursing: NursingSheet(onStart: startNursing) { log($0, feel: .success) }.minaSheet()
                case .note: NoteSheet { log($0, feel: .success) }.minaSheet()
                case .extra(let kind): ExtraSheet(kind: kind, unit: unit) { log($0, feel: .success) }.minaSheet()
                }
            }
            .sheet(item: $editing) { EntryEditor(entry: $0).minaSheet() }
            .sensoryFeedback(trigger: haptic) { _, new in new.kind == .success ? .success : .impact(weight: .light) }
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
                StatusRow(symbol: "bell.slash.fill", color: MinaTheme.textMuted) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(quiet).font(.mina(.headline))
                        Text("No alarm, reminders or partner alerts on this phone").font(.mina(.subheadline)).foregroundStyle(MinaTheme.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                } trailing: {
                    if Quiet.until != nil {
                        Button("Resume") { resumeAlerts() }.buttonStyle(.bordered).font(.mina(.subheadline, weight: .semibold))
                            .accessibilityLabel("Resume alerts")
                    }
                }
                Divider()
            }
            if dismissedPromptTick >= 0, let dismissed = FeedAlarm.pendingDismissal, day.lastFeed.map({ ($0.startedAt ?? .distantPast) < dismissed }) ?? true {
                StatusRow(symbol: "alarm.fill", color: MinaTheme.warning) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Feed alarm went off \(Format.ago(from: dismissed, to: now))").font(.mina(.headline))
                        Text("Nothing logged since. Did she eat?").font(.mina(.subheadline)).foregroundStyle(MinaTheme.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Feed alarm went off \(Spoken.text(Format.ago(from: dismissed, to: now))). Nothing logged since. Did she eat?")
                } trailing: {
                    Button("Log it") { sheet = .bottle }.buttonStyle(.borderedProminent).tint(MinaTheme.bottle).font(.mina(.subheadline, weight: .semibold))
                        .accessibilityLabel("Log a bottle")
                    Button {
                        FeedAlarm.pendingDismissal = nil
                        dismissedPromptTick &+= 1
                    } label: {
                        Image(systemName: "xmark").font(.footnote.weight(.semibold)).frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).foregroundStyle(MinaTheme.textMuted).accessibilityLabel("Dismiss, she didn't eat")
                }
                // A warning tap when the "did she eat?" prompt comes up.
                .onAppear { promptShown &+= 1 }
                .sensoryFeedback(.warning, trigger: promptShown)
                Divider()
            }
            StatusRow(symbol: Shifts.thisPhoneIsOn(for: baby, at: now) ? "person.fill.checkmark" : "person.fill",
                      color: Shifts.thisPhoneIsOn(for: baby, at: now) ? MinaTheme.diaper : MinaTheme.textMuted) {
                VStack(alignment: .leading, spacing: 2) {
                    if let who = Shifts.onDutyLabel(for: baby, at: now) {
                        Text(Shifts.thisPhoneIsOn(for: baby, at: now) ? "You're on" : "\(who) is on").font(.mina(.headline))
                        Text(baby.onDutyDeviceID != nil ? "since \(Format.time(baby.onDutySince ?? now))" : "by schedule").font(.mina(.subheadline)).foregroundStyle(MinaTheme.textSecondary)
                    } else {
                        Text("Nobody's on").font(.mina(.headline))
                        Text("Alarms and alerts go to both phones").font(.mina(.subheadline)).foregroundStyle(MinaTheme.textSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
            } trailing: {
                if baby.onDutyDeviceID == Prefs.deviceID {
                    Button("Hand off") { do { try Shifts.handOff(baby, in: context); scheduleFeedAlerts(day) } catch { self.error = error.localizedDescription } }
                        .buttonStyle(.bordered).tint(MinaTheme.textSecondary).font(.mina(.subheadline, weight: .semibold))
                        .accessibilityHint("Alarms and alerts go back to both phones")
                } else {
                    Button("I'm on") { do { try Shifts.takeOver(baby, in: context); scheduleFeedAlerts(day) } catch { self.error = error.localizedDescription } }
                        .buttonStyle(.borderedProminent).tint(MinaTheme.diaper).font(.mina(.subheadline, weight: .semibold))
                        .accessibilityHint("Only this phone rings the alarm and gets partner alerts")
                }
            }
            Divider()
            StatusRow(symbol: "clock.fill", color: MinaTheme.accent) {
                VStack(alignment: .leading, spacing: 2) {
                    if let lastFeed = day.lastFeed, let at = lastFeed.startedAt {
                        Text("Fed \(Format.ago(from: at, to: now))")
                            .font(.mina(.headline))
                        Text("\(lastFeed.title(unit: unit, now: now)) at \(Format.time(at)) · tap to edit")
                            .font(.mina(.subheadline))
                            .foregroundStyle(MinaTheme.textSecondary)
                            .accessibilityLabel(Spoken.sentence([lastFeed.title(unit: unit, now: now), "at \(Format.time(at))"]))
                    } else {
                        Text("No feeds logged yet")
                            .font(.mina(.headline))
                        Text("Tap Bottle below, or say “Hey Siri, \(baby.displayName) ate 3 ounces.”")
                            .font(.mina(.subheadline))
                            .foregroundStyle(MinaTheme.textSecondary)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { if let lastFeed = day.lastFeed { editing = lastFeed } }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(day.lastFeed == nil ? [] : .isButton)
            .accessibilityHint(day.lastFeed == nil ? "" : "Opens the feed to edit")
            if let nursing = day.nursing, let since = nursing.startedAt {
                Divider()
                StatusRow(symbol: "heart.fill", color: MinaTheme.nursing) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nursing · \(Format.duration(now.timeIntervalSince(since)))")
                            .font(.mina(.headline))
                        Text(nursingSideText(nursing))
                            .font(.mina(.subheadline))
                            .foregroundStyle(MinaTheme.textSecondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Nursing timer")
                    .accessibilityValue(Spoken.sentence(["running", Format.duration(now.timeIntervalSince(since)), nursingSideText(nursing)]))
                } trailing: {
                    Button { switchSide(nursing) } label: { Image(systemName: "arrow.left.arrow.right").frame(minWidth: 30, minHeight: 30) }
                        .buttonStyle(.bordered).tint(MinaTheme.nursing)
                        .accessibilityLabel("Switch side")
                    Button("Done") { endNursing(nursing) }
                        .buttonStyle(.borderedProminent)
                        .tint(MinaTheme.nursing)
                        .font(.mina(.subheadline, weight: .semibold))
                        .accessibilityLabel("Done nursing")
                }
            }
            if let prediction = day.feedPrediction, day.sleeping == nil || prediction.expectedAt > now {
                Divider()
                StatusRow(symbol: "sparkles", color: prediction.expectedAt < now.addingTimeInterval(-15 * 60) ? MinaTheme.warning : MinaTheme.textMuted, small: true) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Next feed \(Predictor.phrase(for: prediction.expectedAt, now: now))")
                            .font(.mina(.subheadline, weight: .semibold))
                        Text("around \(Format.time(prediction.expectedAt)), every \(Format.duration(prediction.interval)) going by \(prediction.basis)")
                            .font(.mina(.caption))
                            .foregroundStyle(MinaTheme.textMuted)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Spoken.sentence(["Next feed \(Predictor.phrase(for: prediction.expectedAt, now: now))", "around \(Format.time(prediction.expectedAt)), every \(Format.duration(prediction.interval)) going by \(prediction.basis)"]))
                }
            }
            if let nap = day.napPrediction {
                Divider()
                StatusRow(symbol: "moon.zzz", color: nap.expectedAt < now ? MinaTheme.sleep : MinaTheme.textMuted, small: true) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(nap.expectedAt < now ? "Nap window is open" : "Nap window \(Predictor.phrase(for: nap.expectedAt, now: now))")
                            .font(.mina(.subheadline, weight: .semibold))
                        Text("about \(Format.duration(nap.wakeWindow)) awake is her limit at this age")
                            .font(.mina(.caption))
                            .foregroundStyle(MinaTheme.textMuted)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Spoken.sentence([nap.expectedAt < now ? "Nap window is open" : "Nap window \(Predictor.phrase(for: nap.expectedAt, now: now))", "about \(Format.duration(nap.wakeWindow)) awake is her limit at this age"]))
                }
            }
            if let sleeping = day.sleeping, let since = sleeping.startedAt {
                Divider()
                StatusRow(symbol: "moon.zzz.fill", color: MinaTheme.sleep) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Asleep for \(Format.duration(now.timeIntervalSince(since)))")
                            .font(.mina(.headline))
                        Text("since \(Format.time(since))")
                            .font(.mina(.subheadline))
                            .foregroundStyle(MinaTheme.textSecondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Sleep timer")
                    .accessibilityValue(Spoken.sentence(["asleep for \(Format.duration(now.timeIntervalSince(since)))", "since \(Format.time(since))"]))
                } trailing: {
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
            let heading = Text("Today's goals").font(.mina(.headline))
            let stage = Text("for \(day.stage?.title.lowercased() ?? "her age")").font(.mina(.caption)).foregroundStyle(MinaTheme.textMuted)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) { heading; stage }
            } else {
                HStack { heading; Spacer(); stage }
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
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Spoken.goal(goal))
            }
            if let concern = Goals.concern(goals, ageDays: baby.ageDays(on: now)) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.bubble.fill").foregroundStyle(MinaTheme.warning).accessibilityHidden(true)
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
        return StatTiles {
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
    }

    private func quickLog(_ day: Day) -> some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 10) {
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
                    Text("Tap a button above to log the first one. Everything you or your partner log shows up here, on both phones.")
                        .font(.mina(.subheadline))
                        .foregroundStyle(MinaTheme.textMuted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
            ForEach(groups, id: \.day) { date, dayEntries in
                VStack(alignment: .leading, spacing: 8) {
                    // The recap sits beside the day; once text is large it goes underneath.
                    let title = Text(Format.dayTitle(date, now: now)).font(.mina(.headline))
                    let recap = Text(dayLine(dayEntries, day: date)).font(.mina(.caption)).foregroundStyle(MinaTheme.textMuted)
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 2) { title; recap }.padding(.horizontal, 4)
                    } else {
                        HStack(alignment: .firstTextBaseline) { title; Spacer(); recap.multilineTextAlignment(.trailing) }.padding(.horizontal, 4)
                    }
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

    private func log(_ draft: EntryDraft, feel: Haptic.Kind = .tap) {
        do {
            try Logbook.shared.add(draft, to: baby, in: context)
            haptic.play(feel)
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
            haptic.play(.tap)
        } catch { self.error = error.localizedDescription }
    }

    private func switchSide(_ entry: LogEntry) {
        do { try Logbook.shared.switchNursingSide(entry, at: now, in: context) } catch { self.error = error.localizedDescription }
    }

    private func endNursing(_ entry: LogEntry) {
        do {
            try Logbook.shared.endNursing(entry, at: now, in: context)
            haptic.play(.tap)
        } catch { self.error = error.localizedDescription }
    }

    private func endSleep(_ entry: LogEntry) {
        entry.endedAt = max(now, entry.startedAt ?? now)
        do {
            try context.save()
            haptic.play(.tap)
            // The widgets and Control Center show "asleep"; tell them she's up.
            Logbook.widgetsChanged()
        } catch { self.error = error.localizedDescription }
    }

    private func delete(_ entry: LogEntry) {
        do { try Logbook.shared.delete(entry, in: context) } catch { self.error = error.localizedDescription }
    }
}

// MARK: Pieces

/// The three Feeds / Diapers / Sleep tiles in a row, top-aligned so the big
/// numbers line up whatever the titles wrap to; a column once text is large.
struct StatTiles<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) { content }
            } else {
                HStack(alignment: .top, spacing: 10) { content }
            }
        }
        .buttonStyle(.plain)
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
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            if let expect {
                Text(expect)
                    .font(.mina(.caption2))
                    .foregroundStyle(MinaTheme.textMuted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .minaCard(padding: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Spoken.tile(title: title, value: value, detail: detail, expect: expect))
    }
}

struct QuickButtonLabel: View {
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color
    @ScaledMetric(relativeTo: .headline) private var badge = 46.0

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(color.opacity(0.18))
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(color)
            }
            .frame(width: badge, height: badge)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.mina(.headline))
                    .foregroundStyle(MinaTheme.text)
                Text(subtitle)
                    .font(.mina(.caption))
                    .foregroundStyle(MinaTheme.textMuted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MinaTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(MinaTheme.border, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Spoken.sentence([title, subtitle]))
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


/// Icon, text and a trailing control in a row of the status card. Once text
/// is large the control drops under the text, so neither gets squeezed into
/// a column of single words.
struct StatusRow<Content: View, Trailing: View>: View {
    let symbol: String
    let color: Color
    /// The prediction rows use a lighter icon.
    var small = false
    @ViewBuilder let content: Content
    @ViewBuilder let trailing: Trailing

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title3) private var iconWidth = 32.0

    init(symbol: String, color: Color, small: Bool = false, @ViewBuilder content: () -> Content, @ViewBuilder trailing: () -> Trailing) {
        self.symbol = symbol
        self.color = color
        self.small = small
        self.content = content()
        self.trailing = trailing()
    }

    var body: some View {
        let icon = Image(systemName: symbol)
            .font(small ? .body : .title3)
            .foregroundStyle(color)
            .frame(width: iconWidth)
            .accessibilityHidden(true)
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) { icon; content; Spacer(minLength: 0) }
                if Trailing.self != EmptyView.self {
                    HStack(spacing: 10) { trailing }.padding(.leading, iconWidth + 12)
                }
            }
        } else {
            HStack(spacing: 12) { icon; content; Spacer(minLength: 8); trailing }
        }
    }
}

extension StatusRow where Trailing == EmptyView {
    init(symbol: String, color: Color, small: Bool = false, @ViewBuilder content: () -> Content) {
        self.init(symbol: symbol, color: color, small: small, content: content, trailing: { EmptyView() })
    }
}

/// A small progress ring coloured by the goal's kind and status.
struct GoalRing: View {
    let progress: Double
    let status: Goal.Status
    let kind: Goal.Kind
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .subheadline) private var size = 34.0

    private var color: Color {
        if status == .short { return MinaTheme.warning }
        switch kind {
        case .feeds, .feedGap, .volume: return MinaTheme.bottle
        case .wet: return MinaTheme.diaper
        case .dirty: return MinaTheme.diaperDirty
        case .sleep: return MinaTheme.sleep
        }
    }

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: 5)
            Circle().trim(from: 0, to: progress).stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
            if status == .done { Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundStyle(color) }
        }
        .frame(width: size, height: size)
        .animation(reduceMotion ? nil : .snappy, value: progress)
        .accessibilityHidden(true)
    }
}
