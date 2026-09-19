import AppKit
import Carbon.HIToolbox
import OSLog

struct GlobalShortcutEvent: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    static let optionL = GlobalShortcutEvent(keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(optionKey))
    static let optionQ = GlobalShortcutEvent(keyCode: UInt32(kVK_ANSI_Q), modifiers: UInt32(optionKey))
}

/// Carbon calls every registered application-level handler for a hotkey event.
/// Only the registrar that owns the event ID may consume it; the rest must let
/// it propagate to the matching handler.
enum CarbonGlobalShortcutRouting {
    static let signature = OSType(0x4C4E5348) // “LNSH”

    static func shouldHandle(signature: OSType, id: UInt32, registeredID: UInt32?) -> Bool {
        signature == Self.signature && id == registeredID
    }
}

enum GlobalShortcutParser {
    static func parse(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> GlobalShortcutEvent? {
        let disallowed = modifierFlags.intersection([.command, .control, .shift])
        guard modifierFlags.contains(.option), disallowed.isEmpty else {
            return nil
        }
        switch keyCode {
        case UInt16(kVK_ANSI_L): return .optionL
        case UInt16(kVK_ANSI_Q): return .optionQ
        default: return nil
        }
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
         shortcut: GlobalShortcutEvent = .optionQ,
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
    private static let signature = CarbonGlobalShortcutRouting.signature
    private static let logger = Logger(subsystem: "com.example.lanes", category: "global-shortcuts")
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var handler: (() -> Void)?
    private var registeredID: UInt32?

    func register(_ shortcut: GlobalShortcutEvent, handler: @escaping () -> Void) -> Bool {
        guard hotKey == nil else { return true }
        self.handler = handler

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let target = GetApplicationEventTarget()
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            let registrar = Unmanaged<CarbonGlobalShortcutRegistrar>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            var actualSize = 0
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size,
                                           &actualSize, &hotKeyID)
            guard status == noErr,
                  CarbonGlobalShortcutRouting.shouldHandle(
                    signature: hotKeyID.signature,
                    id: hotKeyID.id,
                    registeredID: registrar.registeredID
                  ) else { return OSStatus(eventNotHandledErr) }
            registrar.handler?()
            return noErr
        }

        let handlerStatus = InstallEventHandler(target, callback, 1, &eventType,
                                                Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        guard handlerStatus == noErr else {
            Self.logger.error("Unable to install global-shortcut handler: \(handlerStatus, privacy: .public)")
            self.handler = nil
            return false
        }

        // Each registrar owns one global shortcut. Use the key code as the
        // event ID so separate Option-L and Option-Q registrars cannot both
        // handle the same Carbon event.
        registeredID = shortcut.keyCode
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: shortcut.keyCode)
        let hotKeyStatus = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, hotKeyID,
                                               target, 0, &hotKey)
        guard hotKeyStatus == noErr else {
            Self.logger.error("Unable to register global shortcut keyCode=\(shortcut.keyCode, privacy: .public), modifiers=\(shortcut.modifiers, privacy: .public), status=\(hotKeyStatus, privacy: .public)")
            if let eventHandler { RemoveEventHandler(eventHandler); self.eventHandler = nil }
            registeredID = nil
            self.handler = nil
            return false
        }
        Self.logger.info("Registered global shortcut keyCode=\(shortcut.keyCode, privacy: .public), modifiers=\(shortcut.modifiers, privacy: .public)")
        return true
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        if let eventHandler { RemoveEventHandler(eventHandler); self.eventHandler = nil }
        registeredID = nil
        handler = nil
    }

    deinit { unregister() }
}
