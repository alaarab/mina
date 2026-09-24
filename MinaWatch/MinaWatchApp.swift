import SwiftUI
import AppIntents
import WatchConnectivity

@main
struct MinaWatchApp: App {
    @StateObject private var model = WatchModel()

    var body: some Scene {
        WindowGroup { WatchHome().environmentObject(model) }
    }
}

@MainActor
final class WatchModel: NSObject, ObservableObject, WCSessionDelegate {
    @Published var babyName = "Mina"
    @Published var lastFeedTitle = "Open Mina on iPhone"
    @Published var lastFeed: Date?
    @Published var sleepingSince: Date?
    @Published var message = ""
    @Published var working = false
    private var babyID: String?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        apply(WCSession.default.receivedApplicationContext)
    }

    func send(_ action: String) {
        guard !working else { return }
        guard let babyID, UUID(uuidString: babyID) != nil else { message = "Choose your baby in Mina on iPhone"; return }
        guard WCSession.default.isReachable else { message = "Open Mina on the iPhone"; return }
        working = true
        WCSession.default.sendMessage(["action": action, "babyID": babyID], replyHandler: { reply in
            Task { @MainActor in
                self.working = false
                self.message = reply["message"] as? String ?? "Done"
            }
        }, errorHandler: { error in
            Task { @MainActor in self.working = false; self.message = error.localizedDescription }
        })
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        Task { @MainActor in self.apply(context) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.apply(applicationContext) }
    }

    private func apply(_ value: [String: Any]) {
        babyID = value["babyID"] as? String
        babyName = value["babyName"] as? String ?? babyName
        lastFeedTitle = value["lastFeedTitle"] as? String ?? lastFeedTitle
        lastFeed = (value["lastFeed"] as? Double).map(Date.init(timeIntervalSince1970:))
        sleepingSince = (value["sleepingSince"] as? Double).map(Date.init(timeIntervalSince1970:))
    }
}

private struct WatchHome: View {
    @EnvironmentObject private var model: WatchModel

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text(model.babyName).font(.headline)
                if let sleepingSince = model.sleepingSince {
                    Label { Text(sleepingSince, style: .timer).monospacedDigit() } icon: { Image(systemName: "moon.zzz.fill") }
                        .foregroundStyle(.indigo)
                } else {
                    VStack(spacing: 2) {
                        Text(model.lastFeedTitle).font(.caption).multilineTextAlignment(.center)
                        if let lastFeed = model.lastFeed { Text(lastFeed, style: .relative).font(.caption2).foregroundStyle(.secondary) }
                    }
                }
                Button { model.send("bottle") } label: { Label("Bottle", systemImage: "waterbottle.fill") }
                    .disabled(model.working)
                HStack {
                    Button { model.send("pee") } label: { Image(systemName: "drop.fill") }.tint(.green).accessibilityLabel("Log pee")
                    Button { model.send("poop") } label: { Image(systemName: "drop.circle.fill") }.tint(.brown).accessibilityLabel("Log poop")
                    Button { model.send("sleep") } label: { Image(systemName: model.sleepingSince == nil ? "moon.zzz.fill" : "sun.max.fill") }.tint(.indigo)
                        .accessibilityLabel(model.sleepingSince == nil ? "Start sleep" : "End sleep")
                }
                .disabled(model.working)
                if model.working { ProgressView() }
                if !model.message.isEmpty { Text(model.message).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center) }
            }
        }
    }
}
