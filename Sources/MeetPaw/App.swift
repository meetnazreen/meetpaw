import SwiftUI
import AppKit

@main
struct MeetPawApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        // --selftest short-circuits before the UI (see SelfTest.swift).
        if CommandLine.arguments.contains("--selftest") {
            SelfTest.run()
            exit(0)
        }
    }

    // No windows — the status item (AppDelegate) is the whole UI.
    var body: some Scene { Settings { EmptyView() } }
}
