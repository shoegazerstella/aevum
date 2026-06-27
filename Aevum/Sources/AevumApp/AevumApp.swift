// AevumApp.swift — macOS app entry point.

import SwiftUI

@main
struct AevumApp: App {
    @StateObject private var controller: EngineController

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let base = "\(home)/.cache/magenta-rt-v2"
        let modelPath = "\(base)/models/mrt2_small/mrt2_small.mlxfn"
        let resourcePath = "\(base)/resources"
        let spectrostreamPath = "\(base)/resources/spectrostream/spectrostream_encoder.mlxfn"

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let libraryURL = appSupport.appendingPathComponent("Aevum/library.sqlite")

        let ctrl = EngineController(libraryURL: libraryURL,
                                    modelPath: modelPath,
                                    resourcePath: resourcePath,
                                    spectrostreamPath: spectrostreamPath)
        _controller = StateObject(wrappedValue: ctrl)

        Task { await ctrl.loadEngine() }
    }

    var body: some SwiftUI.Scene {
        WindowGroup {
            ContentView()
                .environmentObject(controller)
                .frame(minWidth: 1200, minHeight: 750)
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
