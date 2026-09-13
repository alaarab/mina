import AppIntents
import CloudKit
import SwiftUI
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
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @ObservedObject private var nanit = NanitSync.shared
    @State private var linkingNanit = false

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
                    LabeledContent("iCloud", value: sync.statusText)
                        .font(.mina(.subheadline))
                    Text(sync.stepsText)
                        .font(.mina(.caption2))
                        .foregroundStyle(MinaTheme.textMuted)
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
                    if notificationStatus == .denied {
                        Button("Notifications are off for Mina. Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                        .font(.mina(.subheadline))
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Partner alerts: “Mom fed Mina: 4 oz bottle at 2:15 PM” while the app is in the background. Feed reminders fire at her predicted next feed, learned from her last few feeds.")
                }

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
                        siriPhrase("\(baby.displayName) just ate 4 ounces")
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
                    Text("Say “Hey Siri” and any of these. No setup needed. The app's name is the trigger word; “Mina log”, “Mina app” and “the baby” work too if Siri mishears.")
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
            .sheet(item: $sharing.item) { item in
                CloudSharingView(share: item.share, container: sharing.cloudContainer, title: "\(baby.displayName)'s log")
                    .ignoresSafeArea()
            }
            .errorAlert($sharing.error, title: "Sharing problem")
            .task {
                await sync.refreshAccount()
                notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            }
        }
    }

    // MARK: Subviews

    private func siriPhrase(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform").foregroundStyle(MinaTheme.accent).font(.system(size: 12, weight: .semibold))
            Text("“\(text)”").font(.mina(.subheadline)).foregroundStyle(MinaTheme.textSecondary)
        }
    }
}
