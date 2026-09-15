import XCTest
@testable import lanes

@MainActor
final class ThoughtAgingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testDefaultsAreExactlyOneFiveTwelveTwentyFourHours() {
        XCTAssertEqual(ThoughtAgingSettings.defaults, .init(freshMinutes: 60, warmMinutes: 300, attentionMinutes: 720, oldMinutes: 1_440))
        XCTAssertTrue(ThoughtAgingSettings.defaults.isValid)
    }

    func testStrictOrderingValidation() {
        XCTAssertFalse(ThoughtAgingSettings(freshMinutes: 0, warmMinutes: 300, attentionMinutes: 720, oldMinutes: 1_440).isValid)
        XCTAssertFalse(ThoughtAgingSettings(freshMinutes: 300, warmMinutes: 300, attentionMinutes: 720, oldMinutes: 1_440).isValid)
        XCTAssertFalse(ThoughtAgingSettings(freshMinutes: 60, warmMinutes: 720, attentionMinutes: 720, oldMinutes: 1_440).isValid)
        XCTAssertFalse(ThoughtAgingSettings(freshMinutes: 60, warmMinutes: 300, attentionMinutes: 1_440, oldMinutes: 1_440).isValid)
        XCTAssertTrue(ThoughtAgingSettings(freshMinutes: 135, warmMinutes: 390, attentionMinutes: 795, oldMinutes: 1_800).isValid)
    }

    func testSettingsPersistAndRoundTrip() {
        let suiteName = "lanes.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ThoughtAgingSettingsStore(defaults: defaults)
        let customized = ThoughtAgingSettings(freshMinutes: 120, warmMinutes: 420, attentionMinutes: 1_080, oldMinutes: 2_160)
        store.update(customized)
        XCTAssertEqual(ThoughtAgingSettingsStore(defaults: defaults).settings, customized)
        store.update(.init(freshMinutes: 420, warmMinutes: 120, attentionMinutes: 1_080, oldMinutes: 2_160))
        XCTAssertEqual(store.settings, customized)
    }

    func testClassificationUsesCreatedAtAndEveryBoundary() {
        let settings = ThoughtAgingSettings.defaults
        let thought = Thought(text: "Remember", createdAt: now)
        for (hours, expected) in [(0.0, ThoughtAge.fresh), (1.0, ThoughtAge.fresh), (4.99, ThoughtAge.fresh), (5.0, ThoughtAge.warm), (11.99, ThoughtAge.warm), (12.0, ThoughtAge.attention), (23.99, ThoughtAge.attention), (24.0, ThoughtAge.old)] {
            thought.createdAt = now.addingTimeInterval(-hours * ThoughtAging.hour)
            XCTAssertEqual(ThoughtAging.age(for: thought, settings: settings, now: now), expected, "at \(hours)h")
        }
        thought.lastTouchedAt = now
        thought.createdAt = now.addingTimeInterval(-24 * ThoughtAging.hour)
        XCTAssertEqual(ThoughtAging.age(for: thought, settings: settings, now: now), .old)
    }

    func testNeutralBufferHasNoAgeLabel() {
        let thought = Thought(text: "Buffer", createdAt: now.addingTimeInterval(-3 * ThoughtAging.hour))
        XCTAssertEqual(ThoughtAging.age(for: thought, settings: .defaults, now: now), .fresh)
        XCTAssertNil(ThoughtAging.label(for: thought, settings: .defaults, now: now))
    }

    func testLabelsUseHoursBeforeDaysAndWeeks() {
        let thought = Thought(text: "Labels", createdAt: now)
        for (elapsed, expected) in [(5 * ThoughtAging.hour, "5h"), (12 * ThoughtAging.hour, "12h"), (ThoughtAging.day, "1d"), (7 * ThoughtAging.day, "1w")] {
            thought.createdAt = now.addingTimeInterval(-elapsed)
            XCTAssertEqual(ThoughtAging.label(for: thought, settings: .defaults, now: now), expected)
        }
    }

    func testFutureCreationDateIsFreshAndHasNoLabel() {
        let thought = Thought(text: "Future", createdAt: now.addingTimeInterval(3 * ThoughtAging.day))
        XCTAssertEqual(ThoughtAging.age(for: thought, now: now), .fresh)
        XCTAssertNil(ThoughtAging.label(for: thought, now: now))
    }

    func testNotificationPlannerUsesAgingResetAndOnlyFutureTransitions() {
        let settings = ThoughtAgingSettings.defaults
        let reset = now
        let thought = Thought(text: "Reminder", createdAt: now.addingTimeInterval(-2 * ThoughtAging.day))
        thought.agingResetAt = reset
        let events = ThoughtNotificationPlanner.events(for: thought, settings: settings, now: now)
        XCTAssertEqual(events.map(\.age), [.warm, .attention, .old])
        XCTAssertEqual(events.map(\.date), [reset.addingTimeInterval(300 * 60), reset.addingTimeInterval(720 * 60), reset.addingTimeInterval(1_440 * 60)])
    }

    func testNotificationPlannerSkipsCompletedReleasedAndPastTransitions() {
        let thought = Thought(text: "Done", createdAt: now.addingTimeInterval(-2 * ThoughtAging.day))
        XCTAssertTrue(ThoughtNotificationPlanner.events(for: thought, settings: .defaults, now: now).isEmpty)
        thought.completedAt = now
        XCTAssertTrue(ThoughtNotificationPlanner.events(for: thought, settings: .defaults, now: now).isEmpty)
        thought.completedAt = nil
        thought.releasedAt = now
        XCTAssertTrue(ThoughtNotificationPlanner.events(for: thought, settings: .defaults, now: now).isEmpty)
    }

    func testResetAgingMakesAnOldThoughtFreshWithoutChangingCreationTimestamp() {
        let created = now.addingTimeInterval(-2 * ThoughtAging.day)
        let thought = Thought(text: "Reset me", createdAt: created)
        XCTAssertEqual(ThoughtAging.age(for: thought, now: now), .old)

        let reset = now.addingTimeInterval(-30 * ThoughtAging.hour / 60)
        ThoughtManagement.resetAging(thought, now: reset)

        XCTAssertEqual(thought.createdAt, created)
        XCTAssertEqual(thought.agingResetAt, reset)
        XCTAssertEqual(ThoughtAging.age(for: thought, now: now), .fresh)
        XCTAssertNil(ThoughtAging.label(for: thought, now: now))
    }

    func testTimestampUsesRoundedMinutesThenHoursAndMinutes() {
        XCTAssertEqual(ThoughtTimestamp.label(since: now.addingTimeInterval(-45), now: now), "now")
        XCTAssertEqual(ThoughtTimestamp.label(since: now.addingTimeInterval(-60), now: now), "1m")
        XCTAssertEqual(ThoughtTimestamp.label(since: now.addingTimeInterval(-90), now: now), "2m")
        XCTAssertEqual(ThoughtTimestamp.label(since: now.addingTimeInterval(-(3 * 3_600 + 14 * 60 + 31)), now: now), "3h 15m")
    }

    func testThoughtStateTransitionsUpdatePersistedFieldsDeterministically() {
        let source = Lane(name: "Source", order: 0); let target = Lane(name: "Target", order: 1)
        let created = Date(timeIntervalSince1970: 10); let thought = Thought(text: "Old", lane: source, createdAt: created)
        XCTAssertTrue(ThoughtManagement.edit(thought, rawText: " New ", now: Date(timeIntervalSince1970: 20)))
        XCTAssertTrue(ThoughtManagement.move(thought, to: target, now: Date(timeIntervalSince1970: 30)))
        ThoughtManagement.complete(thought, now: Date(timeIntervalSince1970: 40))
        XCTAssertEqual(thought.completedAt, Date(timeIntervalSince1970: 40))
    }
}
