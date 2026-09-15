import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit

private struct PointingHandCursorModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.onHover { isHovering in
            if isHovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

private extension View {
    func pointingHandCursor() -> some View {
        modifier(PointingHandCursorModifier())
    }
}

/// The neutral system is the visual default. Colour is deliberately reserved for
/// status: a thought only becomes colourful when its age needs attention.
enum LanesTheme {
    static let softGray = Color(red: 0.898, green: 0.898, blue: 0.918) // #E5E5EA
    static let graphite = Color(red: 0.11, green: 0.11, blue: 0.12)

    static func panel(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.11, green: 0.11, blue: 0.12) : Color(red: 0.94, green: 0.94, blue: 0.96)
    }

    static func outline(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.14) : .black.opacity(0.12)
    }

    static func laneFill(_ scheme: ColorScheme) -> Color {
        scheme == .light ? graphite : softGray
    }

    static func laneText(_ scheme: ColorScheme) -> Color {
        scheme == .light ? .white : graphite
    }

    static func secondaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? softGray : Color(red: 0.35, green: 0.35, blue: 0.38)
    }

    static func controlFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.22, green: 0.22, blue: 0.24)
            : Color(red: 0.86, green: 0.86, blue: 0.89)
    }

    static func controlBorder(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.12)
    }

    static func chipFill(for age: ThoughtAge, scheme: ColorScheme) -> Color {
        switch age {
        case .fresh: return scheme == .dark ? Color.white.opacity(0.075) : Color.white.opacity(0.84)
        case .warm: return scheme == .dark ? Color(red: 0.23, green: 0.20, blue: 0.13) : Color(red: 1.0, green: 0.95, blue: 0.80)
        case .attention: return scheme == .dark ? Color(red: 0.28, green: 0.16, blue: 0.10) : Color(red: 1.0, green: 0.86, blue: 0.70)
        case .old: return scheme == .dark ? Color(red: 0.29, green: 0.10, blue: 0.11) : Color(red: 1.0, green: 0.79, blue: 0.79)
        }
    }

    static func chipBorder(for age: ThoughtAge, scheme: ColorScheme) -> Color {
        switch age {
        case .fresh: return scheme == .dark ? .white.opacity(0.16) : .black.opacity(0.12)
        case .warm: return Color(red: 0.76, green: 0.57, blue: 0.16).opacity(scheme == .dark ? 0.65 : 0.48)
        case .attention: return Color(red: 0.90, green: 0.39, blue: 0.08).opacity(scheme == .dark ? 0.70 : 0.52)
        case .old: return Color(red: 0.88, green: 0.23, blue: 0.25).opacity(scheme == .dark ? 0.72 : 0.56)
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 7
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 500
        let rows = layoutRows(in: width, subviews: subviews)
        return CGSize(width: width, height: rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * spacing)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = layoutRows(in: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                let centeredY = y + (row.height - item.size.height) / 2
                item.subview.place(at: CGPoint(x: x, y: centeredY), proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Item { let subview: LayoutSubview; let size: CGSize }
    private struct Row { var items: [Item] = []; var height: CGFloat = 0 }

    private func layoutRows(in width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for subview in subviews {
            let intrinsic = subview.sizeThatFits(.unspecified)
            let available = max(1, width - (rows[rows.count - 1].items.isEmpty ? 0 : rows[rows.count - 1].items.reduce(0) { $0 + $1.size.width + spacing }))
            let size = intrinsic.width > width
                ? subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
                : intrinsic
            if !rows[rows.count - 1].items.isEmpty && (size.width > available || rows[rows.count - 1].items.reduce(0) { $0 + $1.size.width + spacing } + size.width > width) {
                rows.append(Row())
            }
            rows[rows.count - 1].items.append(Item(subview: subview, size: size))
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows.filter { !$0.items.isEmpty }
    }
}

private struct ThoughtFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct LaneDropDelegate: DropDelegate {
    let updateLocation: (CGPoint) -> Void
    let performDrop: (NSItemProvider, CGPoint) -> Void
    @Binding var isTargeted: Bool
    @Binding var insertionIndex: Int?

    func dropEntered(info: DropInfo) {
        isTargeted = true
        updateLocation(info.location)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        isTargeted = true
        updateLocation(info.location)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
        insertionIndex = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        insertionIndex = nil
        guard let provider = info.itemProviders(for: [UTType.text.identifier, UTType.data.identifier]).first else { return false }
        performDrop(provider, info.location)
        return true
    }
}

private struct ThoughtInsertionIndicator: View {
    var body: some View {
        Capsule(style: .continuous)
            .fill(.primary.opacity(0.24))
            .frame(width: 1.5, height: 24)
            .padding(.horizontal, 1)
            .transition(.scale.combined(with: .opacity))
            .accessibilityHidden(true)
    }
}

private struct LaneInsertionIndicator: View {
    var body: some View {
        Capsule(style: .continuous)
            .fill(.primary.opacity(0.22))
            .frame(height: 2)
            .padding(.horizontal, 8)
            .accessibilityHidden(true)
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Lane.order) private var lanes: [Lane]
    @State private var newLane = ""
    @State private var addingLane = false
    @State private var selectedThoughtID: UUID?
    @State private var draggingLaneID: UUID?
    @State private var hoveringLaneBin = false
    @State private var lanePendingDeletion: Lane?
    @State private var showingSettings = false
    @FocusState private var focus: PanelFocus?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appearance") private var appearance = AppAppearance.system.rawValue

    enum PanelFocus: Hashable { case newLane, laneInput(UUID), laneRename(UUID), thought(UUID), thoughtEdit(UUID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if lanes.isEmpty {
                        EmptyLanesView(onCreate: beginNewLane)
                            .frame(maxWidth: .infinity, minHeight: 180)
                    } else {
                        ForEach(lanes) { lane in
                            LaneRow(lane: lane, lanes: lanes, selectedThoughtID: $selectedThoughtID, focus: $focus, draggingLaneID: $draggingLaneID, onDelete: deleteLane, onMoveLane: moveLane)
                                .transition(reduceMotion ? .identity : .move(edge: .top).combined(with: .opacity))
                            if lane.id != lanes.last?.id { Divider() }
                        }
                    }
                }
                .animation(reduceMotion ? nil : .snappy(duration: 0.28, extraBounce: 0.08), value: lanes.map(\.id))
                .padding(.horizontal, 14)
                .padding(.bottom, 52)
            }
            .padding(.top, 8)
        }
        .padding(6)
        .frame(minWidth: 650, idealWidth: 720, maxWidth: 780, minHeight: 190, idealHeight: 330, maxHeight: 500)
        .background(LanesPanelBackground())
        .overlay(alignment: .bottomTrailing) {
            floatingActions
                .padding(.trailing, 16)
                .padding(.bottom, 14)
        }
        .confirmationDialog(
            lanePendingDeletion.map { "Delete \($0.name)?" } ?? "Delete lane?",
            isPresented: Binding(
                get: { lanePendingDeletion != nil },
                set: { if !$0 { lanePendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Lane", role: .destructive) {
                if let lane = lanePendingDeletion { deleteLane(lane) }
                lanePendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { lanePendingDeletion = nil }
        } message: {
            Text("This permanently removes the lane and its active thoughts.")
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(ThoughtAgingSettingsStore.shared)
        }
            .onAppear {
                focus = nil
                AppAppearance.apply(appearance)
            }
            .onChange(of: appearance) { _, value in AppAppearance.apply(value) }
            .onReceive(NotificationCenter.default.publisher(for: .lanesPanelDidOpen)) { _ in focus = nil }
            .onExitCommand { NSApp.keyWindow?.orderOut(nil) }
            .onMoveCommand { direction in
                switch direction {
                case .down: moveSelection(.down)
                case .up: moveSelection(.up)
                default: break
                }
            }
    }

    private var floatingActions: some View {
        HStack(spacing: 6) {
            if addingLane {
                TextField("", text: $newLane,
                          prompt: Text("New lane name…").foregroundStyle(LanesTheme.secondaryText(colorScheme)))
                    .textFieldStyle(.plain)
                    .foregroundStyle(.primary)
                    .frame(width: 160)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(LanesTheme.controlFill(colorScheme), in: Capsule(style: .continuous))
                    .overlay(Capsule(style: .continuous).strokeBorder(LanesTheme.controlBorder(colorScheme)))
                    .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
                    .onSubmit { addLane() }.focused($focus, equals: .newLane)
                    .onExitCommand { cancelNewLane() }
                    .accessibilityLabel("New lane name")
                    .accessibilityHint("Press Return to create the lane, or Escape to cancel")
            } else if draggingLaneID == nil {
                Button { beginNewLane() } label: {
                    Text("+ lane")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(LanesTheme.laneFill(colorScheme), in: Capsule(style: .continuous))
                        .overlay(Capsule(style: .continuous).strokeBorder(LanesTheme.controlBorder(colorScheme)))
                        .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(LanesTheme.laneText(colorScheme))
                .pointingHandCursor()
                .accessibilityLabel("Create lane")
            } else {
                Image(systemName: "trash")
                    .font(.body.weight(.semibold))
                    .frame(width: 30, height: 30)
                    .foregroundStyle(hoveringLaneBin ? .white : .red)
                    .background(hoveringLaneBin ? Color.red : Color.red.opacity(0.12), in: Circle())
                    .overlay(Circle().strokeBorder(Color.red.opacity(hoveringLaneBin ? 0.9 : 0.28)))
                    .scaleEffect(hoveringLaneBin ? 1.08 : 1)
                    .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.72), value: hoveringLaneBin)
                    .onDrop(of: [UTType.text.identifier, UTType.data.identifier], isTargeted: $hoveringLaneBin) { providers, _ in
                        dropLaneOnBin(providers)
                    }
                    .accessibilityLabel("Delete lane")
                    .accessibilityHint("Drop the dragged lane here to delete it")
            }
            MCPControl()
            Button(action: openSettings) {
                Image(systemName: "gearshape")
                    .font(.body.weight(.medium))
                    .frame(width: 30, height: 30)
                    .background(LanesTheme.controlFill(colorScheme), in: Circle())
                    .overlay(Circle().strokeBorder(LanesTheme.controlBorder(colorScheme)))
                    .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .pointingHandCursor()
            .accessibilityLabel("Open Settings")
            .help("Settings")
        }
    }

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        showingSettings = true
    }
    private func beginNewLane() { newLane = ""; addingLane = true; focus = .newLane }
    private func cancelNewLane() { addingLane = false; newLane = ""; focus = nil }
    private func addLane() {
        guard case .valid(let name) = LaneManagement.validateName(newLane, existingNames: lanes.map(\.name)) else { return }
        let lane = Lane(name: name, order: 0)
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.28, extraBounce: 0.08)) {
            LaneManagement.insert(lane, into: lanes, atEnd: InsertionPreferences.lanesAtEnd)
            context.insert(lane)
            try? context.save()
        }
        cancelNewLane()
    }
    private func moveLanes(from source: IndexSet, to destination: Int) { _ = LaneManagement.reordered(lanes, moving: source, to: destination); try? context.save() }
    private func moveLane(_ lane: Lane, onto target: Lane) {
        guard lane.id != target.id,
              let sourceIndex = lanes.firstIndex(where: { $0.id == lane.id }),
              let targetIndex = lanes.firstIndex(where: { $0.id == target.id }) else { return }

        // A drop is interpreted as placing the dragged lane after the lane it lands on.
        // Array.move(toOffset:) uses the post-removal offset, so adjust when moving down.
        let destination = sourceIndex < targetIndex ? targetIndex + 1 : targetIndex
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.28, extraBounce: 0.08)) {
            _ = LaneManagement.reordered(lanes, moving: IndexSet(integer: sourceIndex), to: destination)
            try? context.save()
        }
    }
    private func moveSelection(_ direction: PanelMoveDirection) {
        let thoughts = lanes.flatMap { lane in laneThoughts(lane) }
        guard let next = PanelSelection.nextIndex(current: selectedThoughtID.flatMap { id in thoughts.firstIndex { $0.id == id } }, direction: direction, count: thoughts.count) else { return }
        selectedThoughtID = thoughts[next].id; focus = .thought(thoughts[next].id)
    }
    private func laneThoughts(_ lane: Lane) -> [Thought] {
        ((try? context.fetch(FetchDescriptor<Thought>())) ?? [])
            .filter { $0.lane?.id == lane.id && $0.completedAt == nil && $0.releasedAt == nil }
            .sorted { ($0.order ?? 0, $0.createdAt) > ($1.order ?? 0, $1.createdAt) }
    }
    private func completeSelected() { guard case .thought = focus, let id = selectedThoughtID, let thought = (try? context.fetch(FetchDescriptor<Thought>()))?.first(where: { $0.id == id }) else { return }; ThoughtManagement.complete(thought, now: .now); try? context.save(); selectedThoughtID = nil; focus = nil }
    private func deleteLane(_ lane: Lane) { let thoughts = (try? context.fetch(FetchDescriptor<Thought>())) ?? []; thoughts.filter { $0.lane?.id == lane.id }.forEach(context.delete); context.delete(lane); try? context.save() }
    private func dropLaneOnBin(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let raw = object as? String, let id = UUID(uuidString: raw) else { return }
            DispatchQueue.main.async {
                guard let lane = lanes.first(where: { $0.id == id }) else { return }
                lanePendingDeletion = lane
                draggingLaneID = nil
                hoveringLaneBin = false
            }
        }
        return true
    }
}

private enum MCPSettings {
    static let enabledKey = "mcpEnabled"
}

/// The MCP switch lives on the panel so its availability is visible without
/// opening Settings. The connection itself is owned by the app layer; this
/// view only persists and communicates the user's preference.
private struct MCPControl: View {
    @AppStorage(MCPSettings.enabledKey) private var enabled = true
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button { enabled.toggle() } label: {
            Text("MCP")
                .font(.caption.weight(enabled ? .bold : .regular))
                .opacity(enabled ? 0.9 : 0.35)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(LanesTheme.controlFill(colorScheme), in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(LanesTheme.controlBorder(colorScheme)))
        .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
        .contentShape(Rectangle())
        .pointingHandCursor()
        .accessibilityLabel("MCP connection")
        .accessibilityValue(enabled ? "On" : "Off")
        .accessibilityHint("Toggle MCP access to your lanes and thoughts")
        .onAppear {
            UserDefaults.standard.register(defaults: [MCPSettings.enabledKey: true])
        }
    }
}

struct EmptyLanesView: View {
    let onCreate: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up")
                .font(.title2).foregroundStyle(.tertiary).accessibilityHidden(true)
            Text("No lanes yet").font(.headline)
            Text("Create a lane to give your thoughts a place to land.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Create lane", action: onCreate)
                .buttonStyle(.bordered)
                .pointingHandCursor()
        }.frame(maxWidth: 300).accessibilityElement(children: .combine)
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self { case .system: "System"; case .light: "Light"; case .dark: "Dark" }
    }
    var colorScheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }

    @MainActor
    static func apply(_ rawValue: String) {
        switch AppAppearance(rawValue: rawValue) ?? .system {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

struct LanesPanelBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(LanesTheme.panel(colorScheme))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(LanesTheme.outline(colorScheme), lineWidth: 1)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.42 : 0.16), radius: 24, y: 12)
    }
}

struct SettingsView: View {
    @AppStorage("appearance") private var appearance = AppAppearance.system.rawValue
    @AppStorage(InsertionPreferences.thoughtsAtEndKey) private var thoughtsAtEnd = false
    @AppStorage(InsertionPreferences.lanesAtEndKey) private var lanesAtEnd = false
    @EnvironmentObject private var agingStore: ThoughtAgingSettingsStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var initialAppearance = AppAppearance.system.rawValue
    @State private var fresh = ThoughtAgingSettings.defaults.freshMinutes
    @State private var warm = ThoughtAgingSettings.defaults.warmMinutes
    @State private var attention = ThoughtAgingSettings.defaults.attentionMinutes
    @State private var old = ThoughtAgingSettings.defaults.oldMinutes

    private var draft: ThoughtAgingSettings { ThoughtAgingSettings(freshMinutes: fresh, warmMinutes: warm, attentionMinutes: attention, oldMinutes: old) }
    private var validationMessage: String? {
        guard draft.freshMinutes >= 15 else { return "Fresh must be at least 15 minutes." }
        guard draft.freshMinutes < draft.warmMinutes else { return "Fresh must be less than Warm." }
        guard draft.warmMinutes < draft.attentionMinutes else { return "Warm must be less than Attention." }
        guard draft.attentionMinutes < draft.oldMinutes else { return "Attention must be less than Old." }
        return nil
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
            SettingsSection(title: "Appearance") {
                LabeledContent("Theme") {
                    Picker("Theme", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 254)
                }
                Text("System follows your Mac’s appearance automatically.")
                    .font(.caption)
                    .foregroundStyle(LanesTheme.secondaryText(colorScheme))
                    .padding(.top, 5)
            }
            Divider()
            SettingsSection(title: "New items") {
                HStack {
                    Text("New thoughts")
                    Spacer()
                    Picker("Thought placement", selection: $thoughtsAtEnd) {
                        Text("Start").tag(false)
                        Text("End").tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 138)
                }
                .padding(.vertical, 4)
                Divider()
                HStack {
                    Text("New lanes")
                    Spacer()
                    Picker("Lane placement", selection: $lanesAtEnd) {
                        Text("Top").tag(false)
                        Text("Bottom").tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 138)
                }
                .padding(.vertical, 4)
            }
            Divider()
            SettingsSection(title: "Keyboard shortcuts") {
                ShortcutRow(title: "Capture a thought", shortcut: "⌘N")
                Divider()
                ShortcutRow(title: "New lane", shortcut: "⇧⌘N")
                Divider()
                ShortcutRow(title: "Complete selected thought", shortcut: "⌘↩")
            }
            Divider()
            SettingsSection(title: "Thought aging") {
                Text("Set when a thought begins to draw attention.")
                    .font(.caption)
                    .foregroundStyle(LanesTheme.secondaryText(colorScheme))
                    .padding(.bottom, 6)
                ThresholdStepper(title: "Fresh", minutes: $fresh)
                Divider()
                ThresholdStepper(title: "Warm", minutes: $warm)
                Divider()
                ThresholdStepper(title: "Attention", minutes: $attention)
                Divider()
                ThresholdStepper(title: "Old", minutes: $old)
                if let validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.red)
                        .padding(.top, 7)
                }
                HStack {
                    Button("Restore Defaults") { setDraft(.defaults) }
                        .pointingHandCursor()
                    Spacer()
                    Button("Cancel", role: .cancel) {
                        appearance = initialAppearance
                        AppAppearance.apply(initialAppearance)
                        dismiss()
                    }
                    .pointingHandCursor()
                    Button("Apply") {
                        agingStore.update(draft)
                        dismiss()
                    }
                        .disabled(validationMessage != nil)
                        .keyboardShortcut(.defaultAction)
                        .pointingHandCursor()
                }
                .padding(.top, 8)
            }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ThinScrollbarConfigurator())
        }
        .scrollIndicators(.visible)
        .frame(width: 460, height: 458, alignment: .topLeading)
        .background(LanesTheme.panel(colorScheme))
        .onAppear {
            initialAppearance = appearance
            setDraft(agingStore.settings)
            AppAppearance.apply(appearance)
        }
        .onChange(of: appearance) { _, value in AppAppearance.apply(value) }
    }

    private func setDraft(_ settings: ThoughtAgingSettings) {
        fresh = settings.freshMinutes; warm = settings.warmMinutes
        attention = settings.attentionMinutes; old = settings.oldMinutes
    }
}

private struct ThinScrollbarConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            var ancestor: NSView? = view
            while let current = ancestor {
                if let scrollView = current as? NSScrollView {
                    scrollView.hasVerticalScroller = true
                    scrollView.autohidesScrollers = true
                    scrollView.scrollerStyle = .overlay
                    scrollView.verticalScroller?.controlSize = .small
                    return
                }
                ancestor = current.superview
            }
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 0) { content }
        }
    }
}

private struct ShortcutRow: View {
    let title: String
    let shortcut: String
    var body: some View {
        HStack { Text(title); Spacer(); Text(shortcut).font(.body.monospacedDigit()).foregroundStyle(.secondary) }
            .padding(.vertical, 5)
    }
}

private struct ThresholdStepper: View {
    let title: String
    @Binding var minutes: Int
    var body: some View {
        Stepper(value: $minutes, in: 15...525_600, step: 15) {
            HStack {
                Text(title)
                Spacer()
                Text(Self.format(minutes))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 48, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
    }

    private static func format(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours == 0 { return "\(remainingMinutes)m" }
        if remainingMinutes == 0 { return "\(hours)h" }
        return "\(hours)h \(remainingMinutes)m"
    }
}

extension Notification.Name {
    static let lanesPanelDidOpen = Notification.Name("lanes.panelDidOpen")
}

struct LaneRow: View {
    private static let laneNameFont = Font.subheadline.weight(.semibold)
    private static let lanePillHorizontalPadding: CGFloat = 11
    private static let lanePillVerticalPadding: CGFloat = 8
    private static let lanePillCornerRadius: CGFloat = 9

    @Environment(\.modelContext) private var context
    @Bindable var lane: Lane
    @Query(sort: [SortDescriptor(\Thought.order, order: .reverse), SortDescriptor(\Thought.createdAt, order: .reverse)]) private var allThoughts: [Thought]
    let lanes: [Lane]
    @Binding var selectedThoughtID: UUID?
    @FocusState.Binding var focus: RootView.PanelFocus?
    @Binding var draggingLaneID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(InsertionPreferences.thoughtsAtEndKey) private var thoughtsAtEnd = false
    let onDelete: (Lane) -> Void
    let onMoveLane: (Lane, Lane) -> Void
    @State private var adding = false; @State private var input = ""; @State private var editing = false; @State private var name = ""; @State private var showingDeleteConfirmation = false; @State private var hoveringAdd = false; @State private var hoveringLane = false; @State private var dropTargeted = false; @State private var thoughtFrames: [UUID: CGRect] = [:]
    @State private var insertionIndex: Int?
    @State private var laneDropAfter = false
    var thoughts: [Thought] {
        allThoughts
            .filter { $0.lane?.id == lane.id && $0.completedAt == nil && $0.releasedAt == nil }
            .sorted { ($0.order ?? 0, $0.createdAt) > ($1.order ?? 0, $1.createdAt) }
    }
    var body: some View {
        FlowLayout {
            HStack(spacing: 0) {
                if editing {
                    TextField("Lane name", text: $name)
                        .textFieldStyle(.plain)
                        .focused($focus, equals: .laneRename(lane.id))
                        .onSubmit { saveName() }
                        .onExitCommand { cancelRename() }
                        .accessibilityLabel("Rename lane \(lane.name)")
                        .accessibilityHint("Press Return to save, or Escape to cancel")
                } else {
                    Text(lane.name)
                        .onTapGesture(count: 2) { beginRename() }
                }
            }
            .font(Self.laneNameFont)
            .foregroundStyle(LanesTheme.laneText(colorScheme))
            .padding(.horizontal, Self.lanePillHorizontalPadding)
            .padding(.vertical, Self.lanePillVerticalPadding)
            .background(LanesTheme.laneFill(colorScheme), in: RoundedRectangle(cornerRadius: Self.lanePillCornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Self.lanePillCornerRadius, style: .continuous).strokeBorder(.black.opacity(0.10)))
            .onHover { hoveringLane = $0 }
            .pointingHandCursor()
            .rotationEffect(.degrees(hoveringLane && !editing ? -2 : 0), anchor: .center)
            .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.58), value: hoveringLane)
            // Keep the lane drag source on the name pill only. The row below is
            // intentionally the full-width drop zone for both lane and thought drops.
            .onDrag {
                draggingLaneID = lane.id
                return NSItemProvider(object: lane.id.uuidString as NSString)
            } preview: {
                LaneDragPreview(name: lane.name)
            }
            .focusEffectDisabled()
            .accessibilityLabel("Lane \(lane.name)")
            .accessibilityHint("Double-click or use the context menu to rename")
            if !thoughtsAtEnd { thoughtAdditionControl }
            ForEach(Array(thoughts.enumerated()), id: \.element.id) { index, thought in
                if dropTargeted && insertionIndex == index {
                    ThoughtInsertionIndicator()
                }
                ThoughtChip(thought: thought, laneID: lane.id, selectedThoughtID: $selectedThoughtID, focus: $focus)
            }
            if dropTargeted && insertionIndex == thoughts.count {
                ThoughtInsertionIndicator()
            }
            if thoughtsAtEnd { thoughtAdditionControl }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, dropTargeted ? 5 : 0)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(dropTargeted && draggingLaneID == nil ? 0.055 : 0))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(dropTargeted && draggingLaneID == nil ? 0.18 : 0), lineWidth: 1)
                }
        }
        .overlay {
            if dropTargeted && draggingLaneID != nil {
                VStack(spacing: 0) {
                    if !laneDropAfter { LaneInsertionIndicator() }
                    Spacer(minLength: 0)
                    if laneDropAfter { LaneInsertionIndicator() }
                }
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.76), value: dropTargeted)
        .contentShape(Rectangle())
        .coordinateSpace(name: lane.id.uuidString)
        .onPreferenceChange(ThoughtFramePreferenceKey.self) { thoughtFrames = $0 }
        .onDrop(of: [UTType.text.identifier, UTType.data.identifier], delegate: LaneDropDelegate(
            updateLocation: { location in
                if draggingLaneID == nil {
                    insertionIndex = insertionIndex(at: location, in: thoughts)
                } else {
                    laneDropAfter = location.y > 42
                    insertionIndex = nil
                }
            },
            performDrop: { provider, location in
                provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let raw = object as? String else { return }
                    DispatchQueue.main.async {
                        _ = handleDrop(raw: raw, at: location)
                        insertionIndex = nil
                        draggingLaneID = nil
                    }
                }
            },
            isTargeted: $dropTargeted,
            insertionIndex: $insertionIndex
        ))
        .contextMenu { Button("Rename") { beginRename() }; Button("Add Thought") { adding = true; focus = .laneInput(lane.id) }; Divider(); Button("Delete Lane", role: .destructive, action: requestDeletion) }
        .confirmationDialog("Delete \"\(lane.name)\"?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) { Button("Delete Lane", role: .destructive) { onDelete(lane) }; Button("Cancel", role: .cancel) {} } message: { Text("This will delete its \(thoughts.count) active thought\(thoughts.count == 1 ? "" : "s").") } }
    private func beginRename() { name = lane.name; editing = true; focus = .laneRename(lane.id) }
    private func requestDeletion() {
        if thoughts.isEmpty {
            onDelete(lane)
        } else {
            showingDeleteConfirmation = true
        }
    }
    private func cancelRename() { editing = false; name = ""; focus = nil }
    private func saveName() { guard case .valid(let value) = LaneManagement.validateName(name, existingNames: lanes.map(\.name), excluding: lane.name) else { return }; lane.name = value; try? context.save(); cancelRename() }
    private func cancelAdd() { adding = false; input = ""; focus = nil }
    @ViewBuilder private var thoughtAdditionControl: some View {
        if adding {
            ThoughtBubble {
                HStack(spacing: 6) {
                    TextField("", text: $input,
                              prompt: Text("Add thought").foregroundStyle(LanesTheme.secondaryText(colorScheme)))
                        .textFieldStyle(.plain)
                        .frame(minWidth: 112)
                        .focused($focus, equals: .laneInput(lane.id))
                        .onSubmit { addThought() }
                        .onExitCommand { cancelAdd() }
                        .accessibilityLabel("New thought in \(lane.name)")
                        .accessibilityHint("Press Return to save, or Escape to cancel")
                    Image(systemName: "return")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
        } else {
            Button {
                adding = true
                focus = .laneInput(lane.id)
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.medium))
                    .frame(width: 22, height: 22)
                    .offset(y: 1)
                    .background(hoveringAdd ? Color.primary.opacity(0.12) : .clear, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(hoveringAdd ? .primary : LanesTheme.secondaryText(colorScheme))
            .onHover { hoveringAdd = $0 }
            .animation(.easeOut(duration: 0.14), value: hoveringAdd)
            .pointingHandCursor()
            .accessibilityLabel("Add thought to \(lane.name)")
        }
    }
    private func addThought() {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let orders = thoughts.compactMap(\.order)
        let order = InsertionPreferences.thoughtsAtEnd
            ? (orders.min() ?? 0) - 1
            : (orders.max() ?? 0) + 1
        context.insert(Thought(text: value, lane: lane, order: order))
        try? context.save()
        cancelAdd()
    }
    private func handleDrop(raw: String, at location: CGPoint) -> Bool {
        guard let sourceID = UUID(uuidString: raw) else { return false }
        if let source = lanes.first(where: { $0.id == sourceID }) {
            guard source.id != lane.id else { return false }
            onMoveLane(source, lane)
            return true
        }
        guard let allThoughts = try? context.fetch(FetchDescriptor<Thought>()),
              let thought = allThoughts.first(where: { $0.id == sourceID }),
              thought.completedAt == nil, thought.releasedAt == nil else { return false }
        let destinationThoughts = thoughts
        var destination = insertionIndex(at: location, in: destinationThoughts)
        if let sourceIndex = destinationThoughts.firstIndex(where: { $0.id == thought.id }), sourceIndex < destination {
            destination -= 1
        }
        ThoughtManagement.reorder(thought, to: lane, among: destinationThoughts, at: destination, now: .now)
        try? context.save()
        return true
    }
    private func insertionIndex(at location: CGPoint, in thoughts: [Thought]) -> Int {
        for (index, thought) in thoughts.enumerated() {
            guard let frame = thoughtFrames[thought.id] else { continue }
            if location.y < frame.midY || (abs(location.y - frame.midY) < frame.height / 2 && location.x < frame.midX) {
                return index
            }
        }
        return thoughts.count
    }
}

private struct LaneDragPreview: View {
    @Environment(\.colorScheme) private var colorScheme
    let name: String
    var body: some View {
        Text(name)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(LanesTheme.laneText(colorScheme))
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(LanesTheme.laneFill(colorScheme), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(LanesTheme.outline(colorScheme)))
            .opacity(0.34)
    }
}

private struct ThoughtBubble<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let age: ThoughtAge
    let content: Content

    init(age: ThoughtAge = .fresh, @ViewBuilder content: () -> Content) {
        self.age = age
        self.content = content()
    }

    var body: some View {
        content
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(LanesTheme.chipFill(for: age, scheme: colorScheme), in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).strokeBorder(LanesTheme.chipBorder(for: age, scheme: colorScheme), lineWidth: age == .fresh ? 0.7 : 0.9))
    }
}

struct ThoughtChip: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var agingStore: ThoughtAgingSettingsStore
    @Bindable var thought: Thought
    let laneID: UUID
    @Binding var selectedThoughtID: UUID?
    @FocusState.Binding var focus: RootView.PanelFocus?
    @State private var editing = false; @State private var draft = ""; @State private var hovering = false
    var age: ThoughtAge { ThoughtAging.age(for: thought, settings: agingStore.settings) }
    var timestamp: String { ThoughtTimestamp.label(since: thought.createdAt) }
    var body: some View {
        Group {
            if editing {
                TextField("Thought", text: $draft).textFieldStyle(.roundedBorder).frame(maxWidth: 360)
                    .focused($focus, equals: .thoughtEdit(thought.id)).onSubmit { save() }.onExitCommand { cancelEdit() }
                    .accessibilityLabel("Edit thought \(thought.text)").accessibilityHint("Press Return to save, or Escape to cancel")
            } else {
                ThoughtBubble(age: age) {
                    HStack(spacing: 6) {
                        Text(thought.text).lineLimit(3).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        Text(timestamp).font(.caption2.monospacedDigit()).foregroundStyle(LanesTheme.secondaryText(colorScheme))
                    }
                }
                .overlay(alignment: .trailing) {
                    if hovering {
                        Button(action: complete) { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
                            .buttonStyle(.plain)
                            .foregroundStyle(.primary)
                            .frame(width: 18, height: 18)
                            .background(.regularMaterial, in: Circle())
                            .overlay(Circle().strokeBorder(.primary.opacity(0.12)))
                            .offset(x: 8)
                            .pointingHandCursor()
                            .accessibilityLabel("Complete thought")
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: 360, alignment: .leading).onHover { hovering = $0 }
                .pointingHandCursor()
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovering)
                .onTapGesture { selectedThoughtID = thought.id; focus = .thought(thought.id) }
                .draggable(thought.id.uuidString) {
                    ThoughtDragPreview(text: thought.text, timestamp: timestamp, age: age)
                }
                .focusable()
                .focusEffectDisabled()
                .focused($focus, equals: .thought(thought.id))
                .onKeyPress(.return) { beginEdit(); return .handled }
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: ThoughtFramePreferenceKey.self,
                                       value: [thought.id: proxy.frame(in: .named(laneID.uuidString))])
            }
        }
        .contextMenu { Button("Complete") { complete() }; Button("Edit") { beginEdit() }; Menu("Move to…") { ForEach(fetchLanes()) { lane in Button(lane.name) { move(to: lane) } } }; Divider(); Button("Let Go") { letGo() } }.accessibilityElement(children: .ignore).accessibilityLabel("\(thought.text)").accessibilityValue("Added \(timestamp) ago. \(age == .fresh ? "Fresh" : "Aging: \(ageLabel)")").accessibilityHint("Press Return to edit, or Command-Return to complete").accessibilityAction(named: "Edit") { beginEdit() }.accessibilityAction(named: "Complete") { complete() }
    }
    private var ageLabel: String { ThoughtAging.label(for: thought, settings: agingStore.settings).map { "\($0) old" } ?? "fresh" }
    private func beginEdit() { selectedThoughtID = thought.id; draft = thought.text; editing = true; focus = .thoughtEdit(thought.id) }
    private func cancelEdit() { editing = false; draft = ""; focus = .thought(thought.id) }
    private func complete() { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { ThoughtManagement.complete(thought, now: .now); try? context.save() }; selectedThoughtID = nil; focus = nil }
    private func letGo() { ThoughtManagement.letGo(thought, now: .now); try? context.save(); selectedThoughtID = nil; focus = nil }
    private func move(to lane: Lane) { guard ThoughtManagement.move(thought, to: lane, now: .now) else { return }; try? context.save(); selectedThoughtID = thought.id; focus = .thought(thought.id) }
    private func save() { guard ThoughtManagement.edit(thought, rawText: draft, now: .now) else { return }; try? context.save(); editing = false; focus = .thought(thought.id) }
    private func fetchLanes() -> [Lane] { (try? context.fetch(FetchDescriptor<Lane>(sortBy: [SortDescriptor(\Lane.order)]))) ?? [] }
}

private struct ThoughtDragPreview: View {
    @Environment(\.colorScheme) private var colorScheme
    let text: String
    let timestamp: String
    let age: ThoughtAge
    var body: some View {
        HStack(spacing: 6) {
            Text(text).lineLimit(3).multilineTextAlignment(.leading)
            Text(timestamp).font(.caption2.monospacedDigit()).foregroundStyle(LanesTheme.secondaryText(colorScheme))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(LanesTheme.chipFill(for: age, scheme: colorScheme), in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(LanesTheme.chipBorder(for: age, scheme: colorScheme), lineWidth: 0.9))
        .frame(maxWidth: 360, alignment: .leading)
        .opacity(0.34)
    }
}
