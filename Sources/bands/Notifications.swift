import Foundation
import SwiftData
@preconcurrency import UserNotifications

enum ThoughtNotificationSettings {
    static let enabledKey = "notifications.enabled"
    static let defaultEnabled = true
}

struct ThoughtNotificationEvent: Equatable {
    let thoughtID: UUID
    let text: String
    let age: ThoughtAge
    let date: Date

    var identifier: String { "thought-age-\(thoughtID.uuidString)-\(age.identifierValue)" }
}

enum ThoughtNotificationPlanner {
    static func events(for thought: Thought, settings: ThoughtAgingSettings, now: Date = .now) -> [ThoughtNotificationEvent] {
        guard thought.completedAt == nil, thought.releasedAt == nil else { return [] }
        return events(thoughtID: thought.id, text: thought.text, referenceDate: ThoughtAging.referenceDate(for: thought), settings: settings, now: now)
    }

    static func events(thoughtID: UUID, text: String = "", referenceDate: Date, settings: ThoughtAgingSettings, now: Date = .now) -> [ThoughtNotificationEvent] {
        let transitions: [(ThoughtAge, Int)] = [(.warm, settings.warmMinutes), (.attention, settings.attentionMinutes), (.old, settings.oldMinutes)]
        return transitions.compactMap { age, minutes in
            let date = referenceDate.addingTimeInterval(Double(minutes) * 60)
            return date > now ? ThoughtNotificationEvent(thoughtID: thoughtID, text: text, age: age, date: date) : nil
        }
    }

    static func identifiers(for thoughtID: UUID) -> [String] {
        ThoughtAge.allCases.map { "thought-age-\(thoughtID.uuidString)-\($0.identifierValue)" }
    }
}

extension ThoughtAge: CaseIterable {
    static var allCases: [ThoughtAge] { [.fresh, .warm, .attention, .old] }
    var identifierValue: String {
        switch self { case .fresh: "fresh"; case .warm: "warm"; case .attention: "attention"; case .old: "old" }
    }
}

extension Notification.Name {
    static let bandsThoughtChanged = Notification.Name("bands.thoughtChanged")
    static let bandsThoughtsChanged = Notification.Name("bands.thoughtsChanged")
    static let bandsAgingSettingsChanged = Notification.Name("bands.agingSettingsChanged")
    static let bandsNotificationPreferenceChanged = Notification.Name("bands.notificationPreferenceChanged")
}

enum BandsNotificationBus {
    static func thoughtChanged(_ id: UUID) {
        NotificationCenter.default.post(name: .bandsThoughtChanged, object: nil, userInfo: ["thoughtID": id])
    }

    static func allThoughtsChanged() {
        NotificationCenter.default.post(name: .bandsThoughtsChanged, object: nil)
    }
}

@MainActor
final class BandsNotificationCoordinator {
    private let container: ModelContainer
    private let center = UNUserNotificationCenter.current()
    private var work: Task<Void, Never>?
    private var generation = 0
    private var observers: [NSObjectProtocol] = []

    init(container: ModelContainer) {
        self.container = container
        UserDefaults.standard.register(defaults: [ThoughtNotificationSettings.enabledKey: ThoughtNotificationSettings.defaultEnabled])
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .bandsThoughtChanged, object: nil, queue: .main) { [weak self] note in
            guard let id = note.userInfo?["thoughtID"] as? UUID else { return }
            Task { @MainActor in self?.refresh(thoughtID: id) }
        })
        observers.append(nc.addObserver(forName: .bandsThoughtsChanged, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.rebuild() } })
        observers.append(nc.addObserver(forName: .bandsAgingSettingsChanged, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.rebuild() } })
        observers.append(nc.addObserver(forName: .bandsNotificationPreferenceChanged, object: nil, queue: .main) { [weak self] note in
            let enabled = note.userInfo?["enabled"] as? Bool ?? false
            Task { @MainActor in self?.preferenceChanged(enabled: enabled) }
        })
    }

    func start() {
        guard UserDefaults.standard.bool(forKey: ThoughtNotificationSettings.enabledKey) else { return }
        Task { [weak self] in
            guard let self else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            rebuild()
        }
    }

    func preferenceChanged(enabled: Bool) {
        guard enabled else {
            generation += 1; work?.cancel(); work = nil
            center.removeAllPendingNotificationRequests()
            return
        }
        start()
    }

    private func refresh(thoughtID: UUID) {
        guard UserDefaults.standard.bool(forKey: ThoughtNotificationSettings.enabledKey) else { return }
        generation += 1; work?.cancel()
        let currentGeneration = generation
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Thought>(predicate: #Predicate { $0.id == thoughtID })
        let thought = try? context.fetch(descriptor).first
        let events = thought.map { ThoughtNotificationPlanner.events(for: $0, settings: ThoughtAgingSettingsStore.shared.settings) } ?? []
        work = Task { [weak self] in await self?.apply(events, for: thoughtID, generation: currentGeneration) }
    }

    private func rebuild() {
        guard UserDefaults.standard.bool(forKey: ThoughtNotificationSettings.enabledKey) else { return }
        generation += 1; work?.cancel()
        let currentGeneration = generation
        let context = ModelContext(container)
        let snapshots = ((try? context.fetch(FetchDescriptor<Thought>())) ?? []).filter { $0.completedAt == nil && $0.releasedAt == nil }.map {
            (id: $0.id, text: $0.text, events: ThoughtNotificationPlanner.events(for: $0, settings: ThoughtAgingSettingsStore.shared.settings))
        }
        work = Task { [weak self] in await self?.apply(snapshots.flatMap { $0.events }, for: nil, generation: currentGeneration) }
    }

    private func apply(_ events: [ThoughtNotificationEvent], for thoughtID: UUID?, generation: Int) async {
        guard generation == self.generation else { return }
        if let thoughtID { center.removePendingNotificationRequests(withIdentifiers: ThoughtNotificationPlanner.identifiers(for: thoughtID)) }
        else { center.removeAllPendingNotificationRequests() }
        for event in events {
            guard generation == self.generation else { return }
            let content = UNMutableNotificationContent()
            content.title = event.age.notificationTitle
            content.body = event.text
            let interval = max(1, event.date.timeIntervalSinceNow)
            let request = UNNotificationRequest(identifier: event.identifier, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
            try? await center.add(request)
        }
    }
}

private extension ThoughtAge {
    var notificationTitle: String {
        switch self { case .warm: "Thought is warming up"; case .attention: "Thought needs attention"; case .old: "Thought is getting old"; case .fresh: "Thought is fresh" }
    }
}
