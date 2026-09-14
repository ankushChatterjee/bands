import SwiftUI

@main struct lanesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        Settings { SettingsView().environmentObject(ThoughtAgingSettingsStore.shared) }
            .commands { CommandMenu("lanes") { Button("New Thought") {}; Button("New Lane") {}.keyboardShortcut("n", modifiers: [.command, .shift]) } }
    }
}
