import Foundation
import Combine
import SwiftData

@Model final class Band {
    var id: UUID
    var name: String
    // Optional keeps existing SwiftData stores migratable while allowing new
    // bands to provide semantic context for automatic categorization.
    var descriptionText: String?
    var order: Int
    var createdAt: Date

    init(id: UUID = UUID(), name: String, descriptionText: String? = nil, order: Int, createdAt: Date = .now) {
        self.id = id; self.name = name; self.descriptionText = descriptionText; self.order = order; self.createdAt = createdAt
    }
}

@Model final class Thought {
    var id: UUID
    var text: String
    // Optional keeps existing SwiftData stores migratable; older thoughts use
    // createdAt as their tie-breaker until they are repositioned.
    var order: Int?
    var createdAt: Date
    var updatedAt: Date
    var lastTouchedAt: Date
    // Optional so existing SwiftData stores can migrate without changing
    // the original creation timestamp shown in the UI.
    var agingResetAt: Date?
    var completedAt: Date?
    var releasedAt: Date?
    var band: Band?

    init(id: UUID = UUID(), text: String, band: Band? = nil, order: Int? = nil, createdAt: Date = .now) {
        self.id = id; self.text = text; self.order = order; self.band = band; self.createdAt = createdAt
        self.updatedAt = createdAt; self.lastTouchedAt = createdAt; self.agingResetAt = nil
    }
}

enum ThoughtAge: Equatable { case fresh, warm, attention, old }

struct ThoughtAgingSettings: Equatable {
    static let defaults = ThoughtAgingSettings(freshMinutes: 60, warmMinutes: 300, attentionMinutes: 720, oldMinutes: 1_440)

    var freshMinutes: Int
    var warmMinutes: Int
    var attentionMinutes: Int
    var oldMinutes: Int

    var isValid: Bool { freshMinutes >= 15 && freshMinutes < warmMinutes && warmMinutes < attentionMinutes && attentionMinutes < oldMinutes }
}

/// Persistent choices for where newly created content appears. Keeping these
/// keys outside the view layer also lets captures from the local MCP service
/// follow the same preference.
enum InsertionPreferences {
    static let thoughtsAtEndKey = "insertion.thoughtsAtEnd"
    static let bandsAtEndKey = "insertion.bandsAtEnd"

    static var thoughtsAtEnd: Bool { UserDefaults.standard.bool(forKey: thoughtsAtEndKey) }
    static var bandsAtEnd: Bool { UserDefaults.standard.bool(forKey: bandsAtEndKey) }
}

@MainActor
final class ThoughtAgingSettingsStore: ObservableObject {
    static let shared = ThoughtAgingSettingsStore()
    private let defaults: UserDefaults
    @Published private(set) var settings: ThoughtAgingSettings

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let fallback = ThoughtAgingSettings.defaults
        let saved = ThoughtAgingSettings(
            freshMinutes: Self.loadMinutes(defaults, minuteKey: "aging.freshMinutes", legacyHourKey: "aging.freshHours", fallback: fallback.freshMinutes),
            warmMinutes: Self.loadMinutes(defaults, minuteKey: "aging.warmMinutes", legacyHourKey: "aging.warmHours", fallback: fallback.warmMinutes),
            attentionMinutes: Self.loadMinutes(defaults, minuteKey: "aging.attentionMinutes", legacyHourKey: "aging.attentionHours", fallback: fallback.attentionMinutes),
            oldMinutes: Self.loadMinutes(defaults, minuteKey: "aging.oldMinutes", legacyHourKey: "aging.oldHours", fallback: fallback.oldMinutes)
        )
        settings = saved.isValid ? saved : fallback
    }

    private static func loadMinutes(_ defaults: UserDefaults, minuteKey: String, legacyHourKey: String, fallback: Int) -> Int {
        if let minutes = defaults.object(forKey: minuteKey) as? Int { return minutes }
        if let hours = defaults.object(forKey: legacyHourKey) as? Int { return hours * 60 }
        return fallback
    }

    func update(_ newSettings: ThoughtAgingSettings) {
        guard newSettings.isValid else { return }
        settings = newSettings
        defaults.set(newSettings.freshMinutes, forKey: "aging.freshMinutes")
        defaults.set(newSettings.warmMinutes, forKey: "aging.warmMinutes")
        defaults.set(newSettings.attentionMinutes, forKey: "aging.attentionMinutes")
        defaults.set(newSettings.oldMinutes, forKey: "aging.oldMinutes")
        NotificationCenter.default.post(name: .bandsAgingSettingsChanged, object: nil)
    }

    func restoreDefaults() { update(.defaults) }
}

enum BandNameValidation: Equatable {
    case valid(String)
    case empty
    case duplicate
}

enum PanelMoveDirection { case up, down }

enum BoardDirection { case left, right, up, down }

struct BoardBand: Equatable {
    let id: UUID
    let thoughts: [UUID]
    /// Whether the band renders its + control after the thought bubbles.
    var thoughtsAtEnd: Bool = false
}

enum BoardNavigation {
    static func target(from target: PanelSelection.Target?, direction: BoardDirection, bands: [BoardBand]) -> PanelSelection.Target? {
        guard let first = bands.first else { return nil }
        guard let row = bands.firstIndex(where: { band in
            target == .band(band.id) || target == .addThought(band.id) || band.thoughts.contains(where: { target == .thought($0) })
        }) else { return .band(first.id) }
        let band = bands[row]
        let column = band.thoughts.firstIndex(where: { target == .thought($0) })
        let isAddThought = target == .addThought(band.id)
        switch direction {
        case .left:
            if isAddThought {
                return band.thoughtsAtEnd ? (band.thoughts.last.map(PanelSelection.Target.thought) ?? .band(band.id)) : .band(band.id)
            }
            guard let column else { return .band(band.id) }
            if column > 0 { return .thought(band.thoughts[column - 1]) }
            return band.thoughtsAtEnd ? .band(band.id) : .addThought(band.id)
        case .right:
            if isAddThought {
                return band.thoughts.first.map(PanelSelection.Target.thought) ?? target
            }
            guard !band.thoughts.isEmpty else { return .addThought(band.id) }
            guard let column else { return band.thoughtsAtEnd ? .thought(band.thoughts[0]) : .addThought(band.id) }
            if column < band.thoughts.count - 1 { return .thought(band.thoughts[column + 1]) }
            return band.thoughtsAtEnd ? .addThought(band.id) : .thought(band.thoughts[column])
        case .up, .down:
            let nextRow = max(0, min(bands.count - 1, row + (direction == .up ? -1 : 1)))
            guard nextRow != row else { return target }
            let next = bands[nextRow]
            if isAddThought { return .addThought(next.id) }
            guard let column else { return .band(next.id) }
            guard !next.thoughts.isEmpty else { return .addThought(next.id) }
            return .thought(next.thoughts[min(column, next.thoughts.count - 1)])
        }
    }

    static func afterRemoving(_ id: UUID, from band: BoardBand) -> PanelSelection.Target {
        guard let index = band.thoughts.firstIndex(of: id) else { return .band(band.id) }
        let remaining = band.thoughts.filter { $0 != id }
        return remaining.isEmpty ? .band(band.id) : .thought(remaining[min(index, remaining.count - 1)])
    }
}

/// The panel keeps the selected model separate from how it was selected. This
/// lets keyboard users receive a visible focus treatment without making a
/// pointer click look selected.
struct PanelSelection: Equatable {
    enum Target: Hashable { case band(UUID), thought(UUID), addThought(UUID) }
    enum InputModality { case keyboard, pointer }

    var target: Target?
    var modality: InputModality = .pointer

    var thoughtID: UUID? {
        guard case .thought(let id) = target else { return nil }
        return id
    }

    var bandID: UUID? {
        switch target {
        case .band(let id), .addThought(let id): return id
        default: return nil
        }
    }

    var showsKeyboardFocus: Bool { target != nil && modality == .keyboard }

    mutating func select(_ target: Target?, with modality: InputModality) {
        self.target = target
        self.modality = modality
    }

    static func nextIndex(current: Int?, direction: PanelMoveDirection, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let index = current ?? (direction == .down ? -1 : count)
        return max(0, min(count - 1, index + (direction == .down ? 1 : -1)))
    }
}

enum PanelCommand: String, CaseIterable {
    case quickCapture, newThought, newBand, openSettings
    case copy, editDescription
    case complete, edit, resetAging, move, moveEarlier, moveLater, destructive

    var title: String {
        switch self {
        case .quickCapture: "Quick Capture"
        case .newThought: "New Thought"
        case .newBand: "New Band"
        case .openSettings: "Settings…"
        case .copy: "Copy Thought"
        case .editDescription: "Edit Description"
        case .complete: "Complete Thought"
        case .edit: "Edit"
        case .resetAging: "Reset Aging"
        case .move: "Move Thought…"
        case .moveEarlier: "Move Earlier"
        case .moveLater: "Move Later"
        case .destructive: "Release or Delete"
        }
    }

    var shortcut: String {
        switch self {
        case .quickCapture: "⌥Q"
        case .newThought: "⌘N"
        case .newBand: "⇧⌘N"
        case .openSettings: "⌘,"
        case .copy: "⌘C"
        case .editDescription: "⇧⌘D"
        case .complete: "⌘↩"
        case .edit: "↩"
        case .resetAging: "⌥⌘R"
        case .move: "⌥⌘M"
        case .moveEarlier: "⌥⌘["
        case .moveLater: "⌥⌘]"
        case .destructive: "⌘⌫"
        }
    }

    static let reference: [PanelCommand] = [.quickCapture, .newThought, .newBand, .copy, .editDescription, .complete, .edit, .resetAging, .move, .moveEarlier, .moveLater, .destructive, .openSettings]
}

enum BandsCommandDispatcher {
    static let notification = Notification.Name("bands.panelCommand")

    static func perform(_ command: PanelCommand) {
        NotificationCenter.default.post(name: notification, object: command)
    }
}

enum BandManagement {
    static func validateName(_ rawName: String, existingNames: [String], excluding excludedName: String? = nil) -> BandNameValidation {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .empty }
        let normalized = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let duplicate = existingNames.contains { existing in
            guard existing != excludedName else { return false }
            return existing.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) == normalized
        }
        return duplicate ? .duplicate : .valid(name)
    }

    static func reordered(_ bands: [Band], moving source: IndexSet, to destination: Int) -> [Band] {
        var result = bands
        result.move(fromOffsets: source, toOffset: destination)
        for (index, band) in result.enumerated() { band.order = index }
        return result
    }

    static func prepend(_ band: Band, to bands: [Band]) {
        bands.forEach { $0.order += 1 }
        band.order = 0
    }

    static func insert(_ band: Band, into bands: [Band], atEnd: Bool) {
        guard atEnd else {
            prepend(band, to: bands)
            return
        }
        band.order = (bands.map(\.order).max() ?? -1) + 1
    }

    static func capture(_ rawText: String, in band: Band?, context: ModelContext, now: Date) throws -> Thought? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let existing = try context.fetch(FetchDescriptor<Thought>())
            .filter { $0.band?.id == band?.id && $0.completedAt == nil && $0.releasedAt == nil }
        let orders = existing.compactMap(\.order)
        let order = InsertionPreferences.thoughtsAtEnd
            ? (orders.min() ?? 0) - 1
            : (orders.max() ?? 0) + 1
        let thought = Thought(text: text, band: band, order: order, createdAt: now)
        context.insert(thought)
        try context.save()
        BandsNotificationBus.thoughtChanged(thought.id)
        return thought
    }

    static func validateDropPayload(_ rawPayload: String, onto band: Band, thoughts: [Thought]) -> Thought? {
        guard let id = UUID(uuidString: rawPayload),
              let thought = thoughts.first(where: { $0.id == id }),
              thought.band?.id != band.id,
              thought.completedAt == nil,
              thought.releasedAt == nil else { return nil }
        return thought
    }
}

enum ThoughtManagement {
    static func edit(_ thought: Thought, rawText: String, now: Date) -> Bool {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        thought.text = text
        thought.updatedAt = now
        thought.lastTouchedAt = now
        return true
    }

    static func resetAging(_ thought: Thought, now: Date) {
        thought.agingResetAt = now
        thought.lastTouchedAt = now
    }

    static func move(_ thought: Thought, to band: Band, now: Date) -> Bool {
        guard thought.band?.id != band.id else { return false }
        thought.band = band
        thought.lastTouchedAt = now
        return true
    }

    static func reorder(_ thought: Thought, to band: Band, among thoughts: [Thought], at index: Int, now: Date) {
        var ordered = thoughts.filter { $0.id != thought.id && $0.completedAt == nil && $0.releasedAt == nil }
        let destination = max(0, min(index, ordered.count))
        ordered.insert(thought, at: destination)
        for (index, item) in ordered.enumerated() {
            item.order = ordered.count - index
        }
        thought.band = band
        thought.lastTouchedAt = now
    }

    static func moveWithinBand(_ thought: Thought, among thoughts: [Thought], direction: PanelMoveDirection, now: Date) -> Bool {
        guard let current = thoughts.firstIndex(where: { $0.id == thought.id }) else { return false }
        let destination = direction == .up ? current - 1 : current + 1
        guard thoughts.indices.contains(destination) else { return false }
        reorder(thought, to: thought.band!, among: thoughts, at: destination, now: now)
        return true
    }

    static func complete(_ thought: Thought, now: Date) {
        thought.completedAt = now
        thought.lastTouchedAt = now
    }

    static func letGo(_ thought: Thought, now: Date) {
        thought.releasedAt = now
        thought.lastTouchedAt = now
    }
}

enum ThoughtAging {
    static let hour: TimeInterval = 3_600
    static let day: TimeInterval = 24 * hour
    static func referenceDate(for thought: Thought) -> Date {
        max(thought.createdAt, thought.agingResetAt ?? .distantPast)
    }
    static func age(for thought: Thought, settings: ThoughtAgingSettings = .defaults, now: Date = .now) -> ThoughtAge {
        let hours = max(0, now.timeIntervalSince(referenceDate(for: thought)) / hour)
        let warmHours = Double(settings.warmMinutes) / 60
        let attentionHours = Double(settings.attentionMinutes) / 60
        let oldHours = Double(settings.oldMinutes) / 60
        switch hours {
        case ..<warmHours: return .fresh
        case ..<attentionHours: return .warm
        case ..<oldHours: return .attention
        default: return .old
        }
    }
    static func label(for thought: Thought, settings: ThoughtAgingSettings = .defaults, now: Date = .now) -> String? {
        let elapsed = max(0, now.timeIntervalSince(referenceDate(for: thought)))
        guard elapsed >= Double(settings.warmMinutes) * 60 else { return nil }
        if elapsed < day { return "\(max(1, Int(elapsed / hour)))h" }
        if elapsed < 7 * day { return "\(max(1, Int(elapsed / day)))d" }
        return "\(max(1, Int(elapsed / (7 * day))))w"
    }
}

enum ThoughtTimestamp {
    static let minute: TimeInterval = 60
    static let hour: TimeInterval = 60 * minute
    static let day: TimeInterval = 24 * hour
    static let week: TimeInterval = 7 * day
    static let month: TimeInterval = 30 * day
    static let year: TimeInterval = 365 * day

    static func label(since date: Date, now: Date = .now) -> String {
        let elapsed = max(0, now.timeIntervalSince(date))
        guard elapsed >= minute else { return "now" }

        if elapsed < hour {
            return "\(max(1, Int((elapsed / minute).rounded())))m"
        }
        if elapsed < day {
            let minutes = Int((elapsed / minute).rounded())
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        if elapsed < week {
            let hours = Int((elapsed / hour).rounded())
            return "\(hours / 24)d \(hours % 24)h"
        }
        if elapsed < month {
            let days = Int((elapsed / day).rounded())
            return "\(days / 7)w \(days % 7)d"
        }
        if elapsed < year {
            let days = Int((elapsed / day).rounded())
            return "\(days / 30)mo \(days % 30)d"
        }

        let months = Int((elapsed / month).rounded())
        return "\(months / 12)y \(months % 12)mo"
    }
}
