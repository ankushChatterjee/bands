import XCTest
import AppKit
import SwiftData
@testable import bands

@MainActor
final class BandManagementTests: XCTestCase {
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
        return ModelContext(try ModelContainer(for: Band.self, Thought.self, configurations: configuration))
    }

    func testFreshStoreStartsWithNoBands() throws {
        let context = try makeContext()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Band>()), 0)
    }

    func testBandDescriptionPersists() throws {
        let context = try makeContext()
        let band = Band(name: "Work", descriptionText: "Projects, coding, and professional ideas", order: 0)
        context.insert(band)
        try context.save()

        let persisted = try XCTUnwrap(try context.fetch(FetchDescriptor<Band>()).first)
        XCTAssertEqual(persisted.descriptionText, "Projects, coding, and professional ideas")
    }

    func testMCPBandPayloadIncludesDescription() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Band.self, Thought.self, configurations: configuration)
        let context = ModelContext(container)
        context.insert(Band(name: "Work", descriptionText: "Projects and coding", order: 0))
        try context.save()

        let result = BandsCommandService(container: container).call(name: "bands/list", arguments: [:])
        let bands = try XCTUnwrap(result["bands"] as? [[String: Any]])
        XCTAssertEqual(bands.first?["description"] as? String, "Projects and coding")
    }

    func testJevCriteriaUsesOnlyBandNamesAndDescriptions() {
        let band = Band(name: "Work", descriptionText: "Projects and coding", order: 0)
        let criteria = JevClient.criteria(for: [band])

        XCTAssertEqual(criteria[band.id.uuidString], "Work: Projects and coding")
        XCTAssertEqual(criteria.count, 1)
    }

    func testTopAndInlineCapturePersistToTheRequestedBand() throws {
        let context = try makeContext()
        let bands = [
            Band(name: "First", order: 0, createdAt: .init(timeIntervalSince1970: 0)),
            Band(name: "Second", order: 1, createdAt: .init(timeIntervalSince1970: 0)),
            Band(name: "Third", order: 2, createdAt: .init(timeIntervalSince1970: 0))
        ]
        bands.forEach(context.insert)
        try context.save()
        let top = try XCTUnwrap(BandManagement.capture(" top ", in: bands[0], context: context, now: .init(timeIntervalSince1970: 10)))
        let inline = try XCTUnwrap(BandManagement.capture("inline", in: bands[2], context: context, now: .init(timeIntervalSince1970: 20)))
        let persisted = try context.fetch(FetchDescriptor<Thought>())
        XCTAssertEqual(persisted.first(where: { $0.id == top.id })?.band?.id, bands[0].id)
        XCTAssertEqual(persisted.first(where: { $0.id == inline.id })?.band?.id, bands[2].id)
        XCTAssertEqual(top.text, "top")
        XCTAssertNil(try BandManagement.capture("  \n", in: bands[0], context: context, now: .now))
    }

    func testNamesAreTrimmedAndCaseInsensitiveDuplicatesAreRejected() {
        XCTAssertEqual(BandManagement.validateName("  Work  ", existingNames: ["Home"]), .valid("Work"))
        XCTAssertEqual(BandManagement.validateName(" home ", existingNames: ["Home"]), .duplicate)
        XCTAssertEqual(BandManagement.validateName("   ", existingNames: []), .empty)
    }

    func testRenameMayKeepItsExistingNameButNotAnotherBandName() {
        XCTAssertEqual(BandManagement.validateName("Work", existingNames: ["Work", "Home"], excluding: "Work"), .valid("Work"))
        XCTAssertEqual(BandManagement.validateName("Home", existingNames: ["Work", "Home"], excluding: "Work"), .duplicate)
    }

    func testReorderingRewritesContiguousPersistentOrders() {
        let first = Band(name: "First", order: 0)
        let second = Band(name: "Second", order: 1)
        let third = Band(name: "Third", order: 2)
        let result = BandManagement.reordered([first, second, third], moving: IndexSet(integer: 0), to: 3)
        XCTAssertEqual(result.map(\.name), ["Second", "Third", "First"])
        XCTAssertEqual(result.map(\.order), [0, 1, 2])
    }

    func testPrependingBandPlacesItFirstAndShiftsExistingOrders() {
        let first = Band(name: "First", order: 0)
        let second = Band(name: "Second", order: 1)
        let newBand = Band(name: "New", order: 99)
        BandManagement.prepend(newBand, to: [first, second])
        XCTAssertEqual(newBand.order, 0)
        XCTAssertEqual(first.order, 1)
        XCTAssertEqual(second.order, 2)
    }

    func testAppendingBandPlacesItLast() {
        let first = Band(name: "First", order: 0)
        let second = Band(name: "Second", order: 1)
        let newBand = Band(name: "New", order: 99)
        BandManagement.insert(newBand, into: [first, second], atEnd: true)
        XCTAssertEqual(newBand.order, 2)
        XCTAssertEqual(first.order, 0)
        XCTAssertEqual(second.order, 1)
    }

    func testReorderingPersistsOrder() throws {
        let context = try makeContext()
        let bands = [Band(name: "A", order: 0), Band(name: "B", order: 1), Band(name: "C", order: 2)]
        bands.forEach(context.insert)
        try context.save()
        _ = BandManagement.reordered(bands, moving: IndexSet(integer: 0), to: 3)
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<Band>(sortBy: [SortDescriptor(\.order)]))
        XCTAssertEqual(fetched.map(\.name), ["B", "C", "A"])
        XCTAssertEqual(fetched.map(\.order), [0, 1, 2])
    }

    func testDropPayloadRequiresValidUnfinishedThoughtFromAnotherBand() {
        let source = Band(name: "Source", order: 0)
        let target = Band(name: "Target", order: 1)
        let thought = Thought(text: "Move", band: source)
        XCTAssertEqual(BandManagement.validateDropPayload(thought.id.uuidString, onto: target, thoughts: [thought])?.id, thought.id)
        XCTAssertNil(BandManagement.validateDropPayload("not-an-id", onto: target, thoughts: [thought]))
        XCTAssertNil(BandManagement.validateDropPayload(thought.id.uuidString, onto: source, thoughts: [thought]))
        thought.completedAt = .now
        XCTAssertNil(BandManagement.validateDropPayload(thought.id.uuidString, onto: target, thoughts: [thought]))
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

    func testBoardArrowsRespectBandBoundariesAndEmptyBands() {
        let a = UUID(), b = UUID(), c = UUID(), x = UUID(), y = UUID(), z = UUID()
        let bands = [BoardBand(id: a, thoughts: [x, y]), BoardBand(id: b, thoughts: []), BoardBand(id: c, thoughts: [z])]
        XCTAssertEqual(BoardNavigation.target(from: nil, direction: .down, bands: bands), .band(a))
        XCTAssertEqual(BoardNavigation.target(from: .band(a), direction: .right, bands: bands), .addThought(a))
        XCTAssertEqual(BoardNavigation.target(from: .addThought(a), direction: .right, bands: bands), .thought(x))
        XCTAssertEqual(BoardNavigation.target(from: .thought(x), direction: .left, bands: bands), .addThought(a))
        XCTAssertEqual(BoardNavigation.target(from: .thought(y), direction: .right, bands: bands), .thought(y))
        XCTAssertEqual(BoardNavigation.target(from: .thought(y), direction: .down, bands: bands), .addThought(b))
        XCTAssertEqual(BoardNavigation.target(from: .band(b), direction: .right, bands: bands), .addThought(b))
        XCTAssertEqual(BoardNavigation.target(from: .addThought(b), direction: .left, bands: bands), .band(b))
        XCTAssertEqual(BoardNavigation.target(from: .band(b), direction: .down, bands: bands), .band(c))
        XCTAssertEqual(BoardNavigation.target(from: .thought(z), direction: .down, bands: bands), .thought(z))
        XCTAssertNil(BoardNavigation.target(from: nil, direction: .left, bands: []))
    }

    func testVerticalNavigationPreservesThoughtColumnAndClampsShortBands() {
        let a = UUID(), b = UUID(), x = UUID(), y = UUID(), z = UUID()
        let bands = [BoardBand(id: a, thoughts: [x, y]), BoardBand(id: b, thoughts: [z])]
        XCTAssertEqual(BoardNavigation.target(from: .thought(y), direction: .down, bands: bands), .thought(z))
        XCTAssertEqual(BoardNavigation.target(from: .thought(z), direction: .up, bands: bands), .thought(x))
        XCTAssertEqual(BoardNavigation.target(from: .band(b), direction: .up, bands: bands), .band(a))
    }

    func testRemovalRecoveryIsLocalAndSelectsNextThenPreviousThenHeader() {
        let a = UUID(), x = UUID(), y = UUID(), z = UUID()
        let band = BoardBand(id: a, thoughts: [x, y, z])
        XCTAssertEqual(BoardNavigation.afterRemoving(y, from: band), .thought(z))
        XCTAssertEqual(BoardNavigation.afterRemoving(z, from: band), .thought(y))
        XCTAssertEqual(BoardNavigation.afterRemoving(x, from: BoardBand(id: a, thoughts: [x])), .band(a))
    }

    func testCommandMatchingUsesExactModifiers() throws {
        func event(_ flags: NSEvent.ModifierFlags, _ key: UInt16, _ characters: String) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: key))
        }
        XCTAssertEqual(PanelCommand.matching(try event(.command, 45, "n")), .newThought)
        XCTAssertEqual(PanelCommand.matching(try event(.command, 8, "c")), .copy)
        XCTAssertEqual(PanelCommand.matching(try event([.command, .shift], 45, "N")), .newBand)
        XCTAssertEqual(PanelCommand.matching(try event([.command, .shift], 2, "D")), .editDescription)
        XCTAssertEqual(PanelCommand.matching(try event(.command, 36, "\r")), .complete)
        XCTAssertEqual(PanelCommand.matching(try event([], 36, "\r")), .edit)
        XCTAssertNil(PanelCommand.matching(try event([.command, .control], 45, "n")))
        XCTAssertNil(PanelCommand.matching(try event([], 45, "n")))
    }

    func testKeyboardThoughtReorderingMovesOnlyWhenThereIsAnAdjacentThought() {
        let band = Band(name: "Work", order: 0)
        let first = Thought(text: "First", band: band, order: 3)
        let second = Thought(text: "Second", band: band, order: 2)
        let third = Thought(text: "Third", band: band, order: 1)
        XCTAssertTrue(ThoughtManagement.moveWithinBand(second, among: [first, second, third], direction: .up, now: .now))
        XCTAssertEqual([first, second, third].sorted { ($0.order ?? 0) > ($1.order ?? 0) }.map(\.text), ["Second", "First", "Third"])
        XCTAssertFalse(ThoughtManagement.moveWithinBand(second, among: [second, first, third], direction: .up, now: .now))
    }
}
