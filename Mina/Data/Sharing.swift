import CloudKit
import Combine
import CoreData
import SwiftUI
import UIKit

/// Creates the CloudKit share for the baby, accepts one from a partner, and
/// describes who is on it.
@MainActor
final class ShareManager: ObservableObject {
    static let shared = ShareManager()

    struct Item: Identifiable {
        let id = UUID()
        let share: CKShare
    }

    @Published var item: Item?
    @Published var error: String?

    let persistence = PersistenceController.shared
    var cloudContainer: CKContainer { CKContainer(identifier: PersistenceController.cloudContainerIdentifier) }

    func existingShare(for baby: Baby) -> CKShare? {
        (try? persistence.container.fetchShares(matching: [baby.objectID]))?[baby.objectID]
    }

    /// Opens the system sharing sheet, creating the share on first use.
    /// Share creation talks to iCloud, so it checks the account first and
    /// gives up after 30 seconds instead of spinning forever.
    func present(for baby: Baby) async {
        do {
            if let share = existingShare(for: baby) {
                item = Item(share: share)
                return
            }
            let status = try await cloudContainer.accountStatus()
            guard status == .available else {
                throw ShareError.noAccount(status)
            }
            let container = persistence.container
            let share = try await withThrowingTaskGroup(of: CKShare.self) { group in
                group.addTask {
                    let (_, share, _) = try await container.share([baby], to: nil)
                    return share
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(30))
                    throw ShareError.timedOut
                }
                let first = try await group.next()!
                group.cancelAll()
                return first
            }
            share[CKShare.SystemFieldKey.title] = "\(baby.displayName)'s log" as CKRecordValue
            item = Item(share: share)
        } catch {
            self.error = (error as? ShareError)?.errorDescription ?? error.localizedDescription
        }
    }

    enum ShareError: LocalizedError {
        case noAccount(CKAccountStatus)
        case timedOut

        var errorDescription: String? {
            switch self {
            case .noAccount(.noAccount): return "This phone isn't signed in to iCloud. Sign in under Settings > Apple Account, then try again."
            case .noAccount(.restricted): return "iCloud is restricted on this phone (Screen Time or a profile)."
            case .noAccount: return "iCloud isn't available right now. Try again in a minute."
            case .timedOut: return "iCloud didn't answer in 30 seconds. Check the iCloud line below for a sync error, make sure iCloud Drive is on for Mina in Settings > Apple Account > iCloud, and try again."
            }
        }
    }

    /// Called straight from the scene and app delegates, which are nonisolated,
    /// so this reads the persistence controller from its own static rather than
    /// through the main-actor-isolated `persistence` property.
    nonisolated func accept(_ metadata: CKShare.Metadata) {
        let persistence = PersistenceController.shared
        guard let store = persistence.sharedStore else { return }
        persistence.container.acceptShareInvitations(from: [metadata], into: store) { _, error in
            guard let error else { return }
            Task { @MainActor in self.error = error.localizedDescription }
        }
    }

    struct Participant: Identifiable {
        let id: String
        let name: String
        let isOwner: Bool
        let canWrite: Bool
        let accepted: Bool
    }

    /// Everyone on the share, with what they can do. Owner first.
    func participants(for baby: Baby) -> [Participant] {
        guard let share = existingShare(for: baby) else { return [] }
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .short
        return share.participants.map { participant in
            let identity = participant.userIdentity
            let name = identity.nameComponents.map { formatter.string(from: $0) }
                ?? identity.lookupInfo?.emailAddress ?? identity.lookupInfo?.phoneNumber ?? "Invited person"
            return Participant(id: identity.userRecordID?.recordName ?? name, name: name.isEmpty ? "Invited person" : name,
                               isOwner: participant.role == .owner, canWrite: participant.permission == .readWrite,
                               accepted: participant.acceptanceStatus == .accepted)
        }.sorted { $0.isOwner && !$1.isOwner }
    }

    /// Gives every invited person edit access and saves the share to iCloud.
    func grantWriteToEveryone(for baby: Baby) async {
        guard let share = existingShare(for: baby) else { error = "There's no share on this log yet."; return }
        for participant in share.participants where participant.role != .owner { participant.permission = .readWrite }
        do {
            let database = cloudContainer.privateCloudDatabase
            _ = try await database.modifyRecords(saving: [share], deleting: [], savePolicy: .changedKeys)
            objectWillChange.send()
        } catch {
            self.error = "Couldn't update the share: \(error.localizedDescription)"
        }
    }

    /// "Shared with Sam" or "Not shared yet".
    ///
    /// The email or phone fallback shows the address the owner typed into the
    /// share sheet themselves, back to that same owner, and only when iCloud has
    /// no name for the participant yet. It is not shown to the invitee, and it
    /// reveals nothing the person reading it did not already provide. Deliberate,
    /// and written down in docs/SECURITY.md.
    func describe(_ share: CKShare?, baby: Baby) -> String {
        guard let share else { return "Not shared yet" }
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .short
        let others = share.participants
            .filter { $0.userIdentity.userRecordID != share.currentUserParticipant?.userIdentity.userRecordID }
            .compactMap { participant -> String? in
                if let components = participant.userIdentity.nameComponents { return formatter.string(from: components) }
                return participant.userIdentity.lookupInfo?.emailAddress ?? participant.userIdentity.lookupInfo?.phoneNumber
            }
        if persistence.isShared(baby) {
            let owner = share.owner.userIdentity.nameComponents.map { formatter.string(from: $0) }
            return owner.map { "Shared with you by \($0)" } ?? "Shared with you"
        }
        if others.isEmpty { return "Invite sent, waiting for your partner" }
        return "Shared with \(others.joined(separator: ", "))"
    }
}

struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let title: String

    func makeCoordinator() -> Coordinator { Coordinator(title: title) }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let title: String
        init(title: String) { self.title = title }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            Task { @MainActor in ShareManager.shared.error = error.localizedDescription }
        }
        func itemTitle(for csc: UICloudSharingController) -> String? { title }
        func itemType(for csc: UICloudSharingController) -> String? { "com.alaarab.mina.log" }
    }
}

/// Watches CloudKit import/export events so Settings can say whether sync is
/// healthy, and why not when it isn't.
@MainActor
final class SyncMonitor: ObservableObject {
    @Published var lastError: String?
    @Published var lastSuccess: Date?
    @Published var accountStatus: CKAccountStatus = .couldNotDetermine
    /// Latest outcome per CloudKit step, so Settings can say which one is stuck.
    @Published var steps: [String: String] = [:]

    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            Task { @MainActor in self?.handle(event) }
        }
        Task { await refreshAccount() }
    }

    /// The most recent error text per step, including CloudKit's per-record detail.
    @Published var details: [String: String] = [:]

    private func handle(_ event: NSPersistentCloudKitContainer.Event) {
        let step: String
        switch event.type {
        case .setup: step = "Setup"
        case .import: step = "Import"
        case .export: step = "Export"
        @unknown default: step = "Other"
        }
        // The private store holds a log you created; the shared store one your partner shared.
        let persistence = PersistenceController.shared
        let store = event.storeIdentifier == persistence.sharedStore?.identifier ? "Shared log" : "Your log"
        let name = "\(store) \(step)"
        guard let endDate = event.endDate else {
            steps[name] = "running…"
            return
        }
        if let error = event.error {
            let nsError = error as NSError
            var lines = ["\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"]
            if let partial = nsError.userInfo[NSDetailedErrorsKey] as? [NSError] { lines += partial.prefix(5).map { "\($0.code): \($0.localizedDescription)" } }
            if let partial = nsError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: NSError] { lines += partial.values.prefix(5).map { "\($0.code): \($0.localizedDescription)" } }
            lastError = "\(name): \(nsError.localizedDescription)"
            steps[name] = "failed \(Format.time(endDate))"
            details[name] = lines.joined(separator: "\n")
        } else {
            if lastError?.hasPrefix(name) == true { lastError = nil }
            lastSuccess = endDate
            steps[name] = "ok \(Format.time(endDate))"
            details[name] = nil
        }
    }

    /// One line per store, only for stores that have reported anything.
    var stepsText: String {
        ["Your log", "Shared log"].compactMap { store -> String? in
            let parts = ["Setup", "Export", "Import"].compactMap { step in steps["\(store) \(step)"].map { "\(step) \($0)" } }
            return parts.isEmpty ? nil : "\(store): " + parts.joined(separator: " · ")
        }.joined(separator: "\n")
    }

    func refreshAccount() async {
        let container = CKContainer(identifier: PersistenceController.cloudContainerIdentifier)
        accountStatus = (try? await container.accountStatus()) ?? .couldNotDetermine
    }

    var statusText: String {
        switch accountStatus {
        case .available:
            if let lastError { return "Problem: \(lastError)" }
            if let lastSuccess { return "Synced \(Format.ago(from: lastSuccess))" }
            return "Signed in, waiting for first sync"
        case .noAccount: return "Sign in to iCloud in Settings to sync"
        case .restricted: return "iCloud is restricted on this phone"
        case .temporarilyUnavailable: return "iCloud is temporarily unavailable"
        default: return "Checking iCloud…"
        }
    }
}
