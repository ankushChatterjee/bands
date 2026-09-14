import AppKit
import SwiftUI
import SwiftData

final class LanesPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct PanelPositioning {
    static let horizontalInset: CGFloat = 8
    static let iconGap: CGFloat = 6

    static func origin(panelSize: CGSize, buttonFrame: CGRect, visibleFrame: CGRect) -> CGPoint {
        let bounds = visibleFrame.insetBy(dx: horizontalInset, dy: horizontalInset)
        let maxX = max(bounds.minX, bounds.maxX - panelSize.width)
        let maxY = max(bounds.minY, bounds.maxY - panelSize.height)
        let x = min(max(buttonFrame.midX - panelSize.width / 2, bounds.minX), maxX)
        let y = min(max(buttonFrame.minY - panelSize.height - iconGap, bounds.minY), maxY)
        return CGPoint(x: x, y: y)
    }
}

struct PanelInteraction {
    static func shouldDismissClick(window: NSWindow?, panel: NSWindow, statusButtonWindow: NSWindow?) -> Bool {
        window !== panel && window !== statusButtonWindow
    }

    @MainActor
    static func shouldDismissGlobalClick(at point: NSPoint, panel: NSWindow, statusButton: NSStatusBarButton?) -> Bool {
        guard let button = statusButton, let window = button.window else { return true }
        let buttonFrame = window.convertToScreen(button.frame)
        return !panel.frame.contains(point) && !buttonFrame.contains(point)
    }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private let modelContainer: ModelContainer
    private weak var statusButton: NSStatusBarButton?
    nonisolated(unsafe) private var localMonitor: Any?
    nonisolated(unsafe) private var globalMonitor: Any?

    init(container: ModelContainer) {
        self.modelContainer = container
        super.init()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self, let panel = self.panel, panel.isVisible else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                // Let SwiftUI's focused control receive Escape first. Inline editors
                // cancel themselves; the root view closes the panel when nothing is editing.
                return event
            }
            if (event.type == .leftMouseDown || event.type == .rightMouseDown),
               panel.attachedSheet == nil,
               NSApp.modalWindow == nil,
               PanelInteraction.shouldDismissClick(window: event.window, panel: panel, statusButtonWindow: self.statusButton?.window) {
                panel.orderOut(nil)
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel, panel.isVisible else { return }
            guard panel.attachedSheet == nil, NSApp.modalWindow == nil else { return }
            if PanelInteraction.shouldDismissGlobalClick(at: NSEvent.mouseLocation, panel: panel, statusButton: self.statusButton) {
                panel.orderOut(nil)
            }
        }
    }

    func attach(to button: NSStatusBarButton?) { statusButton = button }

    deinit {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
    }

    func toggle() {
        if let panel, panel.isVisible { panel.orderOut(nil); return }
        show()
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
        configureScrollViews(in: panel.contentView)
        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.configureScrollViews(in: panel.contentView)
        }
        NotificationCenter.default.post(name: .lanesPanelDidOpen, object: nil)
    }

    private func position(_ panel: NSPanel) {
        let screen = statusButton?.window?.screen ?? NSScreen.main
        guard let screen else { return }
        let buttonFrame: NSRect
        if let button = statusButton, let window = button.window {
            buttonFrame = window.convertToScreen(button.frame)
        } else {
            buttonFrame = NSRect(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY, width: 1, height: 1)
        }
        panel.setFrameOrigin(PanelPositioning.origin(panelSize: panel.frame.size,
                                                      buttonFrame: buttonFrame,
                                                      visibleFrame: screen.visibleFrame))
    }

    private func makePanel() -> NSPanel {
        let root = RootView().environmentObject(ThoughtAgingSettingsStore.shared).modelContainer(modelContainer)
        let hosting = NSHostingView(rootView: root)
        let panel = LanesPanel(contentRect: NSRect(x: 0, y: 0, width: 720, height: 330),
                               styleMask: [.borderless, .fullSizeContentView],
                               backing: .buffered, defer: false)
        panel.contentView = hosting
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.transient, .moveToActiveSpace]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Dragging inside the panel belongs to SwiftUI's thought/lane interactions;
        // the panel must not interpret those gestures as window movement.
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = true
        panel.delegate = self
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        return panel
    }

    private func configureScrollViews(in root: NSView?) {
        guard let root else { return }
        if let scrollView = root as? NSScrollView {
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
        }
        root.subviews.forEach { configureScrollViews(in: $0) }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { true }
}
