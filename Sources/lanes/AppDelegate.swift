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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var controller: PanelController!
    private var globalCaptureShortcut: GlobalCaptureShortcutController!
    private var container: ModelContainer!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        do { container = try ModelContainer(for: Lane.self, Thought.self) }
        catch { fatalError("Unable to create local store: \(error)") }
        controller = PanelController(container: container)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = LanesStatusIcon.make()
        statusItem.button?.toolTip = "lanes"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        controller.attach(to: statusItem.button)
        globalCaptureShortcut = GlobalCaptureShortcutController { [weak self] in
            self?.controller.show()
        }
        _ = globalCaptureShortcut.register()
        seedDefaultsIfNeeded()
    }

    @objc private func togglePanel() { controller.toggle() }

    private func seedDefaultsIfNeeded() {
        _ = try? LaneManagement.seedDefaultsIfNeeded(in: container.mainContext)
    }

    func applicationWillTerminate(_ notification: Notification) {
        globalCaptureShortcut?.unregister()
    }
}
