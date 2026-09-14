import AppKit
import Carbon.HIToolbox

struct GlobalShortcutEvent: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    static let optionSpace = GlobalShortcutEvent(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))
}

enum GlobalShortcutParser {
    static func parse(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> GlobalShortcutEvent? {
        let disallowed = modifierFlags.intersection([.command, .control, .shift])
        guard keyCode == UInt16(kVK_Space), modifierFlags.contains(.option), disallowed.isEmpty else {
            return nil
        }
        return .optionSpace
    }
}

enum GlobalShortcutRegistrationState: Equatable {
    case idle
    case registered
    case failed
}

protocol GlobalShortcutRegistering: AnyObject {
    func register(_ shortcut: GlobalShortcutEvent, handler: @escaping () -> Void) -> Bool
    func unregister()
}

@MainActor
final class GlobalCaptureShortcutController {
    private let registrar: GlobalShortcutRegistering
    private let shortcut: GlobalShortcutEvent
    private let action: () -> Void
    private(set) var state: GlobalShortcutRegistrationState = .idle

    init(registrar: GlobalShortcutRegistering = CarbonGlobalShortcutRegistrar(),
         shortcut: GlobalShortcutEvent = .optionSpace,
         action: @escaping () -> Void) {
        self.registrar = registrar
        self.shortcut = shortcut
        self.action = action
    }

    @discardableResult
    func register() -> Bool {
        guard state != .registered else { return true }
        let registeredShortcut = shortcut
        let didRegister = registrar.register(shortcut) { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.route(registeredShortcut)
            }
        }
        state = didRegister ? .registered : .failed
        return didRegister
    }

    func unregister() {
        guard state == .registered else { return }
        registrar.unregister()
        state = .idle
    }

    func route(_ event: GlobalShortcutEvent) {
        guard state == .registered, event == shortcut else { return }
        action()
    }
}

private final class CarbonGlobalShortcutRegistrar: GlobalShortcutRegistering {
    private static let signature = OSType(0x4C4E5348) // “LNSH”
    private static let id = UInt32(1)

    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var handler: (() -> Void)?

    func register(_ shortcut: GlobalShortcutEvent, handler: @escaping () -> Void) -> Bool {
        guard hotKey == nil else { return true }
        self.handler = handler

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let target = GetApplicationEventTarget()
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            let registrar = Unmanaged<CarbonGlobalShortcutRegistrar>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            var actualSize = 0
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size,
                                           &actualSize, &hotKeyID)
            guard status == noErr,
                  hotKeyID.signature == CarbonGlobalShortcutRegistrar.signature,
                  hotKeyID.id == CarbonGlobalShortcutRegistrar.id else { return noErr }
            registrar.handler?()
            return noErr
        }

        let handlerStatus = InstallEventHandler(target, callback, 1, &eventType,
                                                Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        guard handlerStatus == noErr else {
            self.handler = nil
            return false
        }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.id)
        let hotKeyStatus = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, hotKeyID,
                                               target, 0, &hotKey)
        guard hotKeyStatus == noErr else {
            if let eventHandler { RemoveEventHandler(eventHandler); self.eventHandler = nil }
            self.handler = nil
            return false
        }
        return true
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        if let eventHandler { RemoveEventHandler(eventHandler); self.eventHandler = nil }
        handler = nil
    }

    deinit { unregister() }
}
