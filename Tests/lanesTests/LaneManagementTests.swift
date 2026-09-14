import XCTest
import AppKit
import SwiftData
@testable import lanes

@MainActor
final class LaneManagementTests: XCTestCase {
    func testPanelPositioningCentersBelowStatusItemAndClampsToVisibleFrame() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = PanelPositioning.origin(panelSize: CGSize(width: 780, height: 430),
                                              buttonFrame: CGRect(x: 1360, y: 860, width: 24, height: 24),
                                              visibleFrame: visible)
        XCTAssertEqual(origin.x, 652, accuracy: 0.001)
        XCTAssertEqual(origin.y, 424, accuracy: 0.001)
    }

    func testPanelPositioningClampsWhenPanelWouldExceedVisibleBounds() {
        let visible = CGRect(x: 100, y: 80, width: 500, height: 400)
        let origin = PanelPositioning.origin(panelSize: CGSize(width: 780, height: 600),
                                              buttonFrame: CGRect(x: 300, y: 450, width: 20, height: 20),
                                              visibleFrame: visible)
        XCTAssertEqual(origin, CGPoint(x: 108, y: 88))
    }

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: Lane.self, Thought.self, configurations: configuration))
    }

    func testFreshStoreStartsWithNoLanes() throws {
        let context = try makeContext()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Lane>()), 0)
    }

    func testTopAndInlineCapturePersistToTheRequestedLane() throws {
        let context = try makeContext()
        let lanes = [
            Lane(name: "First", order: 0, createdAt: .init(timeIntervalSince1970: 0)),
            Lane(name: "Second", order: 1, createdAt: .init(timeIntervalSince1970: 0)),
            Lane(name: "Third", order: 2, createdAt: .init(timeIntervalSince1970: 0))
        ]
        lanes.forEach(context.insert)
        try context.save()
        let top = try XCTUnwrap(LaneManagement.capture(" top ", in: lanes[0], context: context, now: .init(timeIntervalSince1970: 10)))
        let inline = try XCTUnwrap(LaneManagement.capture("inline", in: lanes[2], context: context, now: .init(timeIntervalSince1970: 20)))
        let persisted = try context.fetch(FetchDescriptor<Thought>())
        XCTAssertEqual(persisted.first(where: { $0.id == top.id })?.lane?.id, lanes[0].id)
        XCTAssertEqual(persisted.first(where: { $0.id == inline.id })?.lane?.id, lanes[2].id)
        XCTAssertEqual(top.text, "top")
        XCTAssertNil(try LaneManagement.capture("  \n", in: lanes[0], context: context, now: .now))
    }

    func testNamesAreTrimmedAndCaseInsensitiveDuplicatesAreRejected() {
        XCTAssertEqual(LaneManagement.validateName("  Work  ", existingNames: ["Home"]), .valid("Work"))
        XCTAssertEqual(LaneManagement.validateName(" home ", existingNames: ["Home"]), .duplicate)
        XCTAssertEqual(LaneManagement.validateName("   ", existingNames: []), .empty)
    }

    func testRenameMayKeepItsExistingNameButNotAnotherLaneName() {
        XCTAssertEqual(LaneManagement.validateName("Work", existingNames: ["Work", "Home"], excluding: "Work"), .valid("Work"))
        XCTAssertEqual(LaneManagement.validateName("Home", existingNames: ["Work", "Home"], excluding: "Work"), .duplicate)
    }

    func testReorderingRewritesContiguousPersistentOrders() {
        let first = Lane(name: "First", order: 0)
        let second = Lane(name: "Second", order: 1)
        let third = Lane(name: "Third", order: 2)
        let result = LaneManagement.reordered([first, second, third], moving: IndexSet(integer: 0), to: 3)
        XCTAssertEqual(result.map(\.name), ["Second", "Third", "First"])
        XCTAssertEqual(result.map(\.order), [0, 1, 2])
    }

    func testPrependingLanePlacesItFirstAndShiftsExistingOrders() {
        let first = Lane(name: "First", order: 0)
        let second = Lane(name: "Second", order: 1)
        let newLane = Lane(name: "New", order: 99)
        LaneManagement.prepend(newLane, to: [first, second])
        XCTAssertEqual(newLane.order, 0)
        XCTAssertEqual(first.order, 1)
        XCTAssertEqual(second.order, 2)
    }

    func testReorderingPersistsOrder() throws {
        let context = try makeContext()
        let lanes = [Lane(name: "A", order: 0), Lane(name: "B", order: 1), Lane(name: "C", order: 2)]
        lanes.forEach(context.insert)
        try context.save()
        _ = LaneManagement.reordered(lanes, moving: IndexSet(integer: 0), to: 3)
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<Lane>(sortBy: [SortDescriptor(\.order)]))
        XCTAssertEqual(fetched.map(\.name), ["B", "C", "A"])
        XCTAssertEqual(fetched.map(\.order), [0, 1, 2])
    }

    func testDropPayloadRequiresValidUnfinishedThoughtFromAnotherLane() {
        let source = Lane(name: "Source", order: 0)
        let target = Lane(name: "Target", order: 1)
        let thought = Thought(text: "Move", lane: source)
        XCTAssertEqual(LaneManagement.validateDropPayload(thought.id.uuidString, onto: target, thoughts: [thought])?.id, thought.id)
        XCTAssertNil(LaneManagement.validateDropPayload("not-an-id", onto: target, thoughts: [thought]))
        XCTAssertNil(LaneManagement.validateDropPayload(thought.id.uuidString, onto: source, thoughts: [thought]))
        thought.completedAt = .now
        XCTAssertNil(LaneManagement.validateDropPayload(thought.id.uuidString, onto: target, thoughts: [thought]))
    }

    func testPanelSelectionStartsAtFirstOrLastItemAndClampsAtEdges() {
        XCTAssertEqual(PanelSelection.nextIndex(current: nil, direction: .down, count: 3), 0)
        XCTAssertEqual(PanelSelection.nextIndex(current: nil, direction: .up, count: 3), 2)
        XCTAssertEqual(PanelSelection.nextIndex(current: 0, direction: .up, count: 3), 0)
        XCTAssertEqual(PanelSelection.nextIndex(current: 2, direction: .down, count: 3), 2)
        XCTAssertNil(PanelSelection.nextIndex(current: nil, direction: .down, count: 0))
    }

    func testPanelSelectionMovesPredictablyBetweenThoughts() {
        XCTAssertEqual(PanelSelection.nextIndex(current: 0, direction: .down, count: 4), 1)
        XCTAssertEqual(PanelSelection.nextIndex(current: 2, direction: .up, count: 4), 1)
    }
}
