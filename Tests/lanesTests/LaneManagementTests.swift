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

    func testLaneDescriptionPersists() throws {
        let context = try makeContext()
        let lane = Lane(name: "Work", descriptionText: "Projects, coding, and professional ideas", order: 0)
        context.insert(lane)
        try context.save()

        let persisted = try XCTUnwrap(try context.fetch(FetchDescriptor<Lane>()).first)
        XCTAssertEqual(persisted.descriptionText, "Projects, coding, and professional ideas")
    }

    func testMCPLanePayloadIncludesDescription() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Lane.self, Thought.self, configurations: configuration)
        let context = ModelContext(container)
        context.insert(Lane(name: "Work", descriptionText: "Projects and coding", order: 0))
        try context.save()

        let result = LanesCommandService(container: container).call(name: "lanes/list", arguments: [:])
        let lanes = try XCTUnwrap(result["lanes"] as? [[String: Any]])
        XCTAssertEqual(lanes.first?["description"] as? String, "Projects and coding")
    }

    func testJevCriteriaUsesOnlyLaneNamesAndDescriptions() {
        let lane = Lane(name: "Work", descriptionText: "Projects and coding", order: 0)
        let criteria = JevClient.criteria(for: [lane])

        XCTAssertEqual(criteria[lane.id.uuidString], "Work: Projects and coding")
        XCTAssertEqual(criteria.count, 1)
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

    func testAppendingLanePlacesItLast() {
        let first = Lane(name: "First", order: 0)
        let second = Lane(name: "Second", order: 1)
        let newLane = Lane(name: "New", order: 99)
        LaneManagement.insert(newLane, into: [first, second], atEnd: true)
        XCTAssertEqual(newLane.order, 2)
        XCTAssertEqual(first.order, 0)
        XCTAssertEqual(second.order, 1)
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

    func testKeyboardSelectionIsOnlyVisibleForKeyboardInput() {
        let id = UUID()
        var selection = PanelSelection()
        selection.select(.thought(id), with: .pointer)
        XCTAssertFalse(selection.showsKeyboardFocus)
        selection.select(.thought(id), with: .keyboard)
        XCTAssertTrue(selection.showsKeyboardFocus)
        XCTAssertEqual(selection.thoughtID, id)
    }

    func testBoardArrowsRespectLaneBoundariesAndEmptyLanes() {
        let a = UUID(), b = UUID(), c = UUID(), x = UUID(), y = UUID(), z = UUID()
        let lanes = [BoardLane(id: a, thoughts: [x, y]), BoardLane(id: b, thoughts: []), BoardLane(id: c, thoughts: [z])]
        XCTAssertEqual(BoardNavigation.target(from: nil, direction: .down, lanes: lanes), .lane(a))
        XCTAssertEqual(BoardNavigation.target(from: .lane(a), direction: .right, lanes: lanes), .addThought(a))
        XCTAssertEqual(BoardNavigation.target(from: .addThought(a), direction: .right, lanes: lanes), .thought(x))
        XCTAssertEqual(BoardNavigation.target(from: .thought(x), direction: .left, lanes: lanes), .addThought(a))
        XCTAssertEqual(BoardNavigation.target(from: .thought(y), direction: .right, lanes: lanes), .thought(y))
        XCTAssertEqual(BoardNavigation.target(from: .thought(y), direction: .down, lanes: lanes), .addThought(b))
        XCTAssertEqual(BoardNavigation.target(from: .lane(b), direction: .right, lanes: lanes), .addThought(b))
        XCTAssertEqual(BoardNavigation.target(from: .addThought(b), direction: .left, lanes: lanes), .lane(b))
        XCTAssertEqual(BoardNavigation.target(from: .lane(b), direction: .down, lanes: lanes), .lane(c))
        XCTAssertEqual(BoardNavigation.target(from: .thought(z), direction: .down, lanes: lanes), .thought(z))
        XCTAssertNil(BoardNavigation.target(from: nil, direction: .left, lanes: []))
    }

    func testVerticalNavigationPreservesThoughtColumnAndClampsShortLanes() {
        let a = UUID(), b = UUID(), x = UUID(), y = UUID(), z = UUID()
        let lanes = [BoardLane(id: a, thoughts: [x, y]), BoardLane(id: b, thoughts: [z])]
        XCTAssertEqual(BoardNavigation.target(from: .thought(y), direction: .down, lanes: lanes), .thought(z))
        XCTAssertEqual(BoardNavigation.target(from: .thought(z), direction: .up, lanes: lanes), .thought(x))
        XCTAssertEqual(BoardNavigation.target(from: .lane(b), direction: .up, lanes: lanes), .lane(a))
    }

    func testRemovalRecoveryIsLocalAndSelectsNextThenPreviousThenHeader() {
        let a = UUID(), x = UUID(), y = UUID(), z = UUID()
        let lane = BoardLane(id: a, thoughts: [x, y, z])
        XCTAssertEqual(BoardNavigation.afterRemoving(y, from: lane), .thought(z))
        XCTAssertEqual(BoardNavigation.afterRemoving(z, from: lane), .thought(y))
        XCTAssertEqual(BoardNavigation.afterRemoving(x, from: BoardLane(id: a, thoughts: [x])), .lane(a))
    }

    func testCommandMatchingUsesExactModifiers() throws {
        func event(_ flags: NSEvent.ModifierFlags, _ key: UInt16, _ characters: String) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: key))
        }
        XCTAssertEqual(PanelCommand.matching(try event(.command, 45, "n")), .newThought)
        XCTAssertEqual(PanelCommand.matching(try event(.command, 8, "c")), .copy)
        XCTAssertEqual(PanelCommand.matching(try event([.command, .shift], 45, "N")), .newLane)
        XCTAssertEqual(PanelCommand.matching(try event([.command, .shift], 2, "D")), .editDescription)
        XCTAssertEqual(PanelCommand.matching(try event(.command, 36, "\r")), .complete)
        XCTAssertEqual(PanelCommand.matching(try event([], 36, "\r")), .edit)
        XCTAssertNil(PanelCommand.matching(try event([.command, .control], 45, "n")))
        XCTAssertNil(PanelCommand.matching(try event([], 45, "n")))
    }

    func testKeyboardThoughtReorderingMovesOnlyWhenThereIsAnAdjacentThought() {
        let lane = Lane(name: "Work", order: 0)
        let first = Thought(text: "First", lane: lane, order: 3)
        let second = Thought(text: "Second", lane: lane, order: 2)
        let third = Thought(text: "Third", lane: lane, order: 1)
        XCTAssertTrue(ThoughtManagement.moveWithinLane(second, among: [first, second, third], direction: .up, now: .now))
        XCTAssertEqual([first, second, third].sorted { ($0.order ?? 0) > ($1.order ?? 0) }.map(\.text), ["Second", "First", "Third"])
        XCTAssertFalse(ThoughtManagement.moveWithinLane(second, among: [second, first, third], direction: .up, now: .now))
    }
}
