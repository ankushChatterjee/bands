import SwiftUI
import AppKit

extension PanelCommand {
    var key: KeyEquivalent {
        switch self {
        case .quickCapture: "l"
        case .newThought, .newLane: "n"
        case .openSettings: ","
        case .copy: "c"
        case .editDescription: "d"
        case .complete, .edit: .return
        case .resetAging: "r"
        case .move: "m"
        case .moveEarlier: "["
        case .moveLater: "]"
        case .destructive: .delete
        }
    }
    var modifiers: EventModifiers {
        switch self {
        case .quickCapture: [.option]
        case .edit: []
        case .newLane: [.command, .shift]
        case .copy: [.command]
        case .resetAging, .move, .moveEarlier, .moveLater: [.command, .option]
        case .editDescription: [.command, .shift]
        default: [.command]
        }
    }
    static func matching(_ event: NSEvent) -> PanelCommand? {
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        return allCases.first { command in
            var expected: NSEvent.ModifierFlags = []
            if command.modifiers.contains(.command) { expected.insert(.command) }
            if command.modifiers.contains(.option) { expected.insert(.option) }
            if command.modifiers.contains(.shift) { expected.insert(.shift) }
            guard flags == expected else { return false }
            if command == .edit || command == .complete { return event.keyCode == 36 || event.keyCode == 76 }
            if command == .destructive { return event.keyCode == 51 }
            return event.charactersIgnoringModifiers?.lowercased() == String(command.key.character)
        }
    }
}

@MainActor final class BoardCommands: ObservableObject {
    static let shared = BoardCommands()
    @Published var available: Set<PanelCommand> = []
}

struct LanesCommands: Commands {
    @ObservedObject private var state = BoardCommands.shared
    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            commandButton(.openSettings)
        }
        CommandMenu("lanes") {
            ForEach(PanelCommand.reference.filter { $0 != .quickCapture && $0 != .openSettings }, id: \.self) { command in
                commandButton(command)
            }
        }
    }
    private func commandButton(_ command: PanelCommand) -> some View {
        Button(command.title) { LanesCommandDispatcher.perform(command) }
            .keyboardShortcut(command.key, modifiers: command.modifiers)
            .disabled(!state.available.contains(command))
    }
}

@main struct lanesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        Settings { SettingsView().environmentObject(ThoughtAgingSettingsStore.shared) }
            .commands { LanesCommands() }
    }
}
