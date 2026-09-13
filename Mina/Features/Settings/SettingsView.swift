import AppIntents
import CloudKit
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

/// Everything with a switch on it: her name and birthday, the iCloud share with
/// the partner, notifications, the Nanit link, your own name, units, and the
/// Siri phrases. Each section writes straight through to the store or to
/// `Prefs`, so there is no Save button anywhere on this screen.

struct SettingsView: View {
    @ObservedObject var baby: Baby

    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var sync: SyncMonitor
    @ObservedObject private var sharing = ShareManager.shared
    @AppStorage(Prefs.nameKey, store: Prefs.defaults) private var yourName = ""
    @AppStorage(Prefs.unitKey, store: Prefs.defaults) private var unitRaw = VolumeUnit.ounces.rawValue
    @State private var name: String
    @State private var birthDate: Date
    @State private var siriTipVisible = true
    @State private var preparingShare = false
    @AppStorage(Prefs.partnerAlertsKey, store: Prefs.defaults) private var partnerAlerts = true
    @AppStorage(Reminders.feedKey, store: Prefs.defaults) private var feedReminders = false
    @AppStorage(FeedAlarm.onKey, store: Prefs.defaults) private var feedAlarm = false
    @AppStorage(FeedAlarm.gapKey, store: Prefs.defaults) private var feedAlarmGap = 180
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @ObservedObject private var nanit = NanitSync.shared
    @State private var linkingNanit = false
    @State private var exportURL: URL?
    @State private var importing = false
    @State private var backupMessage: String?
    @FetchRequest(fetchRequest: Baby.request(), animation: .default) private var babies: FetchedResults<Baby>
    @AppStorage(Prefs.selectedBabyKey, store: Prefs.defaults) private var selectedBabyID = ""
    @State private var addingBaby = false

    private let persistence = PersistenceController.shared

    init(baby: Baby) {
        _baby = ObservedObject(wrappedValue: baby)
        _name = State(initialValue: baby.name ?? "")
        _birthDate = State(initialValue: baby.birthDate ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Baby") {
                    if babies.count > 1 {
                        Picker("Showing", selection: $selectedBabyID) {
                            ForEach(babies) { candidate in
                                Text(candidate.displayName + (persistence.isShared(candidate) ? " · shared" : "")).tag(candidate.id?.uuidString ?? "")
                            }
                        }
                    }
                    TextField("Name", text: $name)
                        .onChange(of: name) { _, value in
                            let trimmed = value.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty, trimmed != baby.name else { return }
                            baby.name = trimmed
                            try? context.save()
                        }
                    DatePicker("Birthday", selection: $birthDate, in: ...Date.now, displayedComponents: .date)
                        .onChange(of: birthDate) { _, value in
                            baby.birthDate = value
                            try? context.save()
                        }
                    Button { addingBaby = true } label: { Label("Add another baby", systemImage: "plus") }
                }

                Section {
                    let share = sharing.existingShare(for: baby)
                    Label(sharing.describe(share, baby: baby), systemImage: "person.2.fill")
                    Button {
                        preparingShare = true
                        Task { await sharing.present(for: baby); preparingShare = false }
                    } label: {
                        HStack {
                            Text(share == nil ? "Share with your partner" : "Manage sharing")
                            if preparingShare { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(preparingShare || persistence.isShared(baby))
                    let people = sharing.participants(for: baby)
                    ForEach(people) { person in
                        HStack {
                            Text(person.isOwner ? "\(person.name) (owner)" : person.name)
                            Spacer()
                            Text(person.isOwner ? "" : person.canWrite ? (person.accepted ? "can make changes" : "invited") : "view only")
                                .foregroundStyle(person.canWrite || person.isOwner ? MinaTheme.textMuted : MinaTheme.danger)
                        }
                        .font(.mina(.subheadline))
                    }
                    if people.contains(where: { !$0.isOwner && !$0.canWrite }) {
                        Button {
                            Task { await sharing.grantWriteToEveryone(for: baby) }
                        } label: {
                            Label("Let everyone on the share make changes", systemImage: "pencil")
                        }
                    }
                    LabeledContent("iCloud", value: sync.statusText)
                        .font(.mina(.subheadline))
                    Text(sync.stepsText.isEmpty ? "No sync activity yet" : sync.stepsText)
                        .font(.mina(.caption2))
                        .foregroundStyle(MinaTheme.textMuted)
                    ForEach(sync.details.keys.sorted(), id: \.self) { key in
                        if let detail = sync.details[key] {
                            DisclosureGroup("\(key) error") {
                                Text(detail).font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                            }
                            .font(.mina(.caption)).foregroundStyle(MinaTheme.danger)
                        }
                    }
                } header: {
                    Text("Sharing")
                } footer: {
                    Text("Both phones need to be signed in to iCloud. Send the invite by Messages; when your partner opens it, Mina opens with the same log and every entry syncs both ways.")
                }

                Section {
                    Toggle("Alert me when my partner logs", isOn: $partnerAlerts)
                    Toggle("Remind me when a feed is due", isOn: $feedReminders)
                        .onChange(of: feedReminders) { _, on in
                            if !on { Reminders.scheduleFeed(nil, babyName: baby.displayName) }
                        }
                    if FeedAlarm.isSupported {
                        Toggle("Feed alarm (rings through silent)", isOn: $feedAlarm)
                            .onChange(of: feedAlarm) { _, on in
                                if on {
                                    let last = Logbook.shared.lastFeed(for: baby, in: context)?.startedAt
                                    let prediction = Predictor.nextFeed(feedTimes: Logbook.shared.recentFeedTimes(for: baby, in: context), stage: baby.ageDays().map(Guidance.stage(forAgeDays:)))
                                    FeedAlarm.reschedule(lastFeed: last, prediction: prediction, babyName: baby.displayName)
                                } else { FeedAlarm.cancel() }
                            }
                        if feedAlarm {
                            Picker("Ring after", selection: $feedAlarmGap) {
                                ForEach(FeedAlarm.gaps, id: \.minutes) { Text($0.title).tag($0.minutes) }
                            }
                            .onChange(of: feedAlarmGap) { _, _ in
                                let last = Logbook.shared.lastFeed(for: baby, in: context)?.startedAt
                                let prediction = Predictor.nextFeed(feedTimes: Logbook.shared.recentFeedTimes(for: baby, in: context), stage: baby.ageDays().map(Guidance.stage(forAgeDays:)))
                                FeedAlarm.reschedule(lastFeed: last, prediction: prediction, babyName: baby.displayName)
                            }
                        }
                    }
                    if notificationStatus == .denied {
                        Button("Notifications are off for Mina. Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                        .font(.mina(.subheadline))
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Partner alerts: “Mom fed Mina: 4 oz bottle at 2:15 PM” while the app is in the background. Feed reminders are a normal notification at her predicted next feed. The feed alarm is a real alarm that rings through silent mode and Focus, moves itself every time a feed is logged, and its Log feed button records a bottle at the last amount.")
                }

                if FeatureFlags.nanit {
                Section {
                    if let camera = nanit.baby {
                        Label("Connected to \(camera.name)'s camera", systemImage: "video.fill")
                        LabeledContent("Last sync", value: nanit.lastSync.map { Format.ago(from: $0) } ?? "not yet")
                        if let error = nanit.lastError { Text(error).font(.mina(.footnote)).foregroundStyle(MinaTheme.danger) }
                        if !nanit.seenTypes.isEmpty {
                            Text("Events seen: \(nanit.seenTypes.joined(separator: ", "))").font(.mina(.footnote)).foregroundStyle(MinaTheme.textMuted)
                        }
                        Button { Task { await nanit.sync() } } label: {
                            HStack { Text("Sync now"); if nanit.syncing { Spacer(); ProgressView() } }
                        }
                        .disabled(nanit.syncing)
                        Button("Disconnect Nanit", role: .destructive) { nanit.unlink() }
                    } else {
                        Button("Connect Nanit") { linkingNanit = true }
                    }
                } header: {
                    Text("Nanit")
                } footer: {
                    Text("Sleep and wake events from the camera become sleep entries, logged as “Nanit”, when the app opens and in the background every so often. Unofficial: Nanit has no public API, so this can stop working if they change things.")
                }
                }

                Section {
                    NavigationLink { ShiftsView(baby: baby) } label: {
                        LabeledContent("Shifts", value: Shifts.blocks(for: baby).isEmpty ? "Off" : "\(Shifts.blocks(for: baby).count) blocks")
                    }
                } header: {
                    Text("Who's on")
                } footer: {
                    Text("Only the phone that's on rings the feed alarm and gets partner alerts. Tap “I'm on” on Today to take over any time, or set a nightly schedule here. With nothing set, both phones get everything.")
                }

                Section {
                    TextField("Your name", text: $yourName)
                } header: {
                    Text("You")
                } footer: {
                    Text("Shown on the entries you log, so you both know who did the 3 AM feed.")
                }

                Section("Units") {
                    Picker("Bottle amounts", selection: $unitRaw) {
                        ForEach(VolumeUnit.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    SiriTipView(intent: LogBottleIntent(), isVisible: $siriTipVisible)
                    VStack(alignment: .leading, spacing: 6) {
                        siriPhrase("My baby just ate 4 ounces")
                        siriPhrase("Mina ate 4 ounces")
                        siriPhrase("\(baby.displayName) nursed on the left")
                        siriPhrase("\(baby.displayName) just peed")
                        siriPhrase("\(baby.displayName) just pooped")
                        siriPhrase("\(baby.displayName) is asleep")
                        siriPhrase("\(baby.displayName) woke up")
                        siriPhrase("\(baby.displayName) weighs 7 pounds 4 ounces")
                        siriPhrase("When did \(baby.displayName) last eat?")
                    }
                    .padding(.vertical, 4)
                    ShortcutsLink()
                } header: {
                    Text("Siri")
                } footer: {
                    Text(babies.count > 1
                         ? "Say “Hey Siri” and any of these. “Mina”, “my baby”, “the baby” and “our baby” all work as the trigger. With more than one baby, phrases log to the baby selected above; say “log a bottle for \(baby.displayName)” to name one, or Siri asks which."
                         : "Say “Hey Siri” and any of these. No setup needed. “Mina”, “my baby”, “the baby” and “our baby” all work as the trigger; replies use \(baby.displayName)'s name.")
                }

                Section {
                    if let exportURL {
                        ShareLink(item: exportURL, subject: Text("\(baby.displayName)'s log")) { Label("Share the export file", systemImage: "square.and.arrow.up") }
                    }
                    Button { export() } label: { Label("Export everything to a file", systemImage: "arrow.up.doc") }
                    Button { importing = true } label: { Label("Import from a file", systemImage: "arrow.down.doc") }
                    if let backupMessage { Text(backupMessage).font(.mina(.footnote)).foregroundStyle(MinaTheme.textSecondary) }
                } header: {
                    Text("Backup")
                } footer: {
                    Text("A plain JSON file with every entry. Importing adds only entries that aren't already in the log, so it's safe to import the same file twice or a file from another phone.")
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                    if let loadError = persistence.loadError {
                        Text("Storage problem: \(loadError.localizedDescription)").foregroundStyle(MinaTheme.danger)
                    }
                }
            }
            .navigationTitle("Settings")
            .scrollContentBackground(.hidden)
            .minaCanvas()
            .sheet(isPresented: $linkingNanit) { NanitLinkSheet() }
            .sheet(isPresented: $addingBaby) { AddBabySheet() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                do {
                    guard let url = try result.get().first else { return }
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let added = try Backup.importData(try Data(contentsOf: url), into: baby, in: context)
                    backupMessage = added == 0 ? "Nothing new in that file." : "Imported \(added) \(added == 1 ? "entry" : "entries")."
                } catch { backupMessage = "Import failed: \(error.localizedDescription)" }
            }
            .sheet(item: $sharing.item) { item in
                CloudSharingView(share: item.share, container: sharing.cloudContainer, title: "\(baby.displayName)'s log")
                    .ignoresSafeArea()
            }
            .errorAlert($sharing.error, title: "Sharing problem")
            .task {
                if sharing.existingShare(for: baby) != nil {
                    PartnerAlerts.shared.registerCloudSubscriptionIfOwner(babyName: baby.displayName, isOwner: !persistence.isShared(baby))
                }
                await sync.refreshAccount()
                notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            }
        }
    }

    // MARK: Subviews

    private func export() {
        do {
            let data = try Backup.exportData(baby: baby, in: context)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(baby.displayName)-log.json")
            try data.write(to: url, options: .atomic)
            exportURL = url
            backupMessage = "Ready to share: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))."
        } catch { backupMessage = "Export failed: \(error.localizedDescription)" }
    }

    private func siriPhrase(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform").foregroundStyle(MinaTheme.accent).font(.system(size: 12, weight: .semibold))
            Text("“\(text)”").font(.mina(.subheadline)).foregroundStyle(MinaTheme.textSecondary)
        }
    }
}


/// A second child (or twins): a new local log you can share separately.
struct AddBabySheet: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var birthDate = Calendar.current.startOfDay(for: .now)
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    DatePicker("Birthday", selection: $birthDate, in: ...Date.now, displayedComponents: .date)
                } footer: {
                    Text("Each baby has its own log and its own sharing. Switch between them under Settings → Baby.")
                }
            }
            .navigationTitle("Add a baby")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        do {
                            let baby = try Logbook.shared.createBaby(name: name.trimmingCharacters(in: .whitespaces), birthDate: birthDate, in: context)
                            Prefs.selectedBabyID = baby.id
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .errorAlert($error)
        }
    }
}


/// A nightly schedule: blocks of time with a name on each. Stored on the
/// shared baby so both phones see the same plan.
struct ShiftsView: View {
    @ObservedObject var baby: Baby
    @Environment(\.managedObjectContext) private var context
    @State private var blocks: [ShiftBlock] = []
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                ForEach($blocks) { $block in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Who", text: $block.name)
                        HStack {
                            DatePicker("From", selection: minuteBinding($block.startMinute), displayedComponents: .hourAndMinute).labelsHidden()
                            Text("to").foregroundStyle(MinaTheme.textMuted)
                            DatePicker("To", selection: minuteBinding($block.endMinute), displayedComponents: .hourAndMinute).labelsHidden()
                            Spacer()
                            Button { block.deviceID = Prefs.deviceID; block.name = Prefs.yourName.isEmpty ? block.name : Prefs.yourName } label: {
                                Image(systemName: block.deviceID == Prefs.deviceID ? "iphone.badge.checkmark" : "iphone")
                            }
                            .buttonStyle(.bordered).accessibilityLabel("This is my phone")
                        }
                    }
                }
                .onDelete { blocks.remove(atOffsets: $0) }
                Button { blocks.append(ShiftBlock(name: Prefs.yourName.isEmpty ? "Me" : Prefs.yourName, deviceID: Prefs.deviceID, startMinute: 21 * 60, endMinute: 2 * 60)) } label: {
                    Label("Add a block", systemImage: "plus")
                }
            } header: {
                Text("Schedule")
            } footer: {
                Text("Blocks can cross midnight. Tap the phone icon on your own block so it follows your phone even if you rename yourself. Anything outside a block goes to both phones.")
            }
            if !blocks.isEmpty {
                Section {
                    Button("Clear the schedule", role: .destructive) { blocks = [] }
                }
            }
        }
        .navigationTitle("Shifts")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { blocks = Shifts.blocks(for: baby) }
        .onChange(of: blocks) { _, value in
            do { try Shifts.save(value, to: baby, in: context) } catch { self.error = error.localizedDescription }
        }
        .errorAlert($error)
    }

    private func minuteBinding(_ minute: Binding<Int>) -> Binding<Date> {
        Binding(get: { Calendar.current.date(bySettingHour: minute.wrappedValue / 60, minute: minute.wrappedValue % 60, second: 0, of: .now) ?? .now },
                set: { minute.wrappedValue = Calendar.current.component(.hour, from: $0) * 60 + Calendar.current.component(.minute, from: $0) })
    }
}
