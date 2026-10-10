import SwiftUI
import AppKit

@main
struct MeetPawApp: App {
    @State private var model = AppModel()

    init() {
        // --selftest short-circuits before the UI (see SelfTest.swift).
        if CommandLine.arguments.contains("--selftest") {
            SelfTest.run()
            exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra("MeetPaw", systemImage: "pawprint.fill") {
            MenuContent(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
