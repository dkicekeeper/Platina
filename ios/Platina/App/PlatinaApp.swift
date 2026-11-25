import SwiftUI
import SwiftData
import DesignTokens
import DesignSupport
import PlatinaStore

@main
struct PlatinaApp: App {
    @State private var model: AppModel

    init() {
        // Brand first, before any view renders (DesignKit README, "Using it in an app").
        DesignKitTheme.accent = PlatinaColors.accent
        // Cards and sections are a grey fill on the white page, not Liquid Glass (DesignKit
        // 8.12.0, the owner's choice: less glass). Buttons and the tab bar stay glass.
        DesignKitTheme.surface = .fill
        DesignKitFonts.registerIfNeeded()
        // Every RemotePhoto loads through the app's cache: a picture seen before shows at once,
        // from memory or disk, and is downloaded only once (PhotoCache).
        DesignKitPhotoLoader.loader = { key, url in await PhotoCache.shared.image(key: key, url: url) }
        DesignKitPhotoLoader.cached = { key in PhotoCache.shared.cached(key) }

        // The App Store's screenshots: a made-up library in memory, nothing real touched.
        if ScreenshotDemo.isOn {
            ScreenshotDemo.installArt()
            do {
                let container = try LibraryStore.makeContainer(inMemory: true)
                _model = State(initialValue: AppModel(container: container, client: ScreenshotDemo.client()))
            } catch {
                fatalError("SwiftData cannot create an in-memory store: \(error)")
            }
            return
        }

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
        // The background task's closure is Sendable: it takes the model, not the App.
        let model = model
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.start() }
        }
        .modelContainer(model.store.container)
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await model.backgroundRefresh()
        }
    }
}
