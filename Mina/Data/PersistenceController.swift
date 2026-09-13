import CloudKit
import CoreData
import Foundation

/// One Core Data stack mirrored to CloudKit. The private store holds the baby
/// you created; the shared store holds a baby your partner shared with you.
/// Both phones end up editing the same CloudKit zone, which is what makes the
/// log identical on each.
///
/// The SQLite files live in the App Group so widgets can read and write them.
/// Widgets open the same files without CloudKit; the app notices their writes
/// through persistent history and exports them on its next run.
final class PersistenceController {
    static let cloudContainerIdentifier = "iCloud.com.alaarab.mina"
    static var isExtension: Bool { Bundle.main.bundleURL.pathExtension == "appex" }
    static let shared = PersistenceController(cloud: !isExtension)

    static let appAuthor = "mina"
    static let widgetAuthor = "mina-widget"

    let container: NSPersistentCloudKitContainer
    let inMemory: Bool
    let cloud: Bool
    private(set) var privateStore: NSPersistentStore?
    private(set) var sharedStore: NSPersistentStore?
    private(set) var loadError: Error?

    var author: String { Self.isExtension ? Self.widgetAuthor : Self.appAuthor }

    init(inMemory: Bool = false, cloud: Bool = true) {
        self.inMemory = inMemory
        self.cloud = cloud && !inMemory
        container = NSPersistentCloudKitContainer(name: "Mina", managedObjectModel: MinaModel.model)

        let privateDescription: NSPersistentStoreDescription
        var sharedDescription: NSPersistentStoreDescription?
        if inMemory {
            privateDescription = NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))
        } else {
            let directory = Self.storeDirectory()
            Self.moveLegacyStores(into: directory)
            privateDescription = NSPersistentStoreDescription(url: directory.appendingPathComponent("Mina.sqlite"))
            let shared = NSPersistentStoreDescription(url: directory.appendingPathComponent("Mina-shared.sqlite"))
            if self.cloud {
                let privateOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.cloudContainerIdentifier)
                privateOptions.databaseScope = .private
                privateDescription.cloudKitContainerOptions = privateOptions
                let sharedOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.cloudContainerIdentifier)
                sharedOptions.databaseScope = .shared
                shared.cloudKitContainerOptions = sharedOptions
            }
            sharedDescription = shared
        }

        let descriptions = [privateDescription, sharedDescription].compactMap { $0 }
        for description in descriptions {
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            // Encrypted while the phone has not been unlocked since boot, readable
            // after that. Stronger protection would break the two things that have
            // to keep working with the phone locked: CloudKit importing the
            // partner's entries in the background, and widget timeline reloads.
            if !inMemory {
                description.setOption(FileProtectionType.completeUntilFirstUserAuthentication.rawValue as NSString,
                                      forKey: NSPersistentStoreFileProtectionKey)
            }
        }
        container.persistentStoreDescriptions = descriptions

        var errors: [Error] = []
        container.loadPersistentStores { _, error in
            if let error { errors.append(error) }
        }
        loadError = errors.first

        let coordinator = container.persistentStoreCoordinator
        if let url = privateDescription.url { privateStore = coordinator.persistentStore(for: url) }
        if let url = sharedDescription?.url { sharedStore = coordinator.persistentStore(for: url) }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.transactionAuthor = author
    }

    // MARK: Locations

    static func storeDirectory() -> URL {
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Prefs.appGroup) {
            let directory = group.appendingPathComponent("Mina", isDirectory: true)
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
            // The directory may predate this attribute, and App Group containers
            // do not inherit the app container's default class.
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: directory.path
            )
            return directory
        }
        return NSPersistentContainer.defaultDirectoryURL()
    }

    /// The first build kept the stores in the app's own container. Move them
    /// once so nothing logged before the widgets existed is lost.
    private static func moveLegacyStores(into directory: URL) {
        let legacy = NSPersistentContainer.defaultDirectoryURL()
        guard legacy != directory else { return }
        let files = FileManager.default
        for name in ["Mina.sqlite", "Mina-shared.sqlite"] {
            let target = directory.appendingPathComponent(name)
            guard !files.fileExists(atPath: target.path) else { continue }
            for suffix in ["", "-wal", "-shm"] {
                let source = legacy.appendingPathComponent(name + suffix)
                guard files.fileExists(atPath: source.path) else { continue }
                try? files.moveItem(at: source, to: directory.appendingPathComponent(name + suffix))
            }
        }
    }

    // MARK: Helpers

    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.transactionAuthor = author
        return context
    }

    func isShared(_ object: NSManagedObject) -> Bool {
        guard let sharedStore else { return false }
        return object.objectID.persistentStore == sharedStore
    }

    /// A baby someone shared with you wins over one you created locally, so
    /// accepting an invite switches the whole app to the shared log.
    func preferredBaby(from babies: [Baby]) -> Baby? {
        babies.first(where: isShared) ?? babies.first
    }
}
