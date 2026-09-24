#if canImport(WatchConnectivity)
import CoreData
import Foundation
import WatchConnectivity

/// Relays four glanceable Watch actions through the phone, where the shared
/// Core Data + CloudKit stack and every after-save hook already live.
@MainActor
final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()

    func start() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func refresh(for baby: Baby? = nil, in suppliedContext: NSManagedObjectContext? = nil) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let context = suppliedContext ?? PersistenceController.shared.container.viewContext
        let babyID = baby?.objectID
        context.perform {
            let requestedBaby: Baby? = babyID.flatMap { id in
                (try? context.existingObject(with: id)) as? Baby
            }
            guard let baby = requestedBaby ?? Logbook.shared.currentBaby(in: context) else { return }
            let last = Logbook.shared.lastFeed(for: baby, in: context)
            let sleep = Logbook.shared.ongoingSleep(for: baby, in: context)
            var payload: [String: Any] = [
                "babyID": baby.id?.uuidString ?? "",
                "babyName": baby.displayName,
                "lastFeedTitle": last?.title(unit: Prefs.unit) ?? "No feeds yet",
                "lastBottleML": Prefs.lastBottleML,
                "unit": Prefs.unit.rawValue,
            ]
            if let date = last?.startedAt { payload["lastFeed"] = date.timeIntervalSince1970 }
            if let date = sleep?.startedAt { payload["sleepingSince"] = date.timeIntervalSince1970 }
            try? WCSession.default.updateApplicationContext(payload)
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        Task { @MainActor in self.refresh() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.refresh() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            do {
                guard let rawID = message["babyID"] as? String, let babyID = UUID(uuidString: rawID) else {
                    throw LogbookError.notSetUp
                }
                let text = try await self.perform(message["action"] as? String ?? "", babyID: babyID)
                self.refresh()
                replyHandler(["ok": true, "message": text])
            } catch {
                replyHandler(["ok": false, "message": error.localizedDescription])
            }
        }
    }

    func perform(_ action: String, babyID: UUID, logbook: Logbook = .shared) async throws -> String {
        try await logbook.perform(babyID: babyID) { context, baby in
            switch action {
            case "bottle":
                var draft = EntryDraft(kind: .bottle)
                draft.amountML = Prefs.lastBottleML
                try logbook.add(draft, to: baby, in: context)
                return "Logged \(Prefs.unit.format(ml: draft.amountML))"
            case "pee", "poop":
                var draft = EntryDraft(kind: .diaper)
                draft.diaper = action == "pee" ? .wet : .dirty
                try logbook.add(draft, to: baby, in: context)
                return action == "pee" ? "Logged pee" : "Logged poop"
            case "sleep":
                if try logbook.endSleep(for: baby, in: context) != nil { return "Marked awake" }
                try logbook.add(EntryDraft(kind: .sleep), to: baby, in: context)
                return "Started sleep"
            default:
                return "Unknown action"
            }
        }
    }
}

#endif
