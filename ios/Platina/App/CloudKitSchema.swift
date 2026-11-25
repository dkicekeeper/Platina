#if DEBUG
import CoreData
import Foundation
import os
import SwiftData
import PlatinaStore

/// Writes every record type and field of the person's own store (`LibraryStore.userModels`) to
/// CloudKit's Development environment at once, so CloudKit Console can deploy the whole schema to
/// Production (docs/testflight.md). Without it Development learns a type or a field only when a
/// Debug build first saves one, and a Production schema deployed from it misses the rest.
///
/// Run once from Xcode on a device signed in to iCloud: the "Platina CloudKit Schema" scheme
/// (`-InitializeCloudKitSchema`), then watch the console for "CloudKit schema:". Debug builds only.
@MainActor
enum CloudKitSchema {
    static let isRequested = ProcessInfo.processInfo.arguments.contains("-InitializeCloudKitSchema")

    private static let log = Logger(subsystem: "dakacom.Platina", category: "CloudKit")

    static func initialize() {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: LibraryStore.userModels) else {
            report("no Core Data model for the person's store")
            return
        }
        // A store of its own in temporary files: the app's real store is not touched.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cloudkit-schema.sqlite")
        let description = NSPersistentStoreDescription(url: url)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.dakacom.Platina")
        description.shouldAddStoreAsynchronously = false

        let container = NSPersistentCloudKitContainer(name: "PlatinaCloudKitSchema", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]
        var loadError: (any Error)?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError {
            report("the store did not open: \(loadError)")
            return
        }
        do {
            try container.initializeCloudKitSchema()
            let names = model.entities.compactMap(\.name).map { "CD_\($0)" }.joined(separator: ", ")
            report("done. Development has \(names) with every field: deploy them in CloudKit Console.")
        } catch {
            report("failed: \(error). Is this device signed in to iCloud?")
        }
        for store in container.persistentStoreCoordinator.persistentStores {
            try? container.persistentStoreCoordinator.remove(store)
        }
    }

    private static func report(_ message: String) {
        log.notice("CloudKit schema: \(message, privacy: .public)")
        print("CloudKit schema: \(message)")
    }
}
#endif
