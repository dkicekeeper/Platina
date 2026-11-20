import SwiftUI
import SwiftData
import DesignTokens
import PlatinaStore

@main
struct PlatinaApp: App {
    @State private var model: AppModel

    init() {
        // Brand first, before any view renders (DesignKit README, "Using it in an app").
        DesignKitTheme.accent = PlatinaColors.accent
        DesignKitFonts.registerIfNeeded()

        let container: ModelContainer
        do {
            container = try LibraryStore.makeContainer()
        } catch {
            // The disk refused the store: the app still works for this launch, from memory.
            do {
                container = try LibraryStore.makeContainer(inMemory: true)
            } catch {
                fatalError("SwiftData cannot create even an in-memory store: \(error)")
            }
        }
        _model = State(initialValue: AppModel(container: container))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.start() }
        }
        .modelContainer(model.store.container)
    }
}
