import CloudKit
import CoreData
import SwiftUI
import UIKit

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
            case .active: Task { await NanitSync.shared.sync() }
            case .background: NanitSync.scheduleBackgroundRefresh()
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
    @FetchRequest(fetchRequest: Baby.request(), animation: .default) private var babies: FetchedResults<Baby>

    var body: some View {
        if let baby = PersistenceController.shared.preferredBaby(from: Array(babies)) {
            MainTabs(baby: baby).id(baby.objectID)
        } else {
            OnboardingView()
        }
    }
}

struct MainTabs: View {
    @ObservedObject var baby: Baby
    @State private var tab = DebugLaunch.initialTab ?? "today"

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
    }
}
