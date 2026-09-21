import AppKit
import SwiftData

private enum BandsStatusIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        defer { image.unlockFocus() }

        let path = NSBezierPath()
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        NSColor.black.setStroke()

        // The outer rails are continuous; the center rail is dashed to suggest
        // bands and movement between them.
        for y in [5.0, 13.0] {
            path.move(to: NSPoint(x: 2, y: y))
            path.line(to: NSPoint(x: 16, y: y))
        }
        path.stroke()

        let dashedPath = NSBezierPath()
        dashedPath.lineWidth = 1.5
        dashedPath.lineCapStyle = .round
        dashedPath.setLineDash([3.0, 2.0], count: 2, phase: 0)
        dashedPath.move(to: NSPoint(x: 2, y: 9))
        dashedPath.line(to: NSPoint(x: 16, y: 9))
        dashedPath.stroke()

        image.isTemplate = true
        return image
    }
}

private enum BandsStatusMenu {
    static func make(target: AnyObject) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit bands", action: #selector(AppDelegate.quit), keyEquivalent: "q")
        menu.items[0].target = target
        return menu
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var controller: PanelController!
    private var globalPanelShortcut: GlobalCaptureShortcutController!
    private var globalCaptureShortcut: GlobalCaptureShortcutController!
    private var container: ModelContainer!
    private var mcpBridge: BandsMCPBridge!
    private var notificationCoordinator: BandsNotificationCoordinator!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        do { container = try ModelContainer(for: Band.self, Thought.self) }
        catch { fatalError("Unable to create local store: \(error)") }
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "mcpEnabled") == nil { defaults.set(true, forKey: "mcpEnabled") }
        if defaults.bool(forKey: "mcpEnabled") {
            mcpBridge = BandsMCPBridge(service: BandsCommandService(container: container))
            mcpBridge.start()
        }
        controller = PanelController(container: container)
        notificationCoordinator = BandsNotificationCoordinator(container: container)
        notificationCoordinator.start()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            // Use AppKit's native, subtle selected-state background while the
            // panel is open. The controller owns the highlighted state.
            (button.cell as? NSButtonCell)?.highlightsBy = NSCell.StyleMask(rawValue: 8)
            button.image = BandsStatusIcon.make()
            button.toolTip = "bands"
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            controller.attach(to: button)
        }
        globalPanelShortcut = GlobalCaptureShortcutController(shortcut: .optionL) { [weak self] in
            self?.controller.show()
        }
        globalCaptureShortcut = GlobalCaptureShortcutController(shortcut: .optionQ) { [weak self] in
            self?.controller.show()
            DispatchQueue.main.async {
                BandsCommandDispatcher.perform(.quickCapture)
            }
        }
        let panelShortcutRegistered = globalPanelShortcut.register()
        let captureShortcutRegistered = globalCaptureShortcut.register()
        if !panelShortcutRegistered || !captureShortcutRegistered {
            NSLog("bands global shortcuts: Option-L registered=\(panelShortcutRegistered), Option-Q registered=\(captureShortcutRegistered)")
        }
    }

    @objc private func statusItemClicked() {
        guard let button = statusItem.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            BandsStatusMenu.make(target: self).popUp(positioning: nil,
                                                      at: NSPoint(x: button.bounds.midX, y: button.bounds.minY),
                                                      in: button)
        } else {
            controller.toggle()
        }
    }

    @objc fileprivate func quit() { NSApp.terminate(self) }

    func applicationWillTerminate(_ notification: Notification) {
        globalCaptureShortcut?.unregister()
        globalPanelShortcut?.unregister()
        mcpBridge?.stop()
    }
}
