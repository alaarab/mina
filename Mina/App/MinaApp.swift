import CloudKit
import CoreData
import SwiftUI
import UIKit

/// The app's entry point and its scaffolding: the one-time setup that runs
/// before the first screen, the delegates that catch CloudKit share links and
/// remote pushes, and the tab bar that picks between the baby's log and
/// onboarding.

@main
struct MinaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var sync = SyncMonitor()
    @Environment(\.scenePhase) private var scenePhase
    private let persistence = PersistenceController.shared

    init() {
        MinaShortcuts.updateAppShortcutParameters()
        DebugLaunch.seedIfRequested(logbook: .shared, context: persistence.container.viewContext)
        PartnerAlerts.shared.start()
        EntryIndex.refresh()
        Logbook.anyEntryLogged = { baby, context in WeeklyDigest.schedule(for: baby, in: context) }
        Logbook.feedLogged = { baby, context in
            let last = Logbook.shared.lastFeed(for: baby, in: context)?.startedAt
            let prediction = Predictor.nextFeed(feedTimes: Logbook.shared.recentFeedTimes(for: baby, in: context), stage: baby.ageDays().map(Guidance.stage(forAgeDays:)))
            if Shifts.thisPhoneIsOn(for: baby) {
                FeedAlarm.reschedule(lastFeed: last, prediction: prediction, babyName: baby.displayName)
            } else {
                FeedAlarm.cancel()
            }
        }
        Self.startRecoveryExportIfNeeded(persistence: persistence)
    }

    /// A build installed as com.alaarab.mina.recovery exists only to pull the
    /// development-environment log down and write it where it can be copied off.
    private static func startRecoveryExportIfNeeded(persistence: PersistenceController) {
        guard Bundle.main.bundleIdentifier?.hasSuffix(".recovery") == true else { return }
        // Write the complete record schema (every entity and field) into the
        // Development environment, so it can be deployed to Production whole.
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            let report: String
            do {
                try persistence.container.initializeCloudKitSchema(options: [])
                report = "schema initialized \(Date.now)"
            } catch {
                report = "schema failed: \(error)"
            }
            try? report.write(to: Backup.autoExportURL.deletingLastPathComponent().appendingPathComponent("schema.txt"), atomically: true, encoding: .utf8)
        }
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            let context = persistence.container.viewContext
            context.perform {
                guard let baby = Logbook.shared.currentBaby(in: context), let data = try? Backup.exportData(baby: baby, in: context) else { return }
                try? data.write(to: Backup.autoExportURL, options: .atomic)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistence.container.viewContext)
                .environmentObject(sync)
                .tint(MinaTheme.accent)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: if FeatureFlags.nanit { Task { await NanitSync.shared.sync() } }
            case .background: if FeatureFlags.nanit { NanitSync.scheduleBackgroundRefresh() }
            default: break
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // CloudKit pushes arrive as silent notifications; the container handles them.
        application.registerForRemoteNotifications()
        NanitSync.registerBackgroundTask()
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        ShareManager.shared.accept(metadata)
    }
}

/// Receives the partner's tap on the share link.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        ShareManager.shared.accept(metadata)
    }
}

struct RootView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(fetchRequest: Baby.request(), animation: .default) private var babies: FetchedResults<Baby>
    @AppStorage(Prefs.selectedBabyKey, store: Prefs.defaults) private var selectedBabyID = ""
    @State private var mergeCandidate: Baby?
    @State private var mergeResult: String?

    var body: some View {
        let persistence = PersistenceController.shared
        Group {
            if let baby = persistence.preferredBaby(from: Array(babies)) {
                MainTabs(baby: baby).id(baby.objectID)
                    .task { WeeklyDigest.schedule(for: baby, in: context) }
                    .task {
                        if ShareManager.shared.existingShare(for: baby) != nil {
                            PartnerAlerts.shared.registerCloudSubscriptionIfOwner(babyName: baby.displayName, isOwner: !persistence.isShared(baby))
                        }
                    }
            } else {
                OnboardingView()
            }
        }
        .onChange(of: babies.count, initial: true) { _, _ in offerMergeIfNeeded() }
        .alert("Merge your log?", isPresented: Binding(get: { mergeCandidate != nil }, set: { if !$0 { mergeCandidate = nil } }), presenting: mergeCandidate) { local in
            Button("Merge into the shared log") { merge(local) }
            Button("Keep both", role: .cancel) { Prefs.defaults.set(true, forKey: "merge.declined.\(local.id?.uuidString ?? "")") }
        } message: { local in
            let count = Logbook.shared.entries(for: local, from: .distantPast, in: context).count
            Text("You already had a log for \(local.displayName) with \(count) \(count == 1 ? "entry" : "entries") on this phone. Move them into the log your partner shared? Your own copy is removed afterwards.")
        }
        .errorAlert(Binding(get: { mergeResult }, set: { mergeResult = $0 }), title: "Merged")
    }

    /// After accepting a share: a local baby with the same name as the shared one is almost certainly the same child.
    private func offerMergeIfNeeded() {
        let persistence = PersistenceController.shared
        guard mergeCandidate == nil,
              let shared = babies.first(where: { persistence.isShared($0) }),
              let local = babies.first(where: { !persistence.isShared($0) && $0.displayName.lowercased() == shared.displayName.lowercased() }),
              !Prefs.defaults.bool(forKey: "merge.declined.\(local.id?.uuidString ?? "")") else { return }
        mergeCandidate = local
    }

    private func merge(_ local: Baby) {
        guard let shared = babies.first(where: { PersistenceController.shared.isShared($0) }) else { return }
        do {
            let moved = try Logbook.shared.merge(local, into: shared, in: context)
            mergeResult = "\(moved) \(moved == 1 ? "entry" : "entries") moved into the shared log."
        } catch { mergeResult = "Couldn't merge: \(error.localizedDescription)" }
    }
}

struct MainTabs: View {
    @ObservedObject var baby: Baby
    @State private var tab = DebugLaunch.initialTab ?? "today"
    @State private var showingWhatsNew = Changelog.shouldShow && !DebugLaunch.isDemo

    var body: some View {
        TabView(selection: $tab) {
            TodayView(baby: baby)
                .tabItem { Label("Today", systemImage: "sun.horizon.fill") }
                .tag("today")
            CalendarView(baby: baby)
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag("calendar")
            TrendsView(baby: baby)
                .tabItem { Label("Trends", systemImage: "chart.bar.fill") }
                .tag("trends")
            GuideView(baby: baby)
                .tabItem { Label("Guide", systemImage: "book.fill") }
                .tag("guide")
            SettingsView(baby: baby)
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag("settings")
        }
        .onAppear { if !DebugLaunch.isDemo { PartnerAlerts.shared.requestPermission() } }
        .sheet(isPresented: $showingWhatsNew, onDismiss: { Changelog.markSeen() }) { WhatsNewView(onlyNewest: true) }
    }
}
