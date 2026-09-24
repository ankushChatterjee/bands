import SwiftUI
import Combine
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

private enum ThoughtClipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// The neutral system is the visual default. Colour is deliberately reserved for
/// status: a thought only becomes colourful when its age needs attention.
enum BandsTheme {
    static let softGray = Color(red: 0.898, green: 0.898, blue: 0.918) // #E5E5EA
    static let graphite = Color(red: 0.11, green: 0.11, blue: 0.12)

    static func panel(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.11, green: 0.11, blue: 0.12) : Color(red: 0.94, green: 0.94, blue: 0.96)
    }

    static func outline(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.14) : .black.opacity(0.12)
    }

    static func bandFill(_ scheme: ColorScheme) -> Color {
        scheme == .light ? graphite : softGray
    }

    static func bandText(_ scheme: ColorScheme) -> Color {
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

    static func keyboardFocus(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? softGray : graphite
    }

    /// Age uses one semantic accent per state in every appearance. The fill
    /// opacity changes with the background, but the hue does not.
    static func chipAccent(for age: ThoughtAge) -> Color {
        switch age {
        case .fresh: return .clear
        case .warm: return Color(red: 0.76, green: 0.57, blue: 0.16)
        case .attention: return Color(red: 0.90, green: 0.39, blue: 0.08)
        case .old: return Color(red: 0.88, green: 0.23, blue: 0.25)
        }
    }

    static func chipFill(for age: ThoughtAge, scheme: ColorScheme) -> Color {
        if age == .fresh {
            return scheme == .dark ? Color.white.opacity(0.075) : Color.white.opacity(0.84)
        }
        return chipAccent(for: age).opacity(scheme == .dark ? 0.22 : 0.14)
    }

    static func chipBorder(for age: ThoughtAge, scheme: ColorScheme) -> Color {
        if age == .fresh {
            return scheme == .dark ? .white.opacity(0.16) : .black.opacity(0.12)
        }
        return chipAccent(for: age).opacity(scheme == .dark ? 0.72 : 0.56)
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

private struct BandDropDelegate: DropDelegate {
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

private struct BandInsertionIndicator: View {
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
    @Query(sort: \Band.order) private var bands: [Band]
    @State private var newBand = ""
    @State private var newBandDescription = ""
    @State private var addingBand = false
    @State private var enteringBandDescription = false
    @State private var composingBandID: UUID?
    @State private var selection = PanelSelection()
    @State private var draggingBandID: UUID?
    @State private var hoveringBandBin = false
    @State private var bandPendingDeletion: Band?
    @State private var showingSettings = false
    @State private var showingQuickCapture = false
    @State private var quickCaptureText = ""
    @State private var quickCaptureBusy = false
    @State private var quickCaptureNeedsBand = false
    @State private var quickCaptureMessage: String?
    @State private var thoughtPendingRelease: Thought?
    @State private var thoughtPendingMove: Thought?
    @FocusState private var focus: PanelFocus?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appearance") private var appearance = AppAppearance.system.rawValue
    @AppStorage(InsertionPreferences.thoughtsAtEndKey) private var thoughtsAtEnd = false
    @State private var timestampRefreshDate = Date.now
    private let timestampRefreshTimer = Timer.publish(every: 5 * 60, on: .main, in: .common).autoconnect()

    enum PanelFocus: Hashable {
        case newBand, newBandDescription, quickCapture, band(UUID), bandAdd(UUID), bandInput(UUID), bandRename(UUID), bandDescription(UUID), thought(UUID), thoughtEdit(UUID)
        var isEditing: Bool {
            switch self {
            case .newBand, .newBandDescription, .quickCapture, .bandInput, .bandRename, .bandDescription, .thoughtEdit: true
            default: false
            }
        }
    }

    private var boardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            bandsList
        }
        .padding(6)
        .frame(minWidth: 650, idealWidth: 720, maxWidth: 780, minHeight: 190, idealHeight: 330, maxHeight: 500)
        .background(BandsPanelBackground())
        .overlay(alignment: .bottomTrailing) {
            floatingActions
                .padding(.trailing, 16)
                .padding(.bottom, 14)
        }
    }

    private var boardWithSheets: some View {
        boardContent
        .confirmationDialog(
            bandPendingDeletion.map { "Delete \($0.name)?" } ?? "Delete band?",
            isPresented: Binding(
                get: { bandPendingDeletion != nil },
                set: { if !$0 { bandPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Band", role: .destructive) {
                if let band = bandPendingDeletion { deleteBand(band) }
                bandPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { bandPendingDeletion = nil }
        } message: {
            Text("This permanently removes the band and its active thoughts.")
        }
        .confirmationDialog(
            thoughtPendingRelease.map { "Release \($0.text)?" } ?? "Release thought?",
            isPresented: Binding(get: { thoughtPendingRelease != nil }, set: { if !$0 { thoughtPendingRelease = nil } })
        ) {
            Button("Release Thought", role: .destructive) {
                if let thought = thoughtPendingRelease { release(thought) }
                thoughtPendingRelease = nil
            }
            Button("Cancel", role: .cancel) { thoughtPendingRelease = nil }
        } message: {
            Text("Released thoughts are removed from active bands.")
        }
        .sheet(item: $thoughtPendingMove, onDismiss: restoreSelection) { thought in
            MoveThoughtSheet(thought: thought, bands: bands) { band in move(thought, to: band) }
        }
        .sheet(isPresented: $showingSettings, onDismiss: restoreSelection) {
            SettingsView()
                .environmentObject(ThoughtAgingSettingsStore.shared)
        }
    }

    var body: some View {
        observedBoard
            .onAppear {
                focus = nil
                AppAppearance.apply(appearance)
                timestampRefreshDate = .now
                updateCommands()
            }
            .onChange(of: appearance) { _, value in AppAppearance.apply(value) }
            .onReceive(NotificationCenter.default.publisher(for: .bandsPanelDidOpen)) { _ in
                if case .bandInput(let id) = focus {
                    composingBandID = nil
                    selection.select(.band(id), with: .keyboard)
                    focus = .band(id)
                } else if focus?.isEditing != true {
                    composingBandID = nil
                    restoreSelection()
                }
                timestampRefreshDate = .now
            }
            .onReceive(NotificationCenter.default.publisher(for: BandsCommandDispatcher.notification)) { notification in
                guard let command = notification.object as? PanelCommand else { return }
                perform(command)
            }
            .onReceive(timestampRefreshTimer) { timestampRefreshDate = $0 }
            .onExitCommand { NSApp.keyWindow?.orderOut(nil) }
    }

    private var observedBoard: some View {
        boardWithSheets
            .onChange(of: selection) { _, _ in updateCommands() }
            .onChange(of: showingSettings) { _, visible in
                updateCommands()
                if !visible { restoreSelection() }
            }
            .onChange(of: showingQuickCapture) { _, _ in updateCommands() }
            .onChange(of: thoughtPendingMove?.id) { _, id in
                updateCommands()
                if id == nil { restoreSelection() }
            }
            .onChange(of: thoughtPendingRelease?.id) { _, id in
                updateCommands()
                if id == nil { restoreSelection() }
            }
            .onChange(of: bandPendingDeletion?.id) { _, id in
                updateCommands()
                if id == nil { restoreSelection() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .bandsKeyRequest)) { notification in
                if let request = notification.object as? PanelKeyRequest { handleKey(request) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .bandsPointerInput)) { _ in
                selection.modality = .pointer
            }
            .onChange(of: focus) { _, focus in
                updateCommands()
                switch focus {
                case .band(let id):
                    if selection.target != .band(id) { selection.select(.band(id), with: .keyboard) }
                case .thought(let id):
                    if selection.target != .thought(id) { selection.select(.thought(id), with: .keyboard) }
                case .bandAdd(let id):
                    if selection.target != .addThought(id) { selection.select(.addThought(id), with: .keyboard) }
                case .bandInput(let id), .bandRename(let id):
                    if selection.target != .band(id) { selection.select(.band(id), with: .keyboard) }
                case .bandDescription(let id):
                    if selection.target != .band(id) { selection.select(.band(id), with: .keyboard) }
                default: break
                }
            }
    }

    private var bandsList: some View {
        ScrollViewReader { proxy in
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if bands.isEmpty {
                    EmptyBandsView(onCreate: beginNewBand)
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    ForEach(bands) { band in
                        BandRow(band: band, bands: bands, now: timestampRefreshDate, selection: $selection, focus: $focus, composingBandID: $composingBandID, draggingBandID: $draggingBandID, onDelete: deleteBand, onMoveBand: moveBand)
                            .id(PanelSelection.Target.band(band.id))
                            .transition(reduceMotion ? .identity : .move(edge: .top).combined(with: .opacity))
                        if band.id != bands.last?.id { Divider() }
                    }
                }
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.28, extraBounce: 0.08), value: bands.map(\.id))
            .padding(.horizontal, 14)
            .padding(.bottom, 52)
        }
        .padding(.top, 8)
        .onChange(of: selection.target) { _, target in
            guard selection.modality == .keyboard, let target else { return }
            scrollToKeyboardTarget(target, using: proxy)
        }
        .onChange(of: focus) { _, value in
            if case .bandInput(let id) = value {
                scrollToKeyboardTarget(.band(id), using: proxy)
            }
        }
        }
    }

    private func scrollToKeyboardTarget(_ target: PanelSelection.Target, using proxy: ScrollViewProxy) {
        // Selection changes and layout changes are delivered in separate SwiftUI
        // passes. Defer until the selected chip has been placed, then keep it
        // comfortably inside the viewport instead of pinning it to an edge.
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.22)) {
                switch target {
                case .addThought(let id):
                    proxy.scrollTo(PanelSelection.Target.band(id), anchor: .center)
                case .band, .thought:
                    proxy.scrollTo(target, anchor: .center)
                }
            }
        }
    }

    private var floatingActions: some View {
        HStack(spacing: 6) {
            if showingQuickCapture {
                QuickCaptureBubble(
                    text: $quickCaptureText,
                    isBusy: $quickCaptureBusy,
                    needsBand: $quickCaptureNeedsBand,
                    message: $quickCaptureMessage,
                    bands: bands,
                    onSubmit: submitQuickCapture,
                    onChooseBand: chooseQuickCaptureBand,
                    onCancel: cancelQuickCapture
                )
            } else if addingBand && !enteringBandDescription {
                TextField("", text: $newBand,
                          prompt: Text("New band name…").foregroundStyle(BandsTheme.secondaryText(colorScheme)))
                    .textFieldStyle(.plain)
                    .foregroundStyle(.primary)
                    .frame(width: 160)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(BandsTheme.controlFill(colorScheme), in: Capsule(style: .continuous))
                    .overlay(Capsule(style: .continuous).strokeBorder(BandsTheme.controlBorder(colorScheme)))
                    .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
                    .onSubmit { beginBandDescription() }.focused($focus, equals: .newBand)
                    .onExitCommand { cancelNewBand() }
                    .accessibilityLabel("New band name")
                    .accessibilityHint("Press Return to enter a description, or Escape to cancel")
            } else if addingBand && enteringBandDescription {
                TextField("", text: $newBandDescription,
                          prompt: Text("Band description…").foregroundStyle(BandsTheme.secondaryText(colorScheme)))
                    .textFieldStyle(.plain)
                    .foregroundStyle(.primary)
                    .frame(width: 190)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(BandsTheme.controlFill(colorScheme), in: Capsule(style: .continuous))
                    .overlay(Capsule(style: .continuous).strokeBorder(BandsTheme.controlBorder(colorScheme)))
                    .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
                    .onSubmit { addBand() }.focused($focus, equals: .newBandDescription)
                    .onExitCommand { cancelNewBand() }
                    .accessibilityLabel("Band description")
                    .accessibilityHint("Enter a one-line description, then press Return to create the band")
            } else if draggingBandID == nil {
                Button(action: beginQuickCapture) {
                    Image(systemName: "bolt.fill")
                        .font(.body.weight(.semibold))
                        .frame(width: 30, height: 30)
                        .background(BandsTheme.controlFill(colorScheme), in: Circle())
                        .overlay(Circle().strokeBorder(BandsTheme.controlBorder(colorScheme)))
                        .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .pointingHandCursor()
                .accessibilityLabel("Quick Capture")
                .help("Quick Capture (⌥Q); open bands (⌥L)")
                Button { beginNewBand() } label: {
                    Text("+ band")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(BandsTheme.bandFill(colorScheme), in: Capsule(style: .continuous))
                        .overlay(Capsule(style: .continuous).strokeBorder(BandsTheme.controlBorder(colorScheme)))
                        .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(BandsTheme.bandText(colorScheme))
                .pointingHandCursor()
                .accessibilityLabel("Create band")
            } else {
                Image(systemName: "trash")
                    .font(.body.weight(.semibold))
                    .frame(width: 30, height: 30)
                    .foregroundStyle(hoveringBandBin ? .white : .red)
                    .background(hoveringBandBin ? Color.red : Color.red.opacity(0.12), in: Circle())
                    .overlay(Circle().strokeBorder(Color.red.opacity(hoveringBandBin ? 0.9 : 0.28)))
                    .scaleEffect(hoveringBandBin ? 1.08 : 1)
                    .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.72), value: hoveringBandBin)
                    .onDrop(of: [UTType.text.identifier, UTType.data.identifier], isTargeted: $hoveringBandBin) { providers, _ in
                        dropBandOnBin(providers)
                    }
                    .accessibilityLabel("Delete band")
                    .accessibilityHint("Drop the dragged band here to delete it")
            }
            Button(action: openSettings) {
                Image(systemName: "gearshape")
                    .font(.body.weight(.medium))
                    .frame(width: 30, height: 30)
                    .background(BandsTheme.controlFill(colorScheme), in: Circle())
                    .overlay(Circle().strokeBorder(BandsTheme.controlBorder(colorScheme)))
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
    private func beginQuickCapture() {
        guard !modalIsPresented else { return }
        quickCaptureText = ""
        quickCaptureBusy = false
        quickCaptureNeedsBand = false
        quickCaptureMessage = nil
        showingQuickCapture = true
        DispatchQueue.main.async { focus = .quickCapture }
    }
    private func beginNewBand() {
        newBand = ""
        newBandDescription = ""
        enteringBandDescription = false
        addingBand = true
        focus = .newBand
    }
    private func beginBandDescription() {
        guard case .valid = BandManagement.validateName(newBand, existingNames: bands.map(\.name)) else { return }
        enteringBandDescription = true
        DispatchQueue.main.async { focus = .newBandDescription }
    }
    private func cancelNewBand() {
        addingBand = false
        enteringBandDescription = false
        newBand = ""
        newBandDescription = ""
        restoreSelection()
    }
    private func addBand() {
        guard case .valid(let name) = BandManagement.validateName(newBand, existingNames: bands.map(\.name)) else { return }
        let description = newBandDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let band = Band(name: name, descriptionText: description.isEmpty ? nil : description, order: 0)
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.28, extraBounce: 0.08)) {
            BandManagement.insert(band, into: bands, atEnd: InsertionPreferences.bandsAtEnd)
            context.insert(band)
            try? context.save()
        }
        addingBand = false
        enteringBandDescription = false
        newBand = ""
        newBandDescription = ""
        select(.band(band.id))
    }
    private func focusQuickCapture() {
        let targetBandID = selection.bandID ?? selectedThought?.band?.id
        guard let band = targetBandID.flatMap({ id in bands.first(where: { $0.id == id }) }) ?? bands.first else { beginNewBand(); return }
        selection.select(.band(band.id), with: .keyboard)
        composingBandID = band.id
        // The conditional editor must exist before FocusState can target it.
        DispatchQueue.main.async { focus = .bandInput(band.id) }
    }
    private func submitQuickCapture() {
        let thought = quickCaptureText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !thought.isEmpty else {
            quickCaptureMessage = "Enter a thought to capture."
            return
        }
        guard !bands.isEmpty else {
            quickCaptureMessage = "Create a band before capturing a thought."
            return
        }

        quickCaptureBusy = true
        quickCaptureNeedsBand = false
        quickCaptureMessage = nil
        Task { @MainActor in
            do {
                let result = try await JevClient().autoCategorize(thought: thought, bands: bands)
                guard result.confidence >= JevSettings.confidenceThreshold,
                      let bandID = result.bandID,
                      let band = bands.first(where: { $0.id == bandID }) else {
                    quickCaptureBusy = false
                    quickCaptureNeedsBand = true
                    quickCaptureMessage = "Jev was only \(Int((result.confidence * 100).rounded()))% confident. Choose a band below."
                    return
                }
                captureQuickThought(thought, in: band)
            } catch JevClientError.missingToken {
                quickCaptureBusy = false
                quickCaptureNeedsBand = true
                quickCaptureMessage = "Add a Jev token in Settings, or choose a band below."
            } catch {
                quickCaptureBusy = false
                quickCaptureNeedsBand = true
                quickCaptureMessage = "Jev could not categorize this thought. Choose a band below."
            }
        }
    }
    private func chooseQuickCaptureBand(_ band: Band) {
        let thought = quickCaptureText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !thought.isEmpty else { return }
        captureQuickThought(thought, in: band)
    }
    private func captureQuickThought(_ text: String, in band: Band) {
        do {
            guard let thought = try BandManagement.capture(text, in: band, context: context, now: .now) else {
                quickCaptureBusy = false
                quickCaptureMessage = "Enter a thought to capture."
                return
            }
            try context.save()
            BandsNotificationBus.thoughtChanged(thought.id)
            selection.select(.thought(thought.id), with: .keyboard)
            showingQuickCapture = false
        } catch {
            quickCaptureBusy = false
            quickCaptureMessage = "The thought could not be saved. Try again."
        }
    }
    private func cancelQuickCapture() {
        showingQuickCapture = false
        resetQuickCapture()
        restoreSelection()
    }
    private func resetQuickCapture() {
        quickCaptureText = ""
        quickCaptureBusy = false
        quickCaptureNeedsBand = false
        quickCaptureMessage = nil
    }
    private var modalIsPresented: Bool {
        showingSettings || showingQuickCapture || thoughtPendingMove != nil || thoughtPendingRelease != nil || bandPendingDeletion != nil
    }
    private func updateCommands() {
        var available: Set<PanelCommand> = []
        if !modalIsPresented && focus?.isEditing != true {
            available = [.quickCapture, .newThought, .newBand, .openSettings]
            if selection.bandID != nil { available.insert(.editDescription) }
            if case .addThought = selection.target {
                // Return on the focused + opens its inline composer.
                available.insert(.edit)
            }
            let targets: [PanelSelection.Target]
            if let thought = selectedThought, let band = thought.band {
                targets = bandThoughts(band).map { .thought($0.id) }
            } else {
                targets = bands.map { .band($0.id) }
            }
            if let target = selection.target, let index = targets.firstIndex(of: target) {
                available.formUnion([.edit, .destructive])
                if index > 0 { available.insert(.moveEarlier) }
                if index < targets.count - 1 { available.insert(.moveLater) }
            }
            if selectedThought != nil {
                available.formUnion([.copy, .complete, .resetAging])
                if bands.count > 1 { available.insert(.move) }
            }
        }
        BoardCommands.shared.available = available
    }
    private func select(_ target: PanelSelection.Target?) {
        selection.select(target, with: .keyboard)
        // Let the destination row/control render before asking SwiftUI to focus it.
        // This is essential for an empty band, whose + button is the destination.
        DispatchQueue.main.async { restoreSelection() }
    }
    private func restoreSelection() {
        switch selection.target {
        case .band(let id): focus = .band(id)
        case .thought(let id): focus = .thought(id)
        case .addThought(let id): focus = .bandAdd(id)
        case nil: focus = nil
        }
    }
    private var boardBands: [BoardBand] {
        bands.map { BoardBand(id: $0.id, thoughts: bandThoughts($0).map(\.id), thoughtsAtEnd: thoughtsAtEnd) }
    }
    private func handleKey(_ request: PanelKeyRequest) {
        guard !modalIsPresented else { return }
        let event = request.event
        // Never steal cursor keys, text selection, or IME input from an editor.
        let textEditing = (NSApp.keyWindow?.firstResponder as? NSTextView)?.isEditable == true
        guard focus?.isEditing != true && !textEditing else { return }
        if let command = PanelCommand.matching(event) {
            request.handled = true
            perform(command)
            return
        }
        if event.keyCode == 48 && event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
            request.handled = true
            return
        }
        guard event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else { return }
        let direction: BoardDirection?
        switch event.keyCode {
        case 123: direction = .left
        case 124: direction = .right
        case 125: direction = .down
        case 126: direction = .up
        case 48: request.handled = true; return
        default: direction = nil
        }
        if let direction {
            select(BoardNavigation.target(from: selection.target, direction: direction, bands: boardBands))
            request.handled = true
        }
    }
    private var selectedThought: Thought? {
        guard let id = selection.thoughtID else { return nil }
        return (try? context.fetch(FetchDescriptor<Thought>()))?.first(where: { $0.id == id && $0.completedAt == nil && $0.releasedAt == nil })
    }
    private func perform(_ command: PanelCommand) {
        guard !modalIsPresented else { return }
        // Global invocation restores an existing editor rather than discarding its draft.
        if focus?.isEditing == true { return }
        updateCommands()
        guard BoardCommands.shared.available.contains(command) else { return }
        switch command {
        case .quickCapture:
            beginQuickCapture()
        case .newThought: focusQuickCapture()
        case .newBand: beginNewBand()
        case .openSettings: openSettings()
        case .copy: if let thought = selectedThought { ThoughtClipboard.copy(thought.text) }
        case .editDescription:
            if let bandID = selection.bandID {
                NotificationCenter.default.post(name: .bandsBeginEditDescription, object: bandID)
            }
        case .complete: if let thought = selectedThought { complete(thought) }
        case .edit:
            if case .addThought = selection.target {
                focusQuickCapture()
            } else if let target = selection.target {
                NotificationCenter.default.post(name: .bandsBeginEdit, object: target)
            }
        case .resetAging: if let thought = selectedThought { resetAging(thought) }
        case .move: if let thought = selectedThought, bands.count > 1 { thoughtPendingMove = thought }
        case .moveEarlier: moveSelected(.up)
        case .moveLater: moveSelected(.down)
        case .destructive:
            if let thought = selectedThought { thoughtPendingRelease = thought }
            else if let bandID = selection.bandID, let band = bands.first(where: { $0.id == bandID }) { bandPendingDeletion = band }
        }
    }
    private func moveBands(from source: IndexSet, to destination: Int) { _ = BandManagement.reordered(bands, moving: source, to: destination); try? context.save() }
    private func moveBand(_ band: Band, onto target: Band) {
        guard band.id != target.id,
              let sourceIndex = bands.firstIndex(where: { $0.id == band.id }),
              let targetIndex = bands.firstIndex(where: { $0.id == target.id }) else { return }

        // A drop is interpreted as placing the dragged band after the band it lands on.
        // Array.move(toOffset:) uses the post-removal offset, so adjust when moving down.
        let destination = sourceIndex < targetIndex ? targetIndex + 1 : targetIndex
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.28, extraBounce: 0.08)) {
            _ = BandManagement.reordered(bands, moving: IndexSet(integer: sourceIndex), to: destination)
            try? context.save()
        }
    }
    private func bandThoughts(_ band: Band) -> [Thought] {
        ((try? context.fetch(FetchDescriptor<Thought>())) ?? [])
            .filter { $0.band?.id == band.id && $0.completedAt == nil && $0.releasedAt == nil }
            .sorted { ($0.order ?? 0, $0.createdAt) > ($1.order ?? 0, $1.createdAt) }
    }
    private func complete(_ thought: Thought) {
        selectAdjacent(after: thought)
        ThoughtManagement.complete(thought, now: .now)
        try? context.save()
        BandsNotificationBus.thoughtChanged(thought.id)
    }
    private func release(_ thought: Thought) {
        selectAdjacent(after: thought)
        ThoughtManagement.letGo(thought, now: .now)
        try? context.save()
        BandsNotificationBus.thoughtChanged(thought.id)
    }
    private func resetAging(_ thought: Thought) { ThoughtManagement.resetAging(thought, now: .now); try? context.save(); BandsNotificationBus.thoughtChanged(thought.id) }
    private func move(_ thought: Thought, to band: Band) {
        let destination = bandThoughts(band)
        ThoughtManagement.reorder(thought, to: band, among: destination, at: 0, now: .now)
        try? context.save()
        selection.select(.thought(thought.id), with: .keyboard)
        focus = .thought(thought.id)
    }
    private func moveSelected(_ direction: PanelMoveDirection) {
        if let thought = selectedThought, let band = thought.band, ThoughtManagement.moveWithinBand(thought, among: bandThoughts(band), direction: direction, now: .now) { try? context.save() }
        else if let bandID = selection.bandID, let current = bands.firstIndex(where: { $0.id == bandID }) {
            let destination = direction == .up ? current - 1 : current + 1
            guard bands.indices.contains(destination) else { return }
            _ = BandManagement.reordered(bands, moving: IndexSet(integer: current), to: direction == .up ? destination : destination + 1)
            try? context.save()
        }
    }
    private func selectAdjacent(after thought: Thought) {
        guard let band = boardBands.first(where: { $0.id == thought.band?.id }) else { select(nil); return }
        select(BoardNavigation.afterRemoving(thought.id, from: band))
    }
    private func deleteBand(_ band: Band) {
        let index = bands.firstIndex(where: { $0.id == band.id }) ?? 0
        let remaining = bands.filter { $0.id != band.id }
        let next = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)]
        let thoughts = (try? context.fetch(FetchDescriptor<Thought>())) ?? []
        let affected = thoughts.filter { $0.band?.id == band.id }
        let ids = affected.map(\.id)
        affected.forEach(context.delete)
        context.delete(band)
        try? context.save()
        ids.forEach(BandsNotificationBus.thoughtChanged)
        select(next.map { .band($0.id) })
    }
    private func dropBandOnBin(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let raw = object as? String, let id = UUID(uuidString: raw) else { return }
            DispatchQueue.main.async {
                guard let band = bands.first(where: { $0.id == id }) else { return }
                bandPendingDeletion = band
                draggingBandID = nil
                hoveringBandBin = false
            }
        }
        return true
    }
}

private enum MCPSettings {
    static let enabledKey = "mcpEnabled"
}

/// The connection itself is owned by the app layer; this view only persists
/// and communicates the user's preference.
private struct MCPControl: View {
    @AppStorage(MCPSettings.enabledKey) private var enabled = true

    var body: some View {
        Toggle("", isOn: $enabled)
            .labelsHidden()
            .toggleStyle(.switch)
        .pointingHandCursor()
        .accessibilityLabel("MCP connection")
        .accessibilityHint("Toggle MCP access to your bands and thoughts")
        .onAppear {
            UserDefaults.standard.register(defaults: [MCPSettings.enabledKey: true])
        }
    }
}

struct EmptyBandsView: View {
    let onCreate: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up")
                .font(.title2).foregroundStyle(.tertiary).accessibilityHidden(true)
            Text("No bands yet").font(.headline)
            Text("Create a band to give your thoughts a place to land.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Create band", action: onCreate)
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

struct BandsPanelBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    private let cornerRadius: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(BandsTheme.panel(colorScheme))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        colorScheme == .dark ? .white.opacity(0.18) : .black.opacity(0.14),
                        lineWidth: 0.75
                    )
            }
    }
}

private struct QuickCaptureBubble: View {
    @Binding var text: String
    @Binding var isBusy: Bool
    @Binding var needsBand: Bool
    @Binding var message: String?
    let bands: [Band]
    let onSubmit: () -> Void
    let onChooseBand: (Band) -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ThoughtBubble(fill: BandsTheme.controlFill(colorScheme)) {
                HStack(spacing: 6) {
                    ZStack(alignment: .leading) {
                        TextField("", text: $text, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(1...4)
                            // ThoughtBubble adds 24 points of horizontal padding,
                            // plus the return/spinner affordance and its gap.
                            // Keep the editor inside the width reserved by the
                            // floating action row, just like the add-band field.
                            .frame(width: 210, alignment: .leading)
                            .focused($focused)
                            .onSubmit { if !isBusy { onSubmit() } }
                            .disabled(isBusy)
                        if text.isEmpty {
                            Text("Add thought")
                                .foregroundStyle(BandsTheme.secondaryText(colorScheme))
                                .allowsHitTesting(false)
                        }
                    }
                    if isBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "return")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(width: 252, alignment: .leading)

            if message != nil || needsBand {
                VStack(alignment: .leading, spacing: 6) {
                    if let message {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(BandsTheme.secondaryText(colorScheme))
                    }
                    if needsBand {
                        FlowLayout(spacing: 7) {
                            Text("Choose band")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(BandsTheme.secondaryText(colorScheme))
                            ForEach(bands) { band in
                                Button(band.name) { onChooseBand(band) }
                                    .buttonStyle(.plain)
                                    .font(.caption)
                                    .foregroundStyle(BandsTheme.bandText(colorScheme))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(BandsTheme.bandFill(colorScheme), in: Capsule(style: .continuous))
                                    .overlay(Capsule(style: .continuous).strokeBorder(BandsTheme.controlBorder(colorScheme)))
                            }
                        }
                    }
                }
                .padding(8)
                .background(BandsTheme.controlFill(colorScheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(BandsTheme.controlBorder(colorScheme)))
            }

        }
        .frame(width: 252, alignment: .trailing)
        .onAppear { focused = true }
        .onExitCommand { onCancel() }
    }
}

struct SettingsView: View {
    @AppStorage("appearance") private var appearance = AppAppearance.system.rawValue
    @AppStorage(ThoughtNotificationSettings.enabledKey) private var notificationsEnabled = ThoughtNotificationSettings.defaultEnabled
    @AppStorage(InsertionPreferences.thoughtsAtEndKey) private var thoughtsAtEnd = false
    @AppStorage(InsertionPreferences.bandsAtEndKey) private var bandsAtEnd = false
    @EnvironmentObject private var agingStore: ThoughtAgingSettingsStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var initialAppearance = AppAppearance.system.rawValue
    @State private var fresh = ThoughtAgingSettings.defaults.freshMinutes
    @State private var warm = ThoughtAgingSettings.defaults.warmMinutes
    @State private var attention = ThoughtAgingSettings.defaults.attentionMinutes
    @State private var old = ThoughtAgingSettings.defaults.oldMinutes
    @State private var jevConfidencePercent = Int((JevSettings.defaultConfidenceThreshold * 100).rounded())
    @State private var jevToken = ""
    @State private var tokenMessage: String?

    private var draft: ThoughtAgingSettings { ThoughtAgingSettings(freshMinutes: fresh, warmMinutes: warm, attentionMinutes: attention, oldMinutes: old) }
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
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
                    .foregroundStyle(BandsTheme.secondaryText(colorScheme))
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
                    Text("New bands")
                    Spacer()
                    Picker("Band placement", selection: $bandsAtEnd) {
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
            SettingsSection(title: "Thought aging") {
                Text("Set when a thought begins to draw attention.")
                    .font(.caption)
                    .foregroundStyle(BandsTheme.secondaryText(colorScheme))
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
            }
            Divider()
            HStack {
                Text("Notifications")
                Spacer()
                Toggle("Notifications", isOn: $notificationsEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .pointingHandCursor()
                    .onChange(of: notificationsEnabled) { _, value in
                        NotificationCenter.default.post(name: .bandsNotificationPreferenceChanged, object: nil, userInfo: ["enabled": value])
                    }
            }
            .padding(.vertical, 4)
            Divider()
            HStack {
                Text("MCP")
                Spacer()
                MCPControl()
            }
            .padding(.vertical, 4)
            Divider()
            SettingsSection(title: "Jev") {
                Text("Configure automatic thought categorization with Jev.")
                    .font(.caption)
                    .foregroundStyle(BandsTheme.secondaryText(colorScheme))
                    .padding(.bottom, 4)
                HStack {
                    Text("Minimum confidence")
                    Spacer()
                    Stepper("\(jevConfidencePercent)%", value: $jevConfidencePercent, in: 0...100)
                        .labelsHidden()
                    Text("\(jevConfidencePercent)%")
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                }
                .padding(.vertical, 4)
                Divider()
                SecureField("Jev token", text: $jevToken)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { saveJevToken() }
                if let tokenMessage {
                    Text(tokenMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            SettingsSection(title: "Keyboard shortcuts") {
                ShortcutRow(title: "Change band", shortcut: "↑ / ↓")
                ShortcutRow(title: "Navigate thoughts", shortcut: "← / →")
                ShortcutRow(title: "Select band name", shortcut: "← from first thought / +")
                ShortcutRow(title: "Open selected +", shortcut: "Return")
                ShortcutRow(title: "Cancel editor / close panel", shortcut: "Esc")
                Text("Arrow navigation applies when browsing. Empty bands use + as their content target. Return renames a selected band name or opens a selected +. Text fields keep standard editing keys. New Thought uses the selected band; Quick Capture asks Jev to choose a band and lets you choose manually when needed.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Array(PanelCommand.reference.enumerated()), id: \.element) { index, command in
                    ShortcutRow(title: command.title, shortcut: command.shortcut)
                    if index != PanelCommand.reference.count - 1 { Divider() }
                }
            }
            Divider()
            HStack {
                Button("Restore Defaults") {
                    setDraft(.defaults)
                    jevConfidencePercent = Int((JevSettings.defaultConfidenceThreshold * 100).rounded())
                }
                    .pointingHandCursor()
                Spacer()
                Button("Cancel", role: .cancel) {
                    appearance = initialAppearance
                    AppAppearance.apply(initialAppearance)
                    dismiss()
                }
                .pointingHandCursor()
                Button("Apply") {
                    guard saveJevToken() else { return }
                    agingStore.update(draft)
                    UserDefaults.standard.set(Double(jevConfidencePercent) / 100, forKey: JevSettings.confidenceThresholdKey)
                    dismiss()
                }
                    .disabled(validationMessage != nil)
                    .keyboardShortcut(.defaultAction)
                    .pointingHandCursor()
            }
            Divider()
            Text("Version \(appVersion)")
                .font(.caption)
                .foregroundStyle(BandsTheme.secondaryText(colorScheme))
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ThinScrollbarConfigurator())
        }
        .scrollIndicators(.visible)
        .frame(width: 460, height: 520, alignment: .topLeading)
        .background(BandsTheme.panel(colorScheme))
        .onAppear {
            initialAppearance = appearance
            setDraft(agingStore.settings)
            jevConfidencePercent = Int((JevSettings.confidenceThreshold * 100).rounded())
            loadJevToken()
            AppAppearance.apply(appearance)
        }
        .onChange(of: appearance) { _, value in AppAppearance.apply(value) }
    }

    private func setDraft(_ settings: ThoughtAgingSettings) {
        fresh = settings.freshMinutes; warm = settings.warmMinutes
        attention = settings.attentionMinutes; old = settings.oldMinutes
    }

    private func loadJevToken() {
        do {
            jevToken = try LocalTokenStore.shared.token(forKey: SecureTokenKeys.jev) ?? ""
        } catch {
            tokenMessage = "Unable to read the stored token."
        }
    }

    @discardableResult
    private func saveJevToken() -> Bool {
        do {
            if jevToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try LocalTokenStore.shared.deleteToken(forKey: SecureTokenKeys.jev)
            } else {
                try LocalTokenStore.shared.setToken(jevToken, forKey: SecureTokenKeys.jev)
            }
            tokenMessage = "Token stored locally."
            return true
        } catch {
            tokenMessage = "Unable to store the local token."
            return false
        }
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

private struct MoveThoughtSheet: View {
    let thought: Thought
    let bands: [Band]
    let onMove: (Band) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusPicker: Bool
    @State private var destinationID: UUID

    init(thought: Thought, bands: [Band], onMove: @escaping (Band) -> Void) {
        self.thought = thought
        self.bands = bands
        self.onMove = onMove
        _destinationID = State(initialValue: bands.first(where: { $0.id != thought.band?.id })?.id ?? thought.band?.id ?? UUID())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Move Thought").font(.headline)
            Text(thought.text).lineLimit(2).foregroundStyle(.secondary)
            Picker("Move to band", selection: $destinationID) {
                ForEach(bands.filter { $0.id != thought.band?.id }) { band in Text(band.name).tag(band.id) }
            }
            .focused($focusPicker)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Move") {
                    if let band = bands.first(where: { $0.id == destinationID }) { onMove(band) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear { focusPicker = true }
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
    static let bandsPanelDidOpen = Notification.Name("bands.panelDidOpen")
    static let bandsBeginEdit = Notification.Name("bands.beginEdit")
    static let bandsBeginEditDescription = Notification.Name("bands.beginEditDescription")
}

struct BandRow: View {
    private static let bandNameFont = Font.subheadline.weight(.semibold)
    private static let bandPillHorizontalPadding: CGFloat = 11
    private static let bandPillVerticalPadding: CGFloat = 8
    private static let bandPillCornerRadius: CGFloat = 9

    @Environment(\.modelContext) private var context
    @Bindable var band: Band
    @Query(sort: [SortDescriptor(\Thought.order, order: .reverse), SortDescriptor(\Thought.createdAt, order: .reverse)]) private var allThoughts: [Thought]
    let bands: [Band]
    let now: Date
    @Binding var selection: PanelSelection
    @FocusState.Binding var focus: RootView.PanelFocus?
    @Binding var composingBandID: UUID?
    @Binding var draggingBandID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(InsertionPreferences.thoughtsAtEndKey) private var thoughtsAtEnd = false
    let onDelete: (Band) -> Void
    let onMoveBand: (Band, Band) -> Void
    @State private var input = ""; @State private var editing = false; @State private var name = ""; @State private var editingDescription = false; @State private var descriptionDraft = ""; @State private var showingDeleteConfirmation = false; @State private var hoveringAdd = false; @State private var hoveringBand = false; @State private var dropTargeted = false; @State private var thoughtFrames: [UUID: CGRect] = [:]
    @State private var insertionIndex: Int?
    @State private var bandDropAfter = false
    var thoughts: [Thought] {
        allThoughts
            .filter { $0.band?.id == band.id && $0.completedAt == nil && $0.releasedAt == nil }
            .sorted { ($0.order ?? 0, $0.createdAt) > ($1.order ?? 0, $1.createdAt) }
    }
    var body: some View {
        bandFlow
        .padding(.vertical, 8)
        .padding(.horizontal, dropTargeted ? 5 : 0)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(dropTargeted && draggingBandID == nil ? 0.055 : 0))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(dropTargeted && draggingBandID == nil ? 0.18 : 0), lineWidth: 1)
                }
        }
        .overlay {
            if dropTargeted && draggingBandID != nil {
                VStack(spacing: 0) {
                    if !bandDropAfter { BandInsertionIndicator() }
                    Spacer(minLength: 0)
                    if bandDropAfter { BandInsertionIndicator() }
                }
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.76), value: dropTargeted)
        .contentShape(Rectangle())
        .coordinateSpace(name: band.id.uuidString)
        .onPreferenceChange(ThoughtFramePreferenceKey.self) { thoughtFrames = $0 }
        .onDrop(of: [UTType.text.identifier, UTType.data.identifier], delegate: BandDropDelegate(
            updateLocation: { location in
                if draggingBandID == nil {
                    insertionIndex = insertionIndex(at: location, in: thoughts)
                } else {
                    bandDropAfter = location.y > 42
                    insertionIndex = nil
                }
            },
            performDrop: { provider, location in
                provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let raw = object as? String else { return }
                    DispatchQueue.main.async {
                        _ = handleDrop(raw: raw, at: location)
                        insertionIndex = nil
                        draggingBandID = nil
                    }
                }
            },
            isTargeted: $dropTargeted,
            insertionIndex: $insertionIndex
        ))
        .contextMenu { Button("Rename") { beginRename() }; Button("Edit Description") { beginEditDescription() }; Button("Add Thought") { beginAdd() }; Divider(); Button("Delete Band", role: .destructive, action: requestDeletion) }
        .confirmationDialog("Delete \"\(band.name)\"?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) { Button("Delete Band", role: .destructive) { onDelete(band) }; Button("Cancel", role: .cancel) {} } message: { Text("This will delete its \(thoughts.count) active thought\(thoughts.count == 1 ? "" : "s").") }
        .onChange(of: focus) { _, focus in
            if focus == .bandRename(band.id), !editing { beginRename() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bandsBeginEdit)) { notification in
            guard let target = notification.object as? PanelSelection.Target,
                  target == .band(band.id) else { return }
            beginRename()
        }
        .onReceive(NotificationCenter.default.publisher(for: .bandsBeginEditDescription)) { notification in
            guard let target = notification.object as? UUID, target == band.id else { return }
            beginEditDescription()
        }
    }
    private var bandFlow: some View {
        FlowLayout {
            bandPill
            if !thoughtsAtEnd { thoughtAdditionControl }
            thoughtItems
            if thoughtsAtEnd { thoughtAdditionControl }
        }
    }
    @ViewBuilder private var thoughtItems: some View {
        ForEach(Array(thoughts.enumerated()), id: \.element.id) { index, thought in
            if dropTargeted && insertionIndex == index { ThoughtInsertionIndicator() }
            ThoughtChip(thought: thought, bandID: band.id, now: now, selection: $selection, focus: $focus)
                .id(PanelSelection.Target.thought(thought.id))
        }
        if dropTargeted && insertionIndex == thoughts.count { ThoughtInsertionIndicator() }
    }
    private var bandPill: some View {
        HStack(spacing: 0) {
            if editing {
                TextField("Band name", text: $name).textFieldStyle(.plain).focused($focus, equals: .bandRename(band.id)).onSubmit { saveName() }.onExitCommand { cancelRename() }
                    .onAppear { DispatchQueue.main.async { focus = .bandRename(band.id) } }
            } else if editingDescription {
                ZStack(alignment: .leading) {
                    TextField("", text: $descriptionDraft)
                        .textFieldStyle(.plain)
                        .foregroundStyle(BandsTheme.bandText(colorScheme))
                    if descriptionDraft.isEmpty {
                        Text("Band description")
                            .foregroundStyle(BandsTheme.bandText(colorScheme).opacity(0.55))
                            .allowsHitTesting(false)
                    }
                }
                    .frame(minWidth: 220)
                    .focused($focus, equals: .bandDescription(band.id))
                    .onSubmit { saveDescription() }
                    .onExitCommand { cancelDescriptionEdit() }
                    .onAppear { DispatchQueue.main.async { focus = .bandDescription(band.id) } }
            } else {
                Text(band.name)
                    .contentShape(Rectangle())
                    .onTapGesture { selection.select(.band(band.id), with: .pointer); focus = .band(band.id) }
                    .focusable().focused($focus, equals: .band(band.id))
                    .onKeyPress(.return) { beginRename(); return .handled }
            }
        }
        .font(Self.bandNameFont).foregroundStyle(BandsTheme.bandText(colorScheme))
        .padding(.horizontal, Self.bandPillHorizontalPadding).padding(.vertical, Self.bandPillVerticalPadding)
        .background(BandsTheme.bandFill(colorScheme), in: RoundedRectangle(cornerRadius: Self.bandPillCornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Self.bandPillCornerRadius, style: .continuous).strokeBorder(.black.opacity(0.10)))
        .overlay { if focus == .band(band.id) && selection.target == .band(band.id) && selection.showsKeyboardFocus && !editing { RoundedRectangle(cornerRadius: Self.bandPillCornerRadius + 3, style: .continuous).stroke(BandsTheme.keyboardFocus(colorScheme), lineWidth: 2).padding(-3).allowsHitTesting(false) } }
        .onHover { hoveringBand = $0 }.pointingHandCursor()
        .rotationEffect(.degrees(hoveringBand && !editing ? -2 : 0), anchor: .center)
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.58), value: hoveringBand)
        // Keep the source on a plain view. Interactive controls can consume
        // the mouse gesture before SwiftUI creates the drag provider.
        .onDrag { draggingBandID = band.id; return NSItemProvider(object: band.id.uuidString as NSString) } preview: {
            BandDragPreview(name: band.name)
        }
        .focusEffectDisabled().accessibilityLabel("Band \(band.name)")
    }
    private func beginRename() {
        editingDescription = false
        name = band.name
        editing = true
        DispatchQueue.main.async { focus = .bandRename(band.id) }
    }
    private func beginEditDescription() {
        editing = false
        descriptionDraft = band.descriptionText ?? ""
        editingDescription = true
        selection.select(.band(band.id), with: .keyboard)
        DispatchQueue.main.async { focus = .bandDescription(band.id) }
    }
    private func requestDeletion() {
        showingDeleteConfirmation = true
    }
    private func cancelRename() { editing = false; name = ""; focus = .band(band.id) }
    private func cancelDescriptionEdit() { editingDescription = false; descriptionDraft = ""; focus = .band(band.id) }
    private func saveDescription() {
        let value = descriptionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        band.descriptionText = value.isEmpty ? nil : value
        try? context.save()
        cancelDescriptionEdit()
    }
    private func saveName() { guard case .valid(let value) = BandManagement.validateName(name, existingNames: bands.map(\.name), excluding: band.name) else { return }; band.name = value; try? context.save(); cancelRename() }
    private func beginAdd() {
        input = ""
        composingBandID = band.id
        DispatchQueue.main.async { focus = .bandInput(band.id) }
    }
    private func cancelAdd() { composingBandID = nil; input = ""; selection.select(.band(band.id), with: .keyboard); focus = .band(band.id) }
    @ViewBuilder private var thoughtAdditionControl: some View {
        if composingBandID == band.id {
            ThoughtBubble {
                HStack(spacing: 6) {
                    TextField("", text: $input,
                              prompt: Text("Add thought").foregroundStyle(BandsTheme.secondaryText(colorScheme)))
                        .textFieldStyle(.plain)
                        .frame(minWidth: 112)
                        .focused($focus, equals: .bandInput(band.id))
                        .onAppear { DispatchQueue.main.async { focus = .bandInput(band.id) } }
                        .onSubmit { addThought() }
                        .onExitCommand { cancelAdd() }
                        .accessibilityLabel("New thought in \(band.name)")
                        .accessibilityHint("Press Return to save, or Escape to cancel")
                    Image(systemName: "return")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
        } else {
            Button {
                beginAdd()
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.medium))
                    .frame(width: 22, height: 22)
                    .offset(y: 1)
                    .background(hoveringAdd ? Color.primary.opacity(0.12) : .clear, in: Circle())
            }
            .buttonStyle(.plain)
            .focusable()
            .focused($focus, equals: .bandAdd(band.id))
            .focusEffectDisabled()
            .foregroundStyle(hoveringAdd ? .primary : BandsTheme.secondaryText(colorScheme))
            .background {
                if focus == .bandAdd(band.id) && selection.target == .addThought(band.id) && selection.showsKeyboardFocus {
                    Circle().fill(BandsTheme.keyboardFocus(colorScheme).opacity(0.08)).padding(-3).allowsHitTesting(false)
                }
            }
            .overlay {
                if focus == .bandAdd(band.id) && selection.target == .addThought(band.id) && selection.showsKeyboardFocus {
                    Circle().stroke(BandsTheme.keyboardFocus(colorScheme), lineWidth: 2).padding(-3).allowsHitTesting(false)
                }
            }
            .onKeyPress(.return) {
                beginAdd()
                return .handled
            }
            .onHover { hoveringAdd = $0 }
            .animation(.easeOut(duration: 0.14), value: hoveringAdd)
            .pointingHandCursor()
            .accessibilityLabel("Add thought to \(band.name)")
        }
    }
    private func addThought() {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let orders = thoughts.compactMap(\.order)
        let order = InsertionPreferences.thoughtsAtEnd
            ? (orders.min() ?? 0) - 1
            : (orders.max() ?? 0) + 1
        let thought = Thought(text: value, band: band, order: order)
        context.insert(thought)
        try? context.save()
        BandsNotificationBus.thoughtChanged(thought.id)
        composingBandID = nil
        input = ""
        selection.select(.thought(thought.id), with: .keyboard)
        focus = .thought(thought.id)
    }
    private func handleDrop(raw: String, at location: CGPoint) -> Bool {
        guard let sourceID = UUID(uuidString: raw) else { return false }
        if let source = bands.first(where: { $0.id == sourceID }) {
            guard source.id != band.id else { return false }
            onMoveBand(source, band)
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
        ThoughtManagement.reorder(thought, to: band, among: destinationThoughts, at: destination, now: .now)
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

private struct BandDragPreview: View {
    @Environment(\.colorScheme) private var colorScheme
    let name: String
    var body: some View {
        Text(name)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(BandsTheme.bandText(colorScheme))
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(BandsTheme.bandFill(colorScheme), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(BandsTheme.outline(colorScheme)))
            .opacity(0.34)
    }
}

private struct ThoughtBubble<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let age: ThoughtAge
    let fill: Color?
    let content: Content

    init(age: ThoughtAge = .fresh, fill: Color? = nil, @ViewBuilder content: () -> Content) {
        self.age = age
        self.fill = fill
        self.content = content()
    }

    var body: some View {
        content
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(fill ?? BandsTheme.chipFill(for: age, scheme: colorScheme), in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).strokeBorder(BandsTheme.chipBorder(for: age, scheme: colorScheme), lineWidth: age == .fresh ? 0.7 : 0.9))
    }
}

struct ThoughtChip: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var agingStore: ThoughtAgingSettingsStore
    @Bindable var thought: Thought
    let bandID: UUID
    let now: Date
    @Binding var selection: PanelSelection
    @FocusState.Binding var focus: RootView.PanelFocus?
    @State private var editing = false; @State private var draft = ""; @State private var hovering = false
    var age: ThoughtAge { ThoughtAging.age(for: thought, settings: agingStore.settings, now: now) }
    var timestamp: String { ThoughtTimestamp.label(since: thought.createdAt, now: now) }
    /// The text label is capped at 292 points below. Measure against the same
    /// system font so the detail bubble is only offered when the visible label
    /// really has to elide. This is computed from the model value, therefore an
    /// edit immediately updates the result.
    var isThoughtTruncated: Bool {
        let width = (thought.text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]).width
        return width > 292
    }
    var body: some View {
        observedChip
    }
    private var observedChip: some View {
        accessibleChip
            .onChange(of: focus) { _, focus in
                if focus == .thoughtEdit(thought.id), !editing { beginEdit() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .bandsBeginEdit)) { notification in
                guard let target = notification.object as? PanelSelection.Target,
                      target == .thought(thought.id) else { return }
                beginEdit()
            }
    }
    private var accessibleChip: some View {
        framedChip
            .accessibilityElement(children: editing ? .contain : .ignore)
            .accessibilityLabel("\(thought.text)")
            .accessibilityValue("Added \(timestamp) ago. \(age == .fresh ? "Fresh" : "Aging: \(ageLabel)")")
            .accessibilityHint("Press Return to edit, or Command-Return to complete")
            .accessibilityAction(named: "Edit") { beginEdit() }
            .accessibilityAction(named: "Complete") { complete() }
            .accessibilityAction(named: "Reset Aging") { resetAging() }
    }
    private var framedChip: some View {
        chipContent
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: ThoughtFramePreferenceKey.self,
                                           value: [thought.id: proxy.frame(in: .named(bandID.uuidString))])
                }
            }
            .contextMenu {
                Button("Copy") { ThoughtClipboard.copy(thought.text) }
                Button("Edit") { beginEdit() }
                Button("Reset Aging") { resetAging() }
            }
    }

    @ViewBuilder private var chipContent: some View {
        if editing { thoughtEditor } else { displayChip }
    }
    private var thoughtEditor: some View {
        TextField("Thought", text: $draft).textFieldStyle(.roundedBorder).frame(maxWidth: 360)
            .focused($focus, equals: .thoughtEdit(thought.id)).onSubmit { save() }.onExitCommand { cancelEdit() }
            .onAppear { DispatchQueue.main.async { focus = .thoughtEdit(thought.id) } }
            .accessibilityLabel("Edit thought \(thought.text)").accessibilityHint("Press Return to save, or Escape to cancel")
    }
    private var displayChip: some View {
        thoughtBubble
            // Reserve the checkmark's overhanging area in the hover region.
            // Without this, moving from the bubble onto the offset button can
            // clear `hovering` and remove the button before the click lands.
            .padding(.trailing, 8)
            .overlay(alignment: .trailing) { if hovering { completionButton } }
            .overlay { keyboardFocusOverlay }
            .overlay(alignment: .bottomLeading) { if hovering && isThoughtTruncated { fullTextOverlay } }
            .frame(maxWidth: 360, alignment: .leading).zIndex(hovering ? 10 : 0)
            .onHover { hovering = $0 }.pointingHandCursor()
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovering)
            .onTapGesture { selection.select(.thought(thought.id), with: .pointer); focus = .thought(thought.id) }
            .draggable(thought.id.uuidString) { ThoughtDragPreview(text: thought.text, timestamp: timestamp, age: age) }
            .focusable().focusEffectDisabled().focused($focus, equals: .thought(thought.id))
            .onKeyPress(.return) { beginEdit(); return .handled }
    }
    private var thoughtBubble: some View {
        ThoughtBubble(age: age) { HStack(spacing: 6) { Text(thought.text).lineLimit(1).truncationMode(.tail).frame(maxWidth: 292, alignment: .leading); Text(timestamp).font(.caption2.monospacedDigit()).foregroundStyle(BandsTheme.secondaryText(colorScheme)) } }
    }
    private var completionButton: some View {
        Button(action: complete) { Image(systemName: "checkmark").font(.caption.weight(.bold)) }.buttonStyle(.plain).foregroundStyle(.primary).frame(width: 18, height: 18).background(.regularMaterial, in: Circle()).overlay(Circle().strokeBorder(.primary.opacity(0.12))).pointingHandCursor().accessibilityLabel("Complete thought")
    }
    @ViewBuilder private var keyboardFocusOverlay: some View {
        if focus == .thought(thought.id) && selection.target == .thought(thought.id) && selection.showsKeyboardFocus {
            Capsule(style: .continuous).fill(BandsTheme.keyboardFocus(colorScheme).opacity(0.08)).padding(-3).allowsHitTesting(false)
            Capsule(style: .continuous).stroke(BandsTheme.keyboardFocus(colorScheme), lineWidth: 2).padding(-3).allowsHitTesting(false)
        }
    }
    private var fullTextOverlay: some View {
        Text(thought.text).font(.callout).foregroundStyle(.primary).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 340, alignment: .leading).padding(.horizontal, 11).padding(.vertical, 8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.primary.opacity(0.14))).shadow(color: .black.opacity(0.18), radius: 10, y: 5).offset(y: 12).zIndex(20).allowsHitTesting(false)
    }
    private var ageLabel: String { ThoughtAging.label(for: thought, settings: agingStore.settings, now: now).map { "\($0) old" } ?? "fresh" }
    private func beginEdit() {
        selection.select(.thought(thought.id), with: .keyboard)
        draft = thought.text
        editing = true
        DispatchQueue.main.async { focus = .thoughtEdit(thought.id) }
    }
    private func cancelEdit() { editing = false; draft = ""; focus = .thought(thought.id) }
    private func complete() {
        selection.select(.thought(thought.id), with: .pointer)
        focus = .thought(thought.id)
        BandsCommandDispatcher.perform(.complete)
    }
    private func resetAging() { ThoughtManagement.resetAging(thought, now: .now); try? context.save(); BandsNotificationBus.thoughtChanged(thought.id) }
    private func save() { guard ThoughtManagement.edit(thought, rawText: draft, now: .now) else { return }; try? context.save(); BandsNotificationBus.thoughtChanged(thought.id); editing = false; focus = .thought(thought.id) }
}

private struct ThoughtDragPreview: View {
    @Environment(\.colorScheme) private var colorScheme
    let text: String
    let timestamp: String
    let age: ThoughtAge
    var body: some View {
        HStack(spacing: 6) {
            Text(text).lineLimit(3).multilineTextAlignment(.leading)
            Text(timestamp).font(.caption2.monospacedDigit()).foregroundStyle(BandsTheme.secondaryText(colorScheme))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(BandsTheme.chipFill(for: age, scheme: colorScheme), in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(BandsTheme.chipBorder(for: age, scheme: colorScheme), lineWidth: 0.9))
        .frame(maxWidth: 360, alignment: .leading)
        .opacity(0.34)
    }
}
