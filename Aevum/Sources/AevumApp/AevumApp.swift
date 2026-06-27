// AevumApp.swift — macOS app entry point.
//
// On launch, checks whether the model assets are present at
// ~/.cache/magenta-rt-v2. If not, shows FirstRunView (downloads them
// from HuggingFace) before constructing the EngineController — loading
// the engine without the model files would just produce a confusing
// error. Once the downloader reports .done, swap to the main window.

import SwiftUI

@main
struct AevumApp: App {
    @StateObject private var controller: EngineController
    @State private var modelsReady: Bool = ModelAssets.isPresent

    init() {
        // Build paths from the single source of truth in ModelAssets.
        let libraryURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Aevum/library.sqlite")

        let ctrl = EngineController(libraryURL: libraryURL,
                                    modelPath: ModelAssets.modelPath,
                                    resourcePath: ModelAssets.resourcePath,
                                    spectrostreamPath: ModelAssets.spectrostreamPath)
        _controller = StateObject(wrappedValue: ctrl)
    }

    var body: some SwiftUI.Scene {
        WindowGroup {
            if modelsReady {
                ContentView()
                    .environmentObject(controller)
                    .frame(minWidth: 1200, minHeight: 750)
                    .task { if !controller.isEngineLoaded { await controller.loadEngine() } }
            } else {
                FirstRunView { modelsReady = true }
            }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Import Songs…") {
                    NotificationCenter.default.post(name: .importSongs, object: nil)
                }.keyboardShortcut("i", modifiers: [.command])

                Button("Play / Stop") {
                    NotificationCenter.default.post(name: .togglePlay, object: nil)
                }.keyboardShortcut(" ", modifiers: [])

                Button("Reset Engine") {
                    NotificationCenter.default.post(name: .triggerReset, object: nil)
                }.keyboardShortcut("r", modifiers: [])

                Button("Focus Mode") {
                    NotificationCenter.default.post(name: .toggleFocused, object: nil)
                }.keyboardShortcut("f", modifiers: [.command])
            }
        }
    }
}

extension Notification.Name {
    static let importSongs = Notification.Name("Aevum.importSongs")
    static let togglePlay = Notification.Name("Aevum.togglePlay")
    static let triggerReset = Notification.Name("Aevum.triggerReset")
    static let toggleFocused = Notification.Name("Aevum.toggleFocused")
}
