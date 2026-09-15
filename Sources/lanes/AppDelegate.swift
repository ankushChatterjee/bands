import AppKit
import SwiftData

private enum LanesStatusIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        defer { image.unlockFocus() }

        let path = NSBezierPath()
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        NSColor.black.setStroke()

        // The outer rails are continuous; the center rail is dashed to suggest
        // lanes and movement between them.
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

private enum LanesStatusMenu {
    static func make(target: AnyObject) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit lanes", action: #selector(AppDelegate.quit), keyEquivalent: "q")
        menu.items[0].target = target
        return menu
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var controller: PanelController!
    private var globalCaptureShortcut: GlobalCaptureShortcutController!
    private var container: ModelContainer!
    private var mcpBridge: LanesMCPBridge!
    private var notificationCoordinator: LanesNotificationCoordinator!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        do { container = try ModelContainer(for: Lane.self, Thought.self) }
        catch { fatalError("Unable to create local store: \(error)") }
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "mcpEnabled") == nil { defaults.set(true, forKey: "mcpEnabled") }
        if defaults.bool(forKey: "mcpEnabled") {
            mcpBridge = LanesMCPBridge(service: LanesCommandService(container: container))
            mcpBridge.start()
        }
        controller = PanelController(container: container)
        notificationCoordinator = LanesNotificationCoordinator(container: container)
        notificationCoordinator.start()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = LanesStatusIcon.make()
            button.toolTip = "lanes"
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            controller.attach(to: button)
        }
        globalCaptureShortcut = GlobalCaptureShortcutController { [weak self] in
            self?.controller.show()
        }
        _ = globalCaptureShortcut.register()
    }

    @objc private func statusItemClicked() {
        guard let button = statusItem.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            LanesStatusMenu.make(target: self).popUp(positioning: nil,
                                                      at: NSPoint(x: button.bounds.midX, y: button.bounds.minY),
                                                      in: button)
        } else {
            controller.toggle()
        }
    }

    @objc fileprivate func quit() { NSApp.terminate(self) }

    func applicationWillTerminate(_ notification: Notification) {
        globalCaptureShortcut?.unregister()
        mcpBridge?.stop()
    }
}
