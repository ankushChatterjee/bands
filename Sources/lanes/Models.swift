import Foundation
import Combine
import SwiftData

@Model final class Lane {
    var id: UUID
    var name: String
    var order: Int
    var createdAt: Date

    init(id: UUID = UUID(), name: String, order: Int, createdAt: Date = .now) {
        self.id = id; self.name = name; self.order = order; self.createdAt = createdAt
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
    var completedAt: Date?
    var releasedAt: Date?
    var lane: Lane?

    init(id: UUID = UUID(), text: String, lane: Lane? = nil, order: Int? = nil, createdAt: Date = .now) {
        self.id = id; self.text = text; self.order = order; self.lane = lane; self.createdAt = createdAt
        self.updatedAt = createdAt; self.lastTouchedAt = createdAt
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
    }

    func restoreDefaults() { update(.defaults) }
}

enum LaneNameValidation: Equatable {
    case valid(String)
    case empty
    case duplicate
}

enum PanelMoveDirection { case up, down }

enum PanelSelection {
    static func nextIndex(current: Int?, direction: PanelMoveDirection, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let index = current ?? (direction == .down ? -1 : count)
        return max(0, min(count - 1, index + (direction == .down ? 1 : -1)))
    }
}

enum LaneManagement {
    static let defaultNames = ["Work", "Home", "Ideas"]

    @discardableResult
    static func seedDefaultsIfNeeded(in context: ModelContext, names: [String] = defaultNames, now: Date = .now) throws -> [Lane] {
        let existing = try context.fetch(FetchDescriptor<Lane>(sortBy: [SortDescriptor(\Lane.order)]))
        guard existing.isEmpty else { return existing }
        for (order, name) in names.enumerated() {
            context.insert(Lane(name: name, order: order, createdAt: now))
        }
        try context.save()
        return try context.fetch(FetchDescriptor<Lane>(sortBy: [SortDescriptor(\Lane.order)]))
    }

    static func validateName(_ rawName: String, existingNames: [String], excluding excludedName: String? = nil) -> LaneNameValidation {
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

    static func reordered(_ lanes: [Lane], moving source: IndexSet, to destination: Int) -> [Lane] {
        var result = lanes
        result.move(fromOffsets: source, toOffset: destination)
        for (index, lane) in result.enumerated() { lane.order = index }
        return result
    }

    static func prepend(_ lane: Lane, to lanes: [Lane]) {
        lanes.forEach { $0.order += 1 }
        lane.order = 0
    }

    static func capture(_ rawText: String, in lane: Lane?, context: ModelContext, now: Date) throws -> Thought? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let thought = Thought(text: text, lane: lane, createdAt: now)
        context.insert(thought)
        try context.save()
        return thought
    }

    static func validateDropPayload(_ rawPayload: String, onto lane: Lane, thoughts: [Thought]) -> Thought? {
        guard let id = UUID(uuidString: rawPayload),
              let thought = thoughts.first(where: { $0.id == id }),
              thought.lane?.id != lane.id,
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

    static func move(_ thought: Thought, to lane: Lane, now: Date) -> Bool {
        guard thought.lane?.id != lane.id else { return false }
        thought.lane = lane
        thought.lastTouchedAt = now
        return true
    }

    static func reorder(_ thought: Thought, to lane: Lane, among thoughts: [Thought], at index: Int, now: Date) {
        var ordered = thoughts.filter { $0.id != thought.id && $0.completedAt == nil && $0.releasedAt == nil }
        let destination = max(0, min(index, ordered.count))
        ordered.insert(thought, at: destination)
        for (index, item) in ordered.enumerated() {
            item.order = ordered.count - index
        }
        thought.lane = lane
        thought.lastTouchedAt = now
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
    static func age(for thought: Thought, settings: ThoughtAgingSettings = .defaults, now: Date = .now) -> ThoughtAge {
        let hours = max(0, now.timeIntervalSince(thought.createdAt) / hour)
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
        let elapsed = max(0, now.timeIntervalSince(thought.createdAt))
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
